param(
  [ValidateSet("local", "cloud")]
  [string]$Mode = "local",
  [string]$HostName,
  [int]$Port = 3210,
  [string]$WorkspaceRoot,
  [string]$AdminPassword,
  [string]$OpenAIKey,
  [switch]$InstallAutoStart,
  [ValidateSet("AtLogon", "AtStartup")]
  [string]$TaskTrigger = "AtLogon",
  [switch]$AsSystem,
  [switch]$StartNow,
  [switch]$Force,
  [switch]$DryRun
)

$ErrorActionPreference = "Stop"

$EngineRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigPath = Join-Path $EngineRoot "sagewrite-web.config.psd1"
$StartScript = Join-Path $EngineRoot "Start-SageWrite-Web.ps1"
$TaskInstallScript = Join-Path $EngineRoot "Install-SageWrite-WebTask.ps1"

function ConvertTo-Psd1String {
  param([string]$Value)
  if ($null -eq $Value) {
    $Value = ""
  }
  return "'" + ($Value -replace "'", "''") + "'"
}

function ConvertTo-Psd1Bool {
  param([bool]$Value)
  if ($Value) {
    return '$true'
  }
  return '$false'
}

function Test-IsAdministrator {
  $Identity = [Security.Principal.WindowsIdentity]::GetCurrent()
  $Principal = New-Object Security.Principal.WindowsPrincipal($Identity)
  return $Principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Write-ToolStatus {
  param(
    [string]$CommandName,
    [bool]$Required
  )

  $Command = Get-Command $CommandName -ErrorAction SilentlyContinue
  if ($Command) {
    Write-Host "OK: $CommandName -> $($Command.Source)"
    return
  }

  if ($Required) {
    Write-Warning "Missing required tool: $CommandName"
  } else {
    Write-Warning "Missing optional tool: $CommandName"
  }
}

if (!(Test-Path -LiteralPath $StartScript)) {
  throw "Cannot find Start-SageWrite-Web.ps1: $StartScript"
}

if (!(Test-Path -LiteralPath $TaskInstallScript)) {
  throw "Cannot find Install-SageWrite-WebTask.ps1: $TaskInstallScript"
}

$EffectiveHostName = if (-not [string]::IsNullOrWhiteSpace($HostName)) {
  $HostName
} elseif ($Mode -eq "cloud") {
  "0.0.0.0"
} else {
  "127.0.0.1"
}

$EffectiveWorkspaceRoot = if (-not [string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
  [System.IO.Path]::GetFullPath($WorkspaceRoot)
} elseif ($Mode -eq "cloud") {
  "D:\SageWriteWorkspaces"
} else {
  ""
}

$EffectiveAuthMode = if ($Mode -eq "cloud" -or -not [string]::IsNullOrWhiteSpace($AdminPassword) -or -not [string]::IsNullOrWhiteSpace($env:SAGEWRITE_ADMIN_PASSWORD)) {
  "password"
} else {
  "off"
}

if ($Mode -eq "cloud" -and [string]::IsNullOrWhiteSpace($AdminPassword) -and [string]::IsNullOrWhiteSpace($env:SAGEWRITE_ADMIN_PASSWORD)) {
  $Message = "Cloud standalone install requires -AdminPassword or SAGEWRITE_ADMIN_PASSWORD."
  if ($DryRun) {
    Write-Warning $Message
  } else {
    throw $Message
  }
}

if ($AsSystem -and !(Test-IsAdministrator)) {
  $Message = "Installing an AtStartup SYSTEM task requires an elevated PowerShell session."
  if ($DryRun) {
    Write-Warning $Message
  } else {
    throw $Message
  }
}

if ((Test-Path -LiteralPath $ConfigPath) -and !$Force -and !$DryRun) {
  throw "Config already exists: $ConfigPath. Re-run with -Force to overwrite it."
}

Write-Host "SageWrite standalone installer"
Write-Host "Version scope: single-user local/personal-cloud standalone. Multi-user cloud starts in a later version."
Write-Host "EngineRoot: $EngineRoot"
Write-Host "Mode: $Mode"
Write-Host "HostName: $EffectiveHostName"
Write-Host "Port: $Port"
Write-Host "AuthMode: $EffectiveAuthMode"
Write-Host "WorkspaceRoot: $($EffectiveWorkspaceRoot -replace '^$', '(default)')"
Write-Host "ConfigPath: $ConfigPath"

Write-ToolStatus -CommandName "node" -Required $true
Write-ToolStatus -CommandName "powershell.exe" -Required $true
Write-ToolStatus -CommandName "magick" -Required $false
Write-ToolStatus -CommandName "pandoc" -Required $false

$ConfigLines = @(
  "@{",
  "    Mode = $(ConvertTo-Psd1String $Mode)",
  "    HostName = $(ConvertTo-Psd1String $EffectiveHostName)",
  "    Port = $Port",
  "    WorkspaceRoot = $(ConvertTo-Psd1String $EffectiveWorkspaceRoot)",
  "    AuthMode = $(ConvertTo-Psd1String $EffectiveAuthMode)",
  "    AdminPassword = $(ConvertTo-Psd1String $AdminPassword)",
  "    OpenAIKey = $(ConvertTo-Psd1String $OpenAIKey)",
  "    OpenBrowser = $(ConvertTo-Psd1Bool ($Mode -eq 'local'))",
  "}"
)
$ConfigText = $ConfigLines -join "`r`n"

if ($DryRun) {
  Write-Host "Dry run only. No files or scheduled tasks were changed."
  Write-Host ""
  Write-Host $ConfigText
  exit 0
}

if (-not [string]::IsNullOrWhiteSpace($EffectiveWorkspaceRoot)) {
  New-Item -ItemType Directory -Force -Path $EffectiveWorkspaceRoot | Out-Null
}

Set-Content -LiteralPath $ConfigPath -Value $ConfigText -Encoding UTF8
Write-Host "Wrote config: $ConfigPath"

if ($InstallAutoStart) {
  $TaskArgs = @{
    ConfigPath = $ConfigPath
    Trigger = $TaskTrigger
  }
  if ($AsSystem) {
    $TaskArgs.AsSystem = $true
  }
  if ($StartNow) {
    $TaskArgs.RunNow = $true
  }
  if ($Force) {
    $TaskArgs.Force = $true
  }
  & $TaskInstallScript @TaskArgs
} elseif ($StartNow) {
  & $StartScript -ConfigPath $ConfigPath
} else {
  Write-Host "Start later with:"
  Write-Host "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$StartScript`" -ConfigPath `"$ConfigPath`""
}
