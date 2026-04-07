param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$Chapter,

    [int]$StartChapter,
    [int]$EndChapter,

    [int]$MaxTokens = 6000,

    [string]$AdditionalInstructions,

    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [string]$Key
    )

    $Normalized = $Content -replace "`r", ""
    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---")
    if (-not $Match.Success) {
        return ""
    }

    foreach ($line in ($Match.Groups[1].Value -split "`n")) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$") {
            return $Matches[1].Trim()
        }
    }

    return ""
}

function Get-MarkdownSectionBody {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [string]$Heading
    )

    $Normalized = $Content -replace "`r", ""
    $EscapedHeading = [regex]::Escape($Heading)
    $Match = [regex]::Match($Normalized, "(?ms)^##\s+$EscapedHeading\s*\n(.*?)(?=^##\s+|\z)")
    if ($Match.Success) {
        return $Match.Groups[1].Value.Trim()
    }

    return ""
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

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "write" -Data @{
    chapter = $Chapter
    start_chapter = $StartChapter
    end_chapter = $EndChapter
    max_tokens = $MaxTokens
    has_additional_instructions = -not [string]::IsNullOrWhiteSpace($AdditionalInstructions)
    force = [bool]$Force
}

$BookRoot = $Context.BookRoot
$TocPath = Join-Path $BookRoot "01_outline\toc.md"
$ChapterRoot = Join-Path $BookRoot "02_chapters"
$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
$RewriteNotesRoot = Join-Path $BookRoot "00_brief\rewrite_notes"

if (!(Test-Path $TocPath)) {
    Fail-SageStep -Context $Context -Step "write" -Message "toc.md not found." -Data @{ toc = $TocPath }
    Write-Output "ERROR: toc.md not found."
    exit 1
}

if (!(Test-Path $ObjectivePath)) {
    Fail-SageStep -Context $Context -Step "write" -Message "objective.md not found." -Data @{ objective = $ObjectivePath }
    Write-Output "ERROR: objective.md not found."
    exit 1
}

if (-not $env:OPENAI_API_KEY) {
    Fail-SageStep -Context $Context -Step "write" -Message "OPENAI_API_KEY not set." -Data @{}
    Write-Output "ERROR: OPENAI_API_KEY not set."
    exit 1
}

if (!(Test-Path $ChapterRoot)) {
    New-Item -ItemType Directory -Path $ChapterRoot -Force | Out-Null
}

if (!(Test-Path $RewriteNotesRoot)) {
    New-Item -ItemType Directory -Path $RewriteNotesRoot -Force | Out-Null
}

$TocContent = Get-Content $TocPath -Raw
$ObjectiveContent = Get-Content $ObjectivePath -Raw
$StyleFromFrontMatter = Get-FrontMatterValue -Content $ObjectiveContent -Key "style"
$StyleGuideBody = Get-MarkdownSectionBody -Content $ObjectiveContent -Heading "风格指南"
$ResolvedStyleGuidance = if (-not [string]::IsNullOrWhiteSpace($StyleGuideBody)) {
    $StyleGuideBody.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($StyleFromFrontMatter)) {
    $StyleFromFrontMatter.Trim()
} else {
    ""
}
$HasObjectiveStyleGuidance = -not [string]::IsNullOrWhiteSpace($ResolvedStyleGuidance)

$ChapterMatches = [regex]::Matches($TocContent, "^###\s+(.+)", "Multiline")
$TotalChapters = $ChapterMatches.Count

if ($TotalChapters -eq 0) {
    Fail-SageStep -Context $Context -Step "write" -Message "No chapters detected in toc.md." -Data @{ toc = $TocPath }
    Write-Output "ERROR: No chapters detected in toc.md."
    exit 1
}

if ($Chapter -and ($StartChapter -or $EndChapter)) {
    Fail-SageStep -Context $Context -Step "write" -Message "Conflicting chapter arguments." -Data @{
        chapter = $Chapter
        start_chapter = $StartChapter
        end_chapter = $EndChapter
    }
    Write-Output "ERROR: Cannot use -Chapter with -StartChapter/-EndChapter."
    exit 1
}

if ($Chapter) {
    if ($Chapter -lt 1 -or $Chapter -gt $TotalChapters) {
        Fail-SageStep -Context $Context -Step "write" -Message "Chapter out of range." -Data @{
            chapter = $Chapter
            chapter_count = $TotalChapters
        }
        Write-Output "ERROR: Chapter out of range."
        exit 1
    }

    $StartIndex = $Chapter
    $EndIndex   = $Chapter
}
elseif ($StartChapter -or $EndChapter) {
    if (-not $StartChapter -or -not $EndChapter) {
        Fail-SageStep -Context $Context -Step "write" -Message "Chapter range missing boundary." -Data @{
            start_chapter = $StartChapter
            end_chapter = $EndChapter
        }
        Write-Output "ERROR: Both -StartChapter and -EndChapter must be specified."
        exit 1
    }

    if ($StartChapter -lt 1 -or $EndChapter -gt $TotalChapters -or $StartChapter -gt $EndChapter) {
        Fail-SageStep -Context $Context -Step "write" -Message "Invalid chapter range." -Data @{
            start_chapter = $StartChapter
            end_chapter = $EndChapter
            chapter_count = $TotalChapters
        }
        Write-Output "ERROR: Invalid chapter range."
        exit 1
    }

    $StartIndex = $StartChapter
    $EndIndex   = $EndChapter
}
else {
    $StartIndex = 1
    $EndIndex   = $TotalChapters
}

$GeneratedCount = 0
$StartTime = Get-Date
$TotalInputTokens = 0
$TotalOutputTokens = 0
$TotalTokens = 0
$SkippedCount = 0
$HasAdditionalInstructions = -not [string]::IsNullOrWhiteSpace($AdditionalInstructions)

for ($i = $StartIndex; $i -le $EndIndex; $i++) {
    $ChapterTitle = $ChapterMatches[$i - 1].Groups[1].Value.Trim()
    $ChapterFileName = "{0:D2}.md" -f $i
    $ChapterPath = Join-Path $ChapterRoot $ChapterFileName

    Write-Output "[progress] Chapter $i / $EndIndex"

    if ((Test-Path $ChapterPath) -and (-not $Force)) {
        $SkippedCount++
        Write-Output "$ChapterFileName exists. Skipping."
        continue
    }

    Write-Output "Generating $ChapterFileName ..."

    $AdditionalInstructionsBlock = ""
    $StyleInstructionsBlock = ""
    if ($HasAdditionalInstructions) {
        $RewriteNotesPath = Join-Path $RewriteNotesRoot ("chapter-{0:D2}.md" -f $i)
        $RewriteNotesContent = @"
---
file_role: rewrite_notes
chapter_index: $i
created_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
---

$AdditionalInstructions
"@
        [System.IO.File]::WriteAllText(
            $RewriteNotesPath,
            $RewriteNotesContent,
            [System.Text.UTF8Encoding]::new($true)
        )

        $AdditionalInstructionsBlock = @"

Additional rewrite instructions:
$RewriteNotesContent

When these rewrite instructions conflict with generic defaults, prioritize these chapter-specific rewrite instructions while still respecting the book objective and TOC.
"@
    }

    if ($HasObjectiveStyleGuidance) {
        $StyleInstructionsBlock = @"

Writing style guidance from the book definition:
$ResolvedStyleGuidance

Treat this as the authoritative style requirement for the chapter. Do not replace it with a generic default style.
"@
    }

    $StyleRequirementLine = if ($HasObjectiveStyleGuidance) {
        "Follow the writing style guidance defined in the book definition above."
    } else {
        "Maintain professional academic tone."
    }

    $Prompt = @"
You are writing a professional book chapter.

Book definition:
$ObjectiveContent

Full book table of contents (TOC):
$TocContent
$StyleInstructionsBlock
$AdditionalInstructionsBlock

Current chapter:
- chapter_index: $i
- total_chapters: $TotalChapters
- chapter_title: $ChapterTitle

Requirements:
1. Target length: 3000-4000 words.
2. Use a clear hierarchical structure with numbered sections.
3. Include an introduction, multiple core sections, and a concluding section.
4. $StyleRequirementLine
5. Avoid repetition and filler content.
6. Do not include meta commentary.
7. Output in clean Markdown format only.

Write the complete chapter now.
"@

    $BodyObject = @{
        model = "gpt-5.2"
        input = $Prompt
        max_output_tokens = $MaxTokens
    }

    $JsonString = $BodyObject | ConvertTo-Json -Depth 10 -Compress
    $Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonString)

    try {
        $Response = Invoke-RestMethod `
            -Uri "https://api.openai.com/v1/responses" `
            -Method Post `
            -Headers @{
                "Authorization" = "Bearer $env:OPENAI_API_KEY"
                "Content-Type"  = "application/json; charset=utf-8"
            } `
            -Body $Utf8Bytes
    }
    catch {
        Fail-SageStep -Context $Context -Step "write" -Message "API request failed." -Data @{
            chapter_index = $i
            chapter_title = $ChapterTitle
            error = $_.Exception.Message
        }
        Write-Output "ERROR: API request failed."
        exit 1
    }

    $ChapterInputTokens = 0
    $ChapterOutputTokens = 0
    $ChapterTotalTokens = 0

    if ($Response.usage) {
        if ($Response.usage.input_tokens)  {
            $ChapterInputTokens = [int]$Response.usage.input_tokens
            $TotalInputTokens += $ChapterInputTokens
        }
        if ($Response.usage.output_tokens) {
            $ChapterOutputTokens = [int]$Response.usage.output_tokens
            $TotalOutputTokens += $ChapterOutputTokens
        }
        if ($Response.usage.total_tokens)  {
            $ChapterTotalTokens = [int]$Response.usage.total_tokens
            $TotalTokens += $ChapterTotalTokens
        }
    }

    $ChapterText = ""

    foreach ($item in $Response.output) {
        foreach ($content in $item.content) {
            if ($content.type -eq "output_text") {
                $ChapterText += $content.text
            }
        }
    }

    if (-not $ChapterText) {
        Fail-SageStep -Context $Context -Step "write" -Message "Empty response." -Data @{
            chapter_index = $i
            chapter_title = $ChapterTitle
        }
        Write-Output "ERROR: Empty response."
        exit 1
    }

    $ChapterText = Normalize-MarkdownOutput -Content $ChapterText

@"
---
file_role: chapter
chapter_index: $i
title: "$ChapterTitle"
generated_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
model: gpt-5.2
max_tokens: $MaxTokens
input_tokens: $ChapterInputTokens
output_tokens: $ChapterOutputTokens
total_tokens: $ChapterTotalTokens
---

$ChapterText
"@ | Out-File $ChapterPath -Encoding utf8

    $GeneratedCount++
}

$EndTime = Get-Date
$Duration = ($EndTime - $StartTime).TotalSeconds

Complete-SageStep -Context $Context -Step "write" -State "success" -Message "Chapter generation finished." -Data @{
    chapters_generated = $GeneratedCount
    chapters_skipped = $SkippedCount
    total_chapters = $TotalChapters
    processed_range = "$StartIndex-$EndIndex"
    duration_seconds = [math]::Round($Duration, 2)
    input_tokens_total = $TotalInputTokens
    output_tokens_total = $TotalOutputTokens
        total_tokens_total = $TotalTokens
        model = "gpt-5.2"
        has_objective_style_guidance = $HasObjectiveStyleGuidance
        has_additional_instructions = $HasAdditionalInstructions
}

Write-Output "SUCCESS: $GeneratedCount chapter(s) generated."
