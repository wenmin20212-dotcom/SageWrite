param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [string]$Language,

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
        "en"      { return @{ code = "en";      name = "English";           native_name = "English" } }
        "ms"      { return @{ code = "ms";      name = "Malay";             native_name = "Bahasa Melayu" } }
        "fr"      { return @{ code = "fr";      name = "French";            native_name = "Francais" } }
        "de"      { return @{ code = "de";      name = "German";            native_name = "Deutsch" } }
        "es"      { return @{ code = "es";      name = "Spanish";           native_name = "Espanol" } }
        "it"      { return @{ code = "it";      name = "Italian";           native_name = "Italiano" } }
        "pt"      { return @{ code = "pt";      name = "Portuguese";        native_name = "Portugues" } }
        "ja"      { return @{ code = "ja";      name = "Japanese";          native_name = "Japanese" } }
        "ko"      { return @{ code = "ko";      name = "Korean";            native_name = "Korean" } }
        "ru"      { return @{ code = "ru";      name = "Russian";           native_name = "Russian" } }
        "ar"      { return @{ code = "ar";      name = "Arabic";            native_name = "Arabic" } }
        "zh"      { return @{ code = "zh";      name = "Chinese";           native_name = "Chinese" } }
        "zh-cn"   { return @{ code = "zh-cn";   name = "Simplified Chinese"; native_name = "Chinese" } }
        "zh-hans" { return @{ code = "zh-hans"; name = "Simplified Chinese"; native_name = "Chinese" } }
        "zh-tw"   { return @{ code = "zh-tw";   name = "Traditional Chinese"; native_name = "Chinese" } }
        "zh-hant" { return @{ code = "zh-hant"; name = "Traditional Chinese"; native_name = "Chinese" } }
        default   { return @{ code = $Normalized; name = $LanguageCode.Trim(); native_name = $LanguageCode.Trim() } }
    }
}

function Get-FrontMatterBlock {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---\n?")
    if ($Match.Success) {
        return $Match.Value.TrimEnd()
    }

    return ""
}

function Get-MarkdownBody {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    $Match = [regex]::Match($Normalized, "(?s)^---\n.*?\n---\n?")
    if ($Match.Success) {
        return $Normalized.Substring($Match.Length).TrimStart("`n")
    }

    return $Normalized
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

function Invoke-TranslatedMarkdown {
    param(
        [Parameter(Mandatory=$true)]
        [string]$SourceText,

        [Parameter(Mandatory=$true)]
        [string]$TargetLanguageName,

        [Parameter(Mandatory=$true)]
        [string]$FileRole,

        [Parameter(Mandatory=$true)]
        [string]$RelativePath
    )

    $Prompt = @"
You are translating a SageWrite markdown file from Chinese into $TargetLanguageName.

File role: $FileRole
Relative path: $RelativePath

Rules:
1. Preserve valid Markdown structure.
2. Preserve all front matter keys exactly as written. Translate front matter values, but do not rename keys.
3. Preserve heading levels, lists, numbering, blockquotes, tables, and links.
4. Preserve fenced code blocks exactly unless the fenced block is clearly normal prose wrapped in a markdown fence by mistake.
5. Translate normal prose completely and naturally into $TargetLanguageName.
6. Preserve filenames, chapter indexes, dates, numeric ids, and machine-readable metadata keys.
7. Do not add commentary, explanations, or surrounding code fences.
8. Return only the translated markdown file content.

Source markdown:
$SourceText
"@

    $BodyObject = @{
        model = "gpt-5.2"
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
        throw "Empty translation response for $RelativePath"
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

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context

$LanguageProfile = Get-LanguageProfile -LanguageCode $Language
$TargetCode = $LanguageProfile.code
$TargetLanguageName = $LanguageProfile.name

Set-SageCurrentStep -Context $Context -Step "translate" -Data @{
    language = $TargetCode
    chapter = $Chapter
    start_chapter = $StartChapter
    end_chapter = $EndChapter
    all = [bool]$All
    force = [bool]$Force
}

$BookRoot = $Context.BookRoot
$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
$TocPath = Join-Path $BookRoot "01_outline\toc.md"
$ChapterRoot = Join-Path $BookRoot "02_chapters"
$TranslationRoot = Join-Path $BookRoot ("03_translation\" + $TargetCode)
$TargetBriefRoot = Join-Path $TranslationRoot "00_brief"
$TargetOutlineRoot = Join-Path $TranslationRoot "01_outline"
$TargetChapterRoot = Join-Path $TranslationRoot "02_chapters"
$ManifestPath = Join-Path $TranslationRoot "translation_manifest.json"

if (!(Test-Path $ObjectivePath)) {
    Fail-SageStep -Context $Context -Step "translate" -Message "objective.md not found." -Data @{ objective = $ObjectivePath; language = $TargetCode }
    Write-Output "ERROR: objective.md not found."
    exit 1
}

if (!(Test-Path $TocPath)) {
    Fail-SageStep -Context $Context -Step "translate" -Message "toc.md not found." -Data @{ toc = $TocPath; language = $TargetCode }
    Write-Output "ERROR: toc.md not found."
    exit 1
}

if (!(Test-Path $ChapterRoot)) {
    Fail-SageStep -Context $Context -Step "translate" -Message "02_chapters not found." -Data @{ chapters = $ChapterRoot; language = $TargetCode }
    Write-Output "ERROR: 02_chapters not found."
    exit 1
}

if (-not $env:OPENAI_API_KEY) {
    Fail-SageStep -Context $Context -Step "translate" -Message "OPENAI_API_KEY not set." -Data @{ language = $TargetCode }
    Write-Output "ERROR: OPENAI_API_KEY not set."
    exit 1
}

$ChapterFiles = Get-ChildItem -LiteralPath $ChapterRoot -Filter *.md -File |
    Where-Object { $_.Name -notmatch "^_" } |
    Sort-Object Name

$TotalChapters = $ChapterFiles.Count
if ($TotalChapters -eq 0) {
    Fail-SageStep -Context $Context -Step "translate" -Message "No chapter files found." -Data @{ chapter_root = $ChapterRoot; language = $TargetCode }
    Write-Output "ERROR: No chapter files found."
    exit 1
}

if ($All -and ($Chapter -or $StartChapter -or $EndChapter)) {
    Fail-SageStep -Context $Context -Step "translate" -Message "Conflicting translation scope arguments." -Data @{
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
    Fail-SageStep -Context $Context -Step "translate" -Message "Conflicting chapter arguments." -Data @{
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
        Fail-SageStep -Context $Context -Step "translate" -Message "Chapter out of range." -Data @{
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
        Fail-SageStep -Context $Context -Step "translate" -Message "Chapter range missing boundary." -Data @{
            language = $TargetCode
            start_chapter = $StartChapter
            end_chapter = $EndChapter
        }
        Write-Output "ERROR: Both -StartChapter and -EndChapter must be specified."
        exit 1
    }

    if ($StartChapter -lt 1 -or $EndChapter -gt $TotalChapters -or $StartChapter -gt $EndChapter) {
        Fail-SageStep -Context $Context -Step "translate" -Message "Invalid chapter range." -Data @{
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

New-Item -ItemType Directory -Path $TranslationRoot -Force | Out-Null
New-Item -ItemType Directory -Path $TargetBriefRoot -Force | Out-Null
New-Item -ItemType Directory -Path $TargetOutlineRoot -Force | Out-Null
New-Item -ItemType Directory -Path $TargetChapterRoot -Force | Out-Null

$StartTime = Get-Date
$TranslatedFiles = @()
$SkippedFiles = @()
$TotalInputTokens = 0
$TotalOutputTokens = 0
$TotalTokens = 0

$CommonSourceFiles = @(
    @{
        source = $ObjectivePath
        target = Join-Path $TargetBriefRoot "objective.md"
        role = "objective"
        relative = "00_brief/objective.md"
    },
    @{
        source = $TocPath
        target = Join-Path $TargetOutlineRoot "toc.md"
        role = "toc"
        relative = "01_outline/toc.md"
    }
)

foreach ($item in $CommonSourceFiles) {
    if ((Test-Path $item.target) -and (-not $Force)) {
        $SkippedFiles += $item.relative
        continue
    }

    Write-Output "Translating $($item.relative) -> $TargetCode"
    try {
        $SourceText = Get-Content -LiteralPath $item.source -Raw -Encoding UTF8
        $Result = Invoke-TranslatedMarkdown -SourceText $SourceText -TargetLanguageName $TargetLanguageName -FileRole $item.role -RelativePath $item.relative
        Save-Utf8File -Path $item.target -Content $Result.content

        $TranslatedFiles += $item.relative
        $TotalInputTokens += $Result.usage.input_tokens
        $TotalOutputTokens += $Result.usage.output_tokens
        $TotalTokens += $Result.usage.total_tokens
    }
    catch {
        Fail-SageStep -Context $Context -Step "translate" -Message "Failed to translate shared source file." -Data @{
            language = $TargetCode
            file = $item.relative
            error = $_.Exception.Message
        }
        Write-Output "ERROR: Failed translating $($item.relative)"
        exit 1
    }
}

for ($i = $StartIndex; $i -le $EndIndex; $i++) {
    $ChapterFile = $ChapterFiles[$i - 1]
    $TargetChapterPath = Join-Path $TargetChapterRoot $ChapterFile.Name
    $RelativePath = "02_chapters/$($ChapterFile.Name)"

    if ((Test-Path $TargetChapterPath) -and (-not $Force)) {
        $SkippedFiles += $RelativePath
        Write-Output "$RelativePath exists. Skipping."
        continue
    }

    Write-Output "[translate] Chapter $i / $EndIndex -> $TargetCode"

    try {
        $SourceText = Get-Content -LiteralPath $ChapterFile.FullName -Raw -Encoding UTF8
        $Result = Invoke-TranslatedMarkdown -SourceText $SourceText -TargetLanguageName $TargetLanguageName -FileRole "chapter" -RelativePath $RelativePath
        Save-Utf8File -Path $TargetChapterPath -Content $Result.content

        $TranslatedFiles += $RelativePath
        $TotalInputTokens += $Result.usage.input_tokens
        $TotalOutputTokens += $Result.usage.output_tokens
        $TotalTokens += $Result.usage.total_tokens
    }
    catch {
        Fail-SageStep -Context $Context -Step "translate" -Message "Failed to translate chapter." -Data @{
            language = $TargetCode
            chapter = $i
            file = $ChapterFile.Name
            error = $_.Exception.Message
        }
        Write-Output "ERROR: Failed translating $($ChapterFile.Name)"
        exit 1
    }
}

$Manifest = [ordered]@{
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    book_name = $BookName
    source_language = "zh"
    target_language = $TargetCode
    target_language_name = $TargetLanguageName
    scope = if ($All) { "all" } elseif ($Chapter) { "single" } elseif ($StartChapter -or $EndChapter) { "range" } else { "all" }
    chapter_range = @{
        start = $StartIndex
        end = $EndIndex
        total_chapters = $TotalChapters
    }
    translated_files = $TranslatedFiles
    skipped_files = $SkippedFiles
    usage = @{
        input_tokens = $TotalInputTokens
        output_tokens = $TotalOutputTokens
        total_tokens = $TotalTokens
        model = "gpt-5.2"
    }
}

$Manifest | ConvertTo-Json -Depth 10 | Out-File -LiteralPath $ManifestPath -Encoding utf8

$Duration = [math]::Round(((Get-Date) - $StartTime).TotalSeconds, 2)
Complete-SageStep -Context $Context -Step "translate" -State "success" -Message "Translation completed." -Data @{
    language = $TargetCode
    translated_file_count = $TranslatedFiles.Count
    skipped_file_count = $SkippedFiles.Count
    processed_range = "$StartIndex-$EndIndex"
    duration_seconds = $Duration
    output_root = $TranslationRoot
    input_tokens_total = $TotalInputTokens
    output_tokens_total = $TotalOutputTokens
    total_tokens_total = $TotalTokens
}

Write-Output "SUCCESS: Translation completed for $TargetCode."
Write-Output "Output root: $TranslationRoot"
