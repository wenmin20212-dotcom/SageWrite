param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$Chapter,

    [int]$StartChapter,
    [int]$EndChapter,

    [int]$MaxTokens = 3000,

    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# ===== Resolve paths =====
$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot   = Split-Path -Parent $EnginePath
$ClawRoot   = Split-Path -Parent $SageRoot

$WorkspaceRoot = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot = Join-Path $WorkspaceRoot "sagewrite\book"

$TocPath        = Join-Path $BookRoot "01_outline\toc.md"
$ChapterRoot    = Join-Path $BookRoot "02_chapters"
$LogRoot        = Join-Path $BookRoot "logs"
$LogPath        = Join-Path $LogRoot "run_history.json"
$ObjectivePath  = Join-Path $BookRoot "00_brief\objective.md"

# ===== Validation =====
if (!(Test-Path $TocPath)) { Write-Output "ERROR: toc.md not found."; exit 1 }
if (!(Test-Path $ObjectivePath)) { Write-Output "ERROR: objective.md not found."; exit 1 }
if (-not $env:OPENAI_API_KEY) { Write-Output "ERROR: OPENAI_API_KEY not set."; exit 1 }

if (!(Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot | Out-Null }

# ===== Read content =====
$TocContent = Get-Content $TocPath -Raw
$ObjectiveContent = Get-Content $ObjectivePath -Raw

$Matches = [regex]::Matches($TocContent, "^###\s+(.+)", "Multiline")
$TotalChapters = $Matches.Count

if ($TotalChapters -eq 0) {
    Write-Output "ERROR: No chapters detected in toc.md."
    exit 1
}

# ===== Mode validation =====
if ($Chapter -and ($StartChapter -or $EndChapter)) {
    Write-Output "ERROR: Cannot use -Chapter with -StartChapter/-EndChapter."
    exit 1
}

# ===== Determine execution range =====
if ($Chapter) {

    if ($Chapter -lt 1 -or $Chapter -gt $TotalChapters) {
        Write-Output "ERROR: Chapter out of range."
        exit 1
    }

    $StartIndex = $Chapter
    $EndIndex   = $Chapter
}
elseif ($StartChapter -or $EndChapter) {

    if (-not $StartChapter -or -not $EndChapter) {
        Write-Output "ERROR: Both -StartChapter and -EndChapter must be specified."
        exit 1
    }

    if ($StartChapter -lt 1 -or $EndChapter -gt $TotalChapters -or $StartChapter -gt $EndChapter) {
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

# ===== Execution =====
$GeneratedCount = 0
$StartTime = Get-Date

# ===== Usage counters =====
$TotalInputTokens  = 0
$TotalOutputTokens = 0
$TotalTokens       = 0

for ($i = $StartIndex; $i -le $EndIndex; $i++) {

    $ChapterTitle = $Matches[$i-1].Groups[1].Value.Trim()
    $ChapterFileName = "{0:D2}.md" -f $i
    $ChapterPath = Join-Path $ChapterRoot $ChapterFileName

    if ((Test-Path $ChapterPath) -and (-not $Force)) {
        Write-Output "$ChapterFileName exists. Skipping."
        continue
    }

    Write-Output "Generating $ChapterFileName ..."

    $Prompt = @"
You are writing a professional book chapter.

Book definition:
$ObjectiveContent

Full book table of contents (TOC):
$TocContent

Current chapter:
- chapter_index: $i
- total_chapters: $TotalChapters
- chapter_title: $ChapterTitle

Requirements:
1. Target length: 2500â€“3500 words.
2. Use a clear hierarchical structure with numbered sections (e.g., 1., 1.1, 1.2).
3. Include:
   - An introduction section.
   - Multiple logically structured core sections.
   - A concluding section that synthesizes the chapter.
4. Maintain professional academic tone.
5. Avoid repetition and filler content.
6. Do not include meta commentary, explanations about writing, or references to the prompt.
7. Output in clean Markdown format only.

Write the complete chapter now.
"@

    $BodyObject = @{
        model = "gpt-4o-mini"
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
        Write-Output "ERROR: API request failed."
        exit 1
    }

    # ===== Usage accounting =====
    $inTok  = 0
    $outTok = 0
    $totTok = 0

    if ($Response.usage) {
        if ($Response.usage.input_tokens)  { $inTok  = [int]$Response.usage.input_tokens }
        if ($Response.usage.output_tokens) { $outTok = [int]$Response.usage.output_tokens }
        if ($Response.usage.total_tokens)  { $totTok = [int]$Response.usage.total_tokens }
    }

    $TotalInputTokens  += $inTok
    $TotalOutputTokens += $outTok
    $TotalTokens       += $totTok

    $ChapterText = ""

    foreach ($item in $Response.output) {
        foreach ($content in $item.content) {
            if ($content.type -eq "output_text") {
                $ChapterText += $content.text
            }
        }
    }

    if (-not $ChapterText) {
        Write-Output "ERROR: Empty response."
        exit 1
    }

@"
---
file_role: chapter
chapter_index: $i
title: "$ChapterTitle"
generated_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
model: gpt-4o-mini
max_tokens: $MaxTokens
---

$ChapterText
"@ | Out-File $ChapterPath -Encoding utf8

    $GeneratedCount++
}

# ===== Logging =====
$EndTime = Get-Date
$Duration = ($EndTime - $StartTime).TotalSeconds

$LogEntry = @{
    run_time = $StartTime.ToString("yyyy-MM-dd HH:mm:ss")
    book = $BookName
    model = "gpt-4o-mini"
    chapters_generated = $GeneratedCount
    duration_seconds = [math]::Round($Duration,2)

    input_tokens_total  = $TotalInputTokens
    output_tokens_total = $TotalOutputTokens
    total_tokens_total  = $TotalTokens
}

$LogEntry | ConvertTo-Json -Compress | Out-File $LogPath -Encoding utf8 -Append

Write-Output "SUCCESS: $GeneratedCount chapter(s) generated."


