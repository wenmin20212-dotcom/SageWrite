param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

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

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $json = $Data | ConvertTo-Json -Depth 20
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

function Read-FrontMatterValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $pattern = '^\s*' + [Regex]::Escape($Key) + '\s*:\s*(.+?)\s*$'
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match $pattern) {
            $value = $Matches[1].Trim().Trim('"').Trim("'")
            return $value
        }
    }
    return $null
}

function Get-TocStructure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $bookHeading = $null
    $sections = @()
    $currentSection = $null

    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }
        if ($trimmed -eq "---" -or $trimmed -eq "# Table of Contents" -or $trimmed -eq "## Directory" -or $trimmed -eq "## 目录") {
            continue
        }
        if ($trimmed -match '^#\s+(.+)$') {
            if ($Matches[1] -ne "Table of Contents") {
                $bookHeading = $Matches[1].Trim()
            }
            continue
        }
        if ($trimmed -match '^###\s+(.+)$') {
            $currentSection = [ordered]@{
                title  = $Matches[1].Trim()
                points = @()
            }
            $sections += $currentSection
            continue
        }
        if ($trimmed -match '^-+\s+(.+)$' -and $null -ne $currentSection) {
            $currentSection.points += $Matches[1].Trim()
        }
    }

    return [ordered]@{
        book_heading = $bookHeading
        sections     = @($sections)
    }
}

function Get-KeywordsFromText {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Texts,
        [int]$MaxCount = 12
    )

    $joined = ($Texts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join " "
    $joined = $joined -replace '[^\p{L}\p{Nd}\s]+', ' '

    $candidates = New-Object System.Collections.Generic.List[string]

    [regex]::Matches($joined, '[A-Za-z][A-Za-z0-9\-]{2,}') | ForEach-Object {
        $token = $_.Value.Trim()
        if ($token.Length -ge 3) { $candidates.Add($token) }
    }

    [regex]::Matches($joined, '[\p{IsCJKUnifiedIdeographs}]{2,8}') | ForEach-Object {
        $token = $_.Value.Trim()
        if ($token.Length -ge 2) { $candidates.Add($token) }
    }

    $stop = @(
        "Table", "Contents", "Directory", "SageWrite",
        "title", "audience", "type", "style",
        "chapter", "chapters", "book", "books"
    )

    $result = $candidates |
        Group-Object |
        Sort-Object -Property Count, Name -Descending |
        ForEach-Object { $_.Name } |
        Where-Object { $stop -notcontains $_ } |
        Select-Object -First $MaxCount

    return @($result)
}

$EnginePath     = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot       = Split-Path -Parent $EnginePath
$ClawRoot       = Split-Path -Parent $SageRoot

$WorkspaceRoot  = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot       = Join-Path $WorkspaceRoot "sagewrite\book"
$BriefRoot      = Join-Path $BookRoot "00_brief"
$OutlineRoot    = Join-Path $BookRoot "01_outline"
$CoverBaseRoot  = Join-Path $BookRoot "07_cover"
$CoverRoot      = Join-Path $CoverBaseRoot $Edition
$CoverBriefRoot = Join-Path $CoverRoot "brief"
$LogRoot        = Join-Path $BookRoot "logs"

$ObjectivePath  = Join-Path $BriefRoot "objective.md"
$TocPath        = Join-Path $OutlineRoot "toc.md"
$BriefJsonPath  = Join-Path $CoverBriefRoot "cover_brief.json"
$BriefMdPath    = Join-Path $CoverBriefRoot "cover_brief.md"
$LogPath        = Join-Path $LogRoot "08a-brief.log"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $CoverBriefRoot
Ensure-Directory -Path $LogRoot

Assert-FileExists -Path $ObjectivePath -Description "objective.md"
Assert-FileExists -Path $TocPath -Description "toc.md"

if ((Test-Path -LiteralPath $BriefJsonPath) -and (-not $Force)) {
    Write-Host "cover_brief.json already exists. Use -Force to regenerate."
    exit 0
}

$DerivedTitle    = Read-FrontMatterValue -Path $ObjectivePath -Key "title"
$DerivedAudience = Read-FrontMatterValue -Path $ObjectivePath -Key "audience"
$DerivedType     = Read-FrontMatterValue -Path $ObjectivePath -Key "type"
$DerivedThesis   = Read-FrontMatterValue -Path $ObjectivePath -Key "core_thesis"
$DerivedScope    = Read-FrontMatterValue -Path $ObjectivePath -Key "scope"
$DerivedStyle    = Read-FrontMatterValue -Path $ObjectivePath -Key "style"

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = $DerivedTitle
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    throw "Title is missing. Provide -Title or ensure objective.md contains title."
}

$TocData = Get-TocStructure -Path $TocPath
$ChapterTitles = @($TocData.sections | ForEach-Object { $_.title })
$KeyTexts = @($Title, $Subtitle, $DerivedAudience, $DerivedType, $DerivedThesis, $DerivedScope, $DerivedStyle) + $ChapterTitles |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$Keywords = Get-KeywordsFromText -Texts $KeyTexts -MaxCount 12

$DesignDirections = @(
    [ordered]@{
        id               = "civilization-blueprint"
        name             = "Civilization Blueprint"
        rationale        = "Highlight knowledge systems, structured creation, and a civilization-scale perspective."
        mood_keywords    = @("rational", "future-facing", "ordered", "serious", "systemic")
        visual_keywords  = @("knowledge grid", "diagram", "structure", "blueprint", "signal flow")
        palette          = @("deep blue", "ivory", "graphite", "cool gray")
        typography_notes = "Keep the title highly legible and suitable for serious non-fiction."
    },
    [ordered]@{
        id               = "human-ai-collaboration"
        name             = "Human-AI Collaboration"
        rationale        = "Emphasize the shift from manual writing to structured human-AI collaboration."
        mood_keywords    = @("collaborative", "modern", "intelligent", "clear", "trustworthy")
        visual_keywords  = @("dual agents", "dialogue", "network", "modules", "workflow")
        palette          = @("teal", "warm white", "charcoal", "silver")
        typography_notes = "Modern but not flashy; avoid looking like a cheap AI poster."
    },
    [ordered]@{
        id               = "popular-thoughtful-nonfiction"
        name             = "Popular Thoughtful Nonfiction"
        rationale        = "Balance mass readability with intellectual depth and publishing polish."
        mood_keywords    = @("accessible", "thoughtful", "credible", "clear", "knowledge-rich")
        visual_keywords  = @("book texture", "light beam", "layered structure", "clean hierarchy")
        palette          = @("off-white", "ink blue", "deep green", "soft gold accent")
        typography_notes = "Publishing feel first; decorative effects should be restrained."
    }
)

$CoverBrief = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name    = $BookName
    cover_text   = [ordered]@{
        title    = $Title
        subtitle = $Subtitle
        author   = $Author
    }
    source = [ordered]@{
        objective_file = Split-Path -Leaf $ObjectivePath
        toc_file       = Split-Path -Leaf $TocPath
    }
    metadata = [ordered]@{
        audience       = $DerivedAudience
        book_type      = $DerivedType
        core_thesis    = $DerivedThesis
        scope          = $DerivedScope
        style          = $DerivedStyle
        toc_heading    = $TocData.book_heading
        chapter_count  = $ChapterTitles.Count
        chapter_titles = @($ChapterTitles)
        top_keywords   = @($Keywords)
    }
    positioning = [ordered]@{
        market_label      = "AI writing / knowledge creation / thoughtful nonfiction"
        core_promise      = "Explain the transition from traditional writing to structured human-AI creation."
        reader_impression = @(
            "credible",
            "clear",
            "modern but serious",
            "knowledge-dense"
        )
        avoid = @(
            "cheap AI icon collage",
            "generic cyberpunk poster look",
            "overdecorated sci-fi treatment",
            "visual tone that clashes with serious nonfiction"
        )
    }
    design_directions = @($DesignDirections)
    downstream_hints = [ordered]@{
        preferred_language = "zh-CN"
        output_goal        = "Produce a stable cover brief for strategy, image generation, review, layout, and export steps."
        visual_priority    = @("title legibility", "nonfiction credibility", "knowledge theme", "structured modernity")
    }
}

$MarkdownLines = @(
    "# Cover Brief",
    "",
    "## Core Metadata",
    "",
    "- BookName: $BookName",
    "- Title: $Title",
    "- Subtitle: $Subtitle",
    "- Author: $Author",
    "- Audience: $DerivedAudience",
    "- Type: $DerivedType",
    "",
    "## Core Thesis",
    "",
    $DerivedThesis,
    "",
    "## Scope",
    "",
    $DerivedScope,
    "",
    "## Style",
    "",
    $DerivedStyle,
    "",
    "## Chapter Map",
    ""
)

foreach ($chapter in $ChapterTitles) {
    $MarkdownLines += "- $chapter"
}

$MarkdownLines += ""
$MarkdownLines += "## Top Keywords"
$MarkdownLines += ""
foreach ($keyword in $Keywords) {
    $MarkdownLines += "- $keyword"
}

$MarkdownLines += ""
$MarkdownLines += "## Design Directions"
$MarkdownLines += ""
foreach ($direction in $DesignDirections) {
    $MarkdownLines += "### $($direction.name)"
    $MarkdownLines += "- Rationale: $($direction.rationale)"
    $MarkdownLines += "- Mood: $($direction.mood_keywords -join ' / ')"
    $MarkdownLines += "- Visual: $($direction.visual_keywords -join ' / ')"
    $MarkdownLines += "- Palette: $($direction.palette -join ' / ')"
    $MarkdownLines += ""
}

Write-JsonUtf8 -Data $CoverBrief -Path $BriefJsonPath
Write-TextUtf8 -Content ($MarkdownLines -join [Environment]::NewLine) -Path $BriefMdPath
Write-TextUtf8 -Content ("[{0}] 08a-brief completed: {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $BriefJsonPath) -Path $LogPath

Write-Host ""
Write-Host "08a-brief completed successfully."
Write-Host "JSON: $BriefJsonPath"
Write-Host "Markdown: $BriefMdPath"
