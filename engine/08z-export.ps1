param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [switch]$SkipLayout,
    [switch]$SkipMockup,
    [switch]$Force,

    [double]$PrintTrimWidthIn = 6.0,
    [double]$PrintTrimHeightIn = 9.0,
    [double]$PrintBleedIn = 0.125,
    [double]$PrintSpineWidthIn = 0.595,
    [int]$PrintPageCount = 264,
    [int]$PrintDpi = 300
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

function Copy-Artifact {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )
    Assert-FileExists -Path $SourcePath -Description "source artifact"
    Copy-Item -LiteralPath $SourcePath -Destination $DestinationPath -Force
}

function Convert-InchesToMillimeters {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Inches
    )
    return [Math]::Round(($Inches * 25.4), 2)
}

function Convert-InchesToPixels {
    param(
        [Parameter(Mandatory = $true)]
        [double]$Inches,
        [Parameter(Mandatory = $true)]
        [int]$Dpi
    )
    return [int][Math]::Round($Inches * $Dpi)
}

function Get-KdpPrintCoverSpec {
    param(
        [double]$TrimWidthIn,
        [double]$TrimHeightIn,
        [double]$BleedIn,
        [double]$SpineWidthIn,
        [int]$PageCount,
        [int]$Dpi
    )

    $coverWidthIn = $BleedIn + $TrimWidthIn + $SpineWidthIn + $TrimWidthIn + $BleedIn
    $coverHeightIn = $BleedIn + $TrimHeightIn + $BleedIn

    return [ordered]@{
        source = "Amazon KDP paperback cover formula"
        formula = "Cover Width = Bleed + Back Cover Width + Spine Width + Front Cover Width + Bleed; Cover Height = Bleed + Trim Height + Bleed"
        trim_width_in = [Math]::Round($TrimWidthIn, 3)
        trim_height_in = [Math]::Round($TrimHeightIn, 3)
        page_count = $PageCount
        bleed_in = [Math]::Round($BleedIn, 3)
        bleed_mm = Convert-InchesToMillimeters -Inches $BleedIn
        spine_width_in = [Math]::Round($SpineWidthIn, 3)
        spine_width_mm = Convert-InchesToMillimeters -Inches $SpineWidthIn
        cover_width_in = [Math]::Round($coverWidthIn, 3)
        cover_height_in = [Math]::Round($coverHeightIn, 3)
        cover_width_mm = Convert-InchesToMillimeters -Inches $coverWidthIn
        cover_height_mm = Convert-InchesToMillimeters -Inches $coverHeightIn
        dpi = $Dpi
        pixel_width = Convert-InchesToPixels -Inches $coverWidthIn -Dpi $Dpi
        pixel_height = Convert-InchesToPixels -Inches $coverHeightIn -Dpi $Dpi
    }
}

function Draw-ImageCoverFill {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)]
        [System.Drawing.Image]$Image,
        [Parameter(Mandatory = $true)]
        [System.Drawing.RectangleF]$Destination
    )

    $sourceRatio = $Image.Width / [double]$Image.Height
    $destRatio = $Destination.Width / [double]$Destination.Height
    if ($sourceRatio -gt $destRatio) {
        $sourceHeight = $Image.Height
        $sourceWidth = [int][Math]::Round($Image.Height * $destRatio)
        $sourceX = [int][Math]::Round(($Image.Width - $sourceWidth) / 2)
        $sourceY = 0
    }
    else {
        $sourceWidth = $Image.Width
        $sourceHeight = [int][Math]::Round($Image.Width / $destRatio)
        $sourceX = 0
        $sourceY = [int][Math]::Round(($Image.Height - $sourceHeight) / 2)
    }

    $sourceRect = New-Object System.Drawing.RectangleF([float]$sourceX, [float]$sourceY, [float]$sourceWidth, [float]$sourceHeight)
    $Graphics.DrawImage($Image, $Destination, $sourceRect, [System.Drawing.GraphicsUnit]::Pixel)
}

function Write-AsciiToStream {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)]
        [string]$Text
    )
    $bytes = [System.Text.Encoding]::ASCII.GetBytes($Text)
    $Stream.Write($bytes, 0, $bytes.Length)
}

function Save-BitmapAsSinglePagePdf {
    param(
        [Parameter(Mandatory = $true)]
        [System.Drawing.Bitmap]$Bitmap,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [Parameter(Mandatory = $true)]
        [double]$PageWidthIn,
        [Parameter(Mandatory = $true)]
        [double]$PageHeightIn
    )

    $pageWidthPt = [Math]::Round($PageWidthIn * 72, 3)
    $pageHeightPt = [Math]::Round($PageHeightIn * 72, 3)
    $jpegStream = New-Object System.IO.MemoryStream
    $fileStream = $null

    try {
        $Bitmap.Save($jpegStream, [System.Drawing.Imaging.ImageFormat]::Jpeg)
        $jpegBytes = $jpegStream.ToArray()
        $content = "q`n$pageWidthPt 0 0 $pageHeightPt 0 0 cm`n/Im0 Do`nQ`n"
        $contentBytes = [System.Text.Encoding]::ASCII.GetBytes($content)
        $offsets = New-Object System.Collections.Generic.List[long]
        $fileStream = [System.IO.File]::Open($OutputPath, [System.IO.FileMode]::Create, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)

        Write-AsciiToStream -Stream $fileStream -Text "%PDF-1.4`n% SageWrite KDP print cover`n"

        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "1 0 obj`n<< /Type /Catalog /Pages 2 0 R >>`nendobj`n"

        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "2 0 obj`n<< /Type /Pages /Kids [3 0 R] /Count 1 >>`nendobj`n"

        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "3 0 obj`n<< /Type /Page /Parent 2 0 R /MediaBox [0 0 $pageWidthPt $pageHeightPt] /Resources << /XObject << /Im0 4 0 R >> >> /Contents 5 0 R >>`nendobj`n"

        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "4 0 obj`n<< /Type /XObject /Subtype /Image /Width $($Bitmap.Width) /Height $($Bitmap.Height) /ColorSpace /DeviceRGB /BitsPerComponent 8 /Filter /DCTDecode /Length $($jpegBytes.Length) >>`nstream`n"
        $fileStream.Write($jpegBytes, 0, $jpegBytes.Length)
        Write-AsciiToStream -Stream $fileStream -Text "`nendstream`nendobj`n"

        $offsets.Add($fileStream.Position)
        Write-AsciiToStream -Stream $fileStream -Text "5 0 obj`n<< /Length $($contentBytes.Length) >>`nstream`n"
        $fileStream.Write($contentBytes, 0, $contentBytes.Length)
        Write-AsciiToStream -Stream $fileStream -Text "endstream`nendobj`n"

        $xrefStart = $fileStream.Position
        Write-AsciiToStream -Stream $fileStream -Text "xref`n0 6`n0000000000 65535 f `n"
        foreach ($offset in $offsets) {
            Write-AsciiToStream -Stream $fileStream -Text ("{0:D10} 00000 n `n" -f $offset)
        }
        Write-AsciiToStream -Stream $fileStream -Text "trailer`n<< /Size 6 /Root 1 0 R >>`nstartxref`n$xrefStart`n%%EOF`n"
    }
    finally {
        if ($null -ne $fileStream) {
            $fileStream.Dispose()
        }
        $jpegStream.Dispose()
    }
}

function New-KdpPrintCoverSpread {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FrontCoverPath,
        [Parameter(Mandatory = $true)]
        [string]$OutputPath,
        [string]$PdfOutputPath,
        [Parameter(Mandatory = $true)]
        $Spec,
        [string]$Title,
        [string]$Subtitle,
        [string]$Author,
        [string]$SpineText
    )

    Add-Type -AssemblyName System.Drawing

    $canvasWidth = [int]$Spec.pixel_width
    $canvasHeight = [int]$Spec.pixel_height
    $dpi = [int]$Spec.dpi
    $bleedPx = $Spec.bleed_in * $dpi
    $trimWidthPx = $Spec.trim_width_in * $dpi
    $trimHeightPx = $Spec.trim_height_in * $dpi
    $spineWidthPx = $Spec.spine_width_in * $dpi
    $backX = $bleedPx
    $frontX = $bleedPx + $trimWidthPx + $spineWidthPx

    $bitmap = New-Object System.Drawing.Bitmap($canvasWidth, $canvasHeight)
    $bitmap.SetResolution($dpi, $dpi)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $frontCover = [System.Drawing.Image]::FromFile($FrontCoverPath)
    $bg = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#F5F1E8"))
    $panel = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#FBF8F1"))
    $spineBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#263945"))
    $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#22313B"))
    $mutedBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#596671"))
    $whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#F9FBFA"))
    $guidePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(120, 170, 80, 80), 1)
    $foldPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 60, 80, 95), 2)

    $titleFont = New-Object System.Drawing.Font("Segoe UI", 48, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)
    $bodyFont = New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $smallFont = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Regular, [System.Drawing.GraphicsUnit]::Pixel)
    $spineFont = New-Object System.Drawing.Font("Segoe UI", 28, [System.Drawing.FontStyle]::Bold, [System.Drawing.GraphicsUnit]::Pixel)

    try {
        $graphics.FillRectangle($bg, 0, 0, $canvasWidth, $canvasHeight)
        $graphics.FillRectangle($panel, [float]$backX, [float]$bleedPx, [float]$trimWidthPx, [float]$trimHeightPx)
        $graphics.FillRectangle($spineBrush, [float]($backX + $trimWidthPx), 0, [float]$spineWidthPx, $canvasHeight)

        $frontRect = New-Object System.Drawing.RectangleF([float]$frontX, 0, [float]($trimWidthPx + $bleedPx), $canvasHeight)
        Draw-ImageCoverFill -Graphics $graphics -Image $frontCover -Destination $frontRect

        $backTextRect = New-Object System.Drawing.RectangleF([float]($backX + 110), [float]($bleedPx + 250), [float]($trimWidthPx - 220), [float]($trimHeightPx - 520))
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
            $graphics.DrawString($Subtitle, $titleFont, $textBrush, $backTextRect)
        }
        else {
            $graphics.DrawString($Title, $titleFont, $textBrush, $backTextRect)
        }
        $graphics.DrawString("Back cover copy placeholder", $bodyFont, $mutedBrush, [float]($backX + 110), [float]($bleedPx + 650))
        $graphics.DrawString("Replace this panel with final KDP back-cover text before upload.", $smallFont, $mutedBrush, [float]($backX + 110), [float]($bleedPx + 700))

        $state = $graphics.Save()
        $graphics.TranslateTransform([float]($backX + $trimWidthPx + ($spineWidthPx / 2) + 16), [float]($bleedPx + $trimHeightPx - 130))
        $graphics.RotateTransform(-90)
        $spineLabel = if (-not [string]::IsNullOrWhiteSpace($SpineText)) { $SpineText } else { $Title }
        $graphics.DrawString($spineLabel, $spineFont, $whiteBrush, 0, 0)
        if (-not [string]::IsNullOrWhiteSpace($Author)) {
            $graphics.DrawString($Author, $smallFont, $whiteBrush, 0, 46)
        }
        $graphics.Restore($state)

        $graphics.DrawRectangle($guidePen, 0, 0, ($canvasWidth - 1), ($canvasHeight - 1))
        $graphics.DrawRectangle($guidePen, [int][Math]::Round($bleedPx), [int][Math]::Round($bleedPx), [int][Math]::Round($canvasWidth - ($bleedPx * 2)), [int][Math]::Round($trimHeightPx))
        $graphics.DrawLine($foldPen, [float]($backX + $trimWidthPx), 0, [float]($backX + $trimWidthPx), $canvasHeight)
        $graphics.DrawLine($foldPen, [float]($frontX), 0, [float]($frontX), $canvasHeight)

        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
        if (-not [string]::IsNullOrWhiteSpace($PdfOutputPath)) {
            Save-BitmapAsSinglePagePdf -Bitmap $bitmap -OutputPath $PdfOutputPath -PageWidthIn $Spec.cover_width_in -PageHeightIn $Spec.cover_height_in
        }
    }
    finally {
        $spineFont.Dispose()
        $smallFont.Dispose()
        $bodyFont.Dispose()
        $titleFont.Dispose()
        $foldPen.Dispose()
        $guidePen.Dispose()
        $whiteBrush.Dispose()
        $mutedBrush.Dispose()
        $textBrush.Dispose()
        $spineBrush.Dispose()
        $panel.Dispose()
        $bg.Dispose()
        $frontCover.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$EnginePath         = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot           = Split-Path -Parent $EnginePath
$ClawRoot           = Split-Path -Parent $SageRoot
$WorkspaceParentRoot = if (-not [string]::IsNullOrWhiteSpace($env:SAGEWRITE_WORKSPACE_ROOT)) { [System.IO.Path]::GetFullPath($env:SAGEWRITE_WORKSPACE_ROOT) } else { $ClawRoot }
$WorkspaceRoot      = Join-Path $WorkspaceParentRoot "workspace-$BookName"
$BookRoot           = Join-Path $WorkspaceRoot "sagewrite\book"
$CoverBaseRoot      = Join-Path $BookRoot "07_cover"
$CoverRoot          = Join-Path $CoverBaseRoot $Edition
$CoverBriefRoot     = Join-Path $CoverRoot "brief"
$DraftRoot          = Join-Path $CoverRoot "drafts"
$ReviewRoot         = Join-Path $CoverRoot "reviews"
$LayoutRoot         = Join-Path $CoverRoot "layout"
$MockupRoot         = Join-Path $CoverRoot "mockup"
$FinalRoot          = Join-Path $CoverRoot "final"
$LogRoot            = Join-Path $BookRoot "logs"

$BriefJsonPath      = Join-Path $CoverBriefRoot "cover_brief.json"
$StrategyJsonPath   = Join-Path $CoverBriefRoot "cover_strategy.json"
$ReviewJsonPath     = Join-Path $ReviewRoot "cover_review.json"
$LayoutManifestPath = Join-Path $LayoutRoot "layout_manifest.json"
$MockupManifestPath = Join-Path $MockupRoot "mockup_manifest.json"
$ExportManifestPath = Join-Path $FinalRoot "cover_export_manifest.json"
$ReportPath         = Join-Path $FinalRoot "cover_report.md"
$LogPath            = Join-Path $LogRoot "08z-export.log"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $FinalRoot
Ensure-Directory -Path $LogRoot

Assert-FileExists -Path $BriefJsonPath -Description "cover_brief.json"
Assert-FileExists -Path $StrategyJsonPath -Description "cover_strategy.json"
Assert-FileExists -Path $ReviewJsonPath -Description "cover_review.json"

if ((Test-Path -LiteralPath $ExportManifestPath) -and (-not $Force)) {
    Write-Host "cover_export_manifest.json already exists. Use -Force to regenerate."
    exit 0
}

Get-ChildItem -LiteralPath $FinalRoot -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue

$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$Strategy = Read-JsonUtf8 -Path $StrategyJsonPath
$Review = Read-JsonUtf8 -Path $ReviewJsonPath

$Title = Get-StringValue -Value $Brief.cover_text.title
$Subtitle = Get-StringValue -Value $Brief.cover_text.subtitle
$Author = Get-StringValue -Value $Brief.cover_text.author
$RawSpineText = $Brief.cover_text.spine_text
$SpineText = if ($null -eq $RawSpineText) { "" } else { Get-StringValue -Value $RawSpineText }
$PrimaryRouteLabel = Get-StringValue -Value $Strategy.primary_strategy.route_label
$PrimaryRouteId = Get-StringValue -Value $Strategy.primary_strategy.route_id
$SelectedFiles = Get-StringArray -Value $Review.selected_files

$finalOutputs = @()
$PrintCoverSpec = $null

if (-not $SkipLayout) {
    Assert-FileExists -Path $LayoutManifestPath -Description "layout_manifest.json"
    $LayoutManifest = Read-JsonUtf8 -Path $LayoutManifestPath
    $LayoutOutputs = @($LayoutManifest.outputs)
    if ($LayoutOutputs.Count -lt 1) {
        throw "No layout outputs found."
    }

    $PrimaryLayout = $LayoutOutputs[0]
    $PrimaryLayoutPath = Get-StringValue -Value $PrimaryLayout.path
    $FinalFrontPath = Join-Path $FinalRoot "cover_final_front.png"
    Copy-Artifact -SourcePath $PrimaryLayoutPath -DestinationPath $FinalFrontPath
    $finalOutputs += [ordered]@{
        role = "front_cover"
        file = Split-Path -Leaf $FinalFrontPath
        path = $FinalFrontPath
        source = Get-StringValue -Value $PrimaryLayout.file
    }

    if ($Edition -eq "print") {
        $PrintCoverSpec = Get-KdpPrintCoverSpec `
            -TrimWidthIn $PrintTrimWidthIn `
            -TrimHeightIn $PrintTrimHeightIn `
            -BleedIn $PrintBleedIn `
            -SpineWidthIn $PrintSpineWidthIn `
            -PageCount $PrintPageCount `
            -Dpi $PrintDpi

        $FinalPrintSpreadPath = Join-Path $FinalRoot "cover_final_kdp_print_spread.png"
        $FinalPrintSpreadPdfPath = Join-Path $FinalRoot "cover_final_kdp_print_spread.pdf"
        New-KdpPrintCoverSpread `
            -FrontCoverPath $FinalFrontPath `
            -OutputPath $FinalPrintSpreadPath `
            -PdfOutputPath $FinalPrintSpreadPdfPath `
            -Spec $PrintCoverSpec `
            -Title $Title `
            -Subtitle $Subtitle `
            -Author $Author `
            -SpineText $SpineText

        $finalOutputs += [ordered]@{
            role = "kdp_print_full_cover_spread"
            file = Split-Path -Leaf $FinalPrintSpreadPath
            path = $FinalPrintSpreadPath
            source = Split-Path -Leaf $FinalFrontPath
            cover_width_in = $PrintCoverSpec.cover_width_in
            cover_height_in = $PrintCoverSpec.cover_height_in
            cover_width_mm = $PrintCoverSpec.cover_width_mm
            cover_height_mm = $PrintCoverSpec.cover_height_mm
            pixel_width = $PrintCoverSpec.pixel_width
            pixel_height = $PrintCoverSpec.pixel_height
            dpi = $PrintCoverSpec.dpi
        }
        $finalOutputs += [ordered]@{
            role = "kdp_print_full_cover_pdf"
            file = Split-Path -Leaf $FinalPrintSpreadPdfPath
            path = $FinalPrintSpreadPdfPath
            source = Split-Path -Leaf $FinalPrintSpreadPath
            cover_width_in = $PrintCoverSpec.cover_width_in
            cover_height_in = $PrintCoverSpec.cover_height_in
            cover_width_mm = $PrintCoverSpec.cover_width_mm
            cover_height_mm = $PrintCoverSpec.cover_height_mm
        }
    }

    $altIndex = 1
    foreach ($layout in ($LayoutOutputs | Select-Object -Skip 1)) {
        $AltName = "cover_alt_front_v{0}.png" -f $altIndex
        $AltPath = Join-Path $FinalRoot $AltName
        Copy-Artifact -SourcePath (Get-StringValue -Value $layout.path) -DestinationPath $AltPath
        $finalOutputs += [ordered]@{
            role = "alternate_front_cover"
            file = Split-Path -Leaf $AltPath
            path = $AltPath
            source = Get-StringValue -Value $layout.file
        }
        $altIndex++
    }
}
else {
    $Ranked = @($Review.ranked_candidates)
    if ($Ranked.Count -lt 1) {
        throw "No ranked candidates found for draft fallback export."
    }
    $PrimaryDraft = $Ranked[0]
    $FinalFrontPath = Join-Path $FinalRoot "cover_final_front.png"
    Copy-Artifact -SourcePath (Get-StringValue -Value $PrimaryDraft.path) -DestinationPath $FinalFrontPath
    $finalOutputs += [ordered]@{
        role = "front_cover_from_draft"
        file = Split-Path -Leaf $FinalFrontPath
        path = $FinalFrontPath
        source = Get-StringValue -Value $PrimaryDraft.file
    }
}

if ((-not $SkipMockup) -and (Test-Path -LiteralPath $MockupManifestPath)) {
    $MockupManifest = Read-JsonUtf8 -Path $MockupManifestPath
    $MockupOutputs = @($MockupManifest.outputs)
    if ($MockupOutputs.Count -gt 0) {
        $PrimaryMockup = $MockupOutputs[0]
        $FinalMockupPath = Join-Path $FinalRoot "cover_final_mockup.jpg"
        Copy-Artifact -SourcePath (Get-StringValue -Value $PrimaryMockup.path) -DestinationPath $FinalMockupPath
        $finalOutputs += [ordered]@{
            role = "mockup"
            file = Split-Path -Leaf $FinalMockupPath
            path = $FinalMockupPath
            source = Get-StringValue -Value $PrimaryMockup.file
        }
    }
}

$SummaryLines = @()
$SummaryLines += "# Cover Export Report"
$SummaryLines += ""
$SummaryLines += "## Book"
$SummaryLines += ""
$SummaryLines += "- BookName: $BookName"
$SummaryLines += "- Title: $Title"
$SummaryLines += "- Subtitle: $Subtitle"
$SummaryLines += "- Author: $Author"
$SummaryLines += ""
$SummaryLines += "## Strategy"
$SummaryLines += ""
$SummaryLines += "- Primary route id: $PrimaryRouteId"
$SummaryLines += "- Primary route label: $PrimaryRouteLabel"
$SummaryLines += "- Selected review files: $($SelectedFiles -join ', ')"
$SummaryLines += ""
if ($null -ne $PrintCoverSpec) {
    $SummaryLines += "## KDP Print Cover Size"
    $SummaryLines += ""
    $SummaryLines += "- Trim size: $($PrintCoverSpec.trim_width_in) x $($PrintCoverSpec.trim_height_in) in"
    $SummaryLines += "- Page count: $($PrintCoverSpec.page_count)"
    $SummaryLines += "- Bleed: $($PrintCoverSpec.bleed_in) in / $($PrintCoverSpec.bleed_mm) mm per outer edge"
    $SummaryLines += "- Spine: $($PrintCoverSpec.spine_width_in) in / $($PrintCoverSpec.spine_width_mm) mm"
    $SummaryLines += "- Full cover: $($PrintCoverSpec.cover_width_in) x $($PrintCoverSpec.cover_height_in) in"
    $SummaryLines += "- Full cover: $($PrintCoverSpec.cover_width_mm) x $($PrintCoverSpec.cover_height_mm) mm"
    $SummaryLines += "- Raster export: $($PrintCoverSpec.pixel_width) x $($PrintCoverSpec.pixel_height) px at $($PrintCoverSpec.dpi) DPI"
    $SummaryLines += "- Formula: $($PrintCoverSpec.formula)"
    $SummaryLines += ""
}
$SummaryLines += "## Output Files"
$SummaryLines += ""
foreach ($item in $finalOutputs) {
    $SummaryLines += "- $($item.role): $($item.file)"
}
$SummaryLines += ""
$SummaryLines += "## Notes"
$SummaryLines += ""
$SummaryLines += "- This export consolidates the current best front-cover candidate."
$SummaryLines += "- Alternate layout outputs are copied when available."
$SummaryLines += "- Mockup export is included unless mockup generation was skipped or unavailable."
if ($null -ne $PrintCoverSpec) {
    $SummaryLines += "- Print edition export uses the KDP full-cover formula with left/right bleed only in the total width and top/bottom bleed in the total height."
    $SummaryLines += "- The generated PDF is a single-page full-cover file at the exact KDP page size; review back-cover and spine content before upload."
}

Write-TextUtf8 -Content ($SummaryLines -join "`r`n") -Path $ReportPath

$Manifest = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    skip_layout = [bool]$SkipLayout
    skip_mockup = [bool]$SkipMockup
    source = [ordered]@{
        brief_file = Split-Path -Leaf $BriefJsonPath
        strategy_file = Split-Path -Leaf $StrategyJsonPath
        review_file = Split-Path -Leaf $ReviewJsonPath
        layout_manifest = if (Test-Path -LiteralPath $LayoutManifestPath) { Split-Path -Leaf $LayoutManifestPath } else { $null }
        mockup_manifest = if (Test-Path -LiteralPath $MockupManifestPath) { Split-Path -Leaf $MockupManifestPath } else { $null }
    }
    kdp_print_cover_spec = $PrintCoverSpec
    outputs = @($finalOutputs)
    report_file = Split-Path -Leaf $ReportPath
}

Write-JsonUtf8 -Data $Manifest -Path $ExportManifestPath
Set-Content -LiteralPath $LogPath -Value ("[{0}] 08z-export completed." -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host ""
Write-Host "08z-export completed successfully."
Write-Host ("Manifest: " + $ExportManifestPath)
Write-Host ("Report: " + $ReportPath)
