"""
TokenThrift Dashboard — hackathon PoC
Run:  streamlit run app.py
"""

import hashlib
import os
from urllib.parse import urlparse

import pandas as pd
import streamlit as st
from dotenv import load_dotenv

from optimizer import TokenOptimizer, SessionState, has_pricing

load_dotenv()

st.set_page_config(page_title="TokenThrift", page_icon="⚡", layout="wide")


def _parse_resource_name(raw: str) -> str:
    """Accept either a bare resource name or a full endpoint URL pasted from
    the Foundry portal (e.g. 'https://my-resource.openai.azure.com/openai/v1')
    and return just the resource name."""
    raw = raw.strip()
    if not raw:
        return raw
    host = urlparse(raw).netloc if "://" in raw else raw
    return host.split(".")[0]


def _fingerprint(secret: str | None) -> str:
    """Detect a changed key without parking the key itself in session state."""
    return hashlib.sha256(secret.encode()).hexdigest() if secret else ""

# ---------------------------------------------------------------------------
# Sidebar — config
# ---------------------------------------------------------------------------
st.sidebar.title("⚡ TokenThrift")
st.sidebar.caption("Same conversation. Half the tokens.")

provider = st.sidebar.radio(
    "Model provider",
    ["anthropic", "openai"],
    index=0 if os.environ.get("LLM_PROVIDER", "anthropic") == "anthropic" else 1,
    format_func=lambda p: "Claude (Anthropic)" if p == "anthropic" else "OpenAI (Azure Foundry)",
    horizontal=True,
)

openai_api_key = openai_foundry_resource = None

if provider == "anthropic":
    backend = st.sidebar.radio(
        "Backend",
        ["anthropic", "foundry"],
        index=0 if os.environ.get("CLAUDE_BACKEND", "anthropic") == "anthropic" else 1,
        format_func=lambda b: "Anthropic API (direct)" if b == "anthropic" else "Azure Foundry",
        horizontal=True,
    )

    if backend == "anthropic":
        api_key = st.sidebar.text_input(
            "Anthropic API Key", type="password", value=os.environ.get("ANTHROPIC_API_KEY", "")
        )
        foundry_resource = foundry_base_url = None
        use_entra_id = False
        main_model = st.sidebar.selectbox("Main model", ["claude-sonnet-5", "claude-opus-5"], index=0)
        cheap_model = st.sidebar.selectbox("Cheap/routing model", ["claude-haiku-4-5-20251001"], index=0)
    else:
        foundry_auth = st.sidebar.radio(
            "Foundry auth method",
            ["api_key", "entra_id"],
            format_func=lambda a: "API key" if a == "api_key" else "Microsoft Entra ID",
            horizontal=True,
        )
        use_entra_id = foundry_auth == "entra_id"
        if use_entra_id:
            api_key = None
            st.sidebar.caption(
                "Uses your local Azure CLI session via `DefaultAzureCredential` — "
                "run `az login` in your terminal before sending a message."
            )
        else:
            api_key = st.sidebar.text_input(
                "Foundry API Key", type="password", value=os.environ.get("ANTHROPIC_FOUNDRY_API_KEY", "")
            )
        foundry_resource = _parse_resource_name(st.sidebar.text_input(
            "Foundry resource name", value=os.environ.get("ANTHROPIC_FOUNDRY_RESOURCE", ""),
            help="Your Foundry resource, e.g. 'my-resource' (used to build https://{resource}.services.ai.azure.com/anthropic/). "
                 "Pasting a full URL from the portal also works — just the resource name is extracted.",
        ))
        foundry_base_url = st.sidebar.text_input(
            "...or full base URL (optional)", value=os.environ.get("ANTHROPIC_FOUNDRY_BASE_URL", ""),
            help="Overrides resource name if set.",
        ) or None
        st.sidebar.caption(
            "Use your **deployment names** here — defaults match model IDs unless you renamed them in the Foundry portal."
        )
        main_model = st.sidebar.selectbox("Main model (deployment name)", ["claude-sonnet-5", "claude-opus-5"], index=0)
        cheap_model = st.sidebar.selectbox("Cheap/routing model (deployment name)", ["claude-haiku-4-5"], index=0)
        st.sidebar.warning(
            "Foundry bills in Azure Marketplace CCUs, not the flat $/token rates below — "
            "treat the $ figures on this dashboard as directional, not your actual invoice.",
            icon="⚠️",
        )
else:
    backend = "anthropic"  # unused when provider == "openai"; Foundry-hosted only
    api_key = foundry_resource = foundry_base_url = None

    foundry_auth = st.sidebar.radio(
        "Foundry auth method",
        ["api_key", "entra_id"],
        format_func=lambda a: "API key" if a == "api_key" else "Microsoft Entra ID",
        horizontal=True,
    )
    use_entra_id = foundry_auth == "entra_id"
    if use_entra_id:
        st.sidebar.caption(
            "Uses your local Azure CLI session via `DefaultAzureCredential` — "
            "run `az login` in your terminal before sending a message."
        )
    else:
        openai_api_key = st.sidebar.text_input(
            "Foundry API Key", type="password", value=os.environ.get("OPENAI_FOUNDRY_API_KEY", "")
        )
    openai_foundry_resource = _parse_resource_name(st.sidebar.text_input(
        "Foundry resource name", value=os.environ.get("OPENAI_FOUNDRY_RESOURCE", ""),
        help="Your Foundry resource, e.g. 'my-resource' (used to build https://{resource}.openai.azure.com/openai/v1/). "
             "Pasting a full URL from the portal also works — just the resource name is extracted.",
    ))
    st.sidebar.caption(
        "Use your **deployment names** here — defaults match model IDs unless you renamed them in the Foundry portal."
    )
    main_model = st.sidebar.selectbox("Main model (deployment name)", ["gpt-5", "gpt51"], index=0)
    cheap_model = st.sidebar.selectbox("Cheap/routing model (deployment name)", ["gpt5mini", "gpt-5-mini"], index=0)
    st.sidebar.warning(
        "Foundry bills in Azure Marketplace CCUs, not the flat $/token rates below — "
        "treat the $ figures on this dashboard as directional, not your actual invoice. "
        "GPT-5 pricing here is also a placeholder — see optimizer.py's PRICING table.",
        icon="⚠️",
    )

st.sidebar.subheader("Optimizations")
st.sidebar.caption(
    "All four run together in the 'optimized' path below; this is a PoC, not per-toggle A/B."
)
max_turns_raw = st.sidebar.slider("Keep last N turns verbatim", 2, 12, 6)
summary_trigger = st.sidebar.slider("Summarize after N turns", 4, 20, 10)
cache_threshold = st.sidebar.slider("Cache similarity threshold", 0.5, 1.0, 0.86)
max_response_tokens = st.sidebar.slider(
    "Max response tokens", 500, 8000, 4000 if provider == "openai" else 1500, step=250,
    key=f"max_response_tokens_{provider}",
    help="Caps reasoning + visible output. GPT-5 reasons before it writes, so too low a "
         "budget returns an empty message on questions that ask for depth.",
)

if st.sidebar.button("🔄 Reset session"):
    st.session_state.clear()
    st.rerun()

unpriced = [m for m in (main_model, cheap_model) if not has_pricing(m)]
if unpriced:
    st.sidebar.warning(
        f"No pricing entry for {', '.join(unpriced)} — costs fall back to Sonnet 5 rates. "
        "Add the deployment name to optimizer.py's PRICING table for accurate figures.",
        icon="💲",
    )

if provider == "anthropic" and backend == "anthropic":
    credentials_error = "" if api_key else "Enter your Anthropic API key in the sidebar first."
else:
    if provider == "anthropic":
        key_set, resource_set = bool(api_key), bool(foundry_base_url or foundry_resource)
    else:
        key_set, resource_set = bool(openai_api_key), bool(openai_foundry_resource)
    if not (key_set or use_entra_id):
        credentials_error = "Enter your Foundry API key (or select Microsoft Entra ID) in the sidebar first."
    elif not resource_set:
        credentials_error = "Enter your Foundry resource name in the sidebar first."
    else:
        credentials_error = ""

credentials_ready = not credentials_error

# Fingerprint of everything that affects which client/model gets built, so we
# can detect a sidebar change and rebuild the optimizer instead of silently
# keeping a stale client from before the user switched provider/backend/auth.
optimizer_config = (
    provider, backend, _fingerprint(api_key), foundry_resource, foundry_base_url, use_entra_id,
    _fingerprint(openai_api_key), openai_foundry_resource, main_model, cheap_model,
    max_turns_raw, summary_trigger, cache_threshold, max_response_tokens,
)

# ---------------------------------------------------------------------------
# Session state
# ---------------------------------------------------------------------------
if "session" not in st.session_state:
    st.session_state.session = SessionState()

state: SessionState = st.session_state.session

# ---------------------------------------------------------------------------
# Layout
# ---------------------------------------------------------------------------
col_chat, col_dash = st.columns([1.1, 1])

with col_chat:
    st.subheader("💬 Chat")
    for m in state.metrics:
        st.chat_message("user").write(m.query)
        with st.chat_message("assistant"):
            badge = "🗂️ cache hit" if m.cache_hit else f"model: {m.model_used}"
            flags = " · 🗜️ summarized" if m.summarized else ""
            flags += " · ✂️ truncated (not cached)" if m.truncated else ""
            st.caption(f"optimized · {badge}{flags}")
            st.write(m.opt_response)
            if m.truncated:
                st.warning(
                    "This answer hit the response-token ceiling and was cut off. It was "
                    "kept out of the cache so a partial answer can't be replayed later — "
                    "raise **Max response tokens** in the sidebar.",
                    icon="✂️",
                )
            with st.expander("Raw (unoptimized) answer — compare"):
                st.write(m.raw_response)

    user_query = st.chat_input("Type a message...")
    if user_query:
        if not credentials_ready:
            st.error(credentials_error)
        else:
            if st.session_state.get("optimizer_config") != optimizer_config:
                st.session_state.optimizer = TokenOptimizer(
                    api_key=api_key,
                    main_model=main_model,
                    cheap_model=cheap_model,
                    max_turns_raw=max_turns_raw,
                    summary_trigger=summary_trigger,
                    cache_similarity_threshold=cache_threshold,
                    backend=backend,
                    foundry_resource=foundry_resource,
                    foundry_base_url=foundry_base_url,
                    use_entra_id=use_entra_id,
                    provider=provider,
                    openai_api_key=openai_api_key,
                    openai_foundry_resource=openai_foundry_resource,
                    max_response_tokens=max_response_tokens,
                )
                st.session_state.optimizer_config = optimizer_config
            try:
                with st.spinner(f"Calling {'Claude' if provider == 'anthropic' else 'GPT'} (raw + optimized paths)..."):
                    st.session_state.optimizer.send(state, user_query)
            except Exception as exc:
                st.error(f"Request failed: {exc}")
            else:
                st.rerun()

with col_dash:
    st.subheader("📊 Savings Dashboard")

    if not state.metrics:
        st.info("Send a few chat messages to see live token/cost savings here.")
    else:
        df = pd.DataFrame([m.__dict__ for m in state.metrics])
        df["raw_total_tokens"] = df.raw_input_tokens + df.raw_output_tokens
        df["opt_total_tokens"] = df.opt_input_tokens + df.opt_output_tokens
        df["cum_raw_cost"] = df.raw_cost.cumsum()
        df["cum_opt_cost"] = df.opt_cost.cumsum()

        total_raw_cost = df.raw_cost.sum()
        total_opt_cost = df.opt_cost.sum()
        pct_saved = (
            (total_raw_cost - total_opt_cost) / total_raw_cost * 100
            if total_raw_cost > 0 else 0
        )
        cache_hits = int(df.cache_hit.sum())
        cache_hit_rate = cache_hits / len(df) * 100

        m1, m2, m3, m4 = st.columns(4)
        m1.metric("Turns", len(df))
        # delta_color="inverse" so a saving (negative delta) reads green; if the
        # optimized path ever costs more (possible now that summary spend is
        # billed), the positive delta reads red instead of a mangled "--" sign.
        m2.metric("$ Saved", f"${total_raw_cost - total_opt_cost:.4f}", f"{-pct_saved:+.0f}%", delta_color="inverse")
        m3.metric("Cache hit rate", f"{cache_hit_rate:.0f}%")
        # "Token delta", not "Tokens saved": routing to a cheaper model can spend
        # MORE tokens and still cut the bill, so a negative here sits happily
        # next to a positive $ Saved. Signed, because the direction is the point.
        token_delta = int(df.raw_total_tokens.sum() - df.opt_total_tokens.sum())
        m4.metric(
            "Token delta", f"{token_delta:+}",
            help="Raw tokens minus optimized tokens. Positive means the optimized path "
                 "moved fewer tokens. It can go negative while cost still drops — routing "
                 "a turn to a cheaper model saves money per token, not token count.",
        )

        st.line_chart(
            df.set_index("turn")[["raw_total_tokens", "opt_total_tokens"]],
            height=220,
        )
        st.caption("Tokens per turn — raw (no optimization) vs. optimized")

        st.line_chart(
            df.set_index("turn")[["cum_raw_cost", "cum_opt_cost"]],
            height=220,
        )
        st.caption("Cumulative cost ($) — raw vs. optimized")

        with st.expander("Per-turn detail"):
            st.dataframe(
                df[[
                    "turn", "raw_total_tokens", "opt_total_tokens",
                    "raw_cost", "opt_cost", "cache_hit", "model_used", "summarized",
                    "truncated",
                ]],
                width="stretch",
            )

st.divider()
st.caption(
    "PoC pricing reference (Aug 2026, direct API only, per million tokens, input/output): "
    "Haiku 4.5 $1/$5 · Sonnet 5 $2/$10 · Opus 5 $5/$25 (see platform.claude.com/docs for current rates); "
    "GPT-5 $2.50/$10 · GPT-5-mini $0.50/$2 (placeholders — optimizer.py's PRICING table). "
    "Foundry runs bill as Azure Marketplace CCUs instead, regardless of provider."
)
