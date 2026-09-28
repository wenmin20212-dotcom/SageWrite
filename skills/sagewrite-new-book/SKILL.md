---
name: sagewrite-new-book
description: Define and initialize a new SageWrite book project when the user wants to start a book, establish its objective, or create its initial workspace. Use for the intake stage only; do not use for importing an existing manuscript, generating a TOC, writing chapters, or revising an existing book.
---

# SageWrite New Book

Turn an early book idea into a clear, bounded SageWrite project and initialize its workspace. Stop after the intake artifacts are verified unless the user separately asks to continue.

## Establish the book definition

Collect or infer only what is needed for these fields:

- `BookName`: filesystem-safe project identifier; it may match the title but contains no path separators or Windows-invalid filename characters.
- `Title`: reader-facing book title.
- `Subtitle` and `Author`: optional; use an empty value when the user intentionally leaves either blank.
- `Audience`: the specific intended readers and their expected knowledge or reading level.
- `Type`: the actual form of the work, such as novel, biography, practical guide, academic monograph, or essay collection.
- `CoreThesis`: one concise statement of the central idea, promise, or narrative purpose that every chapter should serve.
- `Scope`: what the book covers, important limits, approximate depth or length when known, and material explicitly outside scope.
- `Style`: voice, tone, reading difficulty, point of view or evidence expectations that should govern later writing.

If required information is missing, ask a small number of focused questions. When the user's description supports a reasonable draft, propose concrete field values instead of asking them to restate everything. Do not invent an author name, factual premise, target reader, or creative constraint that could materially redirect the book.

Keep each field suitable for a single PowerShell argument: no embedded instructions, YAML blocks, or unrequested workflow steps. Preserve the user's language.

## Protect existing projects

Resolve the actual workspace parent before writing. The expected book path is `workspace-<BookName>/sagewrite/book` beneath `SAGEWRITE_WORKSPACE_ROOT`, or beneath the engine's default workspace parent when that setting is absent.

If the target workspace or `00_brief/objective.md` already exists, inspect it and report that this is an existing project. Do not rerun intake or replace its definition unless the user explicitly asks to redefine that project after seeing the existing values. This skill is for new books, not manuscript import.

## Initialize

Prefer the SageWrite MCP tool `sagewrite_initialize_book` when it is available. Pass exactly the agreed fields and the intended `workspaceRoot` when needed.

If the MCP tool is unavailable, run `engine/01-intake.ps1` with Windows PowerShell and the same parameters. `01-intake.ps1` automatically loads `00-common.ps1`; do not execute `00-common.ps1`, `00-layout.ps1`, or `00-llm.ps1` as standalone commands. The `00-*` files are shared libraries, not the new-book command.

Initialization is deterministic and does not require an LLM call. Do not run `02-structure.ps1`, generate `toc.md`, write chapters, create a cover, or build a PDF unless the user makes a separate request.

## Verify and report

Treat process startup as insufficient. Confirm that:

- the resolved workspace is the intended one;
- `00_brief/objective.md` exists and contains the agreed title, audience, type, core thesis, scope, and style;
- the standard book directories were created;
- `00_brief/amazon_description.md` exists;
- the intake status/log reports success when present.

Report the workspace path, objective path, the final book definition, and any optional fields left blank. Clearly say that only initialization is complete and that TOC generation has not started.
