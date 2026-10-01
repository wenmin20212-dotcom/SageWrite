# Stage 05 Export Routing

## Route table

| Deliverable | MCP tool | PowerShell fallback | Standard output |
|---|---|---|---|
| Formal DOCX | `sagewrite_build_manuscript` | `05-build.ps1` | `04_output/<language>/<BookName>_full.docx` |
| Simple upload DOCX | `sagewrite_build_simple_docx` | `05a-simple-docx.ps1` | `04_output/<language>/<BookName>_upload.docx` |
| Simple upload DOCX with TOC | `sagewrite_build_simple_docx_toc` | `05aa-simple-docx-toc.ps1` | `04_output/<language>/<BookName>_upload_toc.docx` |
| EPUB | `sagewrite_export_epub` | `05b-epub.ps1` | `04_output/<language>/<BookName>_full.epub` |
| Reading PDF | `sagewrite_export_pdf` | `05c-pdf.ps1` | `04_output/<language>/<BookName>_full.pdf` |
| Print DOCX | `sagewrite_build_print_docx` | `05ca-print-docx.ps1` | `04_output/<language>/<BookName>_print.docx` |
| Print PDF | `sagewrite_export_print_pdf` | `05cc-print-pdf.ps1` | `04_output/<language>/<BookName>_print.pdf` |

The simple routes are upload conveniences based on `python-docx`. They are not substitutes for the formal publication layout or its acceptance checks. `AutoNumber` is ignored by the simple builders even though it is accepted for interface consistency.

## Shared preflight

Formal, EPUB, reading-PDF, and print routes require a valid 04F stamp bound to the current manuscript, TOC, reference state, book definition, cover, resources, and relevant program files. Any change can invalidate it. Run:

1. `sagewrite_format_preflight` with `mode: Check` after final inputs are in place.
2. The selected stage-05 MCP tool.
3. Format-specific inspection of the new artifact.

Do not manually patch the stamp. Do not use `Normalize` as an automatic retry; it changes manuscript formatting. A preflight pass does not prove that Word/Pandoc rendered every page correctly.

## Formal DOCX and reading PDF

`sagewrite_export_pdf` verifies preflight, rebuilds the latest formal DOCX through `05-build.ps1`, verifies that inputs did not change during the build, and then uses Word COM to export PDF. It must not fall back to an older DOCX after a failed rebuild.

The exact route is Markdown -> Pandoc -> latest full DOCX -> `Word.Application` COM -> PDF. Pandoc does not render this PDF directly. If 05-build embeds a cover from the source root or `02_chapters` (PNG/JPG/JPEG/WebP), 05c skips its additional `00_intake/cover.png` insertion to avoid duplicate covers; otherwise that intake image remains its fallback.

On 2026-10-01, the Chinese reading-PDF route was tested on Windows with 24 manuscript units, a cover and three illustrations. The unmodified rendering route failed inside the agent sandbox with `80040154`, then succeeded outside it. The desktop `Word.Application` registration pointed to WPS `wps.exe /Automation` in the 32-bit registry view. After cover de-duplication, the exported PDF had 49 pages; representative Chinese body, cover, TOC and illustration pages were inspected. This is evidence for that provider and environment, not general WPS compatibility or print-PDF acceptance.

Check at minimum:

- expected cover and title metadata;
- navigable and correctly ordered TOC;
- every intended chapter and no unintended chapter;
- chapter starts and section breaks;
- no running header on each chapter-opening page when required by the writing/layout specification;
- book title and current chapter title on the appropriate normal-page headers;
- visible, sequential page numbers in the intended footer position;
- no clipped, overlapping, blank, or duplicated content;
- images, captions, citations, references, and final page.

When `outputPath` is supplied for reading PDF, resolve it to an intentional absolute destination and report it. The generated formal DOCX remains in the standard language output directory.

## EPUB

`sagewrite_export_epub` builds directly with Pandoc, includes an available cover, sanitizes unsupported CSS rules, and backs up an existing EPUB. The old `04b-epub.ps1` inspector may look in a legacy root path; do not use it as proof that the new language-scoped EPUB passed inspection unless its target path has been confirmed.

Validate:

- EPUB container can be opened and package metadata is parseable;
- title, author, language, and cover are correct;
- navigation document contains the intended hierarchy and order;
- each chapter opens and text is readable;
- images and styles resolve inside the package;
- internal links and citation/reference links work;
- no source paths, prompt residue, temporary files, or duplicate cover/title pages appear.

## Print outputs

Use `sagewrite_build_print_docx` for editable pagination review. Use `sagewrite_export_print_pdf` only after the print DOCX route and layout rules are appropriate; it rebuilds the latest print DOCX before Word export.

In addition to ordinary content checks, verify trim size, portrait/landscape intent, inside/outside margins, gutter, odd/even page behavior, chapter recto policy, intentionally blank pages, image resolution, bleed when applicable, font embedding/substitution, and total page count. A reading PDF is not automatically a print-ready PDF.

`kdp-png-to-pdf.ps1` converts PNG pages for a separate KDP-oriented workflow. It is not a manuscript PDF builder and has no stage-05 MCP route here.

## Failure handling

- Missing/stale preflight: stop, run 04F Check, fix findings, and retry only after it passes.
- Missing Pandoc/Python/COM provider: report the exact dependency; do not substitute another output and label it equivalent.
- `Word.Application` / `80040154`: distinguish a genuinely absent registration from sandbox restrictions and user/session or registry-view differences. Inspect the desktop registration in both registry views, and retry the identical command outside the sandbox only through the host's authorized permission mechanism. Never infer missing Office solely from one restricted-process probe. The MCP server's child process inherits its host restrictions and cannot grant itself access.
- Locked output: ask the user to close the file or sync process, then rerun once.
- Build fails after backing up the prior output: report the backup and failure; do not present the backup as newly generated.
- Visual defect: retain the artifact as a failed preview, fix the relevant layout rule or source, repeat preflight, rebuild, and re-inspect.
- EPUB opens but navigation/assets fail: treat the build as failed acceptance even if the script exited successfully.
