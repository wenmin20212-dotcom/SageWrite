param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$AutoNumber
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
chcp 65001 | Out-Null
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
$LanguageCode = $Language.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = "zh"
}
Set-SageCurrentStep -Context $Context -Step "build_epub" -Data @{
    language = $LanguageCode
    auto_number = [bool]$AutoNumber
}

$WorkspaceRoot = $Context.WorkspaceRoot
$BookRoot = $Context.BookRoot
$SourceRoot = if ($LanguageCode -eq "zh") {
    $BookRoot
} else {
    Join-Path $BookRoot ("03_translation\" + $LanguageCode)
}
$ObjectivePath = Join-Path $SourceRoot "00_brief\objective.md"
$TocPath = Join-Path $SourceRoot "01_outline\toc.md"
$ChapterRoot = Join-Path $SourceRoot "02_chapters"
$OutputRoot = Join-Path $BookRoot ("04_output\" + $LanguageCode)
$LogRoot = $Context.LogRoot
$BuildTempRoot = Join-Path $LogRoot ("_build_epub_tmp_" + $LanguageCode)

function Get-CoverImagePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RootPath
    )

    $SearchRoots = @(
        $RootPath,
        (Join-Path $RootPath "02_chapters")
    ) | Select-Object -Unique

    $CandidateNames = @(
        "cover.png",
        "cover.jpg",
        "cover.jpeg",
        "cover.webp"
    )

    foreach ($SearchRoot in $SearchRoots) {
        foreach ($Name in $CandidateNames) {
            $CandidatePath = Join-Path $SearchRoot $Name
            if (Test-Path $CandidatePath) {
                return $CandidatePath
            }
        }
    }

    return $null
}

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,

        [Parameter(Mandatory = $true)]
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

function Get-MarkdownBodyText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    if ($Normalized.StartsWith("---`n")) {
        $Match = [regex]::Match($Normalized, "(?s)^---\n.*?\n---\n?")
        if ($Match.Success) {
            return $Normalized.Substring($Match.Length).Trim()
        }
    }

    return $Normalized.Trim()
}

function Copy-SageAssetsToBuildTemp {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookRoot,

        [Parameter(Mandatory = $true)]
        [string]$BuildTempRoot
    )

    $AssetRoot = Join-Path $BookRoot "03_assets"
    if (!(Test-Path -LiteralPath $AssetRoot)) {
        return $null
    }

    Copy-Item -LiteralPath $AssetRoot -Destination $BuildTempRoot -Recurse -Force
    return $AssetRoot
}

function Convert-SageAssetReferencesForBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    return [regex]::Replace($Content, '\.\.[/\\]03_assets[/\\]', '03_assets/')
}

function Get-BookStructureFromToc {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $SectionToChapter = @{}
    $ChapterCount = 0
    $SectionCount = 0
    $CurrentChapter = $null

    if (!(Test-Path $Path)) {
        return [PSCustomObject]@{
            Available = $false
            SectionToChapter = $SectionToChapter
            ChapterCount = 0
            SectionCount = 0
        }
    }

    foreach ($Line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $Trimmed = $Line.Trim()
        if ($Trimmed -match '^##\s+(.+?)\s*$') {
            $CurrentChapter = $Matches[1].Trim()
            $ChapterCount++
            continue
        }

        if ($Trimmed -match '^###\s+(.+?)\s*$' -and -not [string]::IsNullOrWhiteSpace($CurrentChapter)) {
            $SectionTitle = $Matches[1].Trim()
            $SectionToChapter[$SectionTitle] = $CurrentChapter
            if ($SectionTitle -match '^(\d+(?:\.\d+)*)\b') {
                $SectionToChapter[$Matches[1]] = $CurrentChapter
            }
            $SectionCount++
        }
    }

    return [PSCustomObject]@{
        Available = $true
        SectionToChapter = $SectionToChapter
        ChapterCount = $ChapterCount
        SectionCount = $SectionCount
    }
}

function Get-FirstMarkdownHeadingTitle {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    $Match = [regex]::Match($Content, '(?m)^\s*#{1,6}\s+(.+?)\s*$')
    if ($Match.Success) {
        return $Match.Groups[1].Value.Trim()
    }

    return $null
}

function Convert-SectionHeadingsForBookBuild {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content
    )

    return [regex]::Replace($Content, '(?m)^(#{3,6})(\s+)', {
        param($Match)
        $Level = [Math]::Max(1, $Match.Groups[1].Value.Length - 1)
        return ("#" * $Level) + $Match.Groups[2].Value
    })
}

function Convert-ToBookBuildMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Body,

        [Parameter(Mandatory = $true)]
        [object]$BookStructure,

        [System.Collections.Generic.HashSet[string]]$SeenChapterTitles
    )

    $Content = $Body.Trim()
    if (-not $BookStructure.Available -or $BookStructure.SectionCount -le 0) {
        return $Content
    }

    $SectionTitle = Get-FirstMarkdownHeadingTitle -Content $Content
    if ([string]::IsNullOrWhiteSpace($SectionTitle)) {
        return $Content
    }

    $ChapterTitle = $null
    if ($BookStructure.SectionToChapter.ContainsKey($SectionTitle)) {
        $ChapterTitle = $BookStructure.SectionToChapter[$SectionTitle]
    }
    elseif ($SectionTitle -match '^(\d+(?:\.\d+)*)\b' -and $BookStructure.SectionToChapter.ContainsKey($Matches[1])) {
        $ChapterTitle = $BookStructure.SectionToChapter[$Matches[1]]
    }

    if ([string]::IsNullOrWhiteSpace($ChapterTitle)) {
        return $Content
    }

    $Content = Convert-SectionHeadingsForBookBuild -Content $Content
    if (-not $SeenChapterTitles.Contains($ChapterTitle)) {
        [void]$SeenChapterTitles.Add($ChapterTitle)
        return "# $ChapterTitle`r`n`r`n$Content"
    }

    return $Content
}

function Remove-UnsupportedEpubCssRules {
    param(
        [Parameter(Mandatory = $true)]
        [string]$EpubPath
    )

    if (!(Test-Path $EpubPath)) {
        return $false
    }

    $Zip = $null
    $Updated = $false

    try {
        $Zip = [System.IO.Compression.ZipFile]::Open($EpubPath, [System.IO.Compression.ZipArchiveMode]::Update)
        $CssEntries = @($Zip.Entries | Where-Object { $_.FullName -like "EPUB/styles/*.css" })
        if ($CssEntries.Count -eq 0) {
            return $false
        }

        $RulePattern = '(?s)\s*ul\.task-list\s*\{.*?\}\s*ul\.task-list\s+li\s+input\[type="checkbox"\]\s*\{.*?\}\s*'

        foreach ($CssEntry in $CssEntries) {
            $Reader = New-Object System.IO.StreamReader($CssEntry.Open())
            try {
                $CssContent = $Reader.ReadToEnd()
            }
            finally {
                $Reader.Dispose()
            }

            $SanitizedCss = [regex]::Replace($CssContent, $RulePattern, "`r`n")
            if ($SanitizedCss -eq $CssContent) {
                continue
            }

            $EntryName = $CssEntry.FullName
            $CssEntry.Delete()

            $NewEntry = $Zip.CreateEntry($EntryName)
            $Writer = New-Object System.IO.StreamWriter($NewEntry.Open(), [System.Text.UTF8Encoding]::new($false))
            try {
                $Writer.Write($SanitizedCss)
            }
            finally {
                $Writer.Dispose()
            }

            $Updated = $true
        }
    }
    finally {
        if ($null -ne $Zip) {
            $Zip.Dispose()
        }
    }

    return $Updated
}

if (!(Test-Path $WorkspaceRoot)) {
    Fail-SageStep -Context $Context -Step "build_epub" -Message "Workspace not found." -Data @{ workspace = $WorkspaceRoot; language = $LanguageCode }
    Write-Error "Workspace not found: $WorkspaceRoot"
    exit 1
}

if (!(Test-Path $SourceRoot)) {
    Fail-SageStep -Context $Context -Step "build_epub" -Message "Language source root not found." -Data @{ source_root = $SourceRoot; language = $LanguageCode }
    Write-Error "Language source root not found: $SourceRoot"
    exit 1
}

if (!(Test-Path $ChapterRoot)) {
    Fail-SageStep -Context $Context -Step "build_epub" -Message "Chapter folder not found." -Data @{ chapter_root = $ChapterRoot; language = $LanguageCode }
    Write-Error "Chapter folder not found: $ChapterRoot"
    exit 1
}

if (!(Test-Path $OutputRoot)) {
    New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
}

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

if (!(Get-Command pandoc -ErrorAction SilentlyContinue)) {
    Fail-SageStep -Context $Context -Step "build_epub" -Message "Pandoc not found." -Data @{ language = $LanguageCode }
    Write-Error "Pandoc not found."
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
    Fail-SageStep -Context $Context -Step "build_epub" -Message "No markdown files found." -Data @{ chapter_root = $ChapterRoot; language = $LanguageCode }
    Write-Error "No markdown files found."
    exit 1
}

Write-Host "Found $($mdFiles.Count) chapter files."
Write-Host ""

foreach ($file in $mdFiles) {
    Write-Host "Adding: $($file.Name)"
}

$BookStructure = Get-BookStructureFromToc -Path $TocPath
if ($BookStructure.Available -and $BookStructure.SectionCount -gt 0) {
    Write-Host ""
    Write-Host "Using TOC chapter structure:"
    Write-Host $TocPath
}
else {
    Write-Host ""
    Write-Host "TOC chapter structure not found; building chapter files as-is."
}

$DocumentTitle = $BookName
$DocumentAuthor = "Generated by SageWrite"
if (Test-Path $ObjectivePath) {
    $ObjectiveRaw = Get-Content -LiteralPath $ObjectivePath -Raw -Encoding UTF8
    $ObjectiveTitle = Get-FrontMatterValue -Content $ObjectiveRaw -Key "title"
    $ObjectiveAuthor = Get-FrontMatterValue -Content $ObjectiveRaw -Key "author"
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveTitle)) {
        $DocumentTitle = $ObjectiveTitle
    }
    if (-not [string]::IsNullOrWhiteSpace($ObjectiveAuthor)) {
        $DocumentAuthor = $ObjectiveAuthor
    }
}

$TitleYamlLines = @("title: |")
$TitleYamlLines += ($DocumentTitle -split "`r?`n" | ForEach-Object { "  $_" })
$MetaContent = @(
    $TitleYamlLines
    "lang: $LanguageCode"
    $(if ($LanguageCode -eq 'zh') { 'toc-title: 目录' })
    "author: ""$DocumentAuthor"""
    "date: ""$(Get-Date -Format yyyy-MM-dd)"""
) -join "`r`n"

if (Test-Path $BuildTempRoot) {
    Remove-Item $BuildTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}
New-Item -ItemType Directory -Path $BuildTempRoot -Force | Out-Null

$BuildFiles = @()
$CoverImagePath = Get-CoverImagePath -RootPath $SourceRoot
if ($CoverImagePath) {
    $CoverFileName = [System.IO.Path]::GetFileName($CoverImagePath)
    $CoverTempPath = Join-Path $BuildTempRoot $CoverFileName
    Copy-Item -LiteralPath $CoverImagePath -Destination $CoverTempPath -Force

    Write-Host ""
    Write-Host "Including cover image:"
    Write-Host $CoverImagePath
}

$AssetSourceRoot = Copy-SageAssetsToBuildTemp -BookRoot $BookRoot -BuildTempRoot $BuildTempRoot
if ($AssetSourceRoot) {
    Write-Host ""
    Write-Host "Including asset directory:"
    Write-Host $AssetSourceRoot
}

$SeenChapterTitles = New-Object 'System.Collections.Generic.HashSet[string]'
$ReferenceLabels = @{}
$ReferencesPath = Join-Path $ChapterRoot 'references.md'
if (Test-Path -LiteralPath $ReferencesPath) {
    $ReferencesRaw = Get-Content -LiteralPath $ReferencesPath -Raw -Encoding UTF8
    foreach ($Match in [regex]::Matches($ReferencesRaw, '(?m)^\[(前-\d+|\d+-\d+)\] ')) {
        $Label = $Match.Groups[1].Value
        $ReferenceLabels[$Label] = 'ref-' + $Label.Replace('前', 'front')
    }
}
foreach ($file in $mdFiles) {
    $Raw = Get-Content -LiteralPath $file.FullName -Raw -Encoding UTF8
    $Body = Get-MarkdownBodyText -Content $Raw
    $Body = Convert-ToBookBuildMarkdown -Body $Body -BookStructure $BookStructure -SeenChapterTitles $SeenChapterTitles
    $Body = Convert-SageAssetReferencesForBuild -Content $Body
    # Resolve 04R labels only in the build copy; source hashes remain unchanged.
    if ($file.Name -eq 'references.md') {
        $Body = [regex]::Replace($Body, '(?m)^\[(前-\d+|\d+-\d+)\] ', {
            param($m)
            $Label = $m.Groups[1].Value
            return '[\[' + $Label + '\]]{#' + $ReferenceLabels[$Label] + '} '
        })
        $Body = [regex]::Replace($Body, '\.\. (?=\(\d{4}\)|\(n\.d\.\))', '. ')
        $Body = [regex]::Replace($Body, '(?m)(https?://\S+)\s*$', {
            param($m)
            return '<' + $m.Groups[1].Value + '>' + "`n"
        })
    }
    elseif ($file.BaseName -match '^\d+$') {
        $Body = [regex]::Replace($Body, '\[(前-\d+|\d+-\d+)\]', {
            param($m)
            $Label = $m.Groups[1].Value
            if (!$ReferenceLabels.ContainsKey($Label)) { throw "Unresolved citation: $Label" }
            return '[\[' + $Label + '\]](#' + $ReferenceLabels[$Label] + ')'
        })
    }
    $TempPath = Join-Path $BuildTempRoot $file.Name
    Set-Content -LiteralPath $TempPath -Encoding utf8 -Value $Body
    $BuildFiles += $TempPath
}

$MetaFile = Join-Path $BuildTempRoot "_metadata_epub.yaml"
$MetaContent | Set-Content -LiteralPath $MetaFile -Encoding utf8

$OutputFile = Join-Path $OutputRoot "$BookName`_full.epub"
$BackupRoot = Join-Path $OutputRoot "back"
$BackupFile = $null

if (Test-Path $OutputFile) {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $BackupFile = Join-Path $BackupRoot ("{0}_{1}{2}" -f $BookName, $Stamp, [System.IO.Path]::GetExtension($OutputFile))
    Copy-Item -LiteralPath $OutputFile -Destination $BackupFile -Force
    Write-Host ""
    Write-Host "Backed up existing output to:"
    Write-Host $BackupFile

    try {
        Remove-Item -LiteralPath $OutputFile -Force -ErrorAction Stop
    }
    catch {
        Fail-SageStep -Context $Context -Step "build_epub" -Message "Existing EPUB file is locked." -Data @{
            output = $OutputFile
            backup_output = $BackupFile
            error = $_.Exception.Message
            language = $LanguageCode
        }
        Write-Error "Existing EPUB file is locked. Please close any reader or sync process and try again: $OutputFile"
        exit 1
    }
}

$PandocArgs = @()
$PandocArgs += $BuildFiles
$PandocArgs += "--metadata-file=$MetaFile"
$PandocArgs += "-o"
$PandocArgs += $OutputFile
$PandocArgs += "--resource-path=$BuildTempRoot"
$PandocArgs += "--toc"
$PandocArgs += "--standalone"
if ($CoverImagePath) {
    $PandocArgs += "--epub-cover-image=$CoverTempPath"
}

if ($AutoNumber) {
    Write-Host ""
    Write-Host "Auto numbering enabled."
    $PandocArgs += "--number-sections"
}
else {
    Write-Host ""
    Write-Host "Auto numbering disabled."
}

try {
    & pandoc @PandocArgs
    $PandocExitCode = $LASTEXITCODE

    if ($PandocExitCode -ne 0) {
        throw "Pandoc exited with code $PandocExitCode."
    }

    if (!(Test-Path $OutputFile)) {
        throw "Pandoc EPUB build failed."
    }

    $CssSanitized = Remove-UnsupportedEpubCssRules -EpubPath $OutputFile
    if ($CssSanitized) {
        Write-Host ""
        Write-Host "Removed unsupported EPUB CSS rules."
    }

    Write-Host ""
    Write-Host "EPUB build completed successfully:"
    Write-Host $OutputFile
}
catch {
    Fail-SageStep -Context $Context -Step "build_epub" -Message "EPUB build failed." -Data @{
        output = $OutputFile
        error = $_.Exception.Message
        language = $LanguageCode
    }
    Write-Error "EPUB build failed: $_"
    exit 1
}
finally {
    Remove-Item -LiteralPath $MetaFile -ErrorAction SilentlyContinue
    Remove-Item $BuildTempRoot -Recurse -Force -ErrorAction SilentlyContinue
}

Complete-SageStep -Context $Context -Step "build_epub" -State "success" -Message "EPUB build completed." -Data @{
    language = $LanguageCode
    source_root = $SourceRoot
    output = $OutputFile
    backup_output = $BackupFile
    chapter_count = $mdFiles.Count
    cover_included = [bool]$CoverImagePath
    cover_source = $CoverImagePath
    document_title = $DocumentTitle
    document_author = $DocumentAuthor
    auto_number = [bool]$AutoNumber
}
