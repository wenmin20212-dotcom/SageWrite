param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [ValidateSet("prepare", "draft", "assist", "details", "content")]
    [string]$Mode = "prepare",

    [Parameter(Mandatory = $true)]
    [string]$RunRoot,

    [switch]$AttachChrome,
    [int]$ChromeDebugPort = 9222,

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

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

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

$PlatformRoot = Join-Path $Context.BookRoot ("09_publish\" + $LanguageCode + "\amazon")
$MetadataPath = Join-Path $PlatformRoot "metadata.json"
$ResultPath = Join-Path $RunRoot "amazon_result.json"
$SessionRoot = Join-Path $PlatformRoot ".automation\edge-profile"
$AutomationRoot = Join-Path $Context.EnginePath "automation"
$AutomationScript = Join-Path $AutomationRoot "submit-amazon.js"
$PackageJsonPath = Join-Path $AutomationRoot "package.json"

if (-not (Test-Path -LiteralPath $MetadataPath)) {
    throw "Amazon metadata.json not found: $MetadataPath"
}

if (-not (Test-Path -LiteralPath $AutomationScript)) {
    throw "Amazon automation script not found: $AutomationScript"
}

Ensure-Directory -Path $SessionRoot

$PackageInstalled = Test-Path -LiteralPath (Join-Path $AutomationRoot "node_modules\playwright-core")

if ($Mode -eq "prepare" -and -not $PackageInstalled) {
    $Metadata = Get-Content -LiteralPath $MetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $Result = [ordered]@{
        platform = "amazon"
        state = "prepared"
        mode = $Mode
        automation_type = "browser"
        supported_today = $true
        executed_browser = $false
        title = "$($Metadata.title)"
        author = "$($Metadata.author)"
        folder = $PlatformRoot
        result_file = $ResultPath
        session_root = $SessionRoot
        playwright_installed = $false
        next_step = "Install engine/automation dependencies with npm install before non-prepare runs."
        notes = @(
            "Prepare mode can still finish without playwright-core installed.",
            "Node automation entry has been wired and is ready for dependency installation."
        )
    }
    Write-JsonUtf8 -Path $ResultPath -Data $Result
    Write-Host "Amazon submit prepare completed without Playwright install: $ResultPath"
    exit 0
}

if (-not (Test-Path -LiteralPath $PackageJsonPath)) {
    throw "Automation package.json not found: $PackageJsonPath"
}

$nodeArgs = @(
    $AutomationScript,
    "--mode", $Mode,
    "--platform-root", $PlatformRoot,
    "--metadata-path", $MetadataPath,
    "--run-root", $RunRoot,
    "--result-path", $ResultPath,
    "--session-root", $SessionRoot
)

if ($ReuseSession) {
    $nodeArgs += "--reuse-session"
}

if ($AttachChrome) {
    $nodeArgs += "--attach-browser"
    $nodeArgs += "--remote-debug-url"
    $nodeArgs += ("http://127.0.0.1:{0}" -f $ChromeDebugPort)
}

if ($Force) {
    $nodeArgs += "--force"
}

Push-Location $AutomationRoot
try {
    & node @nodeArgs
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "submit-amazon.js failed with exit code $LASTEXITCODE"
    }
}
finally {
    Pop-Location
}

if (-not (Test-Path -LiteralPath $ResultPath)) {
    throw "Amazon automation did not write result file: $ResultPath"
}

Write-Host "Amazon submit automation completed: $ResultPath"
