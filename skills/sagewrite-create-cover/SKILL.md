---
name: sagewrite-create-cover
description: Design, generate, review, typeset, export, and install a publication cover for a SageWrite book using the 07/08n cover workflow and image-generation tools. Use when a book needs a new or revised ebook/front cover, print spread, cover mockup, or when stage-05 PDF export reports that 00_intake/cover.png is missing. Do not use a placeholder image as a final cover or replace an approved cover without explicit authorization.
---

# SageWrite Create Cover

Create the cover before final 04F approval and stage-05 export. Read `references/cover-workflow.md` for the route matching ebook, reading PDF, or print output.

## Establish the cover brief

Resolve `workspace-<BookName>/sagewrite/book`. Read the approved objective, TOC, writing specification, and existing cover artifacts. Confirm title, subtitle, author, edition, audience, genre, visual direction, prohibited elements, and whether an existing cover must be preserved.

Use `sagewrite_cover_assist` for natural-language concept help. Use `sagewrite_cover_base_brief` and `sagewrite_cover_base_prompt` to create the 08n image-only brief and prompt package. A base image must contain no title, author name, letters, numbers, logos, or watermarks; typography is added after the image is approved.

## Generate and select the base image

Use the available image-generation capability to create real bitmap candidates from the approved prompt. The local `08n-base-generate.ps1` route creates placeholders and is deliberately not exposed as a publication MCP tool. Save or import real candidates into the 08n edition import directory described in the reference.

Inspect every candidate visually. Check subject accuracy, composition, genre fit, originality, text-free background, usable title space, resolution, and absence of malformed details. Use `sagewrite_cover_review` to create the local selection record only after real candidates replace placeholders.

## Add typography and output variants

Prefer `sagewrite_cover_layout` for deterministic local Chinese typography. Use `sagewrite_cover_image_edit` only when the user explicitly wants AI image editing and accepts API usage; inspect every rendered character because image models can corrupt Chinese text.

Use `sagewrite_cover_mockup` only for presentation. For print, obtain the real trim size, bleed, paper/page count, spine calculation, and DPI before calling `sagewrite_cover_print_spread`; never rely on its defaults as publication specifications.

Run `sagewrite_cover_export` to collect the approved outputs and manifest. Inspect the final front cover at full resolution. A successful manifest does not itself mean the image is approved.

## Install the publication cover

After the user approves one exact image, call `sagewrite_cover_install` with its explicit path. This converts and installs it as `00_intake/cover.png`. Replacing an existing installed cover requires explicit authorization and `force: true`; preserve the reported backup.

Installing or replacing the cover invalidates the previous format-preflight stamp. Run `sagewrite_format_preflight` in `Check` mode again, then resume `sagewrite_export_pdf`. The PDF MCP automatically detects a missing cover, prepares cover guidance, and returns this Skill as the required next step instead of creating a coverless PDF.

Report the brief and prompt paths, generated candidates, selected image, typography method, dimensions, edition, exported manifests, installed cover path, backup path, and remaining print specifications. Distinguish candidate, mockup, exported cover, installed cover, and accepted final cover.
