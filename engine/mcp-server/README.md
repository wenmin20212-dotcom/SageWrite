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
- `sagewrite_refine_chapters`
- `sagewrite_translate_chapters`
- `sagewrite_edit_book`
- `sagewrite_format_preflight`
- `sagewrite_build_manuscript`
- `sagewrite_export_epub`
- `sagewrite_export_pdf`
- `sagewrite_cover_assist`

Each write tool returns structured JSON containing the script name, success state, exit code, stdout, and stderr. Long-running calls default to a one-hour timeout. Override it with `SAGEWRITE_MCP_TIMEOUT_MS`.

## LLM modes

The MCP wrapper does not choose a model itself. Existing SageWrite environment settings continue to control `00-llm.ps1`, including OpenAI-compatible providers and the `codex` command mode. See `../LLM-CONFIG.md`.

## Safety

- Only named SageWrite scripts are registered.
- PowerShell receives parameters as separate process arguments, not as a command string.
- Book names cannot contain path separators or Windows-invalid filename characters.
- Child-process output is captured so it cannot corrupt the MCP stdio protocol.
