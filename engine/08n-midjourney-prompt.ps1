param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Model = "gpt-5.2",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [int]$MaxTokens = 1800
)

. "$PSScriptRoot\08n-common.ps1"

function Get-ResponseText {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    if ($Response.output_text) {
        return "$($Response.output_text)".Trim()
    }

    $text = ""
    foreach ($item in $Response.output) {
        foreach ($content in $item.content) {
            if ($content.type -eq "output_text") {
                $text += $content.text
            }
        }
    }
    return $text.Trim()
}

function Get-FirstExistingPath {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Paths
    )

    foreach ($candidate in $Paths) {
        if (Test-Path -LiteralPath $candidate) {
            return $candidate
        }
    }
    return $null
}

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$ChiefPath = Get-FirstExistingPath -Paths @(
    (Join-Path $Roots.brief "chief.md"),
    (Join-Path $Roots.brief "objective.md")
)
$TocPath = Join-Path $Roots.outline "toc.md"

if (-not $ChiefPath) {
    throw "chief/objective file not found. Expected 00_brief\chief.md or 00_brief\objective.md."
}
Assert-FileExists -Path $TocPath -Description "toc.md"

if (-not $env:OPENAI_API_KEY) {
    throw "OPENAI_API_KEY not set."
}

$ChiefContent = Get-Content -LiteralPath $ChiefPath -Raw -Encoding UTF8
$TocContent = Get-Content -LiteralPath $TocPath -Raw -Encoding UTF8
$ResolvedTitle = if (-not [string]::IsNullOrWhiteSpace($Title)) {
    $Title.Trim()
} else {
    $frontMatterTitle = Read-FrontMatterValue -Path $ChiefPath -Key "title"
    if ($frontMatterTitle) { $frontMatterTitle } else { "" }
}
$ResolvedSubtitle = if (-not [string]::IsNullOrWhiteSpace($Subtitle)) { $Subtitle.Trim() } else { "" }
$ResolvedAuthor = if (-not [string]::IsNullOrWhiteSpace($Author)) { $Author.Trim() } else { "" }

$Prompt = @"
You are a senior book-cover art director and MidJourney prompt writer.

Task:
Write ONE ready-to-copy MidJourney prompt in English for generating the base image of this book cover.

Important production constraints:
- The MidJourney prompt itself must be written in English only. Translate all relevant Chinese book concepts into natural English visual language.
- The generated image is only the base artwork. It must contain absolutely no text of any kind: no book title, no subtitle, no author name, no Chinese characters, no English letters, no numbers, no typography, no logo, no watermark, no UI labels, no captions, no signage, no diagrams with labels, and no symbols or marks that look like writing.
- Leave generous clean negative space for later title layout. The image should have large quiet blank areas, but still feel deliberately composed and high-end.
- Make the render strong, cinematic, premium, and suitable for a serious nonfiction book.
- Use the book's chief/objective file and TOC below as the main source of concept, mood, audience, and visual metaphors.
- Do not summarize the book. Output the MidJourney prompt only.
- The final prompt should explicitly include negative text constraints such as: no text, no typography, no letters, no numbers, no Chinese characters, no logos, no watermarks.
- Include useful MidJourney parameters at the end, such as aspect ratio and style settings.

Known cover text reserved for later layout:
- Title: $ResolvedTitle
- Subtitle: $ResolvedSubtitle
- Author: $ResolvedAuthor

Chief/objective file path:
$ChiefPath

Chief/objective file content:
$ChiefContent

TOC file path:
$TocPath

TOC content:
$TocContent
"@

$BodyObject = @{
    model = $Model
    input = $Prompt
    max_output_tokens = $MaxTokens
}

$JsonString = $BodyObject | ConvertTo-Json -Depth 10 -Compress
$Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonString)
$StartedAt = Get-Date

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
    throw "08n-midjourney-prompt API request failed: $($_.Exception.Message)"
}

$EndedAt = Get-Date
$DurationSeconds = [math]::Round(($EndedAt - $StartedAt).TotalSeconds, 2)

$InputTokens = 0
$OutputTokens = 0
$TotalTokens = 0
if ($Response.usage) {
    if ($Response.usage.input_tokens) {
        $InputTokens = [int]$Response.usage.input_tokens
    }
    if ($Response.usage.output_tokens) {
        $OutputTokens = [int]$Response.usage.output_tokens
    }
    if ($Response.usage.total_tokens) {
        $TotalTokens = [int]$Response.usage.total_tokens
    }
}

$ResponseText = Get-ResponseText -Response $Response
if ([string]::IsNullOrWhiteSpace($ResponseText)) {
    throw "08n-midjourney-prompt returned empty text."
}

$PromptPath = Join-Path $Roots.prompts "midjourney_prompt.txt"
$ReportJsonPath = Join-Path $Roots.prompts "midjourney_prompt_report.json"
$ReportMdPath = Join-Path $Roots.prompts "midjourney_prompt_report.md"
$LegacyBriefRoot = Join-Path $Roots.old_cover "brief"
$LegacyPromptPath = Join-Path $LegacyBriefRoot "cover_midjourney_prompt.txt"

$Report = [ordered]@{
    generated_at = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    edition = $Edition
    script = "08n-midjourney-prompt.ps1"
    endpoint = "https://api.openai.com/v1/responses"
    model = $Model
    max_output_tokens = $MaxTokens
    duration_seconds = $DurationSeconds
    source_files = [ordered]@{
        chief = $ChiefPath
        toc = $TocPath
    }
    cover_text_reserved_for_layout = [ordered]@{
        title = $ResolvedTitle
        subtitle = $ResolvedSubtitle
        author = $ResolvedAuthor
    }
    usage = [ordered]@{
        input_tokens = $InputTokens
        output_tokens = $OutputTokens
        total_tokens = $TotalTokens
    }
    request_summary = [ordered]@{
        instructions = "Generate one ready-to-copy English MidJourney prompt for image-only base cover art with absolutely no text and generous negative space."
        response_format = "Plain text MidJourney prompt only."
    }
    generated_prompt = $ResponseText
}

$ReportLines = @(
    "# MidJourney Prompt Model Report",
    "",
    "- Generated at: $($Report.generated_at)",
    "- BookName: $BookName",
    "- Edition: $Edition",
    "- Script: 08n-midjourney-prompt.ps1",
    "- Endpoint: OpenAI Responses API",
    "- Model: $Model",
    "- Max output tokens: $MaxTokens",
    "- Duration seconds: $DurationSeconds",
    "- Input tokens: $InputTokens",
    "- Output tokens: $OutputTokens",
    "- Total tokens: $TotalTokens",
    "",
    "## Source Files",
    "",
    "- Chief/objective: $ChiefPath",
    "- TOC: $TocPath",
    "",
    "## Invocation Logic",
    "",
    "1. Read the book chief/objective file.",
    "2. Read the book TOC file.",
    "3. Send both files to the selected model with cover-base constraints: image-only, no typography, generous negative space, strong premium render.",
    "4. Store the model response as the MidJourney prompt and record token usage from Response.usage.",
    "",
    "## Generated MidJourney Prompt",
    "",
    $ResponseText
)

Write-TextUtf8 -Content $ResponseText -Path $PromptPath
Write-TextUtf8 -Content $ResponseText -Path $LegacyPromptPath
Write-JsonUtf8 -Data $Report -Path $ReportJsonPath
Write-TextUtf8 -Content ($ReportLines -join "`r`n") -Path $ReportMdPath

Write-Host "08n-midjourney-prompt completed successfully."
Write-Host "Script: 08n-midjourney-prompt.ps1"
Write-Host "Model: $Model"
Write-Host "Endpoint: OpenAI Responses API"
Write-Host "Source chief/objective: $ChiefPath"
Write-Host "Source TOC: $TocPath"
Write-Host "Token usage: input=$InputTokens output=$OutputTokens total=$TotalTokens"
Write-Host "Prompt: $PromptPath"
Write-Host "Report: $ReportMdPath"
