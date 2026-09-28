---
name: sagewrite-review-edit
description: Review, diagnose, revise, fact-check, normalize, or structurally edit an existing SageWrite manuscript through the 04-stage workflows and their MCP tools. Use when the user asks for editorial review, an actionable revision plan, execution of approved edits, external-audit ingestion, repetition analysis, reference verification, formatting preflight, deterministic heading cleanup, or safe removal and renumbering of a writing unit. Do not use to define a new book, generate a TOC, draft new chapters from a TOC, or export PDF/EPUB.
---

# SageWrite Review And Edit

Treat stage 04 as a router, not one generic editing command. Read `references/tool-routing.md` before choosing a workflow.

## Establish the manuscript state

Resolve `workspace-<BookName>/sagewrite/book` and inspect `00_brief/objective.md`, `01_outline/toc.md`, the target `02_chapters/*.md`, and any existing `03_rewrite`, editorial-audit, reference, or preflight artifacts. Map numeric file indices to actual TOC writing-unit headings before selecting a range. A file index is not necessarily the reader-facing chapter number.

Determine whether the user wants diagnosis only, a proposed plan, or an authorized mutation. Do not infer permission to modify prose or structure from a request to review, inspect, audit, check, or report.

## Route to one primary workflow

Choose the narrowest applicable MCP tool:

- deterministic heading and manuscript cleanup: `sagewrite_edit_book`;
- editorial advice plus action JSON without rewriting: `sagewrite_editorial_action_review`;
- section-length statistics: `sagewrite_part_budget_statistics`;
- one diagnostic editorial round, optionally followed by an authorized rewrite: `sagewrite_editorial_loop`;
- import a third-party audit: `sagewrite_import_third_party_audit`;
- prepare or execute a broad accepted-audit rewrite: `sagewrite_accepted_audit_rewrite`;
- apply an already reviewed action plan: `sagewrite_execute_revision_plan`;
- detect repetition and stock phrases: `sagewrite_repeat_audit`;
- reference planning/application/checking: `sagewrite_reference_workflow`;
- actual source-evidence recording and verification status: `sagewrite_reference_verification`;
- preview/apply approved reference metadata corrections: `sagewrite_apply_reference_changes`;
- formatting gate before stage 05: `sagewrite_format_preflight`;
- remove and renumber one writing unit: `sagewrite_remove_section`.

Do not run both a short wrapper such as `04B33.ps1` and its long implementation script. The MCP tools already choose one canonical entry point.

## Protect the manuscript

Use report-only and preview modes first. `DryRun` can still create reports; it means the manuscript is not rewritten, not that the command has no filesystem output.

Before any real mutation, show the resolved book, file-index-to-heading mapping, affected range, input plan or evidence, expected outputs, and backup location. Obtain explicit authorization for `applyRewrite`, a non-dry revision executor, `Normalize`, reference `Apply`, section removal, or any accepted-audit rewrite that can alter the TOC or chapters.

Never run concurrent writers or editors against the same book. Confirm that a saved plan still matches the current manuscript and TOC before applying it. Preserve unrelated user changes and stop if the target files changed after the plan was generated.

## Execute and validate

Prefer the MCP tools. If MCP is unavailable, use the exact PowerShell fallback listed in `references/tool-routing.md` with equivalent parameters. Let `00-llm.ps1` select the configured provider and model unless the user explicitly chooses an override.

After execution, inspect artifacts and affected Markdown files rather than trusting only the exit code. Verify scope, backups, modified files, unresolved actions, reference evidence state, and any pending agent handoff. Re-run the corresponding report/check workflow after a mutation.

For an ordinary review-then-revise request, use this sequence:

1. Run `sagewrite_editorial_action_review` with `dryRun: true` to verify scope.
2. Run it normally to create the report and action JSON.
3. Present the proposed actions and obtain approval.
4. Run `sagewrite_execute_revision_plan` with `dryRun: true`.
5. After explicit authorization, run it with `dryRun: false`.
6. Re-run the review on the changed range and report remaining issues.

Report which stage-04 route was chosen, why alternatives were not used, inputs, outputs, affected files, backup paths, provider/model when applicable, validation results, and any remaining author decisions. Do not claim the book is publication-ready until `sagewrite_format_preflight` succeeds in the required mode and the stage-05 build is separately completed.
