param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [ValidateSet("prepare", "draft", "assist")]
    [string]$Mode = "prepare",

    [Parameter(Mandatory = $true)]
    [string]$RunRoot,

    [switch]$ReuseSession,
    [switch]$Force
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        $Data
    )
    $Data | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
$LanguageCode = $Language.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = "zh"
}

$PlatformRoot = Join-Path $Context.BookRoot ("09_publish\" + $LanguageCode + "\apple")
$MetadataPath = Join-Path $PlatformRoot "metadata.json"
$PackagePath = Join-Path $PlatformRoot "apple_books_package.json"
$ResultPath = Join-Path $RunRoot "apple_result.json"
$SessionRoot = Join-Path $PlatformRoot ".automation\edge-profile"
$AutomationRoot = Join-Path $Context.EnginePath "automation"
$AutomationScript = Join-Path $AutomationRoot "submit-apple.js"
$PackageJsonPath = Join-Path $AutomationRoot "package.json"

if (-not (Test-Path -LiteralPath $MetadataPath)) {
    throw "Apple metadata.json not found: $MetadataPath"
}

if (-not (Test-Path -LiteralPath $PackagePath)) {
    throw "Apple package file not found: $PackagePath"
}

if (-not (Test-Path -LiteralPath $AutomationScript)) {
    throw "Apple automation script not found: $AutomationScript"
}

if (-not (Test-Path -LiteralPath $PackageJsonPath)) {
    throw "Automation package.json not found: $PackageJsonPath"
}

New-Item -ItemType Directory -Path $SessionRoot -Force | Out-Null

$nodeArgs = @(
    $AutomationScript,
    "--mode", $Mode,
    "--platform-root", $PlatformRoot,
    "--metadata-path", $MetadataPath,
    "--package-path", $PackagePath,
    "--run-root", $RunRoot,
    "--result-path", $ResultPath,
    "--session-root", $SessionRoot
)

if ($ReuseSession) {
    $nodeArgs += "--reuse-session"
}

if ($Force) {
    $nodeArgs += "--force"
}

Push-Location $AutomationRoot
try {
    & node @nodeArgs
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "submit-apple.js failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $ResultPath)) {
    throw "Apple automation did not write result file: $ResultPath"
}

Write-Host "Apple submit automation completed: $ResultPath"
