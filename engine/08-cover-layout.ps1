param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

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

$reviewArgs = @{
    BookName = $BookName
    Edition  = $Edition
    Mode     = $Mode
}
if ($Force) {
    $reviewArgs["Force"] = $true
}

$layoutArgs = @{
    BookName = $BookName
    Edition  = $Edition
    Mode     = $Mode
}
Add-OptionalText -Target $layoutArgs -Key "Title" -Value $Title
Add-OptionalText -Target $layoutArgs -Key "Subtitle" -Value $Subtitle
Add-OptionalText -Target $layoutArgs -Key "Author" -Value $Author
if ($Force) {
    $layoutArgs["Force"] = $true
}

Invoke-CoverStep -ScriptName "08d-review.ps1" -StageLabel "08d review" -Arguments $reviewArgs
Invoke-CoverStep -ScriptName "08e-layout.ps1" -StageLabel "08e layout" -Arguments $layoutArgs

Write-Host ""
Write-Host "08-cover-layout completed successfully."
