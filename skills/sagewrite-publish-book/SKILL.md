---
name: sagewrite-publish-book
description: Build and validate SageWrite publication files through the stage-05 workflows, including formal DOCX, PDF, EPUB, lightweight upload DOCX, and print-layout DOCX/PDF. Use when the user asks to generate, rebuild, package, or inspect book deliverables. Do not use to write or revise manuscript content, create a cover, or treat an unapproved draft as publication-ready.
---

# SageWrite Publish Book

Build publication artifacts only from the current approved manuscript. Read `references/export-routing.md` before selecting an output route, and use its format-specific validation checklist after generation.

## Establish the source edition

Resolve `workspace-<BookName>/sagewrite/book`. Confirm the requested language and source root:

- `zh` uses the primary book root;
- another language uses `03_translation/<language>` and must already contain a complete translated objective, TOC, and chapter set.

Inspect the objective, `01_outline/toc.md`, numeric `02_chapters/*.md`, `00_brief/writing_spec.md` when present, cover assets, referenced images, reference state, and existing outputs. Resolve whether the user wants the whole book or a deliberately prepared subset workspace. Stage 05 builds the chapter files present in the selected source root; it does not accept a chapter-range parameter.

## Require the publication gate

Run `sagewrite_format_preflight` in `Check` mode after manuscript, TOC, references, assets, cover, or layout rules change. Address failures before building. Stage-05 formal outputs verify the current 04F stamp and reject stale inputs; never edit the stamp or reuse an older artifact to bypass that check.

Use `Normalize` only with explicit authorization because it can change formatting. If the book uses the 04R reference workflow, require its `Check` result before final preflight.

Confirm local dependencies for the chosen route:

- formal DOCX and EPUB: Pandoc;
- PDF routes: Pandoc plus installed and activated desktop Microsoft Word with an interactive user session;
- simple DOCX routes: Python and `python-docx`;
- print routes: the approved print layout configuration and the same Word requirement for PDF.

## Choose one output route

Use the narrowest matching MCP tool:

- formal editable manuscript: `sagewrite_build_manuscript`;
- formal EPUB: `sagewrite_export_epub`;
- formal screen/reading PDF: `sagewrite_export_pdf`;
- lightweight upload DOCX without a generated TOC: `sagewrite_build_simple_docx`;
- lightweight upload DOCX with a generated TOC: `sagewrite_build_simple_docx_toc`;
- print-layout DOCX for pagination review: `sagewrite_build_print_docx`;
- print-layout PDF: `sagewrite_export_print_pdf`.

Do not run multiple builds for the same book concurrently. PDF tools rebuild their required DOCX first; do not separately launch the same DOCX build in parallel. Existing outputs are backed up before replacement. If an output is open or locked, stop and ask the user to close it rather than deleting or renaming around the lock.

Use `autoNumber` only when the TOC and layout rules deliberately rely on automatic numbering. Do not enable it to repair inconsistent headings. Use the PDF `outputPath` only when the user requests a specific destination; otherwise preserve the standard language output directory.

## Validate the deliverable

Treat script success as generation, not final acceptance. Inspect the newly created file, its timestamp and size, and the run status. Never report an older DOCX, PDF, or EPUB as the result of a failed build.

For PDF, render or inspect representative pages including the cover, title/TOC pages, the first page of multiple chapters, body pages, image pages, references, and final page. Confirm chapter-opening pages have no header where the layout requires it; normal pages must show the correct book/chapter running heads and page numbers without overlap.

For EPUB, inspect the package and reading structure, not only whether it is a valid ZIP. Confirm metadata, cover, navigation TOC, chapter order, images, internal links, citations, and readable text in an EPUB reader or equivalent parser.

For DOCX, inspect section breaks, TOC behavior, chapter starts, styles, headers/footers, page numbering, fonts, images, and references. Print files additionally require trim-size, margins, blank-page, binding-side, and pagination review.

Report the selected route, source language/root, preflight result, generated and backup paths, dependencies used, cover inclusion, chapter count, validation findings, and a clickable local link to each accepted artifact. Clearly distinguish a generated file from a visually approved publication file.
