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
    $json = $Data | ConvertTo-Json -Depth 30
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
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

function Score-Route {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Route,
        [Parameter(Mandatory = $true)]
        [string]$SourceText
    )

    $score = 0
    if ($Route.ContainsKey("base_score")) {
        $score += [int]$Route.base_score
    }
    foreach ($needle in $Route.match_keywords) {
        if ($SourceText -match [Regex]::Escape($needle)) {
            $score += 3
        }
    }
    foreach ($needle in $Route.soft_keywords) {
        if ($SourceText -match [Regex]::Escape($needle)) {
            $score += 1
        }
    }
    return $score
}

function New-RouteCatalog {
    return @(
        @{
            id = "popular-thoughtful-nonfiction"
            label = "Popular Thoughtful Nonfiction"
            fit = "Best for serious but accessible knowledge books for broad readers."
            composition = "Clean centered hierarchy with one strong concept layer and generous whitespace."
            typography = "Readable, confident, publishing-oriented typography with restrained ornament."
            color_direction = @("off-white", "ink blue", "deep green", "soft gold accent")
            visual_direction = @("knowledge texture", "civilization motif", "light beam", "layered structure")
            avoid = @("cheap AI icon collage", "generic sci-fi neon", "poster-like overdrama")
            prompt_focus = "Create a polished nonfiction book cover with strong title readability, intellectual atmosphere, and commercial credibility."
            base_score = 8
            match_keywords = @("popular", "nonfiction", "reader", "knowledge", "civilization", "writing")
            soft_keywords = @("clear", "depth", "system", "guide", "serious")
        }
        @{
            id = "civilization-blueprint"
            label = "Civilization Blueprint"
            fit = "Best for books emphasizing systems, structure, knowledge infrastructure, and long historical arcs."
            composition = "Blueprint-like field, diagrammatic layers, structured grid, strong vertical and horizontal anchors."
            typography = "High-contrast title, systematic hierarchy, crisp technical elegance."
            color_direction = @("deep blue", "ivory", "graphite", "cool gray")
            visual_direction = @("grid", "knowledge map", "signal flow", "architecture", "blueprint")
            avoid = @("fantasy scenery", "soft lifestyle imagery", "cartoon illustration")
            prompt_focus = "Create a cover that feels systemic, rigorous, and civilization-scale rather than trendy."
            base_score = 9
            match_keywords = @("system", "structure", "knowledge", "civilization", "framework", "mechanism")
            soft_keywords = @("workflow", "module", "engineering", "blueprint", "paradigm")
        }
        @{
            id = "human-ai-collaboration"
            label = "Human-AI Collaboration"
            fit = "Best for books centered on co-creation, workflow, and human-AI partnership."
            composition = "Dual-focus composition with interaction, layered modules, or conversational geometry."
            typography = "Modern but sober, with clear hierarchy and a trustworthy technology feel."
            color_direction = @("teal", "warm white", "charcoal", "silver")
            visual_direction = @("dialogue", "two agents", "workflow nodes", "interface traces", "collaboration")
            avoid = @("robot faces", "cheap hologram overlays", "stock-tech marketing look")
            prompt_focus = "Create a cover that expresses human-AI collaboration as a disciplined creative system."
            base_score = 10
            match_keywords = @("AI", "human", "collaboration", "workflow", "generation", "interactive")
            soft_keywords = @("control", "assist", "editorial", "module", "co-create")
        }
        @{
            id = "educational-illustrative"
            label = "Educational Illustrative"
            fit = "Best for educational positioning, clearer instructional value, and broader classroom usability."
            composition = "Friendly but clean educational composition with strong title block and visual metaphor."
            typography = "Readable and welcoming, but still professional."
            color_direction = @("warm white", "dark green", "soft blue", "muted orange accent")
            visual_direction = @("book", "learning path", "knowledge ladder", "diagrammed learning scene")
            avoid = @("children-book cuteness", "busy textbook clutter", "toy-like graphics")
            prompt_focus = "Create a cover that feels educational, structured, and reliable for adult learners."
            base_score = 6
            match_keywords = @("education", "learning", "reader", "guide", "instruction")
            soft_keywords = @("teacher", "classroom", "training", "practice", "application")
        }
        @{
            id = "symbolic-metaphor"
            label = "Symbolic Metaphor"
            fit = "Best when the book needs stronger conceptual distinctiveness without becoming abstract art."
            composition = "Single bold symbolic motif supported by minimal surrounding structure."
            typography = "Elegant and controlled; let the symbol carry the drama."
            color_direction = @("black", "ivory", "bronze", "deep blue accent")
            visual_direction = @("symbol", "threshold", "network seed", "bridge", "transformative object")
            avoid = @("confusing fine art abstraction", "surreal overload", "weak title contrast")
            prompt_focus = "Create a concept-driven cover with one memorable metaphor and strong shelf recognition."
            base_score = 7
            match_keywords = @("revolution", "future", "innovation", "transform", "rebuild")
            soft_keywords = @("meaning", "upgrade", "shift", "paradigm", "possibility")
        }
    )
}

function New-RouteSummary {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Route,
        [Parameter(Mandatory = $true)]
        [int]$Score,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [Parameter(Mandatory = $true)]
        [string]$BookType,
        [Parameter(Mandatory = $true)]
        [string]$Audience,
        [Parameter(Mandatory = $true)]
        [string]$Style,
        [Parameter(Mandatory = $true)]
        [string[]]$Keywords
    )

    $titleSafe = if ([string]::IsNullOrWhiteSpace($Title)) { "the book" } else { $Title }
    $bookTypeSafe = if ([string]::IsNullOrWhiteSpace($BookType)) { "serious nonfiction" } else { $BookType }
    $audienceSafe = if ([string]::IsNullOrWhiteSpace($Audience)) { "general intelligent readers" } else { $Audience }
    $styleSafe = if ([string]::IsNullOrWhiteSpace($Style)) { "clear and credible" } else { $Style }
    $keywordText = if ($Keywords.Count -gt 0) { ($Keywords | Select-Object -First 8) -join ", " } else { "" }

    $prompt = @(
        "Design a front book cover for `"$titleSafe`"."
        "Book type: $bookTypeSafe."
        "Target audience: $audienceSafe."
        "Writing style impression: $styleSafe."
        "Primary route: $($Route.label)."
        "Visual direction: $($Route.visual_direction -join ', ')."
        "Composition: $($Route.composition)"
        "Typography: $($Route.typography)"
        "Color direction: $($Route.color_direction -join ', ')."
        "Keep title readability strong and publishing quality high."
        "Avoid: $($Route.avoid -join ', ')."
        "Optional concept anchors: $keywordText"
    ) -join " "

    return [ordered]@{
        id              = $Route.id
        label           = $Route.label
        score           = $Score
        fit             = $Route.fit
        composition     = $Route.composition
        typography      = $Route.typography
        color_direction = @($Route.color_direction)
        visual_direction= @($Route.visual_direction)
        avoid           = @($Route.avoid)
        prompt_draft    = $prompt
    }
}

$EnginePath     = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot       = Split-Path -Parent $EnginePath
$ClawRoot       = Split-Path -Parent $SageRoot

$WorkspaceRoot  = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot       = Join-Path $WorkspaceRoot "sagewrite\book"
$CoverBaseRoot  = Join-Path $BookRoot "07_cover"
$CoverRoot      = Join-Path $CoverBaseRoot $Edition
$CoverBriefRoot = Join-Path $CoverRoot "brief"
$LogRoot        = Join-Path $BookRoot "logs"

$BriefJsonPath    = Join-Path $CoverBriefRoot "cover_brief.json"
$StrategyJsonPath = Join-Path $CoverBriefRoot "cover_strategy.json"
$LogPath          = Join-Path $LogRoot "08b-strategy.log"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $CoverBriefRoot
Ensure-Directory -Path $LogRoot

Assert-FileExists -Path $BriefJsonPath -Description "cover_brief.json"

if ((Test-Path -LiteralPath $StrategyJsonPath) -and (-not $Force)) {
    Write-Host "cover_strategy.json already exists. Use -Force to regenerate."
    exit 0
}

$Brief = Read-JsonUtf8 -Path $BriefJsonPath

$Title       = Get-StringValue -Value $Brief.cover_text.title
$Subtitle    = Get-StringValue -Value $Brief.cover_text.subtitle
$Author      = Get-StringValue -Value $Brief.cover_text.author
$Audience    = Get-StringValue -Value $Brief.metadata.audience
$BookType    = Get-StringValue -Value $Brief.metadata.book_type
$Thesis      = Get-StringValue -Value $Brief.metadata.core_thesis
$Scope       = Get-StringValue -Value $Brief.metadata.scope
$Style       = Get-StringValue -Value $Brief.metadata.style
$Keywords    = Get-StringArray -Value $Brief.metadata.top_keywords
$Chapters    = Get-StringArray -Value $Brief.metadata.chapter_titles
$Directions  = @($Brief.design_directions)

$SourceText = @($Title, $Subtitle, $Audience, $BookType, $Thesis, $Scope, $Style) + $Keywords + $Chapters -join " "
$RouteCatalog = New-RouteCatalog

$ScoredRoutes = foreach ($route in $RouteCatalog) {
    [ordered]@{
        route = $route
        score = (Score-Route -Route $route -SourceText $SourceText)
    }
}

$RankedRoutes = $ScoredRoutes |
    Sort-Object -Property @{ Expression = { $_.score }; Descending = $true }, @{ Expression = { $_.route.label }; Descending = $false }

$RouteCount = switch ($Mode) {
    "fast" { 2 }
    "full" { 4 }
    default { 3 }
}

$ChosenRoutes = @($RankedRoutes | Select-Object -First $RouteCount)
if ($ChosenRoutes.Count -lt 1) {
    throw "No strategy routes could be selected."
}

$PrimaryRoute = $ChosenRoutes[0].route
$PrimaryScore = $ChosenRoutes[0].score

$StrategyRoutes = @(
    $ChosenRoutes | ForEach-Object {
        New-RouteSummary -Route $_.route -Score $_.score -Title $Title -BookType $BookType -Audience $Audience -Style $Style -Keywords $Keywords
    }
)

$SelectedDirection = $null
if ($Directions.Count -gt 0) {
    $SelectedDirection = $Directions[0]
    foreach ($direction in $Directions) {
        if ("$($direction.id)" -eq "$($PrimaryRoute.id)") {
            $SelectedDirection = $direction
            break
        }
    }
}

$BasePrompt = @(
    "Design a refined nonfiction book cover for `"$Title`"."
    "The cover should look publishable, readable as a thumbnail, and suitable for serious knowledge readers."
    "Primary strategy route: $($PrimaryRoute.label)."
    "Primary route fit: $($PrimaryRoute.fit)"
    "Primary visual direction: $($PrimaryRoute.visual_direction -join ', ')."
    "Primary color direction: $($PrimaryRoute.color_direction -join ', ')."
    "Typography direction: $($PrimaryRoute.typography)"
    "Composition direction: $($PrimaryRoute.composition)"
    "Avoid: $($PrimaryRoute.avoid -join ', ')."
) -join " "

if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
    $BasePrompt += " Include subtitle: $Subtitle."
}
if (-not [string]::IsNullOrWhiteSpace($Author)) {
    $BasePrompt += " Include author name: $Author."
}
if (-not [string]::IsNullOrWhiteSpace($Style)) {
    $BasePrompt += " The writing voice suggests this visual tone: $Style."
}

$NegativePrompt = @(
    "low readability",
    "cheap AI art",
    "poster composition instead of book cover",
    "overcrowded layout",
    "weak title hierarchy",
    "generic robot face",
    "neon sci-fi wallpaper look",
    "clip-art collage"
)

$Strategy = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name    = $BookName
    mode         = $Mode
    source       = [ordered]@{
        brief_file = Split-Path -Leaf $BriefJsonPath
    }
    cover_text = [ordered]@{
        title    = $Title
        subtitle = $Subtitle
        author   = $Author
    }
    primary_strategy = [ordered]@{
        route_id         = $PrimaryRoute.id
        route_label      = $PrimaryRoute.label
        score            = $PrimaryScore
        main_visual      = @($PrimaryRoute.visual_direction)
        color_direction  = @($PrimaryRoute.color_direction)
        composition      = $PrimaryRoute.composition
        typography       = $PrimaryRoute.typography
        banned_elements  = @($PrimaryRoute.avoid)
    }
    strategy_routes = @($StrategyRoutes)
    selected_design_direction = $SelectedDirection
    generation_plan = [ordered]@{
        candidate_count = switch ($Mode) {
            "fast" { 2 }
            "full" { 6 }
            default { 4 }
        }
        prompt_package = [ordered]@{
            base_prompt     = $BasePrompt
            negative_prompt = @($NegativePrompt)
            route_prompts   = @($StrategyRoutes | ForEach-Object {
                [ordered]@{
                    route_id     = $_.id
                    route_label  = $_.label
                    prompt_draft = $_.prompt_draft
                }
            })
        }
    }
    review_focus = @(
        "title readability",
        "fit with target readers",
        "serious book-cover feel",
        "thumbnail clarity",
        "visual distinctiveness without gimmicks"
    )
}

Write-JsonUtf8 -Data $Strategy -Path $StrategyJsonPath
Set-Content -LiteralPath $LogPath -Value ("[{0}] 08b-strategy completed." -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host ""
Write-Host "08b-strategy completed successfully."
Write-Host ("JSON: " + $StrategyJsonPath)
