param(
  [string]$TaskName = "SageWrite Web",
  [ValidateSet("AtLogon", "AtStartup")]
  [string]$Trigger = "AtLogon",
  [switch]$AsSystem,
  [switch]$RunNow,
  [switch]$Force,
  [switch]$DryRun,
  [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

$EngineRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RunnerPath = Join-Path $EngineRoot "Run-SageWrite-WebTask.ps1"
$DefaultConfigPath = Join-Path $EngineRoot "sagewrite-web.config.psd1"

function Test-IsAdministrator {
  $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
  return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Join-ArgumentList {
  param([string[]]$Parts)
  return ($Parts | ForEach-Object {
    if ($_ -match '\s|"' ) {
      '"' + ($_ -replace '"', '\"') + '"'
    } else {
      $_
    }
  }) -join " "
}

if (!(Get-Command Register-ScheduledTask -ErrorAction SilentlyContinue)) {
  throw "Register-ScheduledTask is not available on this Windows installation."
}

if (!(Test-Path -LiteralPath $RunnerPath)) {
  throw "Cannot find runner script: $RunnerPath"
}

$EffectiveConfigPath = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
  [System.IO.Path]::GetFullPath($ConfigPath)
} elseif (Test-Path -LiteralPath $DefaultConfigPath) {
  $DefaultConfigPath
} else {
  throw "Config file not found. Create sagewrite-web.config.psd1 from sagewrite-web.config.example.psd1, or pass -ConfigPath."
}

if (!(Test-Path -LiteralPath $EffectiveConfigPath)) {
  throw "Config file not found: $EffectiveConfigPath"
}

$Config = Import-PowerShellDataFile -LiteralPath $EffectiveConfigPath
if ($Config.ContainsKey("Mode") -and $Config.Mode -eq "cloud" -and $Config.AuthMode -ne "password") {
  Write-Warning "Config is cloud mode without password auth. Set AuthMode='password' before exposing this server."
}

if ($AsSystem -and !(Test-IsAdministrator)) {
  if ($DryRun) {
    Write-Warning "Real SYSTEM task installation requires an elevated PowerShell session."
  } else {
    throw "Installing a SYSTEM startup task requires an elevated PowerShell session."
  }
}
if ($Trigger -eq "AtStartup" -and !$AsSystem) {
  Write-Warning "AtStartup with the current user may still require that user context to be available. Use -AsSystem from elevated PowerShell for true server boot startup."
}

$ActionParts = @(
  "-NoProfile",
  "-ExecutionPolicy", "Bypass",
  "-File", $RunnerPath,
  "-ConfigPath", $EffectiveConfigPath
)
$ActionArguments = Join-ArgumentList -Parts $ActionParts

if ($DryRun) {
  Write-Host "Dry run only. No scheduled task was registered."
  Write-Host "TaskName: $TaskName"
  Write-Host "Trigger: $Trigger"
  Write-Host "RunAs: $(if ($AsSystem) { 'SYSTEM' } else { [Security.Principal.WindowsIdentity]::GetCurrent().Name })"
  Write-Host "ConfigPath: $EffectiveConfigPath"
  Write-Host "RunnerPath: $RunnerPath"
  Write-Host "Action: powershell.exe $ActionArguments"
  exit 0
}

$Action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $ActionArguments -WorkingDirectory $EngineRoot

$TaskTrigger = if ($Trigger -eq "AtStartup") {
  New-ScheduledTaskTrigger -AtStartup
} else {
  New-ScheduledTaskTrigger -AtLogOn
}

$Settings = New-ScheduledTaskSettingsSet `
  -AllowStartIfOnBatteries `
  -ExecutionTimeLimit ([TimeSpan]::Zero) `
  -MultipleInstances IgnoreNew `
  -RestartCount 3 `
  -RestartInterval (New-TimeSpan -Minutes 1) `
  -StartWhenAvailable

$Principal = if ($AsSystem) {
  New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
} else {
  $CurrentUser = [Security.Principal.WindowsIdentity]::GetCurrent().Name
  New-ScheduledTaskPrincipal -UserId $CurrentUser -LogonType Interactive -RunLevel Limited
}

$Existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
if ($Existing -and !$Force) {
  throw "Scheduled task already exists: $TaskName. Re-run with -Force to replace it."
}

Register-ScheduledTask `
  -TaskName $TaskName `
  -Action $Action `
  -Trigger $TaskTrigger `
  -Settings $Settings `
  -Principal $Principal `
  -Description "Starts SageWrite Web UI from $EngineRoot using $EffectiveConfigPath." `
  -Force:$Force | Out-Null

Write-Host "Installed scheduled task: $TaskName"
Write-Host "Trigger: $Trigger"
Write-Host "RunAs: $(if ($AsSystem) { 'SYSTEM' } else { [Security.Principal.WindowsIdentity]::GetCurrent().Name })"
Write-Host "ConfigPath: $EffectiveConfigPath"
Write-Host "RunnerPath: $RunnerPath"

if ($RunNow) {
  Start-ScheduledTask -TaskName $TaskName
  Write-Host "Started scheduled task: $TaskName"
}
