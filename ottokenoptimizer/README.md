# TokenThrift — Hackathon PoC

**Same conversation. Half the tokens.**

TokenThrift is a live Streamlit dashboard that proves — with real,
side-by-side API calls, not simulated numbers — how much truncation,
lexical response caching, and complexity-based model routing can cut LLM
chatbot cost across Claude and GPT-5.

**Keywords:** LLM cost optimization, token reduction, response caching,
context truncation, model routing, Claude, GPT-5, Anthropic, OpenAI, Azure
AI Foundry, Streamlit, chatbot, provider-agnostic, hackathon

**Problem/Opportunity:** LLM chatbots silently burn tokens by resending
their full conversation history on every turn, and teams have no live,
provider-agnostic way to prove which fix — truncation, caching, routing —
actually cuts the bill before they build it.

**What I made:** A live dashboard that compares every chatbot message across
two execution paths: a naive "raw" path (full history resent every turn, no
optimization) and an "optimized" path (sliding-window truncation +
auto-summarization, fuzzy response caching, complexity-based model routing).
It shows the token/cost gap live, side by side, using the same optimization
logic across model providers. API calls are made sequentially, not in
parallel.

**How I made it:** Python + Streamlit for the UI, with all optimization
logic isolated in a single `optimizer.py` module built around one
provider-agnostic interface — every model client accepts a model, message
history, response budget, and optional system prompt, then returns text,
input/output usage, and whether the answer was truncated. The wrapper uses
Anthropic's Messages API or OpenAI's Chat Completions API underneath. That
lets the same dashboard run against Claude (direct API or Azure Foundry) or
GPT-5 (Azure Foundry, with API-key or Microsoft Entra ID authentication)
without changing the truncation, caching, or routing logic. An uncached turn
makes one raw and one optimized response call; a summarization turn adds a
third call, while a cache hit skips the optimized response call. All reported
token counts come from provider usage rather than simulation.

Every message is compared across **two paths**:

- **Raw path** — full conversation history resent every turn, one fixed
  model, no caching. This is what most naive chatbot integrations do.
- **Optimized path** — sliding-window truncation + periodic summarization,
  fuzzy lexical response caching, and complexity-based model routing
  (cheap model for simple queries).

Both paths receive the same sequence of user prompts. Their assistant-response
histories can differ because routing may select a different model, so use the
expandable raw answer to compare response quality as well as tokens and cost.

## Setup

Requirements:

- Python 3.10 or newer
- An Anthropic API key, or access to an Azure AI Foundry model deployment
- Azure CLI if using Microsoft Entra ID authentication

### Create a Python virtual environment

Using a virtual environment keeps TokenThrift's packages isolated from the
system Python installation.

**Windows PowerShell**

```powershell
python -m venv .venv
.\.venv\Scripts\Activate.ps1
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

If PowerShell blocks the activation script, allow it for the current terminal
session only and then activate again:

```powershell
Set-ExecutionPolicy -Scope Process Bypass
.\.venv\Scripts\Activate.ps1
```

Alternatively, run the environment's Python directly without activating it:

```powershell
.\.venv\Scripts\python.exe -m pip install -r requirements.txt
.\.venv\Scripts\python.exe -m streamlit run app.py
```

**macOS/Linux**

```bash
python3 -m venv .venv
source .venv/bin/activate
python -m pip install --upgrade pip
python -m pip install -r requirements.txt
```

Copy the example configuration before adding resource names or credentials:

```powershell
# Windows PowerShell
Copy-Item .env.example .env
```

```bash
# macOS/Linux
cp .env.example .env
```

The `.env` file is ignored by Git. Never commit API keys or access tokens.

## Run — direct Anthropic API

Add the direct Anthropic key to `.env`:

```dotenv
LLM_PROVIDER=anthropic
CLAUDE_BACKEND=anthropic
ANTHROPIC_API_KEY=your-anthropic-api-key
```

Then run `streamlit run app.py`. In the sidebar, select **Claude
(Anthropic)** and **Anthropic API (direct)**. This path does not require
`az login`.

## Run — Claude on Azure AI Foundry with an API key

This path calls a Claude deployment hosted in Azure AI Foundry and
authenticates with the deployment's API key. It does **not** use
`ANTHROPIC_API_KEY`, which is only for the direct Anthropic API.

1. In the Foundry portal, open the Claude deployment and its endpoint/details
   page. Record:

   - the **API key**
   - the **resource name**
   - the exact **deployment names** for the main and cheaper models

2. Add the following values to `.env`:

   ```dotenv
   LLM_PROVIDER=anthropic
   CLAUDE_BACKEND=foundry
   ANTHROPIC_FOUNDRY_API_KEY=your-foundry-api-key
   ANTHROPIC_FOUNDRY_RESOURCE=your-resource-name
   ```

   Use the resource name, not the whole endpoint. For example, if the endpoint
   is `https://my-ai-resource.services.ai.azure.com/anthropic/`, use:

   ```dotenv
   ANTHROPIC_FOUNDRY_RESOURCE=my-ai-resource
   ```

   If your deployment requires a nonstandard endpoint, set the full URL
   instead and leave `ANTHROPIC_FOUNDRY_RESOURCE` empty:

   ```dotenv
   ANTHROPIC_FOUNDRY_RESOURCE=
   ANTHROPIC_FOUNDRY_BASE_URL=https://your-endpoint.example/anthropic/
   ```

3. Start the app:

   ```powershell
   streamlit run app.py
   ```

4. Confirm these sidebar selections:

   - **Model provider:** Claude (Anthropic)
   - **Backend:** Azure Foundry
   - **Foundry auth method:** API key
   - **Foundry resource name:** the resource configured above, or use the
     optional full base URL field for a nonstandard endpoint
   - **Main model / Cheap model:** select the options matching your Foundry
     deployment names

Values loaded from `.env` prefill the sidebar. You can also leave the
Foundry variables empty and enter the API key and resource interactively, but
the values must be entered again after restarting the app.

## Run — GPT-5 on Azure AI Foundry with an API key

This path does not require `az login`. Add the Foundry key and resource name
to `.env`:

```dotenv
LLM_PROVIDER=openai
OPENAI_FOUNDRY_API_KEY=your-foundry-api-key
OPENAI_FOUNDRY_RESOURCE=your-resource-name
```

Start the app with `streamlit run app.py`, then confirm:

- **Model provider:** OpenAI (Azure Foundry)
- **Foundry auth method:** API key
- **Foundry resource name:** the resource configured above
- **Main model / Cheap model:** select the options matching your Foundry
  deployment names

The OpenAI provider in this PoC targets Azure AI Foundry only; it does not
connect directly to `api.openai.com`.

## Run — Azure AI Foundry with Microsoft Entra ID

This is the only setup path that requires `az login`. Entra authentication
avoids storing a Foundry API key. TokenThrift uses
`DefaultAzureCredential` from `azure-identity`, which detects the active Azure
CLI session.

1. Install the [Azure CLI](https://learn.microsoft.com/cli/azure/install-azure-cli).
2. Sign in to the tenant that owns the Foundry resource:

   ```powershell
   az login
   ```

   If your account has access to multiple tenants, specify the resource
   tenant explicitly:

   ```powershell
   az login --tenant <tenant-id>
   ```

3. Select the subscription containing the Foundry resource:

   ```powershell
   az account list --output table
   az account set --subscription "<subscription-name-or-id>"
   az account show --output table
   ```

4. Add the Foundry resource name to `.env`. Use the resource name only, not
   the complete endpoint URL.

   For GPT-5/OpenAI deployments:

   ```dotenv
   LLM_PROVIDER=openai
   OPENAI_FOUNDRY_RESOURCE=your-resource-name
   ```

   For Claude deployments hosted in Foundry:

   ```dotenv
   LLM_PROVIDER=anthropic
   CLAUDE_BACKEND=foundry
   ANTHROPIC_FOUNDRY_RESOURCE=your-resource-name
   ```

   For example, the OpenAI resource name for
   `https://my-ai-resource.openai.azure.com/openai/v1/` is
   `my-ai-resource`.

5. Start the app:

   ```powershell
   streamlit run app.py
   ```

6. In the sidebar, select the provider and deployment:

   - **Model provider:** OpenAI (Azure Foundry), or Claude (Anthropic) with
     **Backend:** Azure Foundry
   - **Foundry auth method:** Microsoft Entra ID
   - **Main model / Cheap model:** the deployment names configured on the
     resource

No access token is written to `.env`. `azure-identity` obtains and refreshes
short-lived tokens from the Azure CLI session. Your signed-in identity still
needs permission to invoke the model deployment; authentication can succeed
while inference fails with `401` or `403` if the required Foundry/Azure OpenAI
role assignment is missing.

To switch accounts or tenants:

```powershell
az logout
az login --tenant <tenant-id>
az account set --subscription "<subscription-name-or-id>"
```

Notes for Foundry deployments:

- **Model fields contain deployment names**, not catalog model IDs. This PoC
  offers a fixed list of common deployment names in the sidebar. Your
  Foundry deployments must use one of those names; otherwise add the custom
  name to the corresponding select box in `app.py`.
- Foundry billing may not match the flat per-token rates in `PRICING`.
  Dashboard token counts come from provider usage, but dollar figures are
  directional estimates rather than the Azure invoice.
- A custom deployment name also needs a matching entry in `optimizer.py`'s
  `PRICING` table; otherwise the app warns and falls back to Sonnet 5 rates.

Then open the local URL Streamlit prints (usually http://localhost:8501).

## What's happening under the hood (`optimizer.py`)

1. **Truncation + summarization** — keeps the last N turns verbatim; once
   history exceeds a threshold, older turns are compressed into a short
   summary by the cheap model, so the optimized history stays small even in
   long conversations.
2. **Caching** — before calling the API, the optimized path checks past
   queries with `difflib` fuzzy string matching. A near-duplicate question
   returns the cached answer for **zero tokens**. (Swap in embedding
   cosine-similarity, e.g. Voyage AI, for a production-grade version — this
   is a fast stand-in for a weekend build.)
3. **Model routing** — short, low-complexity queries go to the configured
   cheaper model (for example Haiku or GPT-5 mini); longer prompts and
   complexity keywords such as "analyze", "compare", and "debug" use the
   configured main model (for example Sonnet or GPT-5).
4. **Tracking** — every turn's real `usage.input_tokens` /
   `usage.output_tokens` (straight from the API response, not estimates)
   feeds a running before/after cost comparison.

## Dashboard reference — "Per-turn detail" table

Columns in the expandable per-turn table at the bottom of the dashboard:

| Column | Meaning |
|---|---|
| `turn` | Sequential turn number in the conversation |
| `raw_total_tokens` | Input+output tokens used by the **raw** path — full history resent, no optimizations, always the fixed main model |
| `opt_total_tokens` | Input+output tokens used by the **optimized** path (truncation/summarization + caching + routing applied) |
| `raw_cost` | $ cost of that raw-path call, from the pricing table |
| `opt_cost` | $ cost of the optimized-path call — `0` if served from cache |
| `cache_hit` | Whether this turn's optimized response was served from the fuzzy-match cache instead of a real API call |
| `model_used` | Which model actually answered the optimized path — `cache` if cache-hit, otherwise the routed model name (e.g. `gpt5mini`, `gpt-5`, `claude-haiku-4-5-20251001`) |
| `summarized` | Whether this turn triggered auto-summarization — older history got compressed because it crossed the `summary_trigger` threshold |
| `truncated` | Whether the optimized answer hit the response-token ceiling and was cut off — truncated answers are excluded from the cache so a partial answer can't be replayed later |

The table uses the same columns for Claude and GPT-5.

## Test use case

Run the following prompts in order to exercise every optimization path.

### 1. Cheap-model routing

These short factual prompts contain no complexity keywords, so the optimized
path routes them to the cheaper model:

1. `What is the capital of France?`
2. `What year did World War II end?`
3. `How many continents are there?`
4. `What is the boiling point of water in Celsius?`

### 2. Exact and fuzzy cache hits

5. `What is the capital of France?`
6. `what's the capital of france`

Both should display the **cache hit** badge with zero optimized tokens and
zero optimized cost. The first is an exact repeat; the second should match at
the default `0.86` similarity threshold.

### 3. Complexity routing

These prompts force the optimized path onto the main model:

7. `Compare Python and JavaScript.`
8. `Explain why the sky is blue.`
9. `Can you give me a detailed walkthrough of how neural networks learn through backpropagation?`

Prompts 7 and 8 match configured complexity keywords. Prompt 9 exceeds the
simple-query length limit. GPT-5 spends reasoning tokens before producing
visible text, so increase **Max response tokens** if the detailed walkthrough
reaches the response-token ceiling.

### 4. History summarization

Continue with short prompts until the optimized history crosses the default
10-turn summary threshold:

10. `What is 7 times 8?`
11. `Name a primary color.`
12. `What is H2O?`
13. `What's the freezing point of water in Fahrenheit?`

### Expected results

- Turns 5 and 6 show `cache_hit=True`, `model_used=cache`, and
  `opt_cost=0`.
- Turns 7–9 use the main model (`claude-sonnet-5` or the selected GPT-5
  deployment).
- A later row shows `summarized=True` after the history crosses the configured
  threshold; the summarization call's tokens and cost are included in that
  optimized turn.
- **Token delta** may be positive or negative. Routing can use more tokens
  while still reducing cost because the cheaper model has a lower per-token
  price.
- The optimized and raw answers are both available in the chat for a
  side-by-side quality comparison.

## Known PoC limitations

- Caching is fuzzy string-match, not true semantic embedding similarity —
  fine for near-identical rephrasing, not for paraphrases with different
  wording.
- Model routing is a simple length/keyword heuristic, not a trained
  classifier.
- Runs the raw counterfactual live on every turn and calls the optimized model
  when the response is not cached; summarization can add another model call.
  In production, you would run only the optimized path and estimate the raw
  counterfactual instead of paying to execute it.
- No persistence — session state resets on refresh.

## Extending post-hackathon

### Turn the optimizer into an agent tool

Extract `TokenOptimizer` from the Streamlit process into a small authenticated
service. Expose a provider-neutral API such as:

- `optimized_chat(session_id, messages, policy)` — return the response,
  provider/model used, cache status, token usage, cost estimate, and
  truncation status.
- `get_session_metrics(session_id)` — return cumulative token, cost, cache,
  routing, latency, and quality metrics.
- `reset_session(session_id)` — clear that session's history and cache.
- `benchmark(messages, providers)` — run the PoC's raw-versus-optimized
  comparison explicitly. Keep this out of the production response path so
  normal users do not pay for the raw counterfactual.

The service should own provider credentials. Agents receive permission to call
the service, not direct access to Anthropic or Foundry keys.

### Integrate through MCP or REST

- **Claude Desktop / Claude Code:** expose the service as an
  [MCP](https://modelcontextprotocol.io/) server. Claude can call the optimizer
  as a tool while the MCP server maintains session state and metrics.
- **GitHub Copilot agent mode / coding agent:** use the same MCP server and
  repository instructions that tell Copilot when to use optimized chat,
  benchmarking, or metrics tools.
- **Microsoft Copilot Studio / Microsoft 365 agents:** publish an authenticated
  REST/OpenAPI endpoint and call it through a custom connector or agent action.
- **Standalone applications:** provide a small Python/TypeScript SDK over the
  same REST service.

MCP and REST are transports; they do not replace the optimization logic. This
keeps one implementation usable by several agent products.

### Add skills and agent instructions

A skill is an instruction bundle that teaches an agent *when and how* to call
the tools; it should not contain secrets or duplicate the optimizer itself.
Useful skills include:

- **Cost-aware chat:** choose a policy based on task complexity and invoke
  `optimized_chat`.
- **Prompt budget check:** inspect projected context size before a long agent
  task and summarize low-value history.
- **Optimization benchmark:** run a fixed evaluation set and explain cost,
  token delta, latency, cache hits, and response-quality differences.
- **Session report:** retrieve metrics and produce a per-user, repository, or
  project cost report.

Keep product-specific skill files thin. Put routing, caching, accounting, and
security rules in the shared service so Claude and Copilot behave consistently.

### Make the optimizer safe for agent workflows

Agents add tool calls and side effects that ordinary chat does not have:

- Preserve tool-call/tool-result pairs during truncation and summarization;
  removing one side can corrupt the conversation protocol.
- Never replay cached write actions such as sending email, modifying code,
  creating tickets, or provisioning resources. Cache only deterministic,
  read-only responses unless an idempotency design proves otherwise.
- Key cache entries by tenant, user, provider, model, system prompt, tool
  definitions, and relevant permissions. Add a TTL and prevent cross-user
  cache leakage.
- Preserve citations, decisions, constraints, unresolved tasks, and security
  context when summarizing agent history.
- Require authentication and authorization on every MCP/REST call, with audit
  logs and per-agent/session budgets.
- Treat model output and tool results as untrusted input; validate tool
  arguments before executing an action.

### Improve optimization quality and measurement

- Replace `difflib` with embedding-based semantic caching plus a vector store,
  confidence threshold, TTL, and invalidation policy.
- Add provider-native prompt caching for stable system prompts and tool
  definitions where supported.
- Replace keyword routing with an evaluated classifier that considers task
  complexity, latency, cost, required tools, and action risk.
- Measure answer quality and task success alongside cost. A cheaper response
  is not an optimization if the agent needs retries or produces a wrong action.
- Persist metrics to a database and add OpenTelemetry traces, per-user/project
  attribution, latency percentiles, error rates, and budget alerts.
- Estimate the raw counterfactual in production rather than executing it;
  periodically run controlled benchmarks to calibrate the estimate.
