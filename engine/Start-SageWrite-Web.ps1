param(
  [int]$Port,
  [string]$HostName,
  [ValidateSet("local", "cloud")]
  [string]$Mode,
  [ValidateSet("off", "password", "users")]
  [string]$AuthMode,
  [string]$AdminUser,
  [string]$AdminPassword,
  [string]$OpenAIKey,
  [string]$WorkspaceRoot,
  [string]$UsersFile,
  [string]$UserWorkspaceRoot,
  [string]$ConfigPath
)

$ErrorActionPreference = "Stop"

$EngineRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebRoot = Join-Path $EngineRoot "webui"
$ServerPath = Join-Path $WebRoot "server.js"
$DefaultConfigPath = Join-Path $EngineRoot "sagewrite-web.config.psd1"

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

function Resolve-Setting {
  param(
    [string]$ParameterName,
    [hashtable]$Config,
    [string]$ConfigKey,
    $Default = $null
  )

  if ($PSBoundParameters.ContainsKey($ParameterName)) {
    return Get-Variable -Name $ParameterName -ValueOnly
  }
  return Get-ConfigValue -Config $Config -Key $ConfigKey -Default $Default
}

function Test-PortListening {
  param([int]$LocalPort)

  $listener = Get-NetTCPConnection -LocalPort $LocalPort -State Listen -ErrorAction SilentlyContinue |
    Select-Object -First 1
  return [bool]$listener
}

if (!(Test-Path -LiteralPath $ServerPath)) {
  throw "Cannot find server.js: $ServerPath"
}

if (!(Get-Command node -ErrorAction SilentlyContinue)) {
  throw "Cannot find node.exe. Please install Node.js or add it to PATH."
}

$EffectiveConfigPath = if ($PSBoundParameters.ContainsKey("ConfigPath") -and -not [string]::IsNullOrWhiteSpace($ConfigPath)) {
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

$EffectivePort = [int](Resolve-Setting -ParameterName "Port" -Config $Config -ConfigKey "Port" -Default 3210)
$EffectiveHostName = [string](Resolve-Setting -ParameterName "HostName" -Config $Config -ConfigKey "HostName" -Default "127.0.0.1")
$EffectiveMode = [string](Resolve-Setting -ParameterName "Mode" -Config $Config -ConfigKey "Mode" -Default "")
$EffectiveAuthMode = [string](Resolve-Setting -ParameterName "AuthMode" -Config $Config -ConfigKey "AuthMode" -Default "")
$EffectiveAdminUser = [string](Resolve-Setting -ParameterName "AdminUser" -Config $Config -ConfigKey "AdminUser" -Default "")
$EffectiveAdminPassword = [string](Resolve-Setting -ParameterName "AdminPassword" -Config $Config -ConfigKey "AdminPassword" -Default "")
$EffectiveOpenAIKey = [string](Resolve-Setting -ParameterName "OpenAIKey" -Config $Config -ConfigKey "OpenAIKey" -Default "")
$EffectiveWorkspaceRoot = [string](Resolve-Setting -ParameterName "WorkspaceRoot" -Config $Config -ConfigKey "WorkspaceRoot" -Default "")
$EffectiveUsersFile = [string](Resolve-Setting -ParameterName "UsersFile" -Config $Config -ConfigKey "UsersFile" -Default "")
$EffectiveUserWorkspaceRoot = [string](Resolve-Setting -ParameterName "UserWorkspaceRoot" -Config $Config -ConfigKey "UserWorkspaceRoot" -Default "")

if ($EffectivePort -lt 1 -or $EffectivePort -gt 65535) {
  throw "Port must be between 1 and 65535."
}
if ([string]::IsNullOrWhiteSpace($EffectiveMode)) {
  $EffectiveMode = if ($EffectiveHostName -eq "0.0.0.0") { "cloud" } else { "local" }
}
if ($EffectiveMode -notin @("local", "cloud")) {
  throw "Mode must be local or cloud."
}
if ([string]::IsNullOrWhiteSpace($EffectiveAuthMode)) {
  $EffectiveAuthMode = if ($env:SAGEWRITE_AUTH) { $env:SAGEWRITE_AUTH } else { "off" }
}
if ($EffectiveAuthMode -notin @("off", "password", "users")) {
  throw "AuthMode must be off, password, or users."
}
if ($EffectiveAuthMode -in @("password", "users") -and [string]::IsNullOrWhiteSpace($EffectiveAdminPassword) -and [string]::IsNullOrWhiteSpace($env:SAGEWRITE_ADMIN_PASSWORD)) {
  throw "AuthMode requires a password, but AdminPassword and SAGEWRITE_ADMIN_PASSWORD are both empty."
}
if ($EffectiveMode -eq "cloud" -and $EffectiveAuthMode -eq "off") {
  Write-Warning "Cloud mode is starting without login protection. Use AuthMode='password' or AuthMode='users' before exposing this server."
}
if (-not [string]::IsNullOrWhiteSpace($EffectiveWorkspaceRoot)) {
  $EffectiveWorkspaceRoot = [System.IO.Path]::GetFullPath($EffectiveWorkspaceRoot)
  New-Item -ItemType Directory -Force -Path $EffectiveWorkspaceRoot | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace($EffectiveUsersFile)) {
  $EffectiveUsersFile = [System.IO.Path]::GetFullPath($EffectiveUsersFile)
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $EffectiveUsersFile) | Out-Null
}
if (-not [string]::IsNullOrWhiteSpace($EffectiveUserWorkspaceRoot)) {
  $EffectiveUserWorkspaceRoot = [System.IO.Path]::GetFullPath($EffectiveUserWorkspaceRoot)
  New-Item -ItemType Directory -Force -Path $EffectiveUserWorkspaceRoot | Out-Null
}

$env:PORT = "$EffectivePort"
$env:HOST = $EffectiveHostName
$env:SAGEWRITE_PORT = "$EffectivePort"
$env:SAGEWRITE_HOST = $EffectiveHostName
$env:SAGEWRITE_MODE = $EffectiveMode
$env:SAGEWRITE_AUTH = $EffectiveAuthMode
if (-not [string]::IsNullOrWhiteSpace($EffectiveAdminUser)) {
  $env:SAGEWRITE_ADMIN_USER = $EffectiveAdminUser
}
if (-not [string]::IsNullOrWhiteSpace($EffectiveAdminPassword)) {
  $env:SAGEWRITE_ADMIN_PASSWORD = $EffectiveAdminPassword
}
if (-not [string]::IsNullOrWhiteSpace($EffectiveOpenAIKey)) {
  $env:OPENAI_API_KEY = $EffectiveOpenAIKey
}
if (-not [string]::IsNullOrWhiteSpace($EffectiveWorkspaceRoot)) {
  $env:SAGEWRITE_WORKSPACE_ROOT = $EffectiveWorkspaceRoot
}
if (-not [string]::IsNullOrWhiteSpace($EffectiveUsersFile)) {
  $env:SAGEWRITE_USERS_FILE = $EffectiveUsersFile
}
if (-not [string]::IsNullOrWhiteSpace($EffectiveUserWorkspaceRoot)) {
  $env:SAGEWRITE_USER_WORKSPACE_ROOT = $EffectiveUserWorkspaceRoot
}

if (!(Test-PortListening -LocalPort $EffectivePort)) {
  Start-Process -FilePath "node" -ArgumentList "server.js" -WorkingDirectory $WebRoot -WindowStyle Hidden

  $started = $false
  for ($i = 0; $i -lt 30; $i++) {
    Start-Sleep -Milliseconds 300
    if (Test-PortListening -LocalPort $EffectivePort) {
      $started = $true
      break
    }
  }

  if (!$started) {
    throw "SageWrite web service did not start on port $EffectivePort."
  }
}

$BrowserHost = if ($EffectiveHostName -eq "0.0.0.0") { "127.0.0.1" } else { $EffectiveHostName }
$Url = "http://${BrowserHost}:$EffectivePort"
Start-Process $Url
