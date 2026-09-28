---
name: sagewrite-write-chapters
description: Generate new SageWrite manuscript sections from an approved objective.md and toc.md by calling the 03 writing stage. Use when the user asks to write one selected TOC unit, a continuous range, or the complete new manuscript; do not use to define a book, generate its TOC, revise existing prose, translate chapters, or rebuild an imported manuscript.
---

# SageWrite Write Chapters

Write new manuscript content from the approved `TOC.md` and stop with reviewable Markdown drafts. Use `$sagewrite-generate-toc` first when the structural TOC is absent or has not been approved.

## Confirm the writing source

Resolve the intended `workspace-<BookName>/sagewrite/book`. Read both `00_brief/objective.md` and `01_outline/toc.md` from disk. Do not rely on a conversational summary or on `toc2.md`: the current `03-write.ps1` reads `toc.md` only.

Confirm that the objective and TOC agree on title, audience, type, thesis or narrative purpose, scope, and style. If the TOC has unresolved structural questions or the user is still changing it, stop before generating prose.

If `ReferenceGlossary` is requested, require and inspect `04_glossary/glossary.md`. Do not enable it merely because the directory exists.

## Map the requested scope

Build and show the mapping from numeric writing-unit index to its `###` TOC title before execution. `03-write.ps1` numbers files by `###` writing units; only when the TOC has no `###` headings does it fall back to `##` chapter headings. Therefore `-Chapter 8` usually means the eighth writing unit, not the book's eighth parent chapter.

Resolve natural-language requests such as “第二章”, “第三节”, or a title against the actual TOC. If the mapping is ambiguous, obtain clarification before writing.

Always pass an explicit selection:

- one unit: `Chapter`;
- a continuous inclusive range: `StartChapter` and `EndChapter`;
- the complete manuscript: omit those parameters only when the user explicitly requested the whole book.

For a large range, prefer a small first batch and review it before continuing unless the user clearly requested uninterrupted full generation. Do not interpret `MaxTokens` as a Chinese character target; it is a model-output limit. The script follows an explicit length requirement under the selected TOC unit, otherwise it targets approximately 2,100–2,400 Chinese characters of body text.

## Protect existing drafts

Inspect every target `02_chapters/NN.md` before execution. Existing files are skipped unless `Force` is used. Do not use `Force` merely to make a command run again.

When the user explicitly authorizes replacement, back up every affected chapter and any matching `00_brief/rewrite_notes/chapter-NN.md` before using `Force`. Preserve unrelated chapters and user edits. Do not run two writers concurrently against the same book.

Use `AdditionalInstructions` only for requirements that the user approved for the selected units. Check for old rewrite-note files so stale instructions are not mistaken for current intent. The saved objective and TOC remain authoritative.

## Execute stage 03

Prefer the MCP tool `sagewrite_write_chapters` when available. Pass the exact `bookName`, `workspaceRoot`, resolved unit selection, output-token limit, glossary choice, additional instructions, model override if explicitly selected, and `force` state.

If MCP is unavailable, run `engine/03-write.ps1` with Windows PowerShell and equivalent parameters. The unified LLM configuration in `00-llm.ps1` controls provider and default model; do not silently replace those settings.

When `codex_agent` returns `SAGE_AGENT_PENDING` or `WAITING: Current assistant response required`, treat it as a normal handoff. Read the generated request, return only the requested clean Markdown section through the established matching-response protocol, and rerun the same command. A multi-unit range may require one handoff and rerun per unfinished unit. Never claim the range is complete while a request remains pending.

The current writer prompt is optimized for structured professional sections. If the approved book is fiction, poetry, drama, or another form where “argument, evidence, mini-conclusion” would distort the work, pause and agree on suitable `AdditionalInstructions` or a program update before generating content. Do not silently force academic prose onto the book.

## Validate each generated file

After each run, inspect the actual files, not only the exit code. For every selected unit confirm:

- the expected `02_chapters/NN.md` exists, or is explicitly reported as skipped;
- frontmatter contains the correct `chapter_index`, exact TOC title, provider, and model label;
- the body contains only the selected writing unit, with no code fence, model commentary, prompt residue, adjacent section, or duplicate frontmatter;
- content follows the objective, TOC, style guidance, approved additional instructions, and glossary when enabled;
- names, terms, facts, chronology, and cross-unit transitions remain consistent with already approved material;
- actual body length is measured and compared with the TOC requirement rather than inferred from token counts;
- logs distinguish generated, skipped, pending, and failed units.

If a range stops partway, preserve completed files, identify the first unfinished unit, and resume only the remaining scope. Do not restart with `Force` over completed work.

Report the resolved mapping, generated and skipped files, actual body lengths, provider/model, pending or failed units, backups, and review concerns. Clearly state that these are drafts awaiting author review and that no editing, formatting approval, or PDF build has been completed.
