param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [switch]$Force
)

. "$PSScriptRoot\08n-common.ps1"

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$BriefJsonPath = Join-Path $Roots.base "base_brief.json"
$PromptJsonPath = Join-Path $Roots.prompts "base_prompts.json"
$ReviewPath = Join-Path $Roots.reviews "base_review.json"
$LayoutManifestPath = Join-Path $Roots.layout "title_layout_manifest.json"
$MockupManifestPath = Join-Path $Roots.mockup "mockup_manifest.json"
$SpreadManifestPath = Join-Path $Roots.print_spread "print_spread_manifest.json"
$ExportManifestPath = Join-Path $Roots.final "next_cover_export_manifest.json"
$ReportPath = Join-Path $Roots.final "next_cover_report.md"
$LogPath = Join-Path $Roots.logs "08n-export.log"

Assert-FileExists -Path $BriefJsonPath -Description "base_brief.json"
Assert-FileExists -Path $LayoutManifestPath -Description "title_layout_manifest.json"

if ((Test-Path -LiteralPath $ExportManifestPath) -and (-not $Force)) {
    Write-Host "next_cover_export_manifest.json already exists. Use -Force to regenerate."
    exit 0
}
if ($Force) { Clear-DirectoryFiles -Path $Roots.final }

$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$LayoutManifest = Read-JsonUtf8 -Path $LayoutManifestPath
$MockupManifest = if (Test-Path -LiteralPath $MockupManifestPath) { Read-JsonUtf8 -Path $MockupManifestPath } else { $null }
$SpreadManifest = if (Test-Path -LiteralPath $SpreadManifestPath) { Read-JsonUtf8 -Path $SpreadManifestPath } else { $null }

$Outputs = @()
$PrimaryLayout = @($LayoutManifest.outputs)[0]
if ($PrimaryLayout) {
    $frontPath = Join-Path $Roots.final "next_cover_final_front.png"
    Copy-Item -LiteralPath (Get-StringValue $PrimaryLayout.path) -Destination $frontPath -Force
    $Outputs += [ordered]@{ role = "front_cover"; file = Split-Path -Leaf $frontPath; path = $frontPath; source = Get-StringValue $PrimaryLayout.file }
}

if ($MockupManifest) {
    $mockup = @($MockupManifest.outputs)[0]
    if ($mockup) {
        $mockupPath = Join-Path $Roots.final "next_cover_final_mockup.jpg"
        Copy-Item -LiteralPath (Get-StringValue $mockup.path) -Destination $mockupPath -Force
        $Outputs += [ordered]@{ role = "mockup"; file = Split-Path -Leaf $mockupPath; path = $mockupPath; source = Get-StringValue $mockup.file }
    }
}

if ($SpreadManifest) {
    foreach ($item in @($SpreadManifest.outputs)) {
        $source = Get-StringValue $item.path
        if (Test-Path -LiteralPath $source) {
            $dest = Join-Path $Roots.final ("next_" + (Split-Path -Leaf $source))
            Copy-Item -LiteralPath $source -Destination $dest -Force
            $Outputs += [ordered]@{ role = Get-StringValue $item.role; file = Split-Path -Leaf $dest; path = $dest; source = Split-Path -Leaf $source }
        }
    }
}

$ReportLines = @(
    "# 08N Next Cover Export Report",
    "",
    "## Book",
    "",
    "- BookName: $BookName",
    "- Edition: $Edition",
    "- Title: $($Brief.cover_text.title)",
    "- Subtitle: $($Brief.cover_text.subtitle)",
    "- Author: $($Brief.cover_text.author)",
    "",
    "## Flow Contract",
    "",
    "- Base image stage is image-only: no embedded text.",
    "- Typography is added only in local title layout stage.",
    "- Print spread is generated separately from the selected title layout.",
    "",
    "## Output Files",
    ""
)
foreach ($item in $Outputs) { $ReportLines += "- $($item.role): $($item.file)" }
if ($SpreadManifest) {
    $ReportLines += ""
    $ReportLines += "## KDP Print Size"
    $ReportLines += ""
    $ReportLines += "- Full cover: $($SpreadManifest.kdp_spec.cover_width_in) x $($SpreadManifest.kdp_spec.cover_height_in) in"
    $ReportLines += "- Full cover: $($SpreadManifest.kdp_spec.cover_width_mm) x $($SpreadManifest.kdp_spec.cover_height_mm) mm"
    $ReportLines += "- Spine: $($SpreadManifest.kdp_spec.spine_width_in) in / $($SpreadManifest.kdp_spec.spine_width_mm) mm"
}

$Manifest = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    edition = $Edition
    source = [ordered]@{
        brief = if (Test-Path -LiteralPath $BriefJsonPath) { $BriefJsonPath } else { $null }
        prompts = if (Test-Path -LiteralPath $PromptJsonPath) { $PromptJsonPath } else { $null }
        review = if (Test-Path -LiteralPath $ReviewPath) { $ReviewPath } else { $null }
        layout = if (Test-Path -LiteralPath $LayoutManifestPath) { $LayoutManifestPath } else { $null }
        mockup = if (Test-Path -LiteralPath $MockupManifestPath) { $MockupManifestPath } else { $null }
        print_spread = if (Test-Path -LiteralPath $SpreadManifestPath) { $SpreadManifestPath } else { $null }
    }
    outputs = @($Outputs)
    report_file = $ReportPath
}

Write-JsonUtf8 -Data $Manifest -Path $ExportManifestPath
Write-TextUtf8 -Content ($ReportLines -join "`r`n") -Path $ReportPath
Write-TextUtf8 -Content ("[{0}] 08n-export completed: {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $ExportManifestPath) -Path $LogPath

Write-Host ""
Write-Host "08n-export completed successfully."
Write-Host "Manifest: $ExportManifestPath"
Write-Host "Report: $ReportPath"
