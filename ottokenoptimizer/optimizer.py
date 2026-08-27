"""
TokenThrift — core logic for a hackathon PoC that reduces LLM token
consumption in a chatbot via:
  1. Sliding-window history truncation + summarization
  2. Lightweight lexical-similarity response caching (difflib, not embeddings)
  3. Complexity-based model routing (cheap model for simple queries)
  4. Before/after token + cost tracking

Pricing reference (direct Anthropic API, per million tokens, Aug 2026):
  Claude Haiku 4.5 : $1 in  / $5 out
  Claude Sonnet 5  : $2 in  / $10 out
  Claude Opus 5    : $5 in  / $25 out
(Check https://platform.claude.com/docs/en/about-claude/pricing for current rates.)

Note: if CLAUDE_BACKEND=foundry, billing runs through Azure Marketplace as
Claude Consumption Units (CCUs), not these flat per-token $ rates. Token
counts stay accurate either way (the `usage` object is identical across
backends), but the dollar figures in this PoC are direct-API estimates —
don't read them as your actual Azure invoice number if you run in Foundry
mode. See https://platform.claude.com/docs/en/about-claude/pricing#claude-in-microsoft-foundry-pricing

GPT-5 / GPT-5-mini pricing below are directional placeholders (this repo has
no first-party OpenAI pricing to crib from) — correct them once you see your
actual Azure Foundry invoice.
"""

import difflib
import os
import re
from dataclasses import dataclass, field

import anthropic

# ---------------------------------------------------------------------------
# Pricing table ($ per million tokens) — direct API estimates only; Foundry
# bills via Azure Marketplace CCUs regardless of provider (see module note).
# ---------------------------------------------------------------------------
PRICING = {
    "claude-haiku-4-5-20251001": {"input": 1.00, "output": 5.00},
    "claude-haiku-4-5": {"input": 1.00, "output": 5.00},  # Foundry deployment name
    "claude-sonnet-5": {"input": 2.00, "output": 10.00},
    "claude-opus-5": {"input": 5.00, "output": 25.00},
    "gpt-5": {"input": 2.50, "output": 10.00},        # placeholder — see module docstring
    "gpt51": {"input": 2.50, "output": 10.00},        # Foundry deployment name variant
    "gpt-5-mini": {"input": 0.50, "output": 2.00},    # placeholder — see module docstring
    "gpt5mini": {"input": 0.50, "output": 2.00},      # Foundry deployment name variant
}


# GPT-5 spends reasoning tokens out of the same budget as visible output, and it
# reasons *before* emitting any text — so if the cap runs out mid-reasoning the
# message comes back empty. "minimal" is only a hint, not a ceiling: prompts that
# ask for depth ("give me a detailed walkthrough...") still reason well past it,
# which is why the budget below has to be generous rather than Claude-sized.
OPENAI_REASONING_EFFORT = "minimal"


class _AnthropicChatClient:
    """Wraps anthropic.Anthropic / AnthropicFoundry behind a provider-neutral
    .create() so TokenOptimizer doesn't need to know which SDK it's using.

    Returns (text, input_tokens, output_tokens, truncated).
    """

    def __init__(self, client):
        self._client = client

    def create(self, model: str, max_tokens: int, messages: list, system: str | None = None):
        kwargs = {"model": model, "max_tokens": max_tokens, "messages": messages}
        if system is not None:
            kwargs["system"] = system
        resp = self._client.messages.create(**kwargs)
        return (
            extract_text(resp),
            resp.usage.input_tokens,
            resp.usage.output_tokens,
            resp.stop_reason == "max_tokens",
        )


class _OpenAIChatClient:
    """Wraps openai.OpenAI (pointed at an Azure Foundry OpenAI deployment)
    behind the same provider-neutral .create() as _AnthropicChatClient."""

    def __init__(self, client):
        self._client = client

    def create(self, model: str, max_tokens: int, messages: list, system: str | None = None):
        full_messages = messages
        if system is not None:
            full_messages = [{"role": "system", "content": system}] + messages
        resp = self._client.chat.completions.create(
            model=model,
            max_completion_tokens=max_tokens,  # gpt-5 is a reasoning model; max_tokens is deprecated/rejected
            reasoning_effort=OPENAI_REASONING_EFFORT,
            messages=full_messages,
        )
        choice = resp.choices[0]
        text = choice.message.content
        finish = choice.finish_reason

        if not text:
            # Empty content has two very different causes; conflating them sends
            # you chasing a token budget when the real problem is the filter.
            if finish == "content_filter":
                raise RuntimeError(
                    f"'{model}' returned no content — the response was blocked by Azure "
                    "content filtering. Rephrase the question or adjust the content filter "
                    "on the deployment."
                )
            raise RuntimeError(
                f"'{model}' returned no content (finish_reason={finish!r}). Reasoning "
                f"consumed the whole {max_tokens}-token budget before any visible text — "
                "raise 'Max response tokens' in the sidebar."
            )

        return text, resp.usage.prompt_tokens, resp.usage.completion_tokens, finish == "length"


def make_client(
    provider: str | None = None,
    backend: str | None = None,
    api_key: str | None = None,
    foundry_resource: str | None = None,
    foundry_base_url: str | None = None,
    use_entra_id: bool = False,
    openai_api_key: str | None = None,
    openai_foundry_resource: str | None = None,
):
    """Build a provider-neutral chat client (see _AnthropicChatClient /
    _OpenAIChatClient) for either model provider.

    provider: "anthropic" (default) or "openai". Falls back to the
    LLM_PROVIDER env var, then "anthropic".

    -- provider="anthropic" --
    backend: "anthropic" (default) or "foundry". Falls back to the
    CLAUDE_BACKEND env var, then "anthropic".

    Direct API reads ANTHROPIC_API_KEY if api_key isn't passed.
    Foundry reads ANTHROPIC_FOUNDRY_API_KEY / ANTHROPIC_FOUNDRY_RESOURCE /
    ANTHROPIC_FOUNDRY_BASE_URL if their params aren't passed — same env
    vars the official SDK and Claude Code use, so a Foundry setup that
    already works elsewhere works here with no changes.

    use_entra_id: for the Foundry backend only, authenticate with Microsoft
    Entra ID (via azure-identity's DefaultAzureCredential — run `az login`
    first) instead of an API key. Ignored for the direct backend.

    -- provider="openai" --
    Azure Foundry-hosted only (no direct api.openai.com path). Reads
    OPENAI_FOUNDRY_API_KEY / OPENAI_FOUNDRY_RESOURCE if their params aren't
    passed. use_entra_id works the same way as for Anthropic Foundry, but
    against the `https://cognitiveservices.azure.com/.default` scope (the
    Azure OpenAI inference endpoint's scope, distinct from the Anthropic
    Foundry endpoint's `https://ai.azure.com/.default`).
    """
    provider = (provider or os.environ.get("LLM_PROVIDER", "anthropic")).lower()

    if provider == "openai":
        from openai import OpenAI

        resource = openai_foundry_resource or os.environ.get("OPENAI_FOUNDRY_RESOURCE")
        if not resource:
            raise ValueError(
                "OpenAI provider needs OPENAI_FOUNDRY_RESOURCE (or openai_foundry_resource=)."
            )
        base_url = f"https://{resource}.openai.azure.com/openai/v1/"

        # Foundry endpoints behind corporate networks intermittently drop the
        # connection mid-request; without explicit retries a single dropped
        # socket kills a live demo turn.
        http_opts = {"timeout": 60.0, "max_retries": 5}

        if use_entra_id:
            from azure.identity import DefaultAzureCredential, get_bearer_token_provider

            credential = DefaultAzureCredential()
            token_provider = get_bearer_token_provider(
                credential, "https://cognitiveservices.azure.com/.default"
            )
            client = OpenAI(base_url=base_url, api_key=token_provider, **http_opts)
        else:
            key = openai_api_key or os.environ.get("OPENAI_FOUNDRY_API_KEY")
            if not key:
                raise ValueError(
                    "OpenAI provider needs OPENAI_FOUNDRY_API_KEY (or openai_api_key=), "
                    "or pass use_entra_id=True for Microsoft Entra ID auth."
                )
            client = OpenAI(base_url=base_url, api_key=key, **http_opts)
        return _OpenAIChatClient(client)

    backend = (backend or os.environ.get("CLAUDE_BACKEND", "anthropic")).lower()

    if backend == "foundry":
        from anthropic import AnthropicFoundry

        resource = foundry_resource or os.environ.get("ANTHROPIC_FOUNDRY_RESOURCE")
        base_url = foundry_base_url or os.environ.get("ANTHROPIC_FOUNDRY_BASE_URL")
        if not resource and not base_url:
            raise ValueError(
                "Foundry backend needs ANTHROPIC_FOUNDRY_RESOURCE or "
                "ANTHROPIC_FOUNDRY_BASE_URL (or foundry_resource=/foundry_base_url=)."
            )
        kwargs = {}
        if base_url:
            kwargs["base_url"] = base_url
        else:
            kwargs["resource"] = resource

        if use_entra_id:
            from azure.identity import DefaultAzureCredential, get_bearer_token_provider

            credential = DefaultAzureCredential()
            kwargs["azure_ad_token_provider"] = get_bearer_token_provider(
                credential, "https://ai.azure.com/.default"
            )
        else:
            key = api_key or os.environ.get("ANTHROPIC_FOUNDRY_API_KEY")
            if not key:
                raise ValueError(
                    "Foundry backend needs ANTHROPIC_FOUNDRY_API_KEY (or api_key=), "
                    "or pass use_entra_id=True for Microsoft Entra ID auth."
                )
            kwargs["api_key"] = key
        return _AnthropicChatClient(AnthropicFoundry(**kwargs))

    key = api_key or os.environ.get("ANTHROPIC_API_KEY")
    if not key:
        raise ValueError("Direct backend needs ANTHROPIC_API_KEY (or api_key=).")
    return _AnthropicChatClient(anthropic.Anthropic(api_key=key))


def has_pricing(model: str) -> bool:
    """False for custom Foundry deployment names absent from PRICING — their
    costs fall back to Sonnet rates, so callers should surface a warning."""
    return model in PRICING


def cost_for(model: str, input_tokens: int, output_tokens: int) -> float:
    rates = PRICING.get(model, PRICING["claude-sonnet-5"])
    return (input_tokens / 1_000_000) * rates["input"] + (
        output_tokens / 1_000_000
    ) * rates["output"]


def extract_text(response) -> str:
    """First text block in a Messages API response. content[0] isn't always
    the text block — extended thinking puts a ThinkingBlock there first."""
    for block in response.content:
        if block.type == "text":
            return block.text
    return ""


# ---------------------------------------------------------------------------
# Data structures
# ---------------------------------------------------------------------------
@dataclass
class TurnMetrics:
    turn: int
    query: str
    raw_input_tokens: int
    raw_output_tokens: int
    opt_input_tokens: int
    opt_output_tokens: int
    raw_cost: float
    opt_cost: float
    cache_hit: bool
    model_used: str
    summarized: bool
    raw_response: str = ""
    opt_response: str = ""
    truncated: bool = False   # optimized answer hit the response-token ceiling


@dataclass
class SessionState:
    raw_history: list = field(default_factory=list)   # unmodified, ever-growing
    opt_history: list = field(default_factory=list)    # truncated/summarized
    cache: list = field(default_factory=list)           # [{"query":..., "response":..., "model":...}]
    metrics: list = field(default_factory=list)         # list[TurnMetrics]
    turn_count: int = 0
    summary: str = ""                                   # compressed older turns, injected via system prompt
    pending_summary_tokens: tuple = (0, 0)              # summary spend orphaned by a failed turn, billed next turn


# ---------------------------------------------------------------------------
# Optimizer
# ---------------------------------------------------------------------------
class TokenOptimizer:
    def __init__(
        self,
        api_key: str | None = None,
        main_model: str = "claude-sonnet-5",
        cheap_model: str = "claude-haiku-4-5-20251001",
        max_turns_raw: int = 6,      # turns, not messages
        summary_trigger: int = 10,   # turns, not messages
        cache_similarity_threshold: float = 0.86,
        simple_query_char_limit: int = 60,
        backend: str | None = None,
        foundry_resource: str | None = None,
        foundry_base_url: str | None = None,
        use_entra_id: bool = False,
        provider: str | None = None,
        openai_api_key: str | None = None,
        openai_foundry_resource: str | None = None,
        max_response_tokens: int | None = None,
        max_summary_tokens: int | None = None,
    ):
        self.provider = (provider or os.environ.get("LLM_PROVIDER", "anthropic")).lower()
        self.backend = (backend or os.environ.get("CLAUDE_BACKEND", "anthropic")).lower()
        self.client = make_client(
            provider=self.provider,
            backend=self.backend,
            api_key=api_key,
            foundry_resource=foundry_resource,
            foundry_base_url=foundry_base_url,
            use_entra_id=use_entra_id,
            openai_api_key=openai_api_key,
            openai_foundry_resource=openai_foundry_resource,
        )
        self.main_model = main_model
        self.cheap_model = cheap_model
        self.max_turns_raw = max_turns_raw
        self.summary_trigger = summary_trigger
        self.cache_threshold = cache_similarity_threshold
        self.simple_query_char_limit = simple_query_char_limit
        # Headroom for GPT-5's reasoning tokens, which are spent before any visible
        # text: 1500 is enough for short factual answers but a prompt asking for a
        # "detailed walkthrough" reasons straight through it and returns nothing.
        # The summary budget needs the same headroom — the summarization call runs
        # on the same reasoning model, and if it comes back empty the whole turn
        # fails right when the "summarized" demo beat should land.
        # 500 was too tight for Sonnet's answers to complexity-routed queries
        # (e.g. "Compare Python and JavaScript") — they routinely ran past it
        # and got silently cut off before truncation was even detected.
        is_openai = self.provider == "openai"
        self.max_response_tokens = max_response_tokens or (4000 if is_openai else 1500)
        self.max_summary_tokens = max_summary_tokens or (1000 if is_openai else 200)

    # -- caching ------------------------------------------------------------
    def _check_cache(self, cache: list, query: str):
        """Difflib-based fuzzy match. Good enough for a demo; swap for
        embedding cosine-similarity (e.g. voyage-3) for production use."""
        best_score, best_entry = 0.0, None
        q_norm = re.sub(r"\s+", " ", query.strip().lower())
        for entry in cache:
            score = difflib.SequenceMatcher(
                None, q_norm, entry["query_norm"]
            ).ratio()
            if score > best_score:
                best_score, best_entry = score, entry
        if best_score >= self.cache_threshold:
            return best_entry
        return None

    # -- routing --------------------------------------------------------------
    def _route_model(self, query: str) -> str:
        """Very simple heuristic router for demo purposes:
        short / low-complexity queries -> cheap model."""
        is_short = len(query) <= self.simple_query_char_limit
        has_complex_signal = bool(
            re.search(r"\b(analyze|compare|design|debug|explain why|architecture)\b", query.lower())
        )
        if is_short and not has_complex_signal:
            return self.cheap_model
        return self.main_model

    # -- summarization --------------------------------------------------------
    @staticmethod
    def _system_with_summary(state: SessionState, system_prompt: str) -> str:
        """Summaries ride in the system prompt rather than as a synthetic user
        message, which would put two `user` turns back to back."""
        if not state.summary:
            return system_prompt
        return f"{system_prompt}\n\n[Summary of earlier conversation: {state.summary}]"

    def _maybe_compress(self, state: SessionState) -> tuple[bool, int, int]:
        """Returns (summarized, input_tokens, output_tokens) — the summary call is
        real spend on the optimized path and must be billed to it."""
        keep = 2 * self.max_turns_raw  # opt_history holds 2 messages per turn
        if len(state.opt_history) <= max(2 * self.summary_trigger, keep):
            return False, 0, 0

        old = state.opt_history[:-keep]
        recent = state.opt_history[-keep:]
        old_text = "\n".join(f"{m['role']}: {m['content']}" for m in old)
        prior = f"Summary so far: {state.summary}\n\n" if state.summary else ""

        try:
            summary_text, sum_in, sum_out, _ = self.client.create(
                model=self.cheap_model,
                max_tokens=self.max_summary_tokens,
                messages=[{
                    "role": "user",
                    "content": f"Summarize the key facts/context from this conversation "
                                f"in 2-3 sentences:\n\n{prior}{old_text}",
                }],
            )
        except RuntimeError as e:
            # The empty-content message from the client suggests the sidebar
            # slider, which doesn't control this call's budget — say what failed.
            raise RuntimeError(f"History summarization call failed: {e}") from e
        state.summary = summary_text
        state.opt_history[:] = recent
        return True, sum_in, sum_out

    # -- main entry point -----------------------------------------------------
    def send(self, state: SessionState, user_query: str, system_prompt: str = "You are a helpful assistant.") -> TurnMetrics:
        state.turn_count += 1

        # ---------- RAW (baseline) path: full history, no optimizations ----------
        state.raw_history.append({"role": "user", "content": user_query})
        try:
            raw_text, raw_in, raw_out, _ = self.client.create(
                model=self.main_model,
                max_tokens=self.max_response_tokens,
                system=system_prompt,
                messages=state.raw_history,
            )
        except Exception:
            # A dangling user message would corrupt every subsequent turn.
            state.raw_history.pop()
            state.turn_count -= 1
            raise
        state.raw_history.append({"role": "assistant", "content": raw_text})
        raw_cost = cost_for(self.main_model, raw_in, raw_out)

        # ---------- OPTIMIZED path ----------
        cache_hit_entry = self._check_cache(state.cache, user_query)
        summarized = False
        truncated = False

        if cache_hit_entry:
            opt_text = cache_hit_entry["response"]
            opt_in, opt_out = 0, 0  # served from cache, no API call
            opt_cost = 0.0
            model_used = "cache"
            # Still record the turn, or the optimized history silently diverges
            # from what the user actually asked.
            state.opt_history.append({"role": "user", "content": user_query})
            state.opt_history.append({"role": "assistant", "content": opt_text})
        else:
            sum_in = sum_out = 0
            appended_user = False
            try:
                summarized, sum_in, sum_out = self._maybe_compress(state)
                # Fold in summary spend orphaned by a previously failed turn so
                # no real API spend ever goes missing from the dashboard.
                pend_in, pend_out = state.pending_summary_tokens
                sum_in, sum_out = sum_in + pend_in, sum_out + pend_out
                state.pending_summary_tokens = (0, 0)

                model_used = self._route_model(user_query)
                state.opt_history.append({"role": "user", "content": user_query})
                appended_user = True
                opt_text, call_in, call_out, truncated = self.client.create(
                    model=model_used,
                    max_tokens=self.max_response_tokens,
                    system=self._system_with_summary(state, system_prompt),
                    messages=state.opt_history,
                )
            except Exception:
                if appended_user:
                    state.opt_history.pop()
                # The raw half already committed; roll it back too so a failed
                # turn leaves no invisible turn in the raw context or a gap in
                # the turn numbering. Any summary spend is parked for the next
                # successful turn instead of vanishing.
                state.raw_history.pop()   # assistant
                state.raw_history.pop()   # user
                state.turn_count -= 1
                state.pending_summary_tokens = (sum_in, sum_out)
                raise
            state.opt_history.append({"role": "assistant", "content": opt_text})

            opt_in, opt_out = call_in + sum_in, call_out + sum_out
            opt_cost = cost_for(model_used, call_in, call_out) + cost_for(
                self.cheap_model, sum_in, sum_out
            )

            if not truncated:
                state.cache.append({
                    "query": user_query,
                    "query_norm": re.sub(r"\s+", " ", user_query.strip().lower()),
                    "response": opt_text,
                    "model": model_used,
                })

        metrics = TurnMetrics(
            turn=state.turn_count,
            query=user_query,
            raw_input_tokens=raw_in,
            raw_output_tokens=raw_out,
            opt_input_tokens=opt_in,
            opt_output_tokens=opt_out,
            raw_cost=raw_cost,
            opt_cost=opt_cost,
            cache_hit=bool(cache_hit_entry),
            model_used=model_used,
            summarized=summarized,
            raw_response=raw_text,
            opt_response=opt_text,
            truncated=truncated,
        )
        state.metrics.append(metrics)
        return metrics
