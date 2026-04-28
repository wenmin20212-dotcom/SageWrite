param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "print",

    [double]$PrintTrimWidthIn = 6.0,
    [double]$PrintTrimHeightIn = 9.0,
    [double]$PrintBleedIn = 0.125,
    [double]$PrintSpineWidthIn = 0.595,
    [int]$PrintPageCount = 264,
    [int]$PrintDpi = 300,

    [switch]$Force
)

. "$PSScriptRoot\08n-common.ps1"

function Draw-ImageCoverFill {
    param(
        [Parameter(Mandatory = $true)][System.Drawing.Graphics]$Graphics,
        [Parameter(Mandatory = $true)][System.Drawing.Image]$Image,
        [Parameter(Mandatory = $true)][System.Drawing.RectangleF]$Destination
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

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$BriefJsonPath = Join-Path $Roots.base "base_brief.json"
$LayoutManifestPath = Join-Path $Roots.layout "title_layout_manifest.json"
$SpreadManifestPath = Join-Path $Roots.print_spread "print_spread_manifest.json"
$LogPath = Join-Path $Roots.logs "08n-print-spread.log"

Assert-FileExists -Path $BriefJsonPath -Description "base_brief.json"
Assert-FileExists -Path $LayoutManifestPath -Description "title_layout_manifest.json"

if ((Test-Path -LiteralPath $SpreadManifestPath) -and (-not $Force)) {
    Write-Host "print_spread_manifest.json already exists. Use -Force to regenerate."
    exit 0
}
if ($Force) { Clear-DirectoryFiles -Path $Roots.print_spread }

$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$LayoutManifest = Read-JsonUtf8 -Path $LayoutManifestPath
$Layout = @($LayoutManifest.outputs)[0]
if ($null -eq $Layout) { throw "No title layout output found." }

$Spec = Get-KdpCoverSpec -TrimWidthIn $PrintTrimWidthIn -TrimHeightIn $PrintTrimHeightIn -BleedIn $PrintBleedIn -SpineWidthIn $PrintSpineWidthIn -PageCount $PrintPageCount -Dpi $PrintDpi

Add-Type -AssemblyName System.Drawing
$front = [System.Drawing.Image]::FromFile((Get-StringValue $Layout.path))
$bitmap = New-Object System.Drawing.Bitmap([int]$Spec.pixel_width, [int]$Spec.pixel_height)
$bitmap.SetResolution($Spec.dpi, $Spec.dpi)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

$bleedPx = $Spec.bleed_in * $Spec.dpi
$trimWidthPx = $Spec.trim_width_in * $Spec.dpi
$trimHeightPx = $Spec.trim_height_in * $Spec.dpi
$spineWidthPx = $Spec.spine_width_in * $Spec.dpi
$backX = $bleedPx
$frontX = $bleedPx + $trimWidthPx + $spineWidthPx

$bgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#F6F1E8"))
$spineBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#263943"))
$textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#273840"))
$whiteBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#F9FBFA"))
$guidePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(110, 160, 70, 70), 1)
$foldPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(150, 60, 80, 95), 2)
$titleFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size 46 -Style ([System.Drawing.FontStyle]::Bold)
$bodyFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size 25 -Style ([System.Drawing.FontStyle]::Regular)
$spineFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size 26 -Style ([System.Drawing.FontStyle]::Bold)

try {
    $graphics.FillRectangle($bgBrush, 0, 0, $bitmap.Width, $bitmap.Height)
    $graphics.FillRectangle($spineBrush, [float]($backX + $trimWidthPx), 0, [float]$spineWidthPx, $bitmap.Height)
    $frontRect = New-Object System.Drawing.RectangleF([float]$frontX, 0, [float]($trimWidthPx + $bleedPx), [float]$bitmap.Height)
    Draw-ImageCoverFill -Graphics $graphics -Image $front -Destination $frontRect

    $backRect = New-Object System.Drawing.RectangleF([float]($backX + 105), [float]($bleedPx + 260), [float]($trimWidthPx - 210), [float]($trimHeightPx - 520))
    $backText = Get-StringValue $Brief.book_context.core_thesis
    if ([string]::IsNullOrWhiteSpace($backText)) { $backText = "Back cover copy placeholder. Replace with final sales copy before KDP upload." }
    $graphics.DrawString($backText, $bodyFont, $textBrush, $backRect)
    $graphics.DrawString((Get-StringValue $Brief.cover_text.title), $titleFont, $textBrush, [float]($backX + 105), [float]($bleedPx + 130))

    $state = $graphics.Save()
    $graphics.TranslateTransform([float]($backX + $trimWidthPx + ($spineWidthPx / 2) + 14), [float]($bleedPx + $trimHeightPx - 120))
    $graphics.RotateTransform(-90)
    $graphics.DrawString((Get-StringValue $Brief.cover_text.title), $spineFont, $whiteBrush, 0, 0)
    $graphics.Restore($state)

    $graphics.DrawRectangle($guidePen, 0, 0, ($bitmap.Width - 1), ($bitmap.Height - 1))
    $graphics.DrawRectangle($guidePen, [int][Math]::Round($bleedPx), [int][Math]::Round($bleedPx), [int][Math]::Round($bitmap.Width - ($bleedPx * 2)), [int][Math]::Round($trimHeightPx))
    $graphics.DrawLine($foldPen, [float]($backX + $trimWidthPx), 0, [float]($backX + $trimWidthPx), $bitmap.Height)
    $graphics.DrawLine($foldPen, [float]$frontX, 0, [float]$frontX, $bitmap.Height)

    $PngPath = Join-Path $Roots.print_spread "kdp_print_spread.png"
    $PdfPath = Join-Path $Roots.print_spread "kdp_print_spread.pdf"
    $bitmap.Save($PngPath, [System.Drawing.Imaging.ImageFormat]::Png)
    Save-BitmapAsSinglePagePdf -Bitmap $bitmap -OutputPath $PdfPath -PageWidthIn $Spec.cover_width_in -PageHeightIn $Spec.cover_height_in
}
finally {
    $spineFont.Dispose()
    $bodyFont.Dispose()
    $titleFont.Dispose()
    $foldPen.Dispose()
    $guidePen.Dispose()
    $whiteBrush.Dispose()
    $textBrush.Dispose()
    $spineBrush.Dispose()
    $bgBrush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
    $front.Dispose()
}

$Manifest = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    edition = $Edition
    kdp_spec = $Spec
    outputs = @(
        [ordered]@{ role = "kdp_print_spread_png"; file = Split-Path -Leaf $PngPath; path = $PngPath },
        [ordered]@{ role = "kdp_print_spread_pdf"; file = Split-Path -Leaf $PdfPath; path = $PdfPath }
    )
}

Write-JsonUtf8 -Data $Manifest -Path $SpreadManifestPath
Write-TextUtf8 -Content ("[{0}] 08n-print-spread completed: {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $SpreadManifestPath) -Path $LogPath

Write-Host ""
Write-Host "08n-print-spread completed successfully."
Write-Host "Manifest: $SpreadManifestPath"
