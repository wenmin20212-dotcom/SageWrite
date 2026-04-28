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

. "$PSScriptRoot\08n-common.ps1"

function Draw-TitleLayout {
    param(
        [Parameter(Mandatory = $true)][string]$InputPath,
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$Title,
        [string]$Subtitle,
        [string]$Author
    )

    Add-Type -AssemblyName System.Drawing
    $bitmap = [System.Drawing.Bitmap]::new($InputPath)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::AntiAliasGridFit

    $w = $bitmap.Width
    $h = $bitmap.Height
    $panelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(224, 250, 247, 238))
    $titleBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#162A31"))
    $metaBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#3B5158"))
    $accentBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#0E7C68"))
    $titleFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size ([float]($w * 0.048)) -Style ([System.Drawing.FontStyle]::Bold)
    $subtitleFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size ([float]($w * 0.024)) -Style ([System.Drawing.FontStyle]::Regular)
    $authorFont = Get-SafeFont -Candidates @("Microsoft YaHei UI", "Microsoft YaHei", "Segoe UI", "Arial") -Size ([float]($w * 0.026)) -Style ([System.Drawing.FontStyle]::Regular)

    try {
        $panelX = [int]($w * 0.07)
        $panelY = [int]($h * 0.075)
        $panelW = [int]($w * 0.52)
        $panelH = [int]($h * 0.55)
        $graphics.FillRectangle($panelBrush, $panelX, $panelY, $panelW, $panelH)
        $graphics.FillRectangle($accentBrush, ($panelX + 58), ($panelY + 70), [int]($panelW * 0.28), 14)

        $y = $panelY + 135
        foreach ($line in (Split-TextLines -Text $Title -MaxChars 11)) {
            $graphics.DrawString($line, $titleFont, $titleBrush, ($panelX + 54), $y)
            $y += [int]($w * 0.072)
        }
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
            $subtitleRect = New-Object System.Drawing.RectangleF([float]($panelX + 58), [float]($y + 28), [float]($panelW - 116), [float]($h * 0.12))
            $graphics.DrawString($Subtitle, $subtitleFont, $metaBrush, $subtitleRect)
        }
        if (-not [string]::IsNullOrWhiteSpace($Author)) {
            $graphics.DrawString($Author, $authorFont, $titleBrush, [float]($panelX + 58), [float]($panelY + $panelH - 112))
        }
        $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally {
        $authorFont.Dispose()
        $subtitleFont.Dispose()
        $titleFont.Dispose()
        $accentBrush.Dispose()
        $metaBrush.Dispose()
        $titleBrush.Dispose()
        $panelBrush.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$BriefJsonPath = Join-Path $Roots.base "base_brief.json"
$ReviewPath = Join-Path $Roots.reviews "base_review.json"
$ManifestPath = Join-Path $Roots.layout "title_layout_manifest.json"
$LogPath = Join-Path $Roots.logs "08n-title-layout.log"

Assert-FileExists -Path $BriefJsonPath -Description "base_brief.json"
Assert-FileExists -Path $ReviewPath -Description "base_review.json"

if ((Test-Path -LiteralPath $ManifestPath) -and (-not $Force)) {
    Write-Host "title_layout_manifest.json already exists. Use -Force to regenerate."
    exit 0
}
if ($Force) { Clear-DirectoryFiles -Path $Roots.layout }

$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$Review = Read-JsonUtf8 -Path $ReviewPath
if ([string]::IsNullOrWhiteSpace($Title)) { $Title = Get-StringValue $Brief.cover_text.title }
if ([string]::IsNullOrWhiteSpace($Subtitle)) { $Subtitle = Get-StringValue $Brief.cover_text.subtitle }
if ([string]::IsNullOrWhiteSpace($Author)) { $Author = Get-StringValue $Brief.cover_text.author }
if ([string]::IsNullOrWhiteSpace($Title)) { throw "Title is missing for layout." }

$Selected = @($Review.selected_files)
if ($Mode -eq "fast") { $Selected = @($Selected | Select-Object -First 1) }

$Outputs = @()
$index = 1
foreach ($file in $Selected) {
    $candidate = Join-Path $Roots.imports $file
    Assert-FileExists -Path $candidate -Description "selected base image"
    $outName = "title_layout_{0:D2}.png" -f $index
    $outPath = Join-Path $Roots.layout $outName
    Draw-TitleLayout -InputPath $candidate -OutputPath $outPath -Title $Title -Subtitle $Subtitle -Author $Author
    $Outputs += [ordered]@{
        index = $index
        file = $outName
        path = $outPath
        source_base = $file
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    }
    $index++
}

$Manifest = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    edition = $Edition
    cover_text = [ordered]@{ title = $Title; subtitle = $Subtitle; author = $Author }
    outputs = @($Outputs)
}

Write-JsonUtf8 -Data $Manifest -Path $ManifestPath
Write-TextUtf8 -Content ("[{0}] 08n-title-layout completed: {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $ManifestPath) -Path $LogPath

Write-Host ""
Write-Host "08n-title-layout completed successfully."
Write-Host "Manifest: $ManifestPath"
