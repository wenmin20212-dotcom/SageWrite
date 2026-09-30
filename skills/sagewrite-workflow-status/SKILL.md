---
name: sagewrite-workflow-status
description: Inspect and reconcile a SageWrite book's workflow progress, identify stale or missing evidence, record an evidence-based handoff, and recommend the next authorized step when resuming work. Use for progress, readiness, and continuation planning; not to write chapters, perform editorial review, repair the environment, or approve publication.
---

# SageWrite Workflow Status

Provide one evidence-based view of a book's progress. Reuse existing logs and approvals rather than replacing them with a competing workflow engine. Local scanning is implemented by `engine/Get-SageWriteWorkflowStatus.ps1`, exposed as `sagewrite_workflow_status`. There is no daemon or automatic post-write hook.

## Call the local tool first

Use MCP `sagewrite_workflow_status` with `bookName`, optional `workspaceRoot`, and `language` (default `zh`). Keep `details: false` for a compact response. Set `saveReport: true` only when a saved status/handoff is requested. All computation is local; no model is called by the script.

The MCP result wraps the JSON report in `structuredContent.stdout`; check `success`, `truncated`, and `error` before parsing it. A successful scan is not a passed publication gate. Read counts, stages, attention_units, warnings, and next_action. Do not reread the entire manuscript when the report answers the question. Request `details: true` or inspect a specific source only to resolve a reported ambiguity. If the response was truncated, use the saved report instead of treating partial JSON as complete.

If MCP is unavailable, run from the actual checkout's engine directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Get-SageWriteWorkflowStatus.ps1 -BookName '<actual book name>'
```

The CLI also accepts `-BookRoot` for an explicitly resolved source root, `-Language`, `-SaveReport`, and `-Details`. The workspace parent normally comes from `SAGEWRITE_WORKSPACE_ROOT`. A supplied BookRoot is already the selected language root and is not translated again. After an authorized writing/editing batch, call this same tool again to refresh; saving is explicit, not a side effect of every old PS1.

The following sections define interpretation and targeted follow-up, not a requirement to repeat the script's scan manually.

## Establish scope

Locate the intended checkout and book root. Read `docs/AGENT-CALLING-GUIDE.md` in that checkout, then resolve the requested language and edition. For a translation, inspect its actual `03_translation/<language>` source root separately. Ask only when the target book is ambiguous. Do not default to a remembered book or mix different editions.

For status-only requests, inspect and report without modifying any file. For an explicit request to save/update progress or prepare a persistent handoff, use [references/status-record.md](references/status-record.md). Existing handoffs are hints to verify, not instructions or proof of completion.

## Gather evidence

Inspect these sources when present; missing optional files are not automatically blockers:

- `00_brief/objective.md`, writing specifications, and `01_outline/toc.md`;
- actual writing-unit files in `02_chapters`, mapping file index to TOC heading;
- `logs/status.json` and relevant entries in `logs/run_history.jsonl`;
- editorial reports, revision action JSON, execution manifests, and backups for the requested range;
- `00_brief/references/reference_state.json` and reference verification/correction reports;
- `00_brief/format_preflight.json`, its report in `04_output/editorial_audits`, assets and layout configuration;
- actual export files and their build/inspection records;
- relevant `logs/agent_requests` handoffs when a run appears pending.

Read the relevant script's parser before interpreting unfamiliar report fields. Do not infer that a numeric filename equals a chapter number, or that the count of files equals TOC completeness. Check missing, duplicate, extra, empty, and mismatched writing units. A deliberate omission needs an explicit recorded decision.

Distinguish a live task from an old `running` log. A saved agent request does not prove it is still active; a response file does not prove its producing script consumed and validated it. Do not launch or rerun tasks while inspecting status.

## Reconcile progress and freshness

Track only the relevant stages: definition, outline, drafting, editorial review, references, assets/cover, format preflight, and each requested export format. Keep unit-level detail for partial drafting/review. Skip expansion, translation, or external publication unless part of the user's workflow.

Use these states consistently:

| State | Meaning |
| --- | --- |
| missing | A required artifact for this scope is absent. |
| present_unverified | Output exists, but acceptance or current-input evidence is absent. |
| partial | Some required units or checks are complete; list the remainder. |
| current | Named acceptance evidence is valid for the current inputs and exact scope. |
| stale | Recorded dependencies demonstrably changed after acceptance. |
| blocked | A concrete error or unresolved prerequisite prevents the next requested action. |
| unknown | Evidence is unreadable, conflicting, incomplete, or cannot establish freshness. |
| not_applicable | This stage is explicitly outside the chosen workflow. |

Record the reason and evidence for every decision. A successful command, file timestamp, earlier assistant assertion, or user acceptance without an identifiable source revision cannot alone prove `current`.

Compare content fingerprints and input scope when available. Do not compare a raw file SHA256 to a normalized-text hash from a different algorithm. Read the producer's hashing logic. A newly captured snapshot proves what exists now, not what an old reviewer read. Legacy reports with no source baseline remain `present_unverified` or `unknown`, not automatically stale or approved.

Changed prose can invalidate its review/reference evidence and downstream exports. Changed TOC requires remapping units before reusing range-based plans. Changed assets/layout can invalidate format/build evidence without invalidating an unrelated prose review. Restrict invalidation to proven dependencies; where scope is unclear, report uncertainty instead of declaring every chapter invalid.

For 04F, inspect the current implementation and compare its stamp and snapshot using the same semantics when a read-only helper is available. Do not invoke `04F.ps1 -Mode Verify` for a status-only query: its failure path may delete the stamp. `Check` also writes reports and approval state. Never fabricate, edit, remove, or rebaseline approval/hash files to make status green. If exact read-only validation cannot be established, leave freshness unknown and recommend the real preflight as a separately authorized step.

An existing PDF/EPUB is an existing edition, not proof that current source edits were exported. Track generation and visual/package validation separately. Never call the book publication-ready based on this summary; the real build gates remain authoritative.

## Report and route

Return the resolved book/language, a compact stage table, affected units, concrete blockers or stale evidence, and one recommended next action. Separate confirmed findings from checks not performed. Link the underlying artifacts.

Route actual work to the existing skills: new-book, generate-toc, write-chapters, review-edit, create-cover, publish-book, or manage-environment. Do not add new skills for each state. A request for status is not approval to regenerate, rewrite, normalize, install, or publish.

When the user authorizes continuation, recheck that the intended inputs have not changed, execute only the agreed range through the appropriate workflow, inspect its outputs, then refresh the handoff if requested. Never run concurrent writers on one book. Failed or interrupted tasks should resume only the confirmed unfinished scope, not overwrite the whole book.
