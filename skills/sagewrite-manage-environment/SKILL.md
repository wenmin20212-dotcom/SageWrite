---
name: sagewrite-manage-environment
description: Inspect SageWrite installation prerequisites, explain environment reports, plan and perform authorized dependency or configuration repairs, and recheck a new or existing computer. Use for installation, migration, or environment failures; not for manuscript review, book workflow status, or publication approval.
---

# SageWrite Environment Management

Manage inspection and repair in one skill. Reuse the environment doctor; do not create a second dependency checker or automatically install everything.

## Locate and inspect

Locate the intended SageWrite checkout containing `engine/Test-SageWriteEnvironment.ps1`. In a repository installation it is two directories above this skill. If the skill was copied elsewhere, use the user's checkout or current workspace; ask when multiple checkouts could be targets. Never assume the original author's drive or home directory.

Read `engine/ENVIRONMENT-CHECK.md` and the relevant sections of `docs/ENVIRONMENT-RESTORE.md` in that checkout. Before model configuration changes, read `engine/LLM-CONFIG.md` and `engine/00-llm.ps1`: the current adapter is authoritative if older installation notes describe only OpenAI. Preserve the selected provider; `codex_agent` does not inherently require an API key.

Choose the requested profile: `Core`, `Writing`, `Web`, `Pdf`, `Epub`, `Mcp`, `Images`, or `SimpleDocx`. Use `All` for a full installation audit. Resolve the intended workspace parent, not the book directory, before supplying `-WorkspaceRoot`.

Run from the checkout's `engine` directory, substituting the chosen profile:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Test-SageWriteEnvironment.ps1 -Profile All -Json -ReportDirectory .\work\environment-reports
```

Report output is the only write requested by this command. Read the new JSON report even when the exit code is 1. Exit 1 means a selected check failed, not that every capability is broken. If execution fails before producing valid JSON, report an execution failure; do not infer check results. If Windows PowerShell is absent, explain that bootstrap prerequisite rather than claiming a completed audit.

Interpret `pass`, `fail`, `warn`, and `unverified` separately. `requires_validation` and exit 0 are not end-to-end readiness. Report selected capabilities and blockers; optional MCP failure must not block an otherwise unrelated writing task.

## Plan repair

For each actionable finding, state the check ID and area, proposed action, affected file or installation scope, expected effect, rollback approach, and whether user action or permission is needed. Group fixes for the requested capability; leave unrelated optional tools alone.

- Dependencies: inspect the repository's current manifests and lockfiles, and use its documented install route. Do not guess package versions or download commands from report text.
- Configuration: resolve paths on this computer, preserve unrelated settings and existing providers, and keep Web and PS1 workspace parents consistent.
- Credentials, login, licenses, and billing: require the user's secure configuration or explicit authorization. Never ask for secrets in chat or serialize them into reports.
- Unverified runtime checks: offer a bounded smoke test separately. Starting Word, services, a paid model request, or external publishing is not authorized by a request for static inspection.

Stop after the report and plan when the user requested only inspection. For repairs, obtain approval for the concrete changes unless the current request already authorizes those changes. No automatic elevated install, firewall change, public network listener, global execution-policy change, or remote publication.

## Repair and recheck

Execute only the approved subset. Back up changed configuration before edits and retain restrictive permissions; credential-bearing backups must stay local outside version control. Do not put secrets in command arguments, DryRun output, logs, or Git commits. Prefer project-local dependencies where the existing installation route supports them.

Record a redacted repair log in the local report directory: original report, approved actions, files affected, backup locations, command outcomes, and skipped or blocked items. Do not copy raw environment variables or raw installer output into that log. On failure, stop that repair chain, record the partial state, and avoid repeated install attempts or unrelated upgrades.

Rerun the same profile and workspace against the repaired environment, creating a new report. Link before/after reports and distinguish resolved failures from remaining warnings and unverified behavior. If a separately authorized smoke test ran, report its actual artifact or result. A static pass does not prove Word activation, model access, or successful book export.

Do not modify manuscript files, mark a book stage complete, or issue 04F approval. Environment management ends with the report, repair record when applicable, and remaining user actions.
