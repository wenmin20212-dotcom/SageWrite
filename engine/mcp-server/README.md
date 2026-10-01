# SageWrite MCP Server

This local MCP server exposes the SageWrite PowerShell workflow as validated MCP tools. It uses stdio, so an MCP host launches it as a child process. The server never exposes arbitrary shell execution.

## Requirements

- Windows PowerShell 5.1
- Node.js 20 or later
- The dependencies required by the SageWrite operation you call
- LLM environment variables described in `../LLM-CONFIG.md` for AI-backed stages

## Install

From this directory:

```powershell
npm install
npm test
```

Copy `mcp-config.example.json` into your MCP host configuration and adjust the absolute paths. Set `SAGEWRITE_WORKSPACE_ROOT` through `-WorkspaceRoot` so the MCP server and Web UI operate on the same books.

If `node.exe` is not on `PATH`, set `SAGEWRITE_NODE_PATH` to its absolute path in the host configuration.

## CodeBuddy

The repository root contains a machine-specific `.mcp.json` for CodeBuddy. Open `D:\SageWrite` as the CodeBuddy project, then open **CodeBuddy Settings > MCP**. The `sagewrite` server should appear and become green after **Try to Run**.

CodeBuddy may request approval before enabling a project MCP server. Approve `sagewrite` for this project when prompted. The configuration uses `alwaysLoad: true`, so CodeBuddy connects before the first prompt and reports startup failures immediately.

## Tools

- `sagewrite_project_status`
- `sagewrite_import_structure` (format-only DOCX/Markdown chapter splitter; no LLM)
- `sagewrite_initialize_book`
- `sagewrite_generate_toc`
- `sagewrite_expand_outline`
- `sagewrite_write_chapters`
- `sagewrite_rewrite_chapters` (runs `03RW.ps1`; preserves source chapters and writes a separate reviewed revision workspace)
- `sagewrite_refine_chapters`
- `sagewrite_translate_chapters`
- `sagewrite_edit_book`
- `sagewrite_workflow_status`: local no-LLM scan via `Get-SageWriteWorkflowStatus.ps1`. Inputs: `bookName`, optional `workspaceRoot`, `language` (zh), `saveReport` (false), `details` (false). Default read-only; saving creates an advisory JSON, never an approval. Call again after writing to refresh. Parse JSON from the script envelope's `stdout` after checking success/truncation.
- `sagewrite_format_preflight`
- `sagewrite_build_manuscript`
- `sagewrite_export_epub`
- `sagewrite_export_pdf`
- `sagewrite_cover_assist`

Each write tool returns structured JSON containing the script name, success state, exit code, stdout, and stderr. Long-running calls default to a one-hour timeout. Override it with `SAGEWRITE_MCP_TIMEOUT_MS`.

### PDF export

完整中文说明、已核实的组件版本、官方下载入口与此前误判的纠正，见 [PDF导出路径、版本与排错](../../docs/PDF-EXPORT.md)。使用前必须核实脚本绝对路径、工作区父目录、当前语言源目录及最终输出路径；MCP客户端与终端的工作区配置可能不同。

无需Word/WPS的已实测辅助路线见[中文附件说明](../../docs/attachments/free-pdf-tools/README.md)和[自动导出附件ZIP](../../docs/attachments/sagewrite-free-pdf-tools.zip)。Typst 0.15.1与Chromium快照1708478已本地下载并自动导出完整书稿，附固定下载校验脚本、export.py和脱敏验收记录。人工导出候选已移除，未通过的LibreOffice不纳入。辅助版式与05C不同，尚未注册为本MCP工具；不可声称sagewrite_export_pdf已支持这些引擎。

`sagewrite_export_pdf` runs `05c-pdf.ps1`, which verifies 04F, invokes `05-build.ps1` to create a fresh full DOCX with Pandoc, then exports through desktop `Word.Application` COM. It does not ask Pandoc to render PDF. The COM provider must work in the server's interactive user context; Microsoft Word is the reference provider. A WPS provider passed an actual local reading-PDF export on 2026-10-01, but other versions and print export need their own validation.

The MCP child inherits its host's restrictions. `80040154` inside a sandbox is not proof that Office is absent: inspect desktop COM registration and registry views and, when authorized by the host, retry the same script outside the sandbox. The tool cannot bypass permissions itself. Check the new PDF's Chinese text, cover count, TOC and illustrations before reporting success. See [export routing](../../skills/sagewrite-publish-book/references/export-routing.md).

## LLM modes

The MCP wrapper does not choose a model itself. Existing SageWrite environment settings continue to control `00-llm.ps1`, including OpenAI-compatible providers and the `codex` command mode. See `../LLM-CONFIG.md`.

## Safety

- Only named SageWrite scripts are registered.
- PowerShell receives parameters as separate process arguments, not as a command string.
- Book names cannot contain path separators or Windows-invalid filename characters.
- Child-process output is captured so it cannot corrupt the MCP stdio protocol.
