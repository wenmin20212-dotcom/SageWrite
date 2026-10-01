param(
    [string]$WorkspaceRoot,
    [switch]$CreateDesktopShortcut,
    [switch]$Force,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$EngineRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $EngineRoot
$LauncherPath = Join-Path $RepoRoot 'Start-SageWrite-Agent.cmd'
$StartScript = Join-Path $EngineRoot 'Start-SageWrite-Agent.ps1'

if (-not (Test-Path -LiteralPath $LauncherPath -PathType Leaf)) {
    throw "Launcher not found: $LauncherPath"
}

$ValidationArgs = @{ DryRun = $true }
if (-not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    $ValidationArgs.WorkspaceRoot = $WorkspaceRoot
}
& $StartScript @ValidationArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $CreateDesktopShortcut) {
    Write-Host "Ready. Double-click: $LauncherPath"
    if (-not $DryRun) {
        & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $EngineRoot 'Complete-SageWriteInstallation.ps1') -Profile Writing -WorkspaceRoot $WorkspaceRoot
        exit $LASTEXITCODE
    }
    exit 0
}

$Desktop = [Environment]::GetFolderPath('Desktop')
$ShortcutPath = Join-Path $Desktop 'SageWrite Agent.lnk'
if ((Test-Path -LiteralPath $ShortcutPath) -and -not $Force) {
    throw "Desktop shortcut already exists: $ShortcutPath. Use -Force to replace it."
}

if ($DryRun) {
    Write-Host "Dry run: desktop shortcut would be created at $ShortcutPath"
    exit 0
}

$Shell = New-Object -ComObject WScript.Shell
$Shortcut = $Shell.CreateShortcut($ShortcutPath)
$Shortcut.TargetPath = $LauncherPath
$Shortcut.WorkingDirectory = $RepoRoot
$Shortcut.Description = 'Start the local SageWrite writing agent'
$Shortcut.Save()
Write-Host "Created desktop shortcut: $ShortcutPath"
& powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $EngineRoot 'Complete-SageWriteInstallation.ps1') -Profile Writing -WorkspaceRoot $WorkspaceRoot
exit $LASTEXITCODE
