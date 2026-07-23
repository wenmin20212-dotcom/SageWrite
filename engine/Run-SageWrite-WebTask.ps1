param(
  [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

$EngineRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$StartScript = Join-Path $EngineRoot "06-web.ps1"
$DefaultConfigPath = Join-Path $EngineRoot "sagewrite-web.config.psd1"
$LogRoot = Join-Path $EngineRoot "logs\web-service"

function Get-ConfigValue {
  param(
    [hashtable]$Config,
    [string]$Key,
    $Default = $null
  )

  if ($Config -and $Config.ContainsKey($Key) -and $null -ne $Config[$Key] -and "$($Config[$Key])" -ne "") {
    return $Config[$Key]
  }
  return $Default
}

if (!(Test-Path -LiteralPath $StartScript)) {
  throw "Cannot find 06-web.ps1: $StartScript"
}

$EffectiveConfigPath = if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
  [System.IO.Path]::GetFullPath($ConfigPath)
} elseif (Test-Path -LiteralPath $DefaultConfigPath) {
  $DefaultConfigPath
} else {
  ""
}

$Config = @{}
if ($EffectiveConfigPath) {
  if (!(Test-Path -LiteralPath $EffectiveConfigPath)) {
    throw "Config file not found: $EffectiveConfigPath"
  }
  $Config = Import-PowerShellDataFile -LiteralPath $EffectiveConfigPath
}

$EffectivePort = [int](Get-ConfigValue -Config $Config -Key "Port" -Default $(if ($env:SAGEWRITE_PORT) { $env:SAGEWRITE_PORT } else { 3210 }))
$Listener = Get-NetTCPConnection -LocalPort $EffectivePort -State Listen -ErrorAction SilentlyContinue |
  Select-Object -First 1
if ($Listener) {
  Write-Host "SageWrite Web already appears to be listening on port $EffectivePort. Owning process: $($Listener.OwningProcess)."
  exit 0
}

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
$Stamp = Get-Date -Format "yyyyMMddHHmmss"
$LogPath = Join-Path $LogRoot "sagewrite-web-$Stamp.log"
$LatestPath = Join-Path $LogRoot "latest.log.path.txt"
Set-Content -LiteralPath $LatestPath -Value $LogPath -Encoding UTF8

Start-Transcript -Path $LogPath -Append | Out-Null
try {
  Write-Host "SageWrite Web scheduled/background runner"
  Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  Write-Host "EngineRoot: $EngineRoot"
  Write-Host "ConfigPath: $($EffectiveConfigPath -replace '^$', '(none)')"
  Write-Host "LogPath: $LogPath"

  if ($EffectiveConfigPath) {
    & $StartScript -ConfigPath $EffectiveConfigPath
  } else {
    & $StartScript
  }
}
finally {
  Write-Host "Stopped: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
  Stop-Transcript | Out-Null
}
