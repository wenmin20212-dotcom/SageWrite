param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [string]$Language,

    [string]$Model = "gpt-5.2",

    [int]$Chapter,
    [int]$StartChapter,
    [int]$EndChapter,

    [switch]$All,
    [switch]$Force
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Get-LanguageProfile {
    param(
        [Parameter(Mandatory=$true)]
        [string]$LanguageCode
    )

    $Normalized = $LanguageCode.Trim().ToLowerInvariant()
    switch ($Normalized) {
        "en"      { return @{ code = "en";      name = "English";             native_name = "English" } }
        "ms"      { return @{ code = "ms";      name = "Malay";               native_name = "Bahasa Melayu" } }
        "fr"      { return @{ code = "fr";      name = "French";              native_name = "Francais" } }
        "de"      { return @{ code = "de";      name = "German";              native_name = "Deutsch" } }
        "es"      { return @{ code = "es";      name = "Spanish";             native_name = "Espanol" } }
        "it"      { return @{ code = "it";      name = "Italian";             native_name = "Italiano" } }
        "pt"      { return @{ code = "pt";      name = "Portuguese";          native_name = "Portugues" } }
        "ja"      { return @{ code = "ja";      name = "Japanese";            native_name = "Japanese" } }
        "ko"      { return @{ code = "ko";      name = "Korean";              native_name = "Korean" } }
        "ru"      { return @{ code = "ru";      name = "Russian";             native_name = "Russian" } }
        "ar"      { return @{ code = "ar";      name = "Arabic";              native_name = "Arabic" } }
        "zh"      { return @{ code = "zh";      name = "Chinese";             native_name = "Chinese" } }
        "zh-cn"   { return @{ code = "zh-cn";   name = "Simplified Chinese";  native_name = "Chinese" } }
        "zh-hans" { return @{ code = "zh-hans"; name = "Simplified Chinese";  native_name = "Chinese" } }
        "zh-tw"   { return @{ code = "zh-tw";   name = "Traditional Chinese"; native_name = "Chinese" } }
        "zh-hant" { return @{ code = "zh-hant"; name = "Traditional Chinese"; native_name = "Chinese" } }
        default   { return @{ code = $Normalized; name = $LanguageCode.Trim(); native_name = $LanguageCode.Trim() } }
    }
}

function Normalize-MarkdownOutput {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content.Trim()
    if ($Normalized -match '^(?:```markdown|```md|```)\s*\r?\n([\s\S]*?)\r?\n```$') {
        return $Matches[1].Trim()
    }

    return $Normalized
}

function Save-Utf8File {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Encoding = [System.Text.UTF8Encoding]::new($true)
    [System.IO.File]::WriteAllText($Path, $Content, $Encoding)
}

function Split-TextLines {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    return @($Normalized -split "`n")
}

function New-DiffReportContent {
    param(
        [Parameter(Mandatory=$true)]
        [string]$RelativePath,

        [Parameter(Mandatory=$true)]
        [string]$OriginalText,

        [Parameter(Mandatory=$true)]
        [string]$RefinedText
    )

    $OriginalLines = Split-TextLines -Content $OriginalText
    $RefinedLines = Split-TextLines -Content $RefinedText
    $DiffLines = Compare-Object -ReferenceObject $OriginalLines -DifferenceObject $RefinedLines -SyncWindow 2

    $ReportLines = New-Object System.Collections.Generic.List[string]
    $ReportLines.Add("# Difference Report")
    $ReportLines.Add("")
    $ReportLines.Add("File: $RelativePath")
    $ReportLines.Add("Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
    $ReportLines.Add("")
    $ReportLines.Add('```diff')

    if ($DiffLines.Count -eq 0) {
        $ReportLines.Add("  No line-level differences detected.")
    }
    else {
        foreach ($Line in $DiffLines) {
            $Text = [string]$Line.InputObject
            switch ($Line.SideIndicator) {
                "<=" { $ReportLines.Add("- $Text") }
                "=>" { $ReportLines.Add("+ $Text") }
                default { $ReportLines.Add("  $Text") }
            }
        }
    }

    $ReportLines.Add('```')

    return ($ReportLines -join "`r`n")
}

function Get-TextHash {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
        $HashBytes = $Sha.ComputeHash($Bytes)
        return ([System.BitConverter]::ToString($HashBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $Sha.Dispose()
    }
}

function Get-RefineResult {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceText,

        [Parameter(Mandatory=$true)]
        [string]$ModelName,

        [Parameter(Mandatory=$true)]
        [string]$TargetLanguageName,

        [Parameter(Mandatory=$true)]
        [string]$FileRole,

        [Parameter(Mandatory=$true)]
        [string]$RelativePath
    )

    $Prompt = @"
You are polishing an existing SageWrite markdown file written in $TargetLanguageName.

File role: $FileRole
Relative path: $RelativePath

Your job:
- Refine this file in $TargetLanguageName with the smallest possible number of edits.
- Only fix clear grammar, spelling, punctuation, or obviously unnatural phrasing.
- Keep the meaning intact.
- Keep the language in $TargetLanguageName. Do not translate it into another language.

Rules:
1. Preserve valid Markdown structure exactly.
2. Preserve all front matter keys exactly as written.
3. Preserve heading levels, lists, numbering, blockquotes, tables, links, and code fences.
4. Preserve filenames, chapter indexes, dates, numeric ids, and machine-readable metadata.
5. Do not add commentary, explanations, or surrounding code fences.
6. Return only the improved markdown file content.
7. Only make sentence-internal edits. Do not reorder, merge, split, summarize, expand, or restructure paragraphs or sections.
8. If a sentence is already correct and natural, leave it unchanged.
9. Do not do synonym-swapping optimization, stylistic rewriting, or tone polishing for preference.
10. The output should stay as close to the source text as possible.
11. If the whole file does not clearly need edits, return it unchanged.
12. When in doubt, keep the original wording.

Priority:
- Highest priority: preserve the original text.
- Second priority: fix only clear language errors.
- Lowest priority: improve obvious machine-translated phrasing, but only when the issue is clearly unnatural.

Publication standard note:
- "Publication-grade" here means error-free and naturally readable.
- It does NOT mean rewriting for style, elegance, or stronger voice.

Source markdown:
$SourceText
"@

    $BodyObject = @{
        model = $ModelName
        input = $Prompt
        max_output_tokens = 8000
    }

    $JsonString = $BodyObject | ConvertTo-Json -Depth 10 -Compress
    $Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonString)

    $Response = Invoke-RestMethod `
        -Uri "https://api.openai.com/v1/responses" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
            "Content-Type"  = "application/json; charset=utf-8"
        } `
        -Body $Utf8Bytes

    $OutputText = ""
    foreach ($item in $Response.output) {
        foreach ($content in $item.content) {
            if ($content.type -eq "output_text") {
                $OutputText += $content.text
            }
        }
    }

    if ([string]::IsNullOrWhiteSpace($OutputText)) {
        throw "Empty refine response for $RelativePath"
    }

    $InputTokens = 0
    $OutputTokens = 0
    $TotalTokens = 0
    if ($Response.usage) {
        if ($null -ne $Response.usage.input_tokens) {
            $InputTokens = [int]$Response.usage.input_tokens
        }
        if ($null -ne $Response.usage.output_tokens) {
            $OutputTokens = [int]$Response.usage.output_tokens
        }
        if ($null -ne $Response.usage.total_tokens) {
            $TotalTokens = [int]$Response.usage.total_tokens
        }
    }

    return @{
        content = (Normalize-MarkdownOutput -Content $OutputText)
        usage = @{
            input_tokens  = $InputTokens
            output_tokens = $OutputTokens
            total_tokens  = $TotalTokens
        }
    }
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context

$LanguageProfile = Get-LanguageProfile -LanguageCode $Language
$TargetCode = $LanguageProfile.code
$TargetLanguageName = $LanguageProfile.name
$SelectedModel = $Model.Trim()
if ([string]::IsNullOrWhiteSpace($SelectedModel)) {
    $SelectedModel = "gpt-5.2"
}

Set-SageCurrentStep -Context $Context -Step "refine_translation" -Data @{
    language = $TargetCode
    model = $SelectedModel
    chapter = $Chapter
    start_chapter = $StartChapter
    end_chapter = $EndChapter
    all = [bool]$All
    force = [bool]$Force
}

$BookRoot = $Context.BookRoot
$TranslationRoot = Join-Path $BookRoot ("03_translation\" + $TargetCode)
$TargetBriefRoot = Join-Path $TranslationRoot "00_brief"
$TargetOutlineRoot = Join-Path $TranslationRoot "01_outline"
$TargetChapterRoot = Join-Path $TranslationRoot "02_chapters"
$ManifestPath = Join-Path $TranslationRoot "refine_manifest.json"
$BackupRoot = Join-Path $TranslationRoot "_refine_backups"

if (!(Test-Path $TranslationRoot)) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "Translation root not found." -Data @{ language = $TargetCode; translation_root = $TranslationRoot }
    Write-Output "ERROR: Translation root not found."
    exit 1
}

if (!(Test-Path $TargetChapterRoot)) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "Translated chapter folder not found." -Data @{ language = $TargetCode; chapter_root = $TargetChapterRoot }
    Write-Output "ERROR: Translated chapter folder not found."
    exit 1
}

if (-not $env:OPENAI_API_KEY) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "OPENAI_API_KEY not set." -Data @{ language = $TargetCode }
    Write-Output "ERROR: OPENAI_API_KEY not set."
    exit 1
}

$ChapterFiles = Get-ChildItem -LiteralPath $TargetChapterRoot -Filter *.md -File |
    Where-Object { $_.Name -notmatch "^_" } |
    Sort-Object Name

$TotalChapters = $ChapterFiles.Count
if ($TotalChapters -eq 0) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "No translated chapter files found." -Data @{ language = $TargetCode; chapter_root = $TargetChapterRoot }
    Write-Output "ERROR: No translated chapter files found."
    exit 1
}

if ($All -and ($Chapter -or $StartChapter -or $EndChapter)) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "Conflicting refine scope arguments." -Data @{
        language = $TargetCode
        chapter = $Chapter
        start_chapter = $StartChapter
        end_chapter = $EndChapter
        all = [bool]$All
    }
    Write-Output "ERROR: Cannot combine -All with chapter selection arguments."
    exit 1
}

if ($Chapter -and ($StartChapter -or $EndChapter)) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "Conflicting chapter arguments." -Data @{
        language = $TargetCode
        chapter = $Chapter
        start_chapter = $StartChapter
        end_chapter = $EndChapter
    }
    Write-Output "ERROR: Cannot use -Chapter with -StartChapter/-EndChapter."
    exit 1
}

if ($All -or (-not $Chapter -and -not $StartChapter -and -not $EndChapter)) {
    $StartIndex = 1
    $EndIndex = $TotalChapters
}
elseif ($Chapter) {
    if ($Chapter -lt 1 -or $Chapter -gt $TotalChapters) {
        Fail-SageStep -Context $Context -Step "refine_translation" -Message "Chapter out of range." -Data @{
            language = $TargetCode
            chapter = $Chapter
            chapter_count = $TotalChapters
        }
        Write-Output "ERROR: Chapter out of range."
        exit 1
    }

    $StartIndex = $Chapter
    $EndIndex = $Chapter
}
else {
    if (-not $StartChapter -or -not $EndChapter) {
        Fail-SageStep -Context $Context -Step "refine_translation" -Message "Chapter range missing boundary." -Data @{
            language = $TargetCode
            start_chapter = $StartChapter
            end_chapter = $EndChapter
        }
        Write-Output "ERROR: Both -StartChapter and -EndChapter must be specified."
        exit 1
    }

    if ($StartChapter -lt 1 -or $EndChapter -gt $TotalChapters -or $StartChapter -gt $EndChapter) {
        Fail-SageStep -Context $Context -Step "refine_translation" -Message "Invalid chapter range." -Data @{
            language = $TargetCode
            start_chapter = $StartChapter
            end_chapter = $EndChapter
            chapter_count = $TotalChapters
        }
        Write-Output "ERROR: Invalid chapter range."
        exit 1
    }

    $StartIndex = $StartChapter
    $EndIndex = $EndChapter
}

$PreviousManifestEntries = @{}
if (Test-Path $ManifestPath) {
    try {
        $PreviousManifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json -Depth 20
        if ($PreviousManifest.entries) {
            foreach ($Entry in $PreviousManifest.entries) {
                if ($Entry.relative_path) {
                    $PreviousManifestEntries[$Entry.relative_path] = $Entry
                }
            }
        }
    }
    catch {
        Write-Output "WARN: Failed to read previous refine_manifest.json, continuing with a fresh run."
    }
}

$Candidates = New-Object System.Collections.Generic.List[object]

if ($All) {
    $CommonFiles = @(
        @{
            source = Join-Path $TargetBriefRoot "objective.md"
            role = "objective"
            relative = "00_brief/objective.md"
        },
        @{
            source = Join-Path $TargetOutlineRoot "toc.md"
            role = "toc"
            relative = "01_outline/toc.md"
        }
    )

    foreach ($Item in $CommonFiles) {
        $Candidates.Add($Item)
    }
}

for ($i = $StartIndex; $i -le $EndIndex; $i++) {
    $ChapterFile = $ChapterFiles[$i - 1]
    $Candidates.Add(@{
        source = $ChapterFile.FullName
        role = "chapter"
        relative = "02_chapters/$($ChapterFile.Name)"
    })
}

$ExistingCandidates = @($Candidates | Where-Object { Test-Path $_.source })
if ($ExistingCandidates.Count -eq 0) {
    Fail-SageStep -Context $Context -Step "refine_translation" -Message "No translated markdown files found for selected scope." -Data @{
        language = $TargetCode
        translation_root = $TranslationRoot
        start_chapter = $StartIndex
        end_chapter = $EndIndex
    }
    Write-Output "ERROR: No translated markdown files found for selected scope."
    exit 1
}

$StartTime = Get-Date
$BackupStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$BackupSessionRoot = Join-Path $BackupRoot $BackupStamp
$BackupCreated = $false
$RefinedFiles = @()
$SkippedFiles = @()
$UnchangedFiles = @()
$MissingFiles = @()
$ManifestEntries = @()
$DiffFiles = @()
$TotalInputTokens = 0
$TotalOutputTokens = 0
$TotalTokens = 0

foreach ($Item in $Candidates) {
    if (!(Test-Path $Item.source)) {
        $MissingFiles += $Item.relative
        Write-Output "$($Item.relative) not found. Skipping."
        continue
    }

    $SourceText = Get-Content -LiteralPath $Item.source -Raw -Encoding UTF8
    $SourceHash = Get-TextHash -Content $SourceText
    $PreviousEntry = $PreviousManifestEntries[$Item.relative]
    if ((-not $Force) -and $PreviousEntry -and ($PreviousEntry.source_hash -eq $SourceHash)) {
        $SkippedFiles += $Item.relative
        Write-Output "$($Item.relative) already refined and unchanged. Skipping."
        continue
    }

    Write-Output "Refining $($Item.relative) -> $TargetCode"

    try {
        $Result = Get-RefineResult -SourceText $SourceText -ModelName $SelectedModel -TargetLanguageName $TargetLanguageName -FileRole $Item.role -RelativePath $Item.relative
        $RefinedText = $Result.content
        $RefinedHash = Get-TextHash -Content $RefinedText

        if ($RefinedHash -ne $SourceHash) {
            if (-not $BackupCreated) {
                New-Item -ItemType Directory -Path $BackupSessionRoot -Force | Out-Null
                $BackupCreated = $true
            }

            $BackupPath = Join-Path $BackupSessionRoot ($Item.relative -replace "/", "\")
            $BackupDir = Split-Path -Parent $BackupPath
            if (!(Test-Path $BackupDir)) {
                New-Item -ItemType Directory -Path $BackupDir -Force | Out-Null
            }

            Copy-Item -LiteralPath $Item.source -Destination $BackupPath -Force
            $DiffPath = [System.IO.Path]::ChangeExtension($BackupPath, ".diff.md")
            $DiffContent = New-DiffReportContent -RelativePath $Item.relative -OriginalText $SourceText -RefinedText $RefinedText
            Save-Utf8File -Path $DiffPath -Content $DiffContent
            Save-Utf8File -Path $Item.source -Content $RefinedText
            $RefinedFiles += $Item.relative
            $DiffFiles += ($DiffPath.Substring($BackupSessionRoot.Length).TrimStart("\"))
        }
        else {
            $UnchangedFiles += $Item.relative
        }

        $ManifestEntries += [ordered]@{
            relative_path = $Item.relative
            file_role = $Item.role
            source_hash = $RefinedHash
            changed = ($RefinedHash -ne $SourceHash)
            refined_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        }

        $TotalInputTokens += $Result.usage.input_tokens
        $TotalOutputTokens += $Result.usage.output_tokens
        $TotalTokens += $Result.usage.total_tokens
    }
    catch {
        Fail-SageStep -Context $Context -Step "refine_translation" -Message "Failed to refine translated markdown file." -Data @{
            language = $TargetCode
            file = $Item.relative
            error = $_.Exception.Message
        }
        Write-Output "ERROR: Failed refining $($Item.relative)"
        exit 1
    }
}

$Manifest = [ordered]@{
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    book_name = $BookName
    target_language = $TargetCode
    target_language_name = $TargetLanguageName
    scope = if ($All) { "all" } elseif ($Chapter) { "single" } elseif ($StartChapter -or $EndChapter) { "range" } else { "all" }
    chapter_range = @{
        start = $StartIndex
        end = $EndIndex
        total_chapters = $TotalChapters
    }
    refined_files = $RefinedFiles
    diff_files = $DiffFiles
    unchanged_files = $UnchangedFiles
    skipped_files = $SkippedFiles
    missing_files = $MissingFiles
    backup_root = if ($BackupCreated) { $BackupSessionRoot } else { "" }
    usage = @{
        input_tokens = $TotalInputTokens
        output_tokens = $TotalOutputTokens
        total_tokens = $TotalTokens
        model = $SelectedModel
    }
    entries = $ManifestEntries
}

$Manifest | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $ManifestPath -Encoding utf8

$Duration = [math]::Round(((Get-Date) - $StartTime).TotalSeconds, 2)
Complete-SageStep -Context $Context -Step "refine_translation" -State "success" -Message "Translation refinement completed." -Data @{
    language = $TargetCode
    refined_file_count = $RefinedFiles.Count
    diff_file_count = $DiffFiles.Count
    unchanged_file_count = $UnchangedFiles.Count
    skipped_file_count = $SkippedFiles.Count
    missing_file_count = $MissingFiles.Count
    processed_range = "$StartIndex-$EndIndex"
    duration_seconds = $Duration
    translation_root = $TranslationRoot
    backup_root = if ($BackupCreated) { $BackupSessionRoot } else { "" }
    model = $SelectedModel
    input_tokens_total = $TotalInputTokens
    output_tokens_total = $TotalOutputTokens
    total_tokens_total = $TotalTokens
}

Write-Output "SUCCESS: Translation refinement completed for $TargetCode."
Write-Output "Model: $SelectedModel"
Write-Output "Translation root: $TranslationRoot"
if ($BackupCreated) {
    Write-Output "Backup root: $BackupSessionRoot"
}
