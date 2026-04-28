param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)

. "$PSScriptRoot\08n-common.ps1"

function Draw-NextMockup {
    param(
        [Parameter(Mandatory = $true)][string]$CoverPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][int]$VariantIndex
    )
    Add-Type -AssemblyName System.Drawing
    $canvas = New-Object System.Drawing.Bitmap(1800, 1350)
    $graphics = [System.Drawing.Graphics]::FromImage($canvas)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $bg = New-Object System.Drawing.Drawing2D.LinearGradientBrush((New-Object System.Drawing.Rectangle(0, 0, 1800, 1350)), [System.Drawing.ColorTranslator]::FromHtml("#F7F3EA"), [System.Drawing.ColorTranslator]::FromHtml("#DDE9EA"), [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
    $shadow = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45, 0, 0, 0))
    $page = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(245, 248, 248, 244))
    $spine = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(230, 215, 220, 224))
    $stroke = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(52, 30, 40, 50), 2)
    $cover = [System.Drawing.Image]::FromFile($CoverPath)
    try {
        $graphics.FillRectangle($bg, 0, 0, 1800, 1350)
        $graphics.FillEllipse($shadow, 465, 920, 880, 130)
        $scaledWidth = 700
        $scaledHeight = [int][Math]::Round(($cover.Height / [double]$cover.Width) * $scaledWidth)
        $bookX = 550
        $bookY = 185
        $graphics.FillRectangle($page, ($bookX + 20), ($bookY + 18), $scaledWidth, $scaledHeight)
        $graphics.FillRectangle($spine, ($bookX - 30), ($bookY + 28), 48, $scaledHeight)
        $graphics.DrawRectangle($stroke, ($bookX - 30), ($bookY + 28), 48, $scaledHeight)
        $graphics.DrawImage($cover, $bookX, $bookY, $scaledWidth, $scaledHeight)
        $graphics.DrawRectangle($stroke, $bookX, $bookY, $scaledWidth, $scaledHeight)
        $canvas.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Jpeg)
    }
    finally {
        $cover.Dispose()
        $stroke.Dispose()
        $spine.Dispose()
        $page.Dispose()
        $shadow.Dispose()
        $bg.Dispose()
        $graphics.Dispose()
        $canvas.Dispose()
    }
}

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$LayoutManifestPath = Join-Path $Roots.layout "title_layout_manifest.json"
$MockupManifestPath = Join-Path $Roots.mockup "mockup_manifest.json"
$LogPath = Join-Path $Roots.logs "08n-mockup.log"

Assert-FileExists -Path $LayoutManifestPath -Description "title_layout_manifest.json"

if ((Test-Path -LiteralPath $MockupManifestPath) -and (-not $Force)) {
    Write-Host "mockup_manifest.json already exists. Use -Force to regenerate."
    exit 0
}
if ($Force) { Clear-DirectoryFiles -Path $Roots.mockup }

$LayoutManifest = Read-JsonUtf8 -Path $LayoutManifestPath
$Outputs = @($LayoutManifest.outputs)
$maxMockups = switch ($Mode) {
    "fast" { 1 }
    "full" { [Math]::Min($Outputs.Count, 3) }
    default { [Math]::Min($Outputs.Count, 2) }
}

$Mockups = @()
for ($i = 0; $i -lt $maxMockups; $i++) {
    $item = $Outputs[$i]
    $mockupName = "next_mockup_{0:D2}.jpg" -f ($i + 1)
    $mockupPath = Join-Path $Roots.mockup $mockupName
    Draw-NextMockup -CoverPath (Get-StringValue $item.path) -OutputPath $mockupPath -VariantIndex ($i + 1)
    $Mockups += [ordered]@{
        index = $i + 1
        file = $mockupName
        path = $mockupPath
        source_layout = Get-StringValue $item.file
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
}

$Manifest = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    edition = $Edition
    outputs = @($Mockups)
}

Write-JsonUtf8 -Data $Manifest -Path $MockupManifestPath
Write-TextUtf8 -Content ("[{0}] 08n-mockup completed: {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $MockupManifestPath) -Path $LogPath

Write-Host ""
Write-Host "08n-mockup completed successfully."
Write-Host "Manifest: $MockupManifestPath"
