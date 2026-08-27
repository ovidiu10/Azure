# TokenThrift — Hackathon PoC

**Same conversation. Half the tokens.**

TokenThrift is a live Streamlit dashboard that proves — with real,
side-by-side API calls, not simulated numbers — how much truncation,
semantic caching, and complexity-based model routing can cut LLM chatbot
token costs, running identically across Claude and GPT-5.

**Keywords:** LLM cost optimization, token reduction, prompt caching,
context truncation, model routing, Claude, GPT-5, Anthropic, OpenAI, Azure
AI Foundry, Streamlit, chatbot, provider-agnostic, hackathon

**Problem/Opportunity:** LLM chatbots silently burn tokens by resending
their full conversation history on every turn, and teams have no live,
provider-agnostic way to prove which fix — truncation, caching, routing —
actually cuts the bill before they build it.

**What I made:** A live dashboard that runs every chatbot message through
two real, parallel API calls at once: a naive "raw" path (full history
resent every turn, no optimization) and an "optimized" path (sliding-window
truncation + auto-summarization, fuzzy response caching, complexity-based
model routing). It shows the token/cost gap live, side by side, running
identically across model providers.

**How I made it:** Python + Streamlit for the UI, with all optimization
logic isolated in a single `optimizer.py` module built around one
provider-agnostic interface — every model client exposes the same
`.create(model, messages) → (text, tokens)` call, whether it's talking to
Anthropic's Messages API or OpenAI's Chat Completions API underneath. That
lets the exact same dashboard run against Claude (direct API or Azure
Foundry) or GPT-5 (Azure Foundry, with Microsoft Entra ID auth via
`azure-identity`) with zero changes to the truncation, caching, or routing
logic. Every turn makes two real API calls, not simulated numbers, so the
before/after savings are honest.

Every message runs through **two parallel paths**, compared live:

- **Raw path** — full conversation history resent every turn, one fixed
  model, no caching. This is what most naive chatbot integrations do.
- **Optimized path** — sliding-window truncation + periodic summarization,
  fuzzy semantic-ish response caching, and complexity-based model routing
  (cheap model for simple queries).

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

```bash
export ANTHROPIC_API_KEY=sk-ant-...   # or paste it in the sidebar
streamlit run app.py
```

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
   - **Main model / Cheap model:** the exact Foundry deployment names

Values loaded from `.env` prefill the sidebar. You can also leave the
Foundry variables empty and enter the API key and resource interactively, but
the values must be entered again after restarting the app.

## Run — Azure AI Foundry with Microsoft Entra ID

Entra authentication avoids storing a Foundry API key. TokenThrift uses
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

Notes for Claude deployments hosted in Foundry:

- `main_model` / `cheap_model` are **deployment names**, not raw model IDs —
  they default to the same string (`claude-sonnet-5`, `claude-haiku-4-5`)
  unless you renamed the deployment in the portal.
- Sonnet 5 and Haiku 4.5 are both available "Hosted on Azure," so the
  existing model-routing logic works unchanged.
- Billing runs through Azure Marketplace as Claude Consumption Units, not
  flat per-token pricing — the dashboard's `$` figures are direct-API
  estimates in this mode, not your real invoice number. Say this out loud
  in the demo if you're running on Foundry, it's an easy question to get
  asked.

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
3. **Model routing** — short, low-complexity queries get routed to Haiku
   4.5; anything flagged as complex (keywords like "analyze", "compare",
   "debug") stays on Sonnet.
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
- Runs both raw and optimized calls live (to get real, honest numbers) —
  in production you'd only run the optimized path and estimate the
  counterfactual raw cost instead of paying for both.
- No persistence — session state resets on refresh.

## Extending post-hackathon

- Swap difflib cache for embedding-based semantic cache (Voyage AI /
  sentence-transformers) with a vector store.
- Add native Anthropic **prompt caching** for the system prompt / static
  context (up to 90% cheaper on cache hits).
- Add a small trained classifier for routing instead of keyword heuristics.
- Persist metrics to a DB and add per-user cost attribution.
