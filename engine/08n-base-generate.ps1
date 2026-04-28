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

. "$PSScriptRoot\08n-common.ps1"

function New-BasePlaceholderImage {
    param(
        [Parameter(Mandatory = $true)][string]$OutputPath,
        [Parameter(Mandatory = $true)][string]$RouteId,
        [Parameter(Mandatory = $true)][int]$VariantIndex
    )

    Add-Type -AssemblyName System.Drawing
    $width = 1800
    $height = 2700
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    $bgTop = switch ($RouteId) {
        "human-ai-workflow-atrium" { "#ECFAF7" }
        "civilization-map-field" { "#E9EEF7" }
        default { "#F7F1E6" }
    }
    $bgBottom = switch ($RouteId) {
        "human-ai-workflow-atrium" { "#123941" }
        "civilization-map-field" { "#182B4A" }
        default { "#173B35" }
    }

    $rect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $bgBrush = New-Object System.Drawing.Drawing2D.LinearGradientBrush($rect, [System.Drawing.ColorTranslator]::FromHtml($bgTop), [System.Drawing.ColorTranslator]::FromHtml($bgBottom), [System.Drawing.Drawing2D.LinearGradientMode]::ForwardDiagonal)
    $graphics.FillRectangle($bgBrush, $rect)

    $lightBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(86, 255, 255, 238))
    $softBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(42, 84, 196, 180))
    $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(58, 255, 255, 255), 5)
    $thinPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(40, 20, 40, 55), 2)

    $graphics.FillEllipse($lightBrush, 980, 180, 620, 620)
    $graphics.FillEllipse($softBrush, 1040, 920, 760, 980)
    $graphics.FillRectangle((New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(205, 250, 247, 238))), 120, 190, 760, 1120)

    for ($i = 0; $i -lt 12; $i++) {
        $x = 160 + ($i * 116)
        $graphics.DrawLine($thinPen, $x, 1180, ($x + 340), 2300)
    }
    for ($i = 0; $i -lt 9; $i++) {
        $y = 1180 + ($i * 110)
        $graphics.DrawLine($linePen, 120, $y, 1680, ($y + 80))
    }

    $accent = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(92, 238, 213, 156))
    $graphics.FillRectangle($accent, 118, 1460, 480, 18)
    $graphics.FillRectangle($accent, 118, 1510, 250, 10)

    $bitmap.Save($OutputPath, [System.Drawing.Imaging.ImageFormat]::Png)

    $accent.Dispose()
    $thinPen.Dispose()
    $linePen.Dispose()
    $softBrush.Dispose()
    $lightBrush.Dispose()
    $bgBrush.Dispose()
    $graphics.Dispose()
    $bitmap.Dispose()
}

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$PromptJsonPath = Join-Path $Roots.prompts "base_prompts.json"
$ManifestPath = Join-Path $Roots.imports "base_generation_manifest.json"
$LogPath = Join-Path $Roots.logs "08n-base-generate.log"

Assert-FileExists -Path $PromptJsonPath -Description "base_prompts.json"

if ((Test-Path -LiteralPath $ManifestPath) -and (-not $Force)) {
    Write-Host "base_generation_manifest.json already exists. Use -Force to regenerate."
    exit 0
}

if ($Force) { Clear-DirectoryFiles -Path $Roots.imports }

$PromptPackage = Read-JsonUtf8 -Path $PromptJsonPath
$Prompts = @($PromptPackage.prompts)
if ($Prompts.Count -lt 1) { throw "No prompts found in base_prompts.json." }

$RequestedCount = switch ($Mode) {
    "fast" { [Math]::Min($Variants, 2) }
    "full" { [Math]::Max($Variants, 6) }
    default { $Variants }
}
if ($RequestedCount -lt 1) { $RequestedCount = 1 }

$Outputs = @()
for ($i = 1; $i -le $RequestedCount; $i++) {
    $prompt = $Prompts[($i - 1) % $Prompts.Count]
    $fileName = "base_candidate_{0:D2}.png" -f $i
    $outputPath = Join-Path $Roots.imports $fileName
    New-BasePlaceholderImage -OutputPath $outputPath -RouteId (Get-StringValue $prompt.route_id) -VariantIndex $i
    $Outputs += [ordered]@{
        index = $i
        file = $fileName
        path = $outputPath
        route_id = Get-StringValue $prompt.route_id
        route_label = Get-StringValue $prompt.route_label
        generator = "local-placeholder-image-only"
        no_text_contract = $true
        source_prompt = Get-StringValue $prompt.midjourney_prompt
        generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        image_size = "1800x2700"
    }
}

$Manifest = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    edition = $Edition
    mode = $Mode
    note = "Local placeholders preserve the new no-text base-image contract. Replace or add Midjourney/Imagen outputs in this imports folder before review."
    outputs = @($Outputs)
}

Write-JsonUtf8 -Data $Manifest -Path $ManifestPath
Write-TextUtf8 -Content ("[{0}] 08n-base-generate completed: {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $ManifestPath) -Path $LogPath

Write-Host ""
Write-Host "08n-base-generate completed successfully."
Write-Host "Manifest: $ManifestPath"
Write-Host "Imports: $($Roots.imports)"
