# Workflow Report Contract

Use MCP `sagewrite_workflow_status` or `engine/Get-SageWriteWorkflowStatus.ps1`. This is an advisory snapshot, not a new approval format recognized by 03, 04F, or 05. Do not hand-author computed fields.

## Storage and evidence

Default inspection is read-only. `saveReport: true` / `-SaveReport` creates a unique UTF-8 JSON under the selected source root's `logs/workflow_status/`. The full report is saved before returning the compact response. Existing reports and native status files are preserved. No API keys, environment dumps, or request prompts are collected.

The script records book-relative input paths and raw-byte SHA256 using the existing native file-digest helper. Missing files are explicit. Native 04F snapshot verification is performed separately with its own engine-inclusive fingerprint semantics; 04R manuscript comparisons use normalized text, not raw-byte hashes.

Hash the relevant input set before and after inspection. If the set or hashes changed while reading, mark the affected assessment `unknown` and explain the concurrent change. Read-only snapshots do not lock the book. Do not record a coherent current state across mixed revisions.

## Fields

- `schema_version`: 1.
- `record_type`: `sagewrite_workflow_advisory`.
- `observed_at`: UTC ISO 8601 observation time.
- `book_root`, `language`, `engine_root`: explicitly resolved identity; these local paths are not portable configuration.
- `stable`: whether the observed inventory was unchanged across the scan.
- `counts`: expected units, mapped drafts, remaining units and extra files.
- `inputs`: path, existence, algorithm and sha256; included in saved/detailed output.
- `units`: index, file, title, state and reason; included in saved/detailed output.
- `stages`: id, state, reason and evidence paths.
- `extra_files`: unexpected buildable files.
- `run_summary`: limited historical telemetry, not live process detection.
- `next_action`, `warnings`, `limitations`: guidance and uncertainty, not permission to modify files.
- `report_path`: new saved report path, or null.
- Compact responses replace inputs/units with at most 20 `attention_units` and `attention_truncated`.
- Compact stage evidence is limited to 10 paths with `evidence_count`; saved/detailed output retains all paths.

Legacy editorial reports remain present_unverified without interpretable acceptance evidence. Native 04R hash drift is detected, but reference correctness and claim-level support are not certified. Do not invent dates, approvals, or historical hashes.

Exports remain present_unverified: existence cannot establish current-source generation or visual/package acceptance.

## Validate and resume

Check the MCP runner envelope's success/error/truncated fields, then parse stdout JSON. Exit 0 means scanning succeeded even if stages are missing or blocked. Saving errors are execution failures, not successful reports.

On resumption or after a batch, call the tool again to recompute current facts. It does not automatically run after other scripts, and does not infer full approval because hashes match. Nonstandard editorial report locations may need targeted follow-up.

There is deliberately no mutable `latest.json` pointer or auto-completion flag. Choose an applicable previous snapshot by its scope and observation time, then verify it. The engine's native logs and approval checks remain authoritative.
