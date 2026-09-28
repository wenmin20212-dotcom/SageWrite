# Cover Workflow

## Locations

- Installed publication cover: `00_intake/cover.png`
- 08n ebook workspace: `07_cover/next/ebook/`
- 08n print workspace: `07_cover/next/print/`
- Base-image imports: `07_cover/next/<edition>/imports/`
- Typography layouts: `07_cover/next/<edition>/layout/`
- Final manifests and collected outputs: `07_cover/next/<edition>/final/`
- Replaced installed-cover backups: `back/cover/`

Stage 05 reads `00_intake/cover.png`; merely generating an image under `07_cover` does not install it.

## MCP route

| Purpose | MCP tool | PowerShell fallback |
|---|---|---|
| Natural-language cover guidance | `sagewrite_cover_assist` | `07a-cover-assist.ps1` |
| Build 08n image-only brief | `sagewrite_cover_base_brief` | `08n-base-brief.ps1` |
| Build text-free image prompts | `sagewrite_cover_base_prompt` | `08n-base-prompt.ps1` |
| Review imported candidates | `sagewrite_cover_review` | `08n-base-review.ps1` |
| Add deterministic local typography | `sagewrite_cover_layout` | `08n-title-layout.ps1` |
| AI-edit an imported image | `sagewrite_cover_image_edit` | `08n-image-edit.ps1` |
| Create presentation mockup | `sagewrite_cover_mockup` | `08n-mockup.ps1` |
| Create print spread | `sagewrite_cover_print_spread` | `08n-print-spread.ps1` |
| Collect final outputs | `sagewrite_cover_export` | `08n-export.ps1` |
| Install approved front cover | `sagewrite_cover_install` | `07b-install-cover.ps1` |

## Ebook and reading-PDF route

1. Prepare brief and text-free prompts.
2. Generate real bitmap candidates with an image-generation tool.
3. Place candidates in the ebook imports directory.
4. Inspect visually, then record selection with the review tool.
5. Add title/subtitle/author through local layout, or explicitly authorized AI image edit.
6. Inspect Chinese text, crop, contrast, safe margins, and resolution.
7. Export the approved route.
8. Install the exact approved front image.
9. Re-run 04F Check and stage-05 PDF/EPUB export.

EPUB can package an available cover from the source tree, but use the installed canonical cover for consistent PDF/EPUB editions.

## Print route

Do not create a print spread until the interior page count and platform specifications are final. Required values include trim width/height, bleed, calculated spine width, page count, paper type assumptions, and DPI. Confirm barcode and publisher requirements separately. Inspect front, spine, back, bleed, fold/safe zones, and text orientation at full resolution.

## Automatic PDF handoff

`sagewrite_export_pdf` checks `00_intake/cover.png` before running `05c-pdf.ps1`. When missing and `autoPrepareCover` is true, it calls the cover-assistance script with `coverRequest` or a safe default, returns `coverRequired: true`, and points to `$sagewrite-create-cover`. It intentionally stops before PDF generation.

This is a resumable handoff, not a failure to be bypassed. Complete and install the approved cover, run 04F Check because the cover changed, then call the PDF tool again. Set `autoPrepareCover: false` only when the caller wants a pure missing-cover diagnostic.

## Acceptance checks

- exact title, subtitle, author, and publisher text;
- no accidental or model-generated lettering in the base image;
- correct visual subject, era, clothing, symbols, and cultural details;
- readable hierarchy at thumbnail and full size;
- adequate contrast without hiding important artwork;
- no clipped text and sufficient edge/safe margins;
- intended aspect ratio and at least 600x900 pixels for installation;
- no watermark, prompt residue, placeholder label, or mockup frame;
- print dimensions and spine values match the actual platform specification.
