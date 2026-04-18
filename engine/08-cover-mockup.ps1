param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$scriptPath = Join-Path $EnginePath "08f-mockup.ps1"

if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Script not found: $scriptPath"
}

$mockupArgs = @{
    BookName = $BookName
    Edition  = $Edition
    Mode     = $Mode
}
if ($Force) {
    $mockupArgs["Force"] = $true
}

Write-Host ""
Write-Host "=== 08f mockup ==="
& $scriptPath @mockupArgs

Write-Host ""
Write-Host "08-cover-mockup completed successfully."
