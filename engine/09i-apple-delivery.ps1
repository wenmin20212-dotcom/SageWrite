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
$ResultPath = Join-Path $RunRoot "apple_result.json"
$ArtifactPath = Join-Path (Join-Path $RunRoot "artifacts") "apple-delivery-note.txt"

if (-not (Test-Path -LiteralPath $MetadataPath)) {
    throw "Apple metadata.json not found: $MetadataPath"
}

$Metadata = Get-Content -LiteralPath $MetadataPath -Raw -Encoding UTF8 | ConvertFrom-Json
Set-Content -LiteralPath $ArtifactPath -Value "Placeholder for future Apple delivery tooling notes." -Encoding UTF8

$Result = [ordered]@{
    platform = "apple"
    state = "prepared"
    mode = $Mode
    automation_type = "delivery"
    supported_today = $false
    executed_browser = $false
    reuse_session = [bool]$ReuseSession
    force = [bool]$Force
    title = "$($Metadata.title)"
    author = "$($Metadata.author)"
    folder = $PlatformRoot
    result_file = $ResultPath
    next_step = "Keep generating Apple delivery package first; do not start browser automation yet."
    notes = @(
        "Apple submission is intentionally kept out of browser automation in phase one.",
        "This module reserves the delivery handoff point for future Apple-specific tooling.",
        "Current action is package verification only."
    )
}

Write-JsonUtf8 -Path $ResultPath -Data $Result
Write-Host "Apple delivery scaffold completed: $ResultPath"
