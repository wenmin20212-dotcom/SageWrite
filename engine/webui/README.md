# SageWrite Web UI

## Important Version Note

This version is a single-user local/personal-cloud standalone version.

It is not a multi-user cloud system. Multiple browsers can open it, but there is no per-user account, per-user workspace isolation, role permission model, or concurrent project editing protection. Multi-user cloud work starts in later versions.

Standalone install entry:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-SageWrite-Standalone.ps1
```

Local standalone install and start:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-SageWrite-Standalone.ps1 -Mode local -StartNow
```

Personal cloud / Windows server install:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-SageWrite-Standalone.ps1 -Mode cloud -AdminPassword "change-this-password" -WorkspaceRoot "D:\SageWriteWorkspaces" -InstallAutoStart -TaskTrigger AtStartup -AsSystem -StartNow
```

Create a standalone package from the current Git commit:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\New-SageWrite-StandalonePackage.ps1
```

## Start

```powershell
cd C:\Users\User\.openclaw\SageWrite\engine
.\06-web.ps1
```

Auto-open browser:

```powershell
.\06-web.ps1 -OpenBrowser
```

Cloud/server listen address:

```powershell
.\06-web.ps1 -HostName 0.0.0.0 -Port 3210
```

Cloud/server config file:

```powershell
Copy-Item .\sagewrite-web.config.example.psd1 .\sagewrite-web.config.psd1
notepad .\sagewrite-web.config.psd1
.\06-web.ps1
```

The real `sagewrite-web.config.psd1` file is ignored by git because it may contain a password. Command-line parameters override config-file values.

In cloud mode, browser buttons do not open Windows Explorer or server desktop apps. File actions return browser download/preview links and folder actions show the server path plus the in-page file lists.

Cloud mode file access is constrained to the configured workspace root. Download, preview, upload-save, and archived-log endpoints reject absolute paths and `..` traversal outside the relevant book subdirectory.

Health check:

```text
GET /api/health
```

The Web UI also shows this in the header. It checks Node.js, PowerShell, ImageMagick, Pandoc, `OPENAI_API_KEY`, login protection, and workspace root read/write access.

Long-running Web UI jobs write state and logs under each book:

```text
sagewrite\book\logs\webui-jobs
sagewrite\book\logs\webui-runs
sagewrite\book\logs\webui_runs.jsonl
```

Refreshing the browser keeps tracking the current running job as long as the server process is still running.

Use a cloud/server workspace parent folder:

```powershell
.\06-web.ps1 -WorkspaceRoot "D:\SageWriteWorkspaces"
```

Enable password login for cloud/server use:

```powershell
@{
    Mode = 'cloud'
    HostName = '0.0.0.0'
    Port = 3210
    WorkspaceRoot = 'D:\SageWriteWorkspaces'
    AuthMode = 'password'
    AdminPassword = 'change-this-password'
    OpenAIKey = ''
    OpenBrowser = $false
}
```

Start with a specific config file:

```powershell
.\06-web.ps1 -ConfigPath .\sagewrite-web.config.psd1
```

Install Windows auto-start task:

```powershell
.\Install-SageWrite-WebTask.ps1 -DryRun
.\Install-SageWrite-WebTask.ps1 -Trigger AtLogon -RunNow
```

For a Windows cloud/server machine where SageWrite should start after boot, run PowerShell as Administrator and install it as SYSTEM:

```powershell
.\Install-SageWrite-WebTask.ps1 -Trigger AtStartup -AsSystem -RunNow
```

Task logs are written here:

```text
logs\web-service
```

Check or remove the task:

```powershell
.\Get-SageWrite-WebTask.ps1
.\Uninstall-SageWrite-WebTask.ps1 -Stop
```

If Windows blocks direct `.ps1` execution, use the same command through PowerShell Bypass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install-SageWrite-WebTask.ps1 -Trigger AtLogon -RunNow
```

Open:

[http://127.0.0.1:3210](http://127.0.0.1:3210)

## What it does

- Creates a local web control panel for the SageWrite PowerShell scripts
- Runs `01-intake.ps1`
- Runs `02-structure.ps1`
- Runs `02b-expand.ps1`
- Runs `03-write.ps1`
- Runs `04-edit.ps1`
- Runs `05-build.ps1`
- Shows script output in the browser

## Notes

- `OPENAI_API_KEY` must exist in your environment, or `OpenAIKey` must be set in `sagewrite-web.config.psd1`, for OpenAI-driven steps
- `pandoc` must already be installed for build
- By default the web server only listens on `127.0.0.1`
- Set `SAGEWRITE_HOST=0.0.0.0` or use `.\06-web.ps1 -HostName 0.0.0.0` for cloud/server access
- `SAGEWRITE_MODE` defaults to `cloud` when the host is `0.0.0.0`; set `SAGEWRITE_MODE=local` only for trusted local desktop use
- Authentication is off by default for local use
- Set `AuthMode='password'` and `AdminPassword='...'` in `sagewrite-web.config.psd1` before exposing the server beyond localhost
- By default workspaces are discovered next to `.openclaw\SageWrite`; set `SAGEWRITE_WORKSPACE_ROOT` or use `.\06-web.ps1 -WorkspaceRoot "D:\SageWriteWorkspaces"` to store `workspace-*` folders elsewhere
- `Start-SageWrite-Web.ps1` reads the same config file and starts the Web UI hidden, then opens the browser; `06-web.ps1` runs in the current terminal and is preferred for server deployment.
- `Install-SageWrite-WebTask.ps1` registers a Windows Scheduled Task that runs `Run-SageWrite-WebTask.ps1`, which writes startup output under `logs\web-service`.
