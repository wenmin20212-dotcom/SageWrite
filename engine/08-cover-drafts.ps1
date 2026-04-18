param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateRange(1, 20)]
    [int]$Variants = 4,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path

function Invoke-CoverStep {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptName,
        [Parameter(Mandatory = $true)]
        [string]$StageLabel,
        [Parameter(Mandatory = $true)]
        [hashtable]$Arguments
    )

    $scriptPath = Join-Path $EnginePath $ScriptName
    if (-not (Test-Path -LiteralPath $scriptPath)) {
        throw "Script not found: $scriptPath"
    }

    Write-Host ""
    Write-Host ("=== {0} ===" -f $StageLabel)
    & $scriptPath @Arguments
}

function Add-OptionalText {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Target,
        [Parameter(Mandatory = $true)]
        [string]$Key,
        [string]$Value
    )

    if (-not [string]::IsNullOrWhiteSpace($Value)) {
        $Target[$Key] = $Value
    }
}

$briefArgs = @{
    BookName = $BookName
    Edition  = $Edition
}
Add-OptionalText -Target $briefArgs -Key "Title" -Value $Title
Add-OptionalText -Target $briefArgs -Key "Subtitle" -Value $Subtitle
Add-OptionalText -Target $briefArgs -Key "Author" -Value $Author
if ($Force) {
    $briefArgs["Force"] = $true
}

$modeArgs = @{
    BookName = $BookName
    Edition  = $Edition
    Mode     = $Mode
}
if ($Force) {
    $modeArgs["Force"] = $true
}

$generateArgs = @{
    BookName = $BookName
    Edition  = $Edition
    Variants = $Variants
    Mode     = $Mode
}
if ($Force) {
    $generateArgs["Force"] = $true
}

Invoke-CoverStep -ScriptName "08a-brief.ps1" -StageLabel "08a brief" -Arguments $briefArgs
Invoke-CoverStep -ScriptName "08b-strategy.ps1" -StageLabel "08b strategy" -Arguments $modeArgs
Invoke-CoverStep -ScriptName "08g-copy.ps1" -StageLabel "08g copy" -Arguments $modeArgs
Invoke-CoverStep -ScriptName "08c-generate.ps1" -StageLabel "08c generate" -Arguments $generateArgs

Write-Host ""
Write-Host "08-cover-drafts completed successfully."
