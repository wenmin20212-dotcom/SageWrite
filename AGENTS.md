# SageWrite agent writing

Read `engine/llm-config.json` and `engine/LLM-CONFIG.md` before model-backed work.
`SAGE_LLM_*` environment variables override the shared file.

When the provider is `codex_agent`, the current assistant does the authorized
research, writing and editing. Do not try the OpenAI API first and do not launch
`codex exec`. Keep the existing SageWrite objective, TOC, numeric manuscript
files, review and build workflow.

For a script-based task, run the requested script to obtain its exact prompt.
`SAGE_AGENT_PENDING` identifies `request.json` in the book's
`logs/agent_requests/<request_id>/` directory. This is a handoff, not generated
text. Read the request in the context of the user's authorization, complete the
work, and use apply_patch to create sibling `response.json` with `request_id`,
`provider: "codex_agent"`, `status: "completed"`, and `text` containing the
requested output. JSON tasks require a valid JSON string inside `text`.
Re-run the identical command so the original script validates/saves the output.
Inspect artifacts before claiming success. Changed prompts receive new IDs.
Responses are reused only for identical prompts and token constraints; remove
or archive the specific response only when a fresh revision is intended.

Do not claim a standalone UI/terminal can wake the current conversation. It
requires an active assistant to handle the request. Do not invent API token
usage, underlying model identity, or a Work Buddy integration. Preserve old
generation provenance; new direct-agent writing is `codex_agent`.
