param(
    [int]$Port,
    [string]$HostName,
    [ValidateSet("local", "cloud")]
    [string]$Mode,
    [ValidateSet("off", "password")]
    [string]$AuthMode,
    [string]$AdminPassword,
    [string]$OpenAIKey,
    [string]$WorkspaceRoot,
    [string]$ConfigPath,
    [switch]$OpenBrowser
)

$ErrorActionPreference = "Stop"

$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$WebRoot = Join-Path $EnginePath "webui"
$DefaultConfigPath = Join-Path $EnginePath "sagewrite-web.config.psd1"

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

function Resolve-BoolSetting {
    param(
        [string]$ParameterName,
        [hashtable]$Config,
        [string]$ConfigKey,
        [bool]$Default = $false
    )

    if ($PSBoundParameters.ContainsKey($ParameterName)) {
        return [bool](Get-Variable -Name $ParameterName -ValueOnly)
    }
    $value = Get-ConfigValue -Config $Config -Key $ConfigKey -Default $Default
    return [System.Convert]::ToBoolean($value)
}

if (!(Test-Path -LiteralPath $WebRoot)) {
    throw "webui folder not found: $WebRoot"
}

if (!(Get-Command node -ErrorAction SilentlyContinue)) {
    throw "Node.js not found."
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
$EffectiveAdminPassword = [string](Resolve-Setting -ParameterName "AdminPassword" -Config $Config -ConfigKey "AdminPassword" -Default "")
$EffectiveOpenAIKey = [string](Resolve-Setting -ParameterName "OpenAIKey" -Config $Config -ConfigKey "OpenAIKey" -Default "")
$EffectiveWorkspaceRoot = [string](Resolve-Setting -ParameterName "WorkspaceRoot" -Config $Config -ConfigKey "WorkspaceRoot" -Default "")
$EffectiveOpenBrowser = Resolve-BoolSetting -ParameterName "OpenBrowser" -Config $Config -ConfigKey "OpenBrowser" -Default $false

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
if ($EffectiveAuthMode -notin @("off", "password")) {
    throw "AuthMode must be off or password."
}
if ($EffectiveAuthMode -eq "password" -and [string]::IsNullOrWhiteSpace($EffectiveAdminPassword) -and [string]::IsNullOrWhiteSpace($env:SAGEWRITE_ADMIN_PASSWORD)) {
    throw "AuthMode is password, but AdminPassword and SAGEWRITE_ADMIN_PASSWORD are both empty."
}
if ($EffectiveMode -eq "cloud" -and $EffectiveAuthMode -ne "password") {
    Write-Warning "Cloud mode is starting without password login. Set AuthMode='password' before exposing this server."
}

if (-not [string]::IsNullOrWhiteSpace($EffectiveWorkspaceRoot)) {
    $EffectiveWorkspaceRoot = [System.IO.Path]::GetFullPath($EffectiveWorkspaceRoot)
    New-Item -ItemType Directory -Force -Path $EffectiveWorkspaceRoot | Out-Null
}

Push-Location $WebRoot

try {
    $env:PORT = "$EffectivePort"
    $env:HOST = $EffectiveHostName
    $env:SAGEWRITE_PORT = "$EffectivePort"
    $env:SAGEWRITE_HOST = $EffectiveHostName
    $env:SAGEWRITE_MODE = $EffectiveMode
    $env:SAGEWRITE_AUTH = $EffectiveAuthMode
    if (-not [string]::IsNullOrWhiteSpace($EffectiveAdminPassword)) {
        $env:SAGEWRITE_ADMIN_PASSWORD = $EffectiveAdminPassword
    }
    if (-not [string]::IsNullOrWhiteSpace($EffectiveOpenAIKey)) {
        $env:OPENAI_API_KEY = $EffectiveOpenAIKey
    }
    if (-not [string]::IsNullOrWhiteSpace($EffectiveWorkspaceRoot)) {
        $env:SAGEWRITE_WORKSPACE_ROOT = $EffectiveWorkspaceRoot
    }

    $BrowserHost = if ($EffectiveHostName -eq "0.0.0.0") { "127.0.0.1" } else { $EffectiveHostName }
    $Url = "http://${BrowserHost}:$EffectivePort"

    Write-Host "SageWrite Web startup configuration:"
    Write-Host "  ConfigPath: $($EffectiveConfigPath -replace '^$', '(none)')"
    Write-Host "  HostName: $EffectiveHostName"
    Write-Host "  Port: $EffectivePort"
    Write-Host "  Mode: $EffectiveMode"
    Write-Host "  AuthMode: $EffectiveAuthMode"
    Write-Host "  OpenAIKey: $(if (-not [string]::IsNullOrWhiteSpace($env:OPENAI_API_KEY)) { 'configured' } else { 'missing' })"
    Write-Host "  WorkspaceRoot: $($EffectiveWorkspaceRoot -replace '^$', '(default)')"
    Write-Host "  LocalUrl: $Url"

    if ($EffectiveOpenBrowser) {
        Start-Job -ScriptBlock {
            param($TargetUrl)
            Start-Sleep -Seconds 2
            Start-Process $TargetUrl
        } -ArgumentList $Url | Out-Null
    }

    & node "server.js"
}
finally {
    Pop-Location
}
