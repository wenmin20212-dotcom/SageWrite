param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot   = Split-Path -Parent $EnginePath
$ClawRoot   = Split-Path -Parent $SageRoot

$WorkspaceRoot = Join-Path $ClawRoot ("workspace-" + $BookName)
$BookRoot      = Join-Path $WorkspaceRoot "sagewrite\book"
$ChapterRoot   = Join-Path $BookRoot "02_chapters"
$LogRoot       = Join-Path $BookRoot "logs"

if (!(Test-Path $ChapterRoot)) {
    Write-Error "02_chapters folder not found"
    exit 1
}

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot | Out-Null
}

$files = Get-ChildItem $ChapterRoot -Filter *.md | Sort-Object Name

if ($files.Count -eq 0) {
    Write-Error "No markdown files found"
    exit 1
}

$issues = @()

foreach ($file in $files) {

    $lines = Get-Content $file.FullName
    $lineNumber = 0

    foreach ($line in $lines) {

        $lineNumber = $lineNumber + 1

        if ($line.Contains("TODO")) {

            $obj = New-Object PSObject
            Add-Member -InputObject $obj -MemberType NoteProperty -Name File -Value $file.Name
            Add-Member -InputObject $obj -MemberType NoteProperty -Name Line -Value $lineNumber
            Add-Member -InputObject $obj -MemberType NoteProperty -Name Type -Value "Warning"
            Add-Member -InputObject $obj -MemberType NoteProperty -Name Message -Value "Found TODO marker"

            $issues += $obj
        }
    }
}

$reportPath = Join-Path $LogRoot "edit_report.txt"

$issues | Format-Table -AutoSize | Out-File $reportPath

$errorCount = 0
$warnCount  = $issues.Count

Write-Host ""
Write-Host "Edit check completed"
Write-Host "Errors: $errorCount"
Write-Host "Warnings: $warnCount"
Write-Host "Report saved to:"
Write-Host $reportPath

exit 0