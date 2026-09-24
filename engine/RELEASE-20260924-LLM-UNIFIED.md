# SageWrite 2026-09-24 LLM Unified

This version is based on `sagewrite-ps1-20260924` and preserves the upstream voice-writing, reference-review, formatting, publishing, web, installation, and packaging features.

## Added

- Central text-generation adapter in `engine/00-llm.ps1`.
- OpenAI defaults to `gpt-5.6`.
- Environment-configurable OpenAI-compatible Responses and Chat Completions endpoints.
- Local non-interactive Codex execution with `SAGE_LLM_PROVIDER=codex`.
- UTF-8-safe Codex stdin/stdout handling for Windows PowerShell 5.1.
- Optional PDF cover insertion from `00_intake/cover.png`.
- Optional PDF output path when an existing PDF is locked.

## Migrated text-generation scripts

- Structure and outline expansion.
- Chapter writing, translation, and translation refinement.
- Editorial review, editorial loop, accepted-audit rewrite, and revision execution.
- Cover assistant, cover copy, and Midjourney prompt generation.

Image-editing scripts keep their dedicated Images API multipart implementation because it is not compatible with the text-generation adapter contract.

## Validation

- 32 Python regression tests passed.
- 112 PowerShell scripts parsed successfully as UTF-8.
- No unresolved merge markers or whitespace errors.
- Text-generation scripts contain no direct OpenAI HTTP calls or hard-coded GPT model versions outside the shared adapter.
