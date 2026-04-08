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

function Get-RouteRankMap {
    param(
        [Parameter(Mandatory = $true)]
        $Strategy
    )
    $map = @{}
    $idx = 1
    foreach ($route in @($Strategy.strategy_routes)) {
        $id = Get-StringValue -Value $route.id
        if (-not [string]::IsNullOrWhiteSpace($id) -and (-not $map.ContainsKey($id))) {
            $map[$id] = $idx
            $idx++
        }
    }
    return $map
}

function Get-ImageStats {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Add-Type -AssemblyName System.Drawing

    $bitmap = [System.Drawing.Bitmap]::new($Path)
    try {
        $stepX = [Math]::Max([int]($bitmap.Width / 40), 1)
        $stepY = [Math]::Max([int]($bitmap.Height / 60), 1)

        $count = 0
        $sum = 0.0
        $sumSq = 0.0
        $min = 255.0
        $max = 0.0

        for ($y = 0; $y -lt $bitmap.Height; $y += $stepY) {
            for ($x = 0; $x -lt $bitmap.Width; $x += $stepX) {
                $pixel = $bitmap.GetPixel($x, $y)
                $lum = (0.299 * $pixel.R) + (0.587 * $pixel.G) + (0.114 * $pixel.B)
                $sum += $lum
                $sumSq += ($lum * $lum)
                if ($lum -lt $min) { $min = $lum }
                if ($lum -gt $max) { $max = $lum }
                $count++
            }
        }

        if ($count -eq 0) {
            throw "Unable to sample image pixels: $Path"
        }

        $avg = $sum / $count
        $variance = ($sumSq / $count) - ($avg * $avg)
        if ($variance -lt 0) { $variance = 0 }
        $stddev = [Math]::Sqrt($variance)

        return [ordered]@{
            width       = $bitmap.Width
            height      = $bitmap.Height
            aspect_ratio= [Math]::Round(($bitmap.Width / $bitmap.Height), 4)
            avg_luma    = [Math]::Round($avg, 2)
            contrast    = [Math]::Round($stddev, 2)
            luma_range  = [Math]::Round(($max - $min), 2)
        }
    }
    finally {
        $bitmap.Dispose()
    }
}

function Get-AspectScore {
    param(
        [double]$AspectRatio
    )
    $target = 2.0 / 3.0
    $delta = [Math]::Abs($AspectRatio - $target)
    $score = 100 - ($delta * 600)
    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }
    return [Math]::Round($score, 2)
}

function Get-RangeScore {
    param(
        [double]$Value,
        [double]$IdealMin,
        [double]$IdealMax,
        [double]$Tolerance
    )
    if ($Value -ge $IdealMin -and $Value -le $IdealMax) {
        return 100.0
    }
    if ($Value -lt $IdealMin) {
        $delta = $IdealMin - $Value
    }
    else {
        $delta = $Value - $IdealMax
    }
    $score = 100 - (($delta / $Tolerance) * 100)
    if ($score -lt 0) { $score = 0 }
    if ($score -gt 100) { $score = 100 }
    return [Math]::Round($score, 2)
}

function Get-RouteAlignmentScore {
    param(
        [string]$RouteId,
        [hashtable]$RouteRankMap
    )
    if (-not $RouteRankMap.ContainsKey($RouteId)) {
        return 55
    }
    $rank = [int]$RouteRankMap[$RouteId]
    switch ($rank) {
        1 { return 100 }
        2 { return 88 }
        3 { return 80 }
        4 { return 72 }
        default { return 65 }
    }
}

function Get-ReviewDecision {
    param(
        [double]$Score,
        [int]$Rank
    )
    if ($Rank -eq 1 -and $Score -ge 80) {
        return "selected"
    }
    if ($Rank -le 2 -and $Score -ge 72) {
        return "shortlisted"
    }
    if ($Score -ge 60) {
        return "usable"
    }
    return "reject"
}

function Get-Strengths {
    param(
        [double]$RouteScore,
        [double]$AspectScore,
        [double]$ContrastScore,
        [double]$BrightnessScore,
        [double]$RangeScore
    )
    $items = New-Object System.Collections.Generic.List[string]
    if ($RouteScore -ge 90) { $items.Add("Strong alignment with primary strategy route.") }
    if ($AspectScore -ge 95) { $items.Add("Aspect ratio is well suited to front-cover composition.") }
    if ($ContrastScore -ge 80) { $items.Add("Contrast profile should support thumbnail readability.") }
    if ($BrightnessScore -ge 75) { $items.Add("Overall brightness sits in a publishable range.") }
    if ($RangeScore -ge 80) { $items.Add("Luminance range suggests a clear visual hierarchy.") }
    return @($items)
}

function Get-Weaknesses {
    param(
        [double]$RouteScore,
        [double]$AspectScore,
        [double]$ContrastScore,
        [double]$BrightnessScore,
        [double]$RangeScore
    )
    $items = New-Object System.Collections.Generic.List[string]
    if ($RouteScore -lt 80) { $items.Add("Route choice is weaker against the current primary strategy.") }
    if ($AspectScore -lt 90) { $items.Add("Aspect ratio deviates from the preferred print cover proportion.") }
    if ($ContrastScore -lt 65) { $items.Add("Contrast may be too soft for strong shelf or thumbnail presence.") }
    if ($BrightnessScore -lt 65) { $items.Add("Brightness balance may be too dark or too washed out.") }
    if ($RangeScore -lt 65) { $items.Add("Visual range may be too flat to create a strong cover hierarchy.") }
    return @($items)
}

$EnginePath       = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot         = Split-Path -Parent $EnginePath
$ClawRoot         = Split-Path -Parent $SageRoot
$WorkspaceRoot    = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot         = Join-Path $WorkspaceRoot "sagewrite\book"
$CoverBaseRoot    = Join-Path $BookRoot "07_cover"
$CoverRoot        = Join-Path $CoverBaseRoot $Edition
$CoverBriefRoot   = Join-Path $CoverRoot "brief"
$DraftRoot        = Join-Path $CoverRoot "drafts"
$ReviewRoot       = Join-Path $CoverRoot "reviews"
$LogRoot          = Join-Path $BookRoot "logs"

$BriefJsonPath    = Join-Path $CoverBriefRoot "cover_brief.json"
$StrategyJsonPath = Join-Path $CoverBriefRoot "cover_strategy.json"
$ManifestPath     = Join-Path $DraftRoot "generation_manifest.json"
$ReviewJsonPath   = Join-Path $ReviewRoot "cover_review.json"
$LogPath          = Join-Path $LogRoot "08d-review.log"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $DraftRoot
Ensure-Directory -Path $ReviewRoot
Ensure-Directory -Path $LogRoot

Assert-FileExists -Path $BriefJsonPath -Description "cover_brief.json"
Assert-FileExists -Path $StrategyJsonPath -Description "cover_strategy.json"
Assert-FileExists -Path $ManifestPath -Description "generation_manifest.json"

if ((Test-Path -LiteralPath $ReviewJsonPath) -and (-not $Force)) {
    Write-Host "cover_review.json already exists. Use -Force to regenerate."
    exit 0
}

$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$Strategy = Read-JsonUtf8 -Path $StrategyJsonPath
$Manifest = Read-JsonUtf8 -Path $ManifestPath

$RouteRankMap = Get-RouteRankMap -Strategy $Strategy
$Candidates = @($Manifest.candidates)
if ($Candidates.Count -lt 1) {
    throw "No candidates found in generation_manifest.json."
}

$Reviewed = @()

foreach ($candidate in $Candidates) {
    $filePath = Get-StringValue -Value $candidate.path
    Assert-FileExists -Path $filePath -Description "candidate image"

    $stats = Get-ImageStats -Path $filePath
    $routeId = Get-StringValue -Value $candidate.route_id
    $routeLabel = Get-StringValue -Value $candidate.route_label

    $routeScore = Get-RouteAlignmentScore -RouteId $routeId -RouteRankMap $RouteRankMap
    $aspectScore = Get-AspectScore -AspectRatio $stats.aspect_ratio
    $contrastScore = Get-RangeScore -Value $stats.contrast -IdealMin 42 -IdealMax 88 -Tolerance 35
    $brightnessScore = Get-RangeScore -Value $stats.avg_luma -IdealMin 120 -IdealMax 220 -Tolerance 70
    $rangeScore = Get-RangeScore -Value $stats.luma_range -IdealMin 140 -IdealMax 255 -Tolerance 120

    $overall = (
        ($routeScore * 0.30) +
        ($aspectScore * 0.15) +
        ($contrastScore * 0.20) +
        ($brightnessScore * 0.15) +
        ($rangeScore * 0.20)
    )
    $overall = [Math]::Round($overall, 2)

    $Reviewed += [ordered]@{
        file = Get-StringValue -Value $candidate.file
        path = $filePath
        route_id = $routeId
        route_label = $routeLabel
        prompt = Get-StringValue -Value $candidate.prompt
        scores = [ordered]@{
            route_alignment = $routeScore
            aspect_ratio = $aspectScore
            thumbnail_contrast = $contrastScore
            brightness_balance = $brightnessScore
            visual_range = $rangeScore
            overall = $overall
        }
        image_stats = $stats
        strengths = @(Get-Strengths -RouteScore $routeScore -AspectScore $aspectScore -ContrastScore $contrastScore -BrightnessScore $brightnessScore -RangeScore $rangeScore)
        weaknesses = @(Get-Weaknesses -RouteScore $routeScore -AspectScore $aspectScore -ContrastScore $contrastScore -BrightnessScore $brightnessScore -RangeScore $rangeScore)
    }
}

$Ranked = @(
    $Reviewed |
        Sort-Object -Property @{ Expression = { $_.scores.overall }; Descending = $true }, @{ Expression = { $_.file }; Descending = $false }
)

for ($i = 0; $i -lt $Ranked.Count; $i++) {
    $rank = $i + 1
    $Ranked[$i]["rank"] = $rank
    $Ranked[$i]["decision"] = Get-ReviewDecision -Score $Ranked[$i].scores.overall -Rank $rank
}

$Selected = @($Ranked | Where-Object { $_.decision -in @("selected", "shortlisted") })
if ($Selected.Count -lt 1) {
    $Selected = @($Ranked | Select-Object -First 1)
}

$Review = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    mode = $Mode
    source = [ordered]@{
        brief_file = Split-Path -Leaf $BriefJsonPath
        strategy_file = Split-Path -Leaf $StrategyJsonPath
        manifest_file = Split-Path -Leaf $ManifestPath
    }
    review_method = [ordered]@{
        type = "stage1-heuristic-review"
        summary = "Candidates are scored by strategy fit, cover aspect ratio, contrast, brightness balance, and luminance range."
        dimensions = @(
            "fit with current primary strategy",
            "front-cover aspect suitability",
            "thumbnail contrast proxy",
            "brightness balance",
            "visual range"
        )
    }
    ranked_candidates = @($Ranked)
    selected_files = @($Selected | ForEach-Object { $_.file })
    summary = [ordered]@{
        candidate_count = $Ranked.Count
        selected_count = $Selected.Count
        top_candidate = if ($Ranked.Count -gt 0) { $Ranked[0].file } else { $null }
        top_score = if ($Ranked.Count -gt 0) { $Ranked[0].scores.overall } else { $null }
    }
}

Write-JsonUtf8 -Data $Review -Path $ReviewJsonPath
Set-Content -LiteralPath $LogPath -Value ("[{0}] 08d-review completed." -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host ""
Write-Host "08d-review completed successfully."
Write-Host ("JSON: " + $ReviewJsonPath)
