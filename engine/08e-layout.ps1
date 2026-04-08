param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

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

function Get-LayoutSpec {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RouteId,
        [Parameter(Mandatory = $true)]
        [int]$VariantIndex
    )
    switch ($RouteId) {
        "human-ai-collaboration" {
            if ($VariantIndex % 2 -eq 1) {
                return @{
                    overlay = "#F7FCFB"
                    title   = "#143A44"
                    meta    = "#255D67"
                    accent  = "#1E8A7A"
                    style   = "left-panel"
                }
            }
            return @{
                overlay = "#102F3A"
                title   = "#F8FBFA"
                meta    = "#D8ECE7"
                accent  = "#5CC7B8"
                style   = "bottom-band"
            }
        }
        "civilization-blueprint" {
            return @{
                overlay = "#F5F3EE"
                title   = "#173A63"
                meta    = "#354C61"
                accent  = "#9A7A48"
                style   = "top-block"
            }
        }
        default {
            return @{
                overlay = "#FBF7F0"
                title   = "#183042"
                meta    = "#4D5D68"
                accent  = "#2E6C62"
                style   = "left-panel"
            }
        }
    }
}

function Draw-LayoutCover {
    param(
        [Parameter(Mandatory = $true)]
        [string]$InputPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Subtitle,
        [string]$Author,
        [Parameter(Mandatory = $true)]
        [string]$RouteId,
        [Parameter(Mandatory = $true)]
        [string]$RouteLabel,
        [Parameter(Mandatory = $true)]
        [int]$VariantIndex
    )

    Add-Type -AssemblyName System.Drawing

    $bitmap = [System.Drawing.Bitmap]::new($InputPath)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    try {
        $spec = Get-LayoutSpec -RouteId $RouteId -VariantIndex $VariantIndex
        $overlayColor = [System.Drawing.ColorTranslator]::FromHtml($spec.overlay)
        $titleColor   = [System.Drawing.ColorTranslator]::FromHtml($spec.title)
        $metaColor    = [System.Drawing.ColorTranslator]::FromHtml($spec.meta)
        $accentColor  = [System.Drawing.ColorTranslator]::FromHtml($spec.accent)

        $overlayBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(232, $overlayColor))
        $titleBrush = New-Object System.Drawing.SolidBrush($titleColor)
        $metaBrush = New-Object System.Drawing.SolidBrush($metaColor)
        $accentBrush = New-Object System.Drawing.SolidBrush($accentColor)
        $linePen = New-Object System.Drawing.Pen($accentColor, 4)

        $titleFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size 60 -Style ([System.Drawing.FontStyle]::Bold)
        $subtitleFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size 28 -Style ([System.Drawing.FontStyle]::Regular)
        $authorFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size 30 -Style ([System.Drawing.FontStyle]::Regular)
        $routeFont = Get-SafeFont -Candidates @("Segoe UI", "Arial") -Size 20 -Style ([System.Drawing.FontStyle]::Bold)

        $w = $bitmap.Width
        $h = $bitmap.Height

        switch ($spec.style) {
            "bottom-band" {
                $bandHeight = 470
                $graphics.FillRectangle($overlayBrush, 0, ($h - $bandHeight), $w, $bandHeight)
                $graphics.FillRectangle($accentBrush, 92, ($h - $bandHeight + 74), 170, 10)

                $titleRect = New-Object System.Drawing.RectangleF(96, ($h - $bandHeight + 118), ($w - 180), 220)
                $graphics.DrawString($Title, $titleFont, $titleBrush, $titleRect)

                if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
                    $subtitleRect = New-Object System.Drawing.RectangleF(98, ($h - $bandHeight + 284), ($w - 180), 110)
                    $graphics.DrawString($Subtitle, $subtitleFont, $metaBrush, $subtitleRect)
                }

                if (-not [string]::IsNullOrWhiteSpace($Author)) {
                    $graphics.DrawString($Author, $authorFont, $titleBrush, 98, ($h - 122))
                }
                $graphics.DrawString($RouteLabel, $routeFont, $metaBrush, ($w - 320), ($h - 112))
            }
            "top-block" {
                $graphics.FillRectangle($overlayBrush, 90, 92, ($w - 180), 520)
                $graphics.DrawRectangle($linePen, 90, 92, ($w - 180), 520)
                $graphics.FillRectangle($accentBrush, 128, 136, 180, 8)

                $titleRect = New-Object System.Drawing.RectangleF(126, 190, ($w - 240), 220)
                $graphics.DrawString($Title, $titleFont, $titleBrush, $titleRect)

                if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
                    $subtitleRect = New-Object System.Drawing.RectangleF(128, 372, ($w - 250), 110)
                    $graphics.DrawString($Subtitle, $subtitleFont, $metaBrush, $subtitleRect)
                }

                if (-not [string]::IsNullOrWhiteSpace($Author)) {
                    $graphics.DrawString($Author, $authorFont, $titleBrush, 128, 510)
                }

                $graphics.DrawString($RouteLabel, $routeFont, $metaBrush, 128, 1440)
            }
            default {
                $panelWidth = 618
                $graphics.FillRectangle($overlayBrush, 88, 88, $panelWidth, ($h - 176))
                $graphics.FillRectangle($accentBrush, 132, 142, 190, 10)
                $graphics.DrawLine($linePen, 132, 1500, 610, 1500)

                $y = 222
                foreach ($line in (Split-TextLines -Text $Title -MaxChars 12)) {
                    $graphics.DrawString($line, $titleFont, $titleBrush, 128, $y)
                    $y += 92
                }

                if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
                    $subtitleRect = New-Object System.Drawing.RectangleF(132, ($y + 18), 480, 180)
                    $graphics.DrawString($Subtitle, $subtitleFont, $metaBrush, $subtitleRect)
                    $y += 138
                }

                if (-not [string]::IsNullOrWhiteSpace($Author)) {
                    $graphics.DrawString($Author, $authorFont, $titleBrush, 132, 1402)
                }

                $graphics.DrawString($RouteLabel, $routeFont, $metaBrush, 132, 1540)
            }
        }

        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)

        $overlayBrush.Dispose()
        $titleBrush.Dispose()
        $metaBrush.Dispose()
        $accentBrush.Dispose()
        $linePen.Dispose()
        $titleFont.Dispose()
        $subtitleFont.Dispose()
        $authorFont.Dispose()
        $routeFont.Dispose()
    }
    finally {
        $graphics.Dispose()
        $bitmap.Dispose()
    }
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
$LayoutRoot       = Join-Path $CoverRoot "layout"
$LogRoot          = Join-Path $BookRoot "logs"

$BriefJsonPath    = Join-Path $CoverBriefRoot "cover_brief.json"
$ReviewJsonPath   = Join-Path $ReviewRoot "cover_review.json"
$LayoutManifest   = Join-Path $LayoutRoot "layout_manifest.json"
$LogPath          = Join-Path $LogRoot "08e-layout.log"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $LayoutRoot
Ensure-Directory -Path $LogRoot

Assert-FileExists -Path $BriefJsonPath -Description "cover_brief.json"
Assert-FileExists -Path $ReviewJsonPath -Description "cover_review.json"

if ((Test-Path -LiteralPath $LayoutManifest) -and (-not $Force)) {
    Write-Host "layout_manifest.json already exists. Use -Force to regenerate."
    exit 0
}

Get-ChildItem -LiteralPath $LayoutRoot -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$Review = Read-JsonUtf8 -Path $ReviewJsonPath

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = Get-StringValue -Value $Brief.cover_text.title
}
if ([string]::IsNullOrWhiteSpace($Subtitle)) {
    $Subtitle = Get-StringValue -Value $Brief.cover_text.subtitle
}
if ([string]::IsNullOrWhiteSpace($Author)) {
    $Author = Get-StringValue -Value $Brief.cover_text.author
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    throw "Title is missing for layout generation."
}

$selectedFiles = Get-StringArray -Value $Review.selected_files
$ranked = @($Review.ranked_candidates)

if ($selectedFiles.Count -lt 1) {
    $selectedFiles = @($ranked | Select-Object -First 1 | ForEach-Object { $_.file })
}

$maxLayouts = switch ($Mode) {
    "fast" { 1 }
    "full" { 3 }
    default { 2 }
}

$chosen = @()
foreach ($file in $selectedFiles) {
    $match = $ranked | Where-Object { "$($_.file)" -eq "$file" } | Select-Object -First 1
    if ($null -ne $match) {
        $chosen += $match
    }
}
if ($chosen.Count -lt 1) {
    throw "No shortlisted candidates could be resolved for layout."
}
if ($chosen.Count -gt $maxLayouts) {
    $chosen = @($chosen | Select-Object -First $maxLayouts)
}

$layoutOutputs = @()
$index = 1
foreach ($item in $chosen) {
    $outName = "cover_front_v{0}.png" -f $index
    $outPath = Join-Path $LayoutRoot $outName
    Draw-LayoutCover `
        -InputPath (Get-StringValue -Value $item.path) `
        -OutputPath $outPath `
        -Title $Title `
        -Subtitle $Subtitle `
        -Author $Author `
        -RouteId (Get-StringValue -Value $item.route_id) `
        -RouteLabel (Get-StringValue -Value $item.route_label) `
        -VariantIndex $index

    $layoutOutputs += [ordered]@{
        version = $index
        file = $outName
        path = $outPath
        source_candidate = Get-StringValue -Value $item.file
        route_id = Get-StringValue -Value $item.route_id
        route_label = Get-StringValue -Value $item.route_label
        source_rank = $item.rank
        source_score = $item.scores.overall
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $index++
}

$manifest = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    mode = $Mode
    cover_text = [ordered]@{
        title = $Title
        subtitle = $Subtitle
        author = $Author
    }
    source = [ordered]@{
        brief_file = Split-Path -Leaf $BriefJsonPath
        review_file = Split-Path -Leaf $ReviewJsonPath
    }
    outputs = @($layoutOutputs)
}

Write-JsonUtf8 -Data $manifest -Path $LayoutManifest
Set-Content -LiteralPath $LogPath -Value ("[{0}] 08e-layout completed." -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host ""
Write-Host "08e-layout completed successfully."
Write-Host ("Manifest: " + $LayoutManifest)
Write-Host ("Layouts: " + $LayoutRoot)
