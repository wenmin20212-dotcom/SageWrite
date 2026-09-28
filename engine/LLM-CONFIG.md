# SageWrite LLM configuration

All SageWrite scripts that generate text with an LLM read their model connection through `00-llm.ps1`. Settings are resolved from environment variables first, then `engine/llm-config.json`, then built-in defaults. `SAGE_LLM_CONFIG` can select a different JSON settings file. The shared file is read at call time by both CLI and UI-launched scripts:

- `02-structure.ps1`
- `02b-expand.ps1`
- `03-write.ps1`
- `03RW.ps1`
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

## Current assistant (codex_agent)

The installed shared configuration selects `SAGE_LLM_PROVIDER: "codex_agent"`.
This is a writing execution mode, not a model ID. It uses the current assistant,
without making an HTTP model request or starting another Codex process.
Per-call model names (including UI defaults) do not select the current assistant's
model; the current conversation controls that. Image APIs are separate.

To switch all shared text calls, change `SAGE_LLM_PROVIDER` in `llm-config.json`.
Existing environment overrides still win. For an API provider, also configure its
model, endpoint and credentials as appropriate; do not store secrets in Git.

Scripts persist the prompt as `logs/agent_requests/<sha256>/request.json` under
the current book, emit `SAGE_AGENT_PENDING`, and stop without writing fabricated
output. The recorded state is `waiting_for_agent`; legacy script/GUI wrappers
may still display a nonzero exit or generic failure message. No background
conversation is automatically started. The active assistant must read the task,
write a sibling `response.json`, and rerun the original command:

```json
{
  "request_id": "copy the request_id from request.json",
  "provider": "codex_agent",
  "status": "completed",
  "text": "The completed text, or serialized JSON required by the task"
}
```

The adapter checks ID, provider, completion state and nonempty text before
returning it to the original script. Prompt, system instructions and output
budget determine the ID. Identical requests reuse the answer; archive that
specific response before requesting a fresh revision with identical inputs.
The optional `SAGE_LLM_AGENT_REQUEST_ROOT` overrides the queue directory.
Without a book context it defaults to ignored `engine/work/agent_requests`.
This protocol does not certify factual accuracy; normal review still applies.

Other assistants could implement this handoff pattern, but Work Buddy support
has not been implemented or verified. The `codex` mode below is a separate CLI
execution mode, not the current conversation.

## OpenAI defaults

Select provider `openai` and supply an API key. The built-in model default is `gpt-5.6` and the default API style is Responses API.

```powershell
$env:SAGE_LLM_PROVIDER = "openai"
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
