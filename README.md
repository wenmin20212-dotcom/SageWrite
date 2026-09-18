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

## 两种创作工作方式：网页操作与 AI Agent 对话

SageWrite 支持两种使用方式。它们不是两套独立的写书系统，而是操作同一套 PowerShell 引擎和书籍工作区的两种入口：**网页模式由人操作界面，Agent 模式由人与 AI 对话，再由 AI 操作系统。** 作者始终负责决定书的思想、结构及修改方向。

### 方式一：网页工作台

这是传统的图形界面操作方式，适合希望通过表单、按钮和日志控制创作过程的用户。

1. 按下面的安装说明准备环境，启动 `06-web.ps1`，或通过已配置的 `Start-SageWrite-Web.ps1` 启动工作台。
2. 在浏览器中选择或建立书籍项目，填写书籍定义、读者定位、核心思想和风格要求。
3. 通过界面中已有的功能生成、查看和修改目录，再选择写作单元进行生成或修订。
4. 检查执行日志与正文，按需要提交补充指令，继续审稿、修改和构建。
5. 完成参考文献与格式检查后，导出所需格式并查看实际成品。

网页是程序的操作入口，不是绕过检查的捷径。不同版本界面提供的按钮可能不同，不能假定所有新增 PS1 都已接入网页；界面未提供的步骤可由终端或 Agent 调用相应脚本完成。

### 方式二：Codex / AI Agent 对话式创作

这种方式以人与 AI 的讨论为起点。用户用自然语言说明意图，Agent 阅读当前目录和书稿，提出或落实修改，再调用 SageWrite 程序并检查结果。**这里的 Agent 是操作与协作层，SageWrite 是文件、流程与构建的执行层。** 不需要为了使用此方式而先打开网页，但 Agent 必须具备本地文件读写和命令执行权限；只有聊天能力、没有工作区访问权限的 AI 不能直接完成这些操作。

典型过程如下：

1. 用户提出任务，例如“先介绍第八章的结构”“只小修这一节”“继续写下一节”或“生成新版 PDF”。
2. Agent 确认书名、工作区、程序版本及任务范围，读取 `objective.md`、`toc.md`、相关正文、写作规范和已有审稿记录，不仅依赖聊天记忆。
3. 讨论阶段只呈现结构、问题和建议；用户要求实施后，Agent 备份受影响文件，修改目录或正文，或调用对应 PS1 生成内容。
4. Agent 检查生成结果，报告实际字数、修改范围、输出文件位置及尚未解决的问题，再根据用户反馈继续推进。
5. 成书阶段执行参考文献与格式检查，通过后调用构建程序，核验 PDF / EPUB，并把可直接打开的文件链接交给用户。

例如，用户可以说：“只调整第十三章目录，先不要写正文。”Agent 应只修改相关目录；用户说“按定稿目录写13.1”后，才进入正文生成。用户要求小修时，不得自行重写整章或重新编号全书。

Agent 可以调用 `03-write.ps1` 等程序生成正文，也可以在用户要求逐段讨论、定点精修时直接编辑 MD。两种操作都必须遵守同一份目录和写作规范，并重新完成受影响的检查。**Agent 自身的模型会话不会自动成为 PS1 的模型配置**；脚本调用模型时仍需其自身的 API 密钥、模型权限和配额。

### 给操作 Agent 的执行规则

- **确认映射再执行。** 书中章号、小节号和 `02_chapters` 内数字 MD 文件号不一定相同。先读取目录及正文标题，确认目标写作单元，再检查脚本参数含义；不要把“第八章”直接当成 `08.md` 或 `-Chapter 8`。
- **先读参数，后调用。** 以当前检出版本的脚本 `param` 和配套说明为准，不凭记忆猜参数。写作通常涉及 `01-intake`、`02-structure`、`02b-expand`、`03-write`；已有书稿不必从头重复执行整条流程。
- **区分生成、审稿与返修。** 根据任务选用对应工具，例如 `04B33` 形成逐节编辑意见、`04C44` 执行相应返修；先确认输入报告、目标范围和文件状态，不能把一次运行成功当成内容审核通过。
- **保护原稿。** 修改前将受影响文件备份到该书工作区的 `back` 下，或使用已验证会自动备份的程序。保留已有用户修改；没有明确要求，不使用覆盖参数，不批量重写或重排编号。
- **同步关联文件。** 标题、节数或术语变动时，检查 `toc.md`、正文标题、图片链接和跨章引用的一致性。插图和封面应保存在对应书籍工作区，不依赖另一台机器的临时路径。
- **不伪造学术依据。** 参考文献须真实核验；使用 `04R` 管理的书籍按其计划、应用和检查流程处理，不能用未核实的条目填补引用缺口。参见 [04R 说明](engine/04R-README.md)。
- **不绕过构建门槛。** 编辑检查与 `04F` 格式检查职责不同。正文或相关资源变动后，重新运行必要检查；正式导出必须通过有效的 `04F` 标记，不能手改标记或拿旧成品代替新结果。参见 [04F 说明](engine/04F-README.md)。
- **如实交付。** 明确区分“已修改文件”“已执行程序”“已验证成品”和“尚未完成”。仅返回聊天文字不等于已保存书稿；启动进程也不等于生成完成。未经用户要求，不自动发布作品、上传外部平台或移动既有锁版标签。

### 两种方式的衔接

用户可以先在网页建项目，再与 Agent 讨论精修，也可以让 Agent 完成操作后回网页查看。切换时必须使用相同的工作区父目录和 `BookName`；以磁盘上的实际文件为依据，刷新界面后再操作，避免旧编辑框覆盖新内容。不要让网页任务和 Agent 同时写入同一份目录、正文或构建产物。

两种入口共享相同的质量要求：思想与结构由作者确认，正文与目录保持一致，参考文献可核验，格式检查通过，最终文件实际可读。操作方式改变，不改变这些出版前提。

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

## 大模型配置与服务商兼容性

SageWrite 的正文生成、部分编辑审稿等功能需要调用大模型 API；本地格式检查与排版不等同于模型调用。当前 `03-write.ps1` 和 `04b33-editorial-action-review.ps1` 默认模型为 `gpt-5.5`，支持的具体参数以各脚本为准，不能假定所有脚本的默认模型都相同。

这不是操作 ChatGPT 聊天窗口，而是程序直接请求 OpenAI API。目标用户需自行提供有相应模型访问权限及可用配额的 API 密钥。ChatGPT 账号登录或订阅不能代替程序需要的 API 配置。

| 配置 | 当前实现 |
| --- | --- |
| 身份认证 | 从环境变量 `OPENAI_API_KEY` 读取密钥 |
| 模型选择 | 支持 `-Model` 的脚本可显式指定模型名称；不设置时使用该脚本默认值 |
| 服务地址与协议 | 当前相关生成、审稿脚本直接请求 `https://api.openai.com/v1/responses`，使用 OpenAI Responses API |

用户应在目标电脑安全地配置 `OPENAI_API_KEY`，并确保启动 SageWrite 的终端或进程能够读取它。环境配置变动后，通常需要重启相关终端、Web 服务或任务进程。Agent 只检查变量是否存在，不打印密钥，不将其写入 Git 仓库。Web 安装器也能将密钥写入本地配置，相关风险见下面的安装说明。

**目前不能仅替换密钥，就直接切换到豆包或其他服务商。** 更换模型名称也不会改变请求地址。支持其他服务商需要适配接口地址、认证方式、请求参数、响应解析、错误处理及相关脚本，再进行实际测试。服务商宣称“兼容 OpenAI”不一定意味着兼容本系统使用的 Responses API，不能未经验证就宣称可用。

安装 Agent 不应自行假定 `OPENAI_BASE_URL` 等环境变量已经生效；当前上述脚本的请求地址为固定值。如需多服务商支持，应作为单独的程序适配任务处理，而不是在安装过程中静默替换端点。操作 SageWrite 的外部 Agent 所使用的模型，也不会自动替换 PS1 内部调用的模型。

## Quick Start

Run these commands from the repository root after downloading or cloning it. Do not copy another computer's absolute installation path.

Run the local web interface:

```powershell
Set-Location .\engine
.\06-web.ps1
```

Auto-open the browser:

```powershell
Set-Location .\engine
.\06-web.ps1 -OpenBrowser
```

Then open:

[http://127.0.0.1:3210](http://127.0.0.1:3210)

## AI Agent 安装与迁移特别说明

本节供 Codex、Claude Code 及其他 AI Agent 在新电脑安装、迁移或排错时参考。**源码下载成功、安装脚本退出成功、网页能打开，都不等于完整写作与出版流程已通过验收。** 当前程序面向 Windows；不要假定 macOS、Linux、WSL 或仅安装 PowerShell 7 的环境可以直接运行全部功能，特别是依赖 Windows COM 的 PDF 导出。

### 1. 确认版本与安装范围

- 要复现 2026-09-17 程序锁版，选择标签 `sagewrite-ps1-20260917`，不要假定默认分支 `main` 等同于锁版。对应提交为 `957e21b763b0034c764516192298bd564f1bd637`。下载 ZIP 时也要先选择正确标签；私有仓库需要用户自己的访问权限。
- Git 用户可运行下面的命令。标签检出后的 detached HEAD 是正常状态；后续开发应新建分支，不得移动或强推既有锁版标签。
- 程序仓库不等于书稿备份。继续已有书籍时，必须另行恢复其完整工作区，包括目录、正文、参考文献状态、图片、封面及排版配置，不能只复制 PS1 或正文 MD。

```powershell
git clone --branch sagewrite-ps1-20260917 --single-branch https://github.com/wenmin20212-dotcom/SageWrite.git SageWrite-PS1-20260917
Set-Location .\SageWrite-PS1-20260917\engine
```

### 2. 按实际功能核对依赖

| 功能 | 必要条件及检查重点 |
| --- | --- |
| 基础脚本 | Windows PowerShell，确认 `powershell.exe` 可用 |
| Web 工作台 | Node.js，确认 `node --version` 可运行 |
| AI 写作与审稿 | 网络连接、用户自己的 `OPENAI_API_KEY`、相应模型权限及可用 API 配额；ChatGPT 登录不能代替 API 配置 |
| 正式 DOCX / EPUB | Pandoc，确认 `pandoc --version` 可运行 |
| 当前 PDF 导出 | 上述排版依赖及已安装、激活的桌面版 Microsoft Word；`05c-pdf.ps1` / `05cc-print-pdf.ps1` 使用 `Word.Application` COM，Word 网页版不能替代 |
| 简版 DOCX 路线 | Python 和 `python-docx`；用 `python -c "import docx; print(docx.__version__)"` 检查实际调用的 Python 环境 |
| 部分图片工具 | ImageMagick，确认 `magick -version` 可运行 |
| 可选发布自动化 | 按 `engine/automation/package.json` 安装依赖，并配置所需浏览器、平台账号及权限；不能以准备模式成功代替真实功能验收 |

`Install-SageWrite-Standalone.ps1` **主要写入配置，并按参数注册启动任务，不会自动安装这些依赖**。它对缺少工具可能只给出警告；Pandoc 在安装器中标为 optional，也不表示导出 EPUB/DOCX 时可以缺少。安装器没有覆盖 Word、Python 等所有检查。`New-SageWrite-StandalonePackage.ps1` 是源码打包程序，也不会把外部运行环境一起打包。

软件安装应使用官方渠道并遵守设备管理政策。依赖安装后重新打开终端，确认 PATH 已更新。不要未经核查就升级或替换用户现有运行环境。

### 3. 配置路径、密钥与启动方式

- 所有路径以实际解压目录为准。核心脚本通过 `00-common.ps1` 定位目录；无需创建 `C:\Users\User\.openclaw`。仓库中的历史 `webui/launchers/*.ps1` 可能包含旧机器绝对路径，不能作为新设备启动入口。
- 直接调用 PS1 时，用 `SAGEWRITE_WORKSPACE_ROOT` 设置工作区父目录。程序在其下创建 `workspace-<BookName>/sagewrite/book`。Web 配置通过安装器的 `-WorkspaceRoot` 指定同一父目录，避免两种入口读取不同书稿。
- 未指定工作区时，核心脚本默认在仓库父目录下建立工作区，需确认目录可写。云模式安装器默认使用 `D:\SageWriteWorkspaces`；没有 D 盘时必须显式指定实际路径。
- 密钥优先通过安全的环境配置提供，不要写入 README、提交记录、截图或日志。安装器的 `-OpenAIKey` / `-AdminPassword` 会写入本地配置，且 `-DryRun` 会打印拟写入的配置；不要在可记录的预检查命令中传入真实凭据。
- 默认保持 `127.0.0.1`。没有明确需求，不启用公网监听、自启动或 SYSTEM 任务。已有配置不得未经确认用 `-Force` 覆盖。

以下命令从 `engine` 目录运行。示例使用用户目录中的独立工作区；先预检查，再按需要执行实际安装：

```powershell
$WorkspaceRoot = Join-Path $HOME 'SageWriteWorkspaces'
$env:SAGEWRITE_WORKSPACE_ROOT = $WorkspaceRoot
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-SageWrite-Standalone.ps1 -Mode local -WorkspaceRoot $WorkspaceRoot -DryRun
# 确认依赖、路径及现有配置后执行；此命令不安装依赖。
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-SageWrite-Standalone.ps1 -Mode local -WorkspaceRoot $WorkspaceRoot
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Start-SageWrite-Web.ps1
```

这里的 ExecutionPolicy 参数只针对当前进程，不是要求修改全机策略。若组织策略阻止运行，应报告限制，不绕过管理控制。下载 ZIP 的脚本若被 Windows 标记为网络来源，应在核验来源后按设备政策处理。

### 4. 安装验收与常见故障

1. 记录实际版本、系统、依赖版本和工作区路径。先在独立测试工作区运行 `01-intake.ps1`，确认能够新建项目，不使用现有书稿做破坏性测试。
2. 确认 Web 界面能打开，且看到的是预期工作区。端口冲突时更换端口，不终止不明进程。网页能打开不代表 API 已可用；联网生成会产生费用，应在用户授权范围内做小规模验证。
3. 用内容完整的测试书稿检查排版；空项目不能验证导出能力。正式构建前运行 `04F.ps1 -BookName <测试书名> -Mode Check`，检查通过后分别验收 `05-build.ps1`、`05c-pdf.ps1` 和 `05b-epub.ps1`。参数说明见对应脚本及 [04F 说明](engine/04F-README.md)。
4. 遇到 04F 标记缺失或过期，应读报告、修复问题并重新检查；采用 04R 的书稿还须满足参考文献完整性要求。不得伪造标记、删除检查逻辑或回退使用旧产物来宣称构建成功。
5. PDF 报 `Word.Application` 错误时，检查桌面 Word 的安装、激活与首次启动状态；无交互会话的服务或 SYSTEM 任务不应视为已验证的 Word 导出环境。中文字体不同也可能改变换行、页数及版式，需实际打开 PDF 检查。
6. 验收实际生成的文件，确认时间戳、目录层级、封面、插图和参考文献，而不只看退出码。分别报告“已通过”“未测试”“被依赖阻塞”的功能，不把本机已有依赖环境中的成功说成全新电脑验收通过。

2026-09-17 的迁移检查已从 GitHub 锁定标签克隆独立副本，并通过安装器 DryRun 和新工作区初始化；**这不是全新 Windows 系统上的完整安装验收**。本说明是锁版后的补充文档，不代表既有锁版标签中的 README 已被改写。

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
