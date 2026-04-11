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

$PlatformRoot = Join-Path $Context.BookRoot ("09_publish\" + $LanguageCode + "\google")
$MetadataPath = Join-Path $PlatformRoot "metadata.json"
$ResultPath = Join-Path $RunRoot "google_result.json"
$ScreenshotPath = Join-Path (Join-Path $RunRoot "screenshots") "google-placeholder.txt"

if (-not (Test-Path -LiteralPath $MetadataPath)) {
    throw "Google metadata.json not found: $MetadataPath"
}

$Metadata = Get-Content -LiteralPath $MetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
Set-Content -LiteralPath $ScreenshotPath -Value "Placeholder for future Playwright screenshots." -Encoding UTF8

$Result = [ordered]@{
    platform = "google"
    state = "prepared"
    mode = $Mode
    automation_type = "browser"
    supported_today = $true
    executed_browser = $false
    reuse_session = [bool]$ReuseSession
    force = [bool]$Force
    title = "$($Metadata.title)"
    author = "$($Metadata.author)"
    folder = $PlatformRoot
    result_file = $ResultPath
    next_step = switch ($Mode) {
        "prepare" { "Validate Google package completeness and prepare automation session." }
        "draft"   { "Future step: fill Google Play Books form and save draft." }
        "assist"  { "Future step: fill form, upload assets, and pause before final publish." }
    }
    notes = @(
        "This is a scaffold module.",
        "No browser session has been started yet.",
        "Future implementation target: Google Play Books draft workflow."
    )
}

Write-JsonUtf8 -Path $ResultPath -Data $Result
Write-Host "Google submit scaffold completed: $ResultPath"
