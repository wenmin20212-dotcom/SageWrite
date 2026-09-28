---
name: sagewrite-generate-toc
description: Generate and validate a SageWrite table of contents from an initialized book's objective.md when the user asks to create, regenerate, or review the structural TOC. Use after new-book intake is complete; do not use to define the book, expand sections into toc2.md, write chapters, or derive a TOC from an existing manuscript.
---

# SageWrite Generate TOC

Create `01_outline/toc.md` from the approved book definition, then stop for author review. Treat `00_brief/objective.md` as the source of truth; conversation memory is not a substitute for the saved definition.

## Confirm the prerequisite

Resolve the intended `workspace-<BookName>/sagewrite/book` and read `00_brief/objective.md`. Require a usable title, audience, type, core thesis, scope, and style. If the definition is missing, incomplete, internally contradictory, or no longer matches the user's stated intent, use `$sagewrite-new-book` when available, or otherwise return to the new-book definition stage, before generating a TOC.

Do not infer that any currently open directory is the intended book. Confirm `BookName` and the workspace parent from project context or the user request.

## Protect an existing TOC

`02-structure.ps1` writes directly to `01_outline/toc.md`. If that file already exists, inspect it and report that regeneration will replace it. Do not regenerate unless the user explicitly requested replacement. Before an authorized replacement, preserve the existing TOC in the book's backup area with a timestamp and retain its original filename in the backup path.

If chapter files already exist, explain that changing the TOC may invalidate chapter mappings, cross-references, images, and later format approvals. Stop for explicit direction unless the user has clearly authorized restructuring the existing book.

## Generate from the saved definition

Prefer the SageWrite MCP tool `sagewrite_generate_toc` when available. Pass the exact `bookName` and the intended `workspaceRoot` when needed. If MCP is unavailable, run `engine/02-structure.ps1 -BookName <BookName>` with Windows PowerShell in the SageWrite installation.

The generator uses the unified LLM configuration in `00-llm.ps1`. Do not silently change provider, model, endpoint, or credentials. If configuration is invalid, report the missing or inconsistent setting without fabricating a TOC.

When the provider is `codex_agent`, `SAGE_AGENT_PENDING` or `WAITING: Current assistant response required` is a normal handoff state. Read the generated request, produce only the requested Markdown TOC body, save a valid matching response through the established agent-handoff protocol, and rerun the same command. Never claim completion while only a request file exists.

## Preserve the structural contract

The generated body must follow the contract expected by the current writing pipeline:

- chapter headings use `## Chapter title`;
- writing-unit headings use exactly `### Chapter.Section Title`;
- section numbering is present, continuous, and belongs to its chapter;
- do not use bullets as substitutes for section headings;
- do not introduce `####` or deeper heading levels;
- chapter and section names remain within the objective's audience, thesis, scope, type, and style.

Do not impose a chapter count that the approved objective does not support. If the objective specifies a count or organization, preserve it. If it does not, choose a proportionate structure and state the resulting chapter and section counts for review.

The current generator prompt is strongest for structured nonfiction. For fiction, poetry, or another form where numbered subsections would distort the work, do not force an academic outline. Explain the mismatch and obtain direction before changing the pipeline contract or creating a custom TOC manually.

## Validate the saved artifact

After the command finishes, read the actual saved `01_outline/toc.md` and verify:

- frontmatter identifies `file_role: toc` and `layer: structure`;
- there is at least one chapter and at least one writing unit;
- headings and numbering satisfy the structural contract;
- no code fences, model commentary, prompt text, duplicated headings, or empty headings remain;
- the progression covers the approved scope without obvious omissions, repetition, or out-of-scope expansion;
- run status records a successful structure step.

Formatting defects may be corrected deterministically without changing content. Material changes to chapter topics, ordering, scope, or count require author review rather than silent rewriting.

Report the TOC path, provider/model when available, chapter count, writing-unit count, backup path if regeneration occurred, validation findings, and unresolved structural questions. Clearly state that the TOC awaits author approval and that no chapter prose has been generated.
