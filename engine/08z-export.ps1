param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [switch]$SkipLayout,
    [switch]$SkipMockup,
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

$EnginePath         = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot           = Split-Path -Parent $EnginePath
$ClawRoot           = Split-Path -Parent $SageRoot
$WorkspaceRoot      = Join-Path $ClawRoot "workspace-$BookName"
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
$PrimaryRouteLabel = Get-StringValue -Value $Strategy.primary_strategy.route_label
$PrimaryRouteId = Get-StringValue -Value $Strategy.primary_strategy.route_id
$SelectedFiles = Get-StringArray -Value $Review.selected_files

$finalOutputs = @()

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
    outputs = @($finalOutputs)
    report_file = Split-Path -Leaf $ReportPath
}

Write-JsonUtf8 -Data $Manifest -Path $ExportManifestPath
Set-Content -LiteralPath $LogPath -Value ("[{0}] 08z-export completed." -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")) -Encoding UTF8

Write-Host ""
Write-Host "08z-export completed successfully."
Write-Host ("Manifest: " + $ExportManifestPath)
Write-Host ("Report: " + $ReportPath)
