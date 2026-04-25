param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
$LanguageCode = $Language.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = "zh"
}
Set-SageCurrentStep -Context $Context -Step "build-simple-toc" -Data @{
    language = $LanguageCode
    auto_number = [bool]$AutoNumber
    generator = "python-docx-clean-toc"
}

$BookRoot = $Context.BookRoot
$SourceRoot = if ($LanguageCode -eq "zh") {
    $BookRoot
} else {
    Join-Path $BookRoot ("03_translation\" + $LanguageCode)
}
$ObjectivePath = Join-Path $SourceRoot "00_brief\objective.md"
$ChapterRoot = Join-Path $SourceRoot "02_chapters"
$OutputRoot = Join-Path $BookRoot ("04_output\" + $LanguageCode)
$BuilderScript = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "05a-simple-docx.py"

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [string]$Key
    )

    $Normalized = $Content -replace "`r", ""
    if (-not $Normalized.StartsWith("---`n")) {
        return $null
    }

    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---\n?")
    if (-not $Match.Success) {
        return $null
    }

    $Pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+?)\s*$"
    $ValueMatch = [regex]::Match($Match.Groups[1].Value, $Pattern)
    if (-not $ValueMatch.Success) {
        return $null
    }

    return $ValueMatch.Groups[1].Value.Trim().Trim('"')
}

if (!(Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

if (!(Test-Path $ChapterRoot)) {
    Fail-SageStep -Context $Context -Step "build-simple-toc" -Message "Chapter root not found." -Data @{ chapter_root = $ChapterRoot; language = $LanguageCode }
    Write-Error "Chapter root not found: $ChapterRoot"
    exit 1
}

$mdFiles = Get-ChildItem $ChapterRoot -Filter *.md |
    Where-Object { $_.Name -notmatch "^_" } |
    Sort-Object {
        if ($_.BaseName -match "^\d+") {
            [int]$matches[0]
        }
        else {
            9999
        }
    }

if ($mdFiles.Count -eq 0) {
    Fail-SageStep -Context $Context -Step "build-simple-toc" -Message "No markdown files found." -Data @{ chapter_root = $ChapterRoot; language = $LanguageCode }
    Write-Error "No markdown files found."
    exit 1
}

Write-Host "Found $($mdFiles.Count) chapter files for TOC upload DOCX."
Write-Host ""
foreach ($file in $mdFiles) {
    Write-Host "Adding: $($file.Name)"
}

$DocumentTitle = $BookName
$DocumentAuthor = ""
if (Test-Path $ObjectivePath) {
    $ObjectiveRaw = Get-Content -LiteralPath $ObjectivePath -Raw
    $ObjectiveTitle = Get-FrontMatterValue -Content $ObjectiveRaw -Key "title"
    $ObjectiveAuthor = Get-FrontMatterValue -Content $ObjectiveRaw -Key "author"
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveTitle)) {
        $DocumentTitle = $ObjectiveTitle
    }
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveAuthor)) {
        $DocumentAuthor = $ObjectiveAuthor
    }
}

$OutputFile = Join-Path $OutputRoot "$BookName`_upload_toc.docx"
$BackupRoot = Join-Path $OutputRoot "back"
$BackupFile = $null

if (Test-Path $OutputFile) {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupFile = Join-Path $BackupRoot ("{0}_{1}{2}" -f ($BookName + "_upload_toc"), $Stamp, [System.IO.Path]::GetExtension($OutputFile))
    Copy-Item -LiteralPath $OutputFile -Destination $BackupFile -Force
    Write-Host ""
    Write-Host "Backed up existing TOC upload DOCX to:"
    Write-Host $BackupFile

    try {
        Remove-Item -LiteralPath $OutputFile -Force -ErrorAction Stop
    }
    catch {
        Fail-SageStep -Context $Context -Step "build-simple-toc" -Message "Existing TOC output file is locked." -Data @{
            output = $OutputFile
            backup_output = $BackupFile
            error = $_.Exception.Message
            language = $LanguageCode
        }
        Write-Error "Existing TOC output file is locked. Please close the Word document and try again: $OutputFile"
        exit 1
    }
}

if (!(Test-Path $BuilderScript)) {
    Fail-SageStep -Context $Context -Step "build-simple-toc" -Message "Builder script not found." -Data @{ builder = $BuilderScript; language = $LanguageCode }
    Write-Error "Builder script not found: $BuilderScript"
    exit 1
}

if ($AutoNumber) {
    Write-Host ""
    Write-Host "Auto numbering is ignored in TOC upload mode."
}

try {
    & python $BuilderScript `
        --source-root $SourceRoot `
        --output-file $OutputFile `
        --title $DocumentTitle `
        --author $DocumentAuthor `
        --include-toc

    if ($LASTEXITCODE -ne 0) {
        throw "TOC DOCX builder exited with code $LASTEXITCODE."
    }

    if (!(Test-Path $OutputFile)) {
        throw "TOC DOCX builder did not produce an output file."
    }

    Write-Host ""
    Write-Host "TOC upload DOCX build completed successfully:"
    Write-Host $OutputFile
}
catch {
    Fail-SageStep -Context $Context -Step "build-simple-toc" -Message "TOC upload DOCX build failed." -Data @{
        output = $OutputFile
        error = $_.Exception.Message
        language = $LanguageCode
    }
    Write-Error "TOC upload DOCX build failed: $($_.Exception.Message)"
    exit 1
}

Complete-SageStep -Context $Context -Step "build-simple-toc" -State "success" -Message "TOC upload DOCX build completed." -Data @{
    language = $LanguageCode
    source_root = $SourceRoot
    output = $OutputFile
    backup_output = $BackupFile
    chapter_count = $mdFiles.Count
    cover_included = $false
    document_title = $DocumentTitle
    generator = "python-docx-clean-toc"
}
