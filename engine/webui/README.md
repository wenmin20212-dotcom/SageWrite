# SageWrite Web UI

## Start

```powershell
cd C:\Users\User\.openclaw\SageWrite\engine
.\06-web.ps1
```

Auto-open browser:

```powershell
.\06-web.ps1 -OpenBrowser
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

- `OPENAI_API_KEY` must already exist in your environment for OpenAI-driven steps
- `pandoc` must already be installed for build
- The web server only listens on `127.0.0.1`
