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

## Installation handoff

After installation or migration, rerun the relevant environment profile against the final configuration and workspace. The installers invoke `engine/Complete-SageWriteInstallation.ps1` for Writing or Web; inspect its JSON output and saved report. Inspect additional profiles when the requested installation includes export or MCP. DryRun is only a preview and must not produce an installation-complete greeting.

Deliver a complete, readable text report directly in the Agent's conversation with the user, in their language. Terminal output or a report link alone is insufficient. Include actual installation actions, project version when known, project and workspace locations, checked capabilities and results, remaining blockers/warnings/unverified items, the saved report link, and a useful next step. Never include secrets. Distinguish static prerequisite checks from runtime tests and actual export verification.

When installation actions are complete and the intended scope has no blockers, welcome the user, for example:

> 欢迎使用 SageWrite！安装配置已完成，写作所需的静态环境检查已通过。您现在可以在当前 Agent 的协助下开始规划书籍。SageWrite 支持构思讨论、目录规划、章节写作、审稿修订与成书导出；具体导出功能以对应检查和实际验证结果为准。您无需先学习全部软件操作，可以直接告诉我想写什么书，或指定要继续处理的已有书稿。

Adapt this wording to the actual checked scope and follow it with the concrete report details. If blockers remain, say which setup steps completed and which capability is blocked; give next actions instead of claiming readiness. For an existing installation or inspection-only task, report its current state without claiming a new installation. No standalone script can wake a conversation: the active Agent must deliver this handoff.
