param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateRange(1, 20)]
    [int]$Variants = 4,

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

function Get-RoutePromptObjects {
    param(
        [Parameter(Mandatory = $true)]
        $Strategy
    )
    $items = @()
    if ($Strategy.generation_plan -and $Strategy.generation_plan.prompt_package -and $Strategy.generation_plan.prompt_package.route_prompts) {
        $items = @($Strategy.generation_plan.prompt_package.route_prompts)
    }
    return @($items)
}

function Get-ColorSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RouteId
    )

    switch ($RouteId) {
        "human-ai-collaboration" {
            return @{
                background = "#F4FBFA"
                accent     = "#1E8A7A"
                accent2    = "#103C45"
                text       = "#10212B"
            }
        }
        "civilization-blueprint" {
            return @{
                background = "#F5F5F0"
                accent     = "#194C80"
                accent2    = "#2B3440"
                text       = "#13202C"
            }
        }
        "popular-thoughtful-nonfiction" {
            return @{
                background = "#FBF8F2"
                accent     = "#245D4E"
                accent2    = "#1F3650"
                text       = "#1E252E"
            }
        }
        "educational-illustrative" {
            return @{
                background = "#FBFBF5"
                accent     = "#2E6C62"
                accent2    = "#D0822C"
                text       = "#1D2228"
            }
        }
        default {
            return @{
                background = "#FAF7F2"
                accent     = "#2D4C7C"
                accent2    = "#7B5A38"
                text       = "#1A1F24"
            }
        }
    }
}

function Get-SafeFont {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Candidates,
        [Parameter(Mandatory = $true)]
        [float]$Size,
        [Parameter(Mandatory = $true)]
        [System.Drawing.FontStyle]$Style
    )
    foreach ($name in $Candidates) {
        try {
            return New-Object System.Drawing.Font($name, $Size, $Style, [System.Drawing.GraphicsUnit]::Pixel)
        }
        catch {
        }
    }
    return New-Object System.Drawing.Font("Arial", $Size, $Style, [System.Drawing.GraphicsUnit]::Pixel)
}

function Split-TextLines {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text,
        [int]$MaxChars = 18
    )
    if ([string]::IsNullOrWhiteSpace($Text)) {
        return @()
    }

    $clean = $Text.Trim()
    $lines = New-Object System.Collections.Generic.List[string]
    $buffer = ""

    foreach ($ch in $clean.ToCharArray()) {
        $buffer += [string]$ch
        if ($buffer.Length -ge $MaxChars) {
            $lines.Add($buffer.Trim())
            $buffer = ""
        }
    }
    if (-not [string]::IsNullOrWhiteSpace($buffer)) {
        $lines.Add($buffer.Trim())
    }
    return @($lines)
}

function New-PlaceholderDraft {
    param(
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Subtitle,
        [string]$Author,
        [Parameter(Mandatory = $true)]
        [string]$RouteLabel,
        [Parameter(Mandatory = $true)]
        [string]$RouteId,
        [Parameter(Mandatory = $true)]
        [int]$VariantIndex
    )

    Add-Type -AssemblyName System.Drawing

    $width = 1200
    $height = 1800
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $colors = Get-ColorSpec -RouteId $RouteId
    $bg = [System.Drawing.ColorTranslator]::FromHtml($colors.background)
    $accent = [System.Drawing.ColorTranslator]::FromHtml($colors.accent)
    $accent2 = [System.Drawing.ColorTranslator]::FromHtml($colors.accent2)
    $text = [System.Drawing.ColorTranslator]::FromHtml($colors.text)
    $muted = [System.Drawing.Color]::FromArgb(145, $text)

    $graphics.Clear($bg)

    $mainBrush = New-Object System.Drawing.SolidBrush($text)
    $mutedBrush = New-Object System.Drawing.SolidBrush($muted)
    $accentBrush = New-Object System.Drawing.SolidBrush($accent)
    $accent2Brush = New-Object System.Drawing.SolidBrush($accent2)

    $pen1 = New-Object System.Drawing.Pen($accent, 5)
    $pen2 = New-Object System.Drawing.Pen($accent2, 2)

    $graphics.FillRectangle($accentBrush, 92, 96, 1016, 18)
    $graphics.FillRectangle($accent2Brush, 92, 132, 360, 10)
    $graphics.FillEllipse($accentBrush, 826, 154, 220, 220)
    $graphics.DrawEllipse($pen2, 752, 780, 280, 280)
    $graphics.DrawLine($pen1, 118, 1520, 1080, 1520)
    $graphics.DrawLine($pen2, 118, 1568, 980, 1642)

    $titleFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size 58 -Style ([System.Drawing.FontStyle]::Bold)
    $subtitleFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size 28 -Style ([System.Drawing.FontStyle]::Regular)
    $metaFont = Get-SafeFont -Candidates @("Segoe UI", "Arial") -Size 24 -Style ([System.Drawing.FontStyle]::Regular)
    $routeFont = Get-SafeFont -Candidates @("Segoe UI", "Arial") -Size 22 -Style ([System.Drawing.FontStyle]::Bold)

    $titleLines = Split-TextLines -Text $Title -MaxChars 14
    $y = 250
    foreach ($line in $titleLines) {
        $graphics.DrawString($line, $titleFont, $mainBrush, 120, $y)
        $y += 88
    }

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        $subtitleRect = New-Object System.Drawing.RectangleF(124, ($y + 24), 840, 180)
        $graphics.DrawString($Subtitle, $subtitleFont, $mutedBrush, $subtitleRect)
        $y += 150
    }

    if (-not [string]::IsNullOrWhiteSpace($Author)) {
        $graphics.DrawString($Author, $metaFont, $mainBrush, 124, 1320)
    }

    $graphics.DrawString(("Route: " + $RouteLabel), $routeFont, $accentBrush, 124, 1456)
    $graphics.DrawString(("Candidate " + ("{0:D2}" -f $VariantIndex)), $metaFont, $mutedBrush, 124, 1602)
    $graphics.DrawString("SageWrite cover draft", $metaFont, $mutedBrush, 124, 1642)

    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)

    $titleFont.Dispose()
    $subtitleFont.Dispose()
    $metaFont.Dispose()
    $routeFont.Dispose()
    $mainBrush.Dispose()
    $mutedBrush.Dispose()
    $accentBrush.Dispose()
    $accent2Brush.Dispose()
    $pen1.Dispose()
    $pen2.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
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
$LogRoot          = Join-Path $BookRoot "logs"

$BriefJsonPath    = Join-Path $CoverBriefRoot "cover_brief.json"
$StrategyJsonPath = Join-Path $CoverBriefRoot "cover_strategy.json"
$ManifestPath     = Join-Path $DraftRoot "generation_manifest.json"
$LogPath          = Join-Path $LogRoot "08c-generate.log"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $CoverBriefRoot
Ensure-Directory -Path $DraftRoot
Ensure-Directory -Path $LogRoot

Assert-FileExists -Path $BriefJsonPath -Description "cover_brief.json"
Assert-FileExists -Path $StrategyJsonPath -Description "cover_strategy.json"

if ((Test-Path -LiteralPath $ManifestPath) -and (-not $Force)) {
    Write-Host "generation_manifest.json already exists. Use -Force to regenerate."
    exit 0
}

Get-ChildItem -LiteralPath $DraftRoot -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$Strategy = Read-JsonUtf8 -Path $StrategyJsonPath

$Title = Get-StringValue -Value $Brief.cover_text.title
$Subtitle = Get-StringValue -Value $Brief.cover_text.subtitle
$Author = Get-StringValue -Value $Brief.cover_text.author
$RoutePrompts = Get-RoutePromptObjects -Strategy $Strategy

if ($RoutePrompts.Count -lt 1) {
    throw "No route prompts found in cover_strategy.json."
}

$RequestedCount = switch ($Mode) {
    "fast" { [Math]::Min($Variants, 2) }
    "full" { [Math]::Max($Variants, 6) }
    default { $Variants }
}

if ($RequestedCount -lt 1) {
    $RequestedCount = 1
}

$ManifestCandidates = @()

for ($i = 1; $i -le $RequestedCount; $i++) {
    $route = $RoutePrompts[($i - 1) % $RoutePrompts.Count]
    $fileName = "candidate_{0:D2}.png" -f $i
    $outputPath = Join-Path $DraftRoot $fileName

    New-PlaceholderDraft `
        -OutputPath $outputPath `
        -Title $Title `
        -Subtitle $Subtitle `
        -Author $Author `
        -RouteLabel (Get-StringValue -Value $route.route_label) `
        -RouteId (Get-StringValue -Value $route.route_id) `
        -VariantIndex $i

    $ManifestCandidates += [ordered]@{
        index            = $i
        file             = $fileName
        path             = $outputPath
        route_id         = Get-StringValue -Value $route.route_id
        route_label      = Get-StringValue -Value $route.route_label
        prompt           = Get-StringValue -Value $route.prompt_draft
        generator        = "local-placeholder"
        generation_mode  = "stage1-draft"
        generated_at     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        image_size       = "1200x1800"
    }
}

$Manifest = [ordered]@{
    generated_at     = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name        = $BookName
    mode             = $Mode
    requested_count  = $RequestedCount
    actual_count     = $ManifestCandidates.Count
    source = [ordered]@{
        brief_file    = Split-Path -Leaf $BriefJsonPath
        strategy_file = Split-Path -Leaf $StrategyJsonPath
    }
    notes = @(
        "Stage 1 stable draft generation mode.",
        "Draft images are placeholder cover comps driven by strategy prompts.",
        "These files are suitable for review, ranking, and later layout replacement."
    )
    candidates       = @($ManifestCandidates)
}

Write-JsonUtf8 -Data $Manifest -Path $ManifestPath
Set-Content -LiteralPath $LogPath -Value ("[{0}] 08c-generate completed." -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host ""
Write-Host "08c-generate completed successfully."
Write-Host ("Manifest: " + $ManifestPath)
Write-Host ("Drafts: " + $DraftRoot)
