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

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$ReviewPath = Join-Path $Roots.reviews "base_review.json"
$ReviewMdPath = Join-Path $Roots.reviews "base_review.md"
$ManifestPath = Join-Path $Roots.imports "base_generation_manifest.json"
$LogPath = Join-Path $Roots.logs "08n-base-review.log"

if ((Test-Path -LiteralPath $ReviewPath) -and (-not $Force)) {
    Write-Host "base_review.json already exists. Use -Force to regenerate."
    exit 0
}

$Manifest = if (Test-Path -LiteralPath $ManifestPath) { Read-JsonUtf8 -Path $ManifestPath } else { $null }
$ManifestMap = @{}
if ($Manifest) {
    foreach ($item in @($Manifest.outputs)) {
        $ManifestMap[(Get-StringValue $item.file)] = $item
    }
}

$ImageFiles = @(Get-ChildItem -LiteralPath $Roots.imports -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Extension -match '^\.(png|jpg|jpeg|webp)$'
} | Sort-Object Name)

if ($ImageFiles.Count -lt 1) {
    throw "No base image files found in imports: $($Roots.imports)"
}

Add-Type -AssemblyName System.Drawing
$Candidates = @()
$rank = 1
foreach ($file in $ImageFiles) {
    $bitmap = [System.Drawing.Bitmap]::new($file.FullName)
    try {
        $aspect = [Math]::Round(($bitmap.Width / [double]$bitmap.Height), 4)
        $preferredAspect = 2 / 3
        $aspectScore = [Math]::Max(0, 100 - ([Math]::Abs($aspect - $preferredAspect) * 260))
        $sizeScore = if ($bitmap.Width -ge 1200 -and $bitmap.Height -ge 1800) { 100 } else { 78 }
        $overall = [Math]::Round(($aspectScore * 0.55) + ($sizeScore * 0.45), 2)
    }
    finally {
        $bitmap.Dispose()
    }

    $manifestItem = if ($ManifestMap.ContainsKey($file.Name)) { $ManifestMap[$file.Name] } else { $null }
    $Candidates += [ordered]@{
        rank = $rank
        file = $file.Name
        path = $file.FullName
        route_id = Get-StringValue $manifestItem.route_id
        route_label = Get-StringValue $manifestItem.route_label
        scores = [ordered]@{
            overall = $overall
            aspect = [Math]::Round($aspectScore, 2)
            resolution = $sizeScore
        }
        verdict = if ($overall -ge 88) { "select" } elseif ($overall -ge 74) { "reserve" } else { "reject" }
        review_note = "Automated review checks size and front-cover aspect only. Human review should verify the image contains no text."
    }
    $rank++
}

$Ranked = @($Candidates | Sort-Object { -[double]$_.scores.overall })
$Selected = @($Ranked | Where-Object { $_.verdict -eq "select" } | Select-Object -First 2)
if ($Selected.Count -lt 1) {
    $Selected = @($Ranked | Select-Object -First 1)
}

$Review = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    edition = $Edition
    selected_files = @($Selected | ForEach-Object { $_.file })
    ranked_candidates = @($Ranked)
    human_review_reminder = "Reject any candidate that contains letters, numbers, logos, watermarks, UI text, or pseudo-typography before moving to title layout."
}

$MarkdownLines = @("# 08N Base Image Review", "", "Selected files:")
foreach ($item in $Selected) { $MarkdownLines += "- $($item.file)" }
$MarkdownLines += ""
$MarkdownLines += "## Ranked Candidates"
foreach ($item in $Ranked) {
    $MarkdownLines += "- $($item.file): $($item.scores.overall) / $($item.verdict)"
}

Write-JsonUtf8 -Data $Review -Path $ReviewPath
Write-TextUtf8 -Content ($MarkdownLines -join "`r`n") -Path $ReviewMdPath
Write-TextUtf8 -Content ("[{0}] 08n-base-review completed: {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $ReviewPath) -Path $LogPath

Write-Host ""
Write-Host "08n-base-review completed successfully."
Write-Host "Review: $ReviewPath"
