# Split a Word Document into Chapter Markdown Files

`01b-import-structure.ps1` performs a format-only split of one large DOCX or Markdown document. It does not call an LLM and does not rewrite chapter prose.

For a 36-chapter document, the primary output is `02_chapters/01.md` through `02_chapters/36.md`. It also creates `toc.md`, a split checklist, and a manifest so SageWrite can edit and merge the imported manuscript.

Apply the Word **Heading 1** style to every chapter title. Use Heading 2 and lower for sections. Tables, footnotes, paragraphs, and image links are converted by Pandoc.

```powershell
.\01b-import-structure.ps1 -BookName Demo -SourcePath D:\input\manuscript.docx -Mode Preview
```

Review the printed preview folder. Use `-ChapterHeadingLevel 2` for another Word heading level, `-SkipFirstHeading` if the first heading is the book title, or a regex such as `-ChapterPattern '^第.+章'`.

```powershell
.\01b-import-structure.ps1 -BookName Demo -SourcePath D:\input\manuscript.docx -Mode Apply
```

If numeric chapter files already exist, the script refuses replacement. After reviewing Preview, use `-Force`; existing chapters and TOC are backed up under `back/document-split-*` first.
