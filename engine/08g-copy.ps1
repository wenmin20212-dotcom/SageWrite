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

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Assert-FileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description not found: $Path"
    }
}

function Read-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Assert-FileExists -Path $Path -Description "JSON file"
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "JSON file is empty: $Path"
    }
    return $raw | ConvertFrom-Json
}

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $json = $Data | ConvertTo-Json -Depth 40
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Write-TextUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Get-StringValue {
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )
    if ($null -eq $Value) {
        return ""
    }
    return "$Value"
}

function Get-StringArray {
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )
    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { "$_" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    if ([string]::IsNullOrWhiteSpace("$Value")) {
        return @()
    }
    return @("$Value")
}

function Normalize-JsonResponseText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    $normalized = $Text.Trim()
    if ($normalized -match '^(?:```json|```)\s*\r?\n([\s\S]*?)\r?\n```$') {
        return $Matches[1].Trim()
    }
    return $normalized
}

function Get-ResponseText {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

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

$EnginePath       = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot         = Split-Path -Parent $EnginePath
$ClawRoot         = Split-Path -Parent $SageRoot
$WorkspaceRoot    = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot         = Join-Path $WorkspaceRoot "sagewrite\book"
$BriefRoot        = Join-Path $BookRoot "00_brief"
$OutlineRoot      = Join-Path $BookRoot "01_outline"
$CoverBaseRoot    = Join-Path $BookRoot "07_cover"
$CoverRoot        = Join-Path $CoverBaseRoot $Edition
$CoverBriefRoot   = Join-Path $CoverRoot "brief"
$LogRoot          = Join-Path $BookRoot "logs"

$ObjectivePath    = Join-Path $BriefRoot "objective.md"
$TocPath          = Join-Path $OutlineRoot "toc.md"
$BriefJsonPath    = Join-Path $CoverBriefRoot "cover_brief.json"
$StrategyJsonPath = Join-Path $CoverBriefRoot "cover_strategy.json"
$CopyJsonPath     = Join-Path $CoverBriefRoot "cover_copy.json"
$CopyMdPath       = Join-Path $CoverBriefRoot "cover_copy.md"
$LogPath          = Join-Path $LogRoot "08g-copy.log"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $CoverBriefRoot
Ensure-Directory -Path $LogRoot

Assert-FileExists -Path $ObjectivePath -Description "objective.md"
Assert-FileExists -Path $TocPath -Description "toc.md"
Assert-FileExists -Path $BriefJsonPath -Description "cover_brief.json"
Assert-FileExists -Path $StrategyJsonPath -Description "cover_strategy.json"

if ((Test-Path -LiteralPath $CopyJsonPath) -and (-not $Force)) {
    Write-Host "cover_copy.json already exists. Use -Force to regenerate."
    exit 0
}

if (-not $env:OPENAI_API_KEY) {
    throw "OPENAI_API_KEY not set."
}

$ObjectiveContent = Get-Content -LiteralPath $ObjectivePath -Raw -Encoding UTF8
$TocContent = Get-Content -LiteralPath $TocPath -Raw -Encoding UTF8
$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$Strategy = Read-JsonUtf8 -Path $StrategyJsonPath

$Title = Get-StringValue -Value $Brief.cover_text.title
$Audience = Get-StringValue -Value $Brief.metadata.audience
$BookType = Get-StringValue -Value $Brief.metadata.book_type
$Thesis = Get-StringValue -Value $Brief.metadata.core_thesis
$Style = Get-StringValue -Value $Brief.metadata.style
$Keywords = Get-StringArray -Value $Brief.metadata.top_keywords
$PrimaryRoute = Get-StringValue -Value $Strategy.primary_strategy.route_label

$VariantCount = switch ($Mode) {
    "fast" { 3 }
    "full" { 6 }
    default { 4 }
}

$Prompt = @"
You are writing Chinese publishing copy for a serious nonfiction book cover package.

Return valid JSON only.
Do not use markdown fences.
Do not include explanatory text outside JSON.

Target language: Simplified Chinese.
Tone: publishable, intelligent, persuasive, clear, not exaggerated.
Book title: $Title
Book type: $BookType
Audience: $Audience
Writing style impression: $Style
Primary cover strategy route: $PrimaryRoute
Concept keywords: $($Keywords -join ", ")

Book definition:
$ObjectiveContent

Table of contents:
$TocContent

Generate a JSON object with this exact shape:
{
  "selected": {
    "subtitle": "",
    "back_cover_hook": "",
    "obi_copy": "",
    "marketing_tagline": "",
    "back_cover_blurb": "",
    "author_bio": "",
    "spine_text": ""
  },
  "candidates": {
    "subtitle": [],
    "back_cover_hook": [],
    "obi_copy": [],
    "marketing_tagline": []
  },
  "editor_notes": []
}

Requirements:
1. subtitle candidates should be 12-28 Chinese characters each.
2. back_cover_hook candidates should be 18-40 Chinese characters each.
3. obi_copy candidates should be 18-36 Chinese characters each.
4. marketing_tagline candidates should be 8-20 Chinese characters each.
5. back_cover_blurb should be one polished paragraph around 120-220 Chinese characters.
6. author_bio should be a placeholder-style author intro around 50-100 Chinese characters, suitable for later manual editing.
7. spine_text should be concise and suitable for a book spine.
8. selected fields must be the recommended final choices.
9. editor_notes should be short Chinese notes about when a human may want to refine the copy.
10. The copy should reflect the actual content of the book, not generic AI hype.
"@

$BodyObject = @{
    model = "gpt-5.2"
    input = $Prompt
    max_output_tokens = 2600
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
    throw "08g-copy API request failed: $($_.Exception.Message)"
}

$ResponseText = Get-ResponseText -Response $Response
if ([string]::IsNullOrWhiteSpace($ResponseText)) {
    throw "08g-copy returned empty text."
}

$NormalizedJsonText = Normalize-JsonResponseText -Text $ResponseText
try {
    $CopyObject = $NormalizedJsonText | ConvertFrom-Json
}
catch {
    throw "08g-copy returned invalid JSON."
}

$SubtitleCandidates = Get-StringArray -Value $CopyObject.candidates.subtitle
$HookCandidates = Get-StringArray -Value $CopyObject.candidates.back_cover_hook
$ObiCandidates = Get-StringArray -Value $CopyObject.candidates.obi_copy
$TaglineCandidates = Get-StringArray -Value $CopyObject.candidates.marketing_tagline
$EditorNotes = Get-StringArray -Value $CopyObject.editor_notes

$Selected = [ordered]@{
    subtitle = Get-StringValue -Value $CopyObject.selected.subtitle
    back_cover_hook = Get-StringValue -Value $CopyObject.selected.back_cover_hook
    obi_copy = Get-StringValue -Value $CopyObject.selected.obi_copy
    marketing_tagline = Get-StringValue -Value $CopyObject.selected.marketing_tagline
    back_cover_blurb = Get-StringValue -Value $CopyObject.selected.back_cover_blurb
    author_bio = Get-StringValue -Value $CopyObject.selected.author_bio
    spine_text = Get-StringValue -Value $CopyObject.selected.spine_text
}

$CoverCopy = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    mode = $Mode
    source = [ordered]@{
        objective_file = Split-Path -Leaf $ObjectivePath
        toc_file = Split-Path -Leaf $TocPath
        brief_file = Split-Path -Leaf $BriefJsonPath
        strategy_file = Split-Path -Leaf $StrategyJsonPath
    }
    selected = $Selected
    candidates = [ordered]@{
        subtitle = @($SubtitleCandidates | Select-Object -First $VariantCount)
        back_cover_hook = @($HookCandidates | Select-Object -First $VariantCount)
        obi_copy = @($ObiCandidates | Select-Object -First $VariantCount)
        marketing_tagline = @($TaglineCandidates | Select-Object -First $VariantCount)
    }
    editor_notes = @($EditorNotes)
}

Write-JsonUtf8 -Data $CoverCopy -Path $CopyJsonPath

$MarkdownLines = @()
$MarkdownLines += "# Cover Copy"
$MarkdownLines += ""
$MarkdownLines += "## Selected"
$MarkdownLines += ""
$MarkdownLines += "- Subtitle: $($Selected.subtitle)"
$MarkdownLines += "- Back cover hook: $($Selected.back_cover_hook)"
$MarkdownLines += "- Obi copy: $($Selected.obi_copy)"
$MarkdownLines += "- Marketing tagline: $($Selected.marketing_tagline)"
$MarkdownLines += "- Spine text: $($Selected.spine_text)"
$MarkdownLines += ""
$MarkdownLines += "## Back Cover Blurb"
$MarkdownLines += ""
$MarkdownLines += $Selected.back_cover_blurb
$MarkdownLines += ""
$MarkdownLines += "## Author Bio"
$MarkdownLines += ""
$MarkdownLines += $Selected.author_bio
$MarkdownLines += ""
$MarkdownLines += "## Candidate Pools"
$MarkdownLines += ""
$MarkdownLines += "### Subtitle"
$MarkdownLines += @($CoverCopy.candidates.subtitle | ForEach-Object { "- $_" })
$MarkdownLines += ""
$MarkdownLines += "### Back Cover Hook"
$MarkdownLines += @($CoverCopy.candidates.back_cover_hook | ForEach-Object { "- $_" })
$MarkdownLines += ""
$MarkdownLines += "### Obi Copy"
$MarkdownLines += @($CoverCopy.candidates.obi_copy | ForEach-Object { "- $_" })
$MarkdownLines += ""
$MarkdownLines += "### Marketing Tagline"
$MarkdownLines += @($CoverCopy.candidates.marketing_tagline | ForEach-Object { "- $_" })
$MarkdownLines += ""
$MarkdownLines += "## Editor Notes"
$MarkdownLines += @($CoverCopy.editor_notes | ForEach-Object { "- $_" })

Write-TextUtf8 -Content ($MarkdownLines -join "`r`n") -Path $CopyMdPath
Set-Content -LiteralPath $LogPath -Value ("[{0}] 08g-copy completed." -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host ""
Write-Host "08g-copy completed successfully."
Write-Host ("JSON: " + $CopyJsonPath)
Write-Host ("Markdown: " + $CopyMdPath)
