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

function New-LinearGradientBrush {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Rectangle]$Rectangle,
        [Parameter(Mandatory = $true)]
        [string]$Color1,
        [Parameter(Mandatory = $true)]
        [string]$Color2,
        [System.Drawing.Drawing2D.LinearGradientMode]$Mode = [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal
    )
    $c1 = [System.Drawing.ColorTranslator]::FromHtml($Color1)
    $c2 = [System.Drawing.ColorTranslator]::FromHtml($Color2)
    return New-Object System.Drawing.Drawing2D.LinearGradientBrush($Rectangle, $c1, $c2, $Mode)
}

function Get-MockupTheme {
    param(
        [Parameter(Mandatory = $true)]
        [int]$VariantIndex
    )
    switch ($VariantIndex) {
        1 {
            return @{
                bg1 = "#F6F0E7"
                bg2 = "#EAE3D7"
                shadow = "#000000"
                floor = "#D9D0C2"
            }
        }
        2 {
            return @{
                bg1 = "#EEF4F5"
                bg2 = "#DCE7EA"
                shadow = "#000000"
                floor = "#C9D6DA"
            }
        }
        default {
            return @{
                bg1 = "#F5F6F7"
                bg2 = "#E7EAED"
                shadow = "#000000"
                floor = "#D6DBE1"
            }
        }
    }
}

function Draw-BookMockup {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CoverPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [int]$VariantIndex
    )

    Add-Type -AssemblyName System.Drawing

    $canvasWidth = 1800
    $canvasHeight = 1350
    $canvas = New-Object System.Drawing.Bitmap($canvasWidth, $canvasHeight)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

    $theme = Get-MockupTheme -VariantIndex $VariantIndex
    $bgRect = New-Object System.Drawing.Rectangle(0, 0, $canvasWidth, $canvasHeight)
    $bgBrush = New-LinearGradientBrush -Rectangle $bgRect -Color1 $theme.bg1 -Color2 $theme.bg2

    $floorBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml($theme.floor))
    $shadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(42, [System.Drawing.ColorTranslator]::FromHtml($theme.shadow)))
    $softShadowBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(24, [System.Drawing.ColorTranslator]::FromHtml($theme.shadow)))
    $strokePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(28, 40, 48, 58), 2)

    $graphics.FillRectangle($bgBrush, $bgRect)
    $graphics.FillRectangle($floorBrush, 0, 1000, $canvasWidth, 350)

    $graphics.FillEllipse($shadowBrush, 450, 905, 920, 150)
    $graphics.FillEllipse($softShadowBrush, 500, 870, 820, 100)

    $cover = [System.Drawing.Bitmap]::new($CoverPath)
    $scaledWidth = 700
    $scaledHeight = [int]([Math]::Round(($cover.Height / [double]$cover.Width) * $scaledWidth))
    $bookX = 550
    $bookY = 195

    $spineBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(220, 230, 233, 236))
    $pageBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 248, 249, 247))

    $graphics.FillRectangle($pageBrush, ($bookX + 18), ($bookY + 16), $scaledWidth, $scaledHeight)
    $graphics.FillRectangle($spineBrush, ($bookX - 26), ($bookY + 24), 42, $scaledHeight)
    $graphics.DrawRectangle($strokePen, ($bookX - 26), ($bookY + 24), 42, $scaledHeight)
    $graphics.DrawImage($cover, $bookX, $bookY, $scaledWidth, $scaledHeight)
    $graphics.DrawRectangle($strokePen, $bookX, $bookY, $scaledWidth, $scaledHeight)

    $tagFont = New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $smallFont = New-Object System.Drawing.Font("Segoe UI", 22, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(180, 46, 58, 70))
    $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(255, 38, 90, 97))

    $graphics.DrawString("SageWrite cover mockup", $tagFont, $accentBrush, 120, 92)
    $graphics.DrawString(("Variant " + ("{0:D2}" -f $VariantIndex)), $smallFont, $textBrush, 120, 140)

    $canvas.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)

    $tagFont.Dispose()
    $smallFont.Dispose()
    $textBrush.Dispose()
    $accentBrush.Dispose()
    $spineBrush.Dispose()
    $pageBrush.Dispose()
    $strokePen.Dispose()
    $shadowBrush.Dispose()
    $softShadowBrush.Dispose()
    $floorBrush.Dispose()
    $bgBrush.Dispose()
    $cover.Dispose()
    $graphics.Dispose()
    $canvas.Dispose()
}

$EnginePath       = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot         = Split-Path -Parent $EnginePath
$ClawRoot         = Split-Path -Parent $SageRoot
$WorkspaceRoot    = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot         = Join-Path $WorkspaceRoot "sagewrite\book"
$CoverBaseRoot    = Join-Path $BookRoot "07_cover"
$CoverRoot        = Join-Path $CoverBaseRoot $Edition
$LayoutRoot       = Join-Path $CoverRoot "layout"
$MockupRoot       = Join-Path $CoverRoot "mockup"
$LogRoot          = Join-Path $BookRoot "logs"

$LayoutManifestPath = Join-Path $LayoutRoot "layout_manifest.json"
$MockupManifestPath = Join-Path $MockupRoot "mockup_manifest.json"
$LogPath            = Join-Path $LogRoot "08f-mockup.log"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $MockupRoot
Ensure-Directory -Path $LogRoot

Assert-FileExists -Path $LayoutManifestPath -Description "layout_manifest.json"

if ((Test-Path -LiteralPath $MockupManifestPath) -and (-not $Force)) {
    Write-Host "mockup_manifest.json already exists. Use -Force to regenerate."
    exit 0
}

Get-ChildItem -LiteralPath $MockupRoot -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$LayoutManifest = Read-JsonUtf8 -Path $LayoutManifestPath
$Outputs = @($LayoutManifest.outputs)
if ($Outputs.Count -lt 1) {
    throw "No layout outputs found in layout_manifest.json."
}

$maxMockups = switch ($Mode) {
    "fast" { 1 }
    "full" { [Math]::Min($Outputs.Count, 3) }
    default { [Math]::Min($Outputs.Count, 2) }
}

$chosen = @($Outputs | Select-Object -First $maxMockups)
$mockups = @()
$i = 1
foreach ($item in $chosen) {
    $mockupName = "mockup_{0:D2}.jpg" -f $i
    $mockupPath = Join-Path $MockupRoot $mockupName
    Draw-BookMockup -CoverPath (Get-StringValue -Value $item.path) -OutputPath $mockupPath -VariantIndex $i

    $mockups += [ordered]@{
        index = $i
        file = $mockupName
        path = $mockupPath
        source_layout = Get-StringValue -Value $item.file
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $i++
}

$Manifest = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    mode = $Mode
    source = [ordered]@{
        layout_manifest = Split-Path -Leaf $LayoutManifestPath
    }
    outputs = @($mockups)
}

Write-JsonUtf8 -Data $Manifest -Path $MockupManifestPath
Set-Content -LiteralPath $LogPath -Value ("[{0}] 08f-mockup completed." -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host ""
Write-Host "08f-mockup completed successfully."
Write-Host ("Manifest: " + $MockupManifestPath)
Write-Host ("Mockups: " + $MockupRoot)
