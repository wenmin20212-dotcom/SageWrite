# SageWrite

SageWrite is a structured AI writing engine and local web workspace for planning, generating, reviewing, rewriting, and building long-form books.

SageWrite 是一套结构化的 AI 写作引擎与本地 Web 工作台，用于完成长篇书籍的规划、生成、检查、重写与构建。

## Overview

SageWrite combines PowerShell workflow scripts with a local browser-based control panel. It is designed for book-length writing projects that need clear structure, repeatable generation steps, editable intermediate files, and human-in-the-loop revision.

SageWrite 将 PowerShell 工作流脚本与本地浏览器控制台结合在一起，适合需要清晰结构、可重复生成流程、可编辑中间文件以及人工干预修订的长篇写作项目。

## Core Capabilities

- Initialize a book project from a single `objective.md` brief
- Generate and edit `toc.md`
- Expand outline sections
- Generate chapters one-by-one, by range, or all at once
- Add chapter-level rewrite instructions for targeted regeneration
- Browse and edit chapters directly in the web interface
- Run build preflight checks and view detailed bilingual reports
- Build final manuscript output from the generated book files

## Workflow

The main pipeline is:

`01-intake -> 02-structure -> 02b-expand -> 03-write -> 04-edit -> 05-build`

Each stage can be run independently from scripts or from the local Web UI.

## Repository Layout

```text
SageWrite/
  README.md
  .gitignore
  engine/
    00-common.ps1
    01-intake.ps1
    02-structure.ps1
    02b-expand.ps1
    03-write.ps1
    04-edit.ps1
    05-build.ps1
    06-web.ps1
    webui/
      server.js
      package.json
      public/
        index.html
        app.js
        styles.css
```

## Requirements

- Windows PowerShell
- Node.js
- `OPENAI_API_KEY` configured in the environment
- `pandoc` installed for the final document build step

## Quick Start

Run the local web interface:

```powershell
cd C:\Users\User\.openclaw\SageWrite\engine
.\06-web.ps1
```

Auto-open the browser:

```powershell
cd C:\Users\User\.openclaw\SageWrite\engine
.\06-web.ps1 -OpenBrowser
```

Then open:

[http://127.0.0.1:3210](http://127.0.0.1:3210)

## Main Files

- `objective.md`: project definition, writing goal, audience, scope, and style guidance
- `toc.md`: editable table of contents
- `02_chapters/*.md`: generated chapter files
- `edit_report.txt`: preflight inspection report
- `edit_report.json`: structured inspection report for the Web UI

## Web UI Features

- Project selection and status dashboard
- Editable project brief fields
- Editable TOC panel with save
- Chapter browser with previous/next navigation
- Chapter editor with save support
- Single-chapter rewrite with additional instructions
- Live script logs
- Preflight report display inside the `04` panel

## Notes

- The Web UI listens on `127.0.0.1` by default
- Existing chapter and TOC files can be edited directly in the interface
- The `04-edit.ps1` report is bilingual and includes a detailed checklist
- Token-limit detection for chapter truncation depends on token metadata written by newer `03-write.ps1` runs

## Philosophy

SageWrite is not the only possible writing system in the AI era. It is a representative engineering pattern: structured prompts, explicit files, script orchestration, local visibility, and human revision working together as a practical long-form writing workflow.

SageWrite 并不是 AI 时代唯一的写作系统，而是一种具有代表性的工程范式：通过结构化提示、显式文件、脚本编排、本地可观察性以及人工修订，构成一个可落地的长篇写作工作流。
