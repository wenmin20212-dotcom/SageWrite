# Structure Import and Rewrite

`01b-import-structure.ps1` converts one structure-oriented source file into a SageWrite book plan.

Outputs:

- `00_brief/objective.md`: normalized book definition
- `01_outline/structure_summary.md`: concise overview
- `01_outline/toc.md`: normalized chapter and section directory
- `01_outline/structure_tasks.md`: checkbox task list
- `01_outline/cards/*.md`: one Markdown structure card per chapter
- `01_outline/structure_import_manifest.json`: traceable run metadata

Supported inputs are Markdown, text, JSON, YAML, and DOCX. DOCX requires Pandoc.

Always preview first:

```powershell
.\01b-import-structure.ps1 -BookName Demo -SourcePath D:\input\structure.docx -Mode Preview
```

The command prints the preview output directory under the book's `logs` folder. Review it, then apply:

```powershell
.\01b-import-structure.ps1 -BookName Demo -SourcePath D:\input\structure.docx -Mode Apply -Force
```

`Apply` refuses to replace existing core structure files unless `-Force` is supplied. Existing files and cards are copied to a timestamped folder under `back` before replacement.
