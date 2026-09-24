# SageWrite LLM configuration

All SageWrite scripts that generate text with an LLM read their model connection from environment variables through `00-llm.ps1`:

- `02-structure.ps1`
- `02b-expand.ps1`
- `03-write.ps1`
- `03t-translate.ps1`
- `03r-refine.ps1`
- `04b33-editorial-action-review.ps1`
- `04c-editorial-loop.ps1`
- `04c2-third-party-audit.ps1` (passes model selection to the shared writer)
- `04c3-accepted-audit-rewrite.ps1`
- `04c44-revision-executor.ps1`
- `07a-cover-assist.ps1`
- `08g-copy.ps1`
- `08n-midjourney-prompt.ps1`

Scripts that do not call an LLM are intentionally unchanged.
Image editing scripts continue to use the Images API because their multipart request and binary response contract is different from text generation.

## OpenAI defaults

Only the API key is required. The default model is `gpt-5.6` and the default API style is Responses API.

```powershell
$env:SAGE_LLM_API_KEY = "your-api-key"
```

The existing `OPENAI_API_KEY` variable remains supported as a fallback.

## Local Codex execution

This mode does not call an LLM HTTP endpoint from SageWrite. It starts a temporary non-interactive Codex run and reuses the Codex CLI authentication already available on the machine.

```powershell
$env:SAGE_LLM_PROVIDER = "codex"
```

By default, Codex uses its configured model. To select a specific Codex model or working directory:

```powershell
$env:SAGE_LLM_MODEL = "model-name"
$env:SAGE_LLM_CODEX_WORKDIR = "D:\SageWrite"
```

`SAGE_LLM_CODEX_COMMAND` can point to a specific `codex.exe` when it is not available on `PATH`. Codex runs with a read-only sandbox and an ephemeral session because this adapter only needs generated text.

Token usage fields are recorded as `0` when the selected adapter returns text without usage metadata. This is expected for the current `codex-exec` integration.

## OpenAI-compatible provider

```powershell
$env:SAGE_LLM_PROVIDER = "openai-compatible"
$env:SAGE_LLM_BASE_URL = "https://provider.example/v1"
$env:SAGE_LLM_API_STYLE = "chat-completions"
$env:SAGE_LLM_MODEL = "provider-model-name"
$env:SAGE_LLM_API_KEY = "your-provider-api-key"
```

Use `SAGE_LLM_ENDPOINT` instead of `SAGE_LLM_BASE_URL` when the provider requires a complete custom endpoint.

## Optional settings

```powershell
$env:SAGE_LLM_SYSTEM_PROMPT = "Additional system-level instructions"
$env:SAGE_LLM_TIMEOUT_SEC = "180"
```

Supported HTTP API styles are `responses` and `chat-completions`. The `codex` provider automatically uses `codex-exec`. Providers with another native request schema require an additional adapter.
