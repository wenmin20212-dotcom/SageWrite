param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateRange(1, 20)]
    [int]$Variants = 4,

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force,
    [switch]$SkipLayout,
    [switch]$SkipMockup
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

# =========================
# Helpers
# =========================

function Write-Stage {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    Write-Host ""
    Write-Host ("==== " + $Message + " ====")
}

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-DirectoryContents {
    param(
        [Parameter(Mandatory = $true)]
        [string]$SourcePath,
        [Parameter(Mandatory = $true)]
        [string]$DestinationPath
    )

    if (-not (Test-Path -LiteralPath $SourcePath)) {
        return
    }

    Ensure-Directory -Path $DestinationPath
    Get-ChildItem -LiteralPath $SourcePath -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $target = Join-Path $DestinationPath $_.Name
        if ($_.PSIsContainer) {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Recurse -Force
        }
        else {
            Copy-Item -LiteralPath $_.FullName -Destination $target -Force
        }
    }
}

function Sync-LegacyEbookOutputs {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LegacyRoot,
        [Parameter(Mandatory = $true)]
        [string]$EditionRoot
    )

    $legacyBrief = Join-Path $LegacyRoot "brief\cover_brief.json"
    $editionBrief = Join-Path $EditionRoot "brief\cover_brief.json"

    if ((-not (Test-Path -LiteralPath $editionBrief)) -and (Test-Path -LiteralPath $legacyBrief)) {
        Copy-DirectoryContents -SourcePath (Join-Path $LegacyRoot "brief") -DestinationPath (Join-Path $EditionRoot "brief")
        Copy-DirectoryContents -SourcePath (Join-Path $LegacyRoot "drafts") -DestinationPath (Join-Path $EditionRoot "drafts")
        Copy-DirectoryContents -SourcePath (Join-Path $LegacyRoot "reviews") -DestinationPath (Join-Path $EditionRoot "reviews")
        Copy-DirectoryContents -SourcePath (Join-Path $LegacyRoot "layout") -DestinationPath (Join-Path $EditionRoot "layout")
        Copy-DirectoryContents -SourcePath (Join-Path $LegacyRoot "mockup") -DestinationPath (Join-Path $EditionRoot "mockup")
        Copy-DirectoryContents -SourcePath (Join-Path $LegacyRoot "final") -DestinationPath (Join-Path $EditionRoot "final")
        Write-LogLine "Legacy ebook cover outputs copied into 07_cover\\ebook."
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

function Get-NowStamp {
    return (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
}

function Save-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $json = $Data | ConvertTo-Json -Depth 20
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
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

function Write-LogLine {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )
    $line = "[{0}] {1}" -f (Get-NowStamp), $Message
    Add-Content -LiteralPath $script:LogPath -Value $line -Encoding UTF8
    Write-Host $line
}

function Read-ObjectiveValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ObjectivePath,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )
    $pattern = '^\s*' + [Regex]::Escape($Key) + '\s*:\s*(.+?)\s*$'
    foreach ($line in Get-Content -LiteralPath $ObjectivePath -Encoding UTF8) {
        if ($line -match $pattern) {
            $value = $Matches[1].Trim()
            $value = $value.Trim('"').Trim("'")
            return $value
        }
    }
    return $null
}

function Invoke-CoverModule {
    param(
        [Parameter(Mandatory = $true)]
        [string]$ScriptPath,
        [Parameter(Mandatory = $true)]
        [string]$ModuleName,
        [Parameter(Mandatory = $true)]
        [hashtable]$Arguments
    )

    Assert-FileExists -Path $ScriptPath -Description "$ModuleName script"

    $argPreview = ($Arguments.GetEnumerator() | Sort-Object Name | ForEach-Object {
        if ($_.Value -is [switch] -or $_.Value -is [System.Management.Automation.SwitchParameter]) {
            if ($_.Value.IsPresent) { "-$($_.Name)" } else { $null }
        }
        elseif ($_.Value -is [bool]) {
            if ($_.Value) { "-$($_.Name)" } else { $null }
        }
        elseif ($null -ne $_.Value -and "$($_.Value)" -ne "") {
            "-$($_.Name) `"$($_.Value)`""
        }
    } | Where-Object { $_ }) -join " "

    Write-LogLine "Running $ModuleName -> $argPreview"

    $invokeSplat = @{}
    foreach ($key in $Arguments.Keys) {
        $value = $Arguments[$key]
        if ($value -is [switch] -or $value -is [System.Management.Automation.SwitchParameter]) {
            if ($value.IsPresent) {
                $invokeSplat[$key] = $true
            }
        }
        elseif ($value -is [bool]) {
            if ($value) {
                $invokeSplat[$key] = $true
            }
        }
        elseif ($null -ne $value -and "$value" -ne "") {
            $invokeSplat[$key] = "$value"
        }
    }

    # Use PowerShell named-parameter splatting so child scripts receive
    # the intended bindings even when values contain spaces or punctuation.
    & $ScriptPath @invokeSplat

    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) {
        throw "$ModuleName failed with exit code $LASTEXITCODE"
    }

    Write-LogLine "$ModuleName completed."
}

function Get-LatestFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Folder,
        [string[]]$Extensions
    )
    if (-not (Test-Path -LiteralPath $Folder)) {
        return @()
    }

    $normalized = @($Extensions | ForEach-Object { $_.ToLowerInvariant() })
    return Get-ChildItem -LiteralPath $Folder -File | Where-Object {
        $ext = $_.Extension.TrimStart(".").ToLowerInvariant()
        $normalized -contains $ext
    } | Sort-Object LastWriteTime -Descending
}

function Build-RunSummary {
    param(
        [Parameter(Mandatory = $true)]
        [string]$FinalRoot,
        [Parameter(Mandatory = $true)]
        [string]$LayoutRoot,
        [Parameter(Mandatory = $true)]
        [string]$MockupRoot,
        [Parameter(Mandatory = $true)]
        [string]$FrontmatterRoot,
        [Parameter(Mandatory = $true)]
        [string]$ReviewPath
    )

    $summary = [ordered]@{
        generated_at = Get-NowStamp
        book_name    = $BookName
        edition      = $Edition
        mode         = $Mode
        variants     = $Variants
        outputs      = [ordered]@{
            frontmatter = @()
            final  = @()
            layout = @()
            mockup = @()
        }
        review_file  = $null
    }

    if (Test-Path -LiteralPath $FrontmatterRoot) {
        $summary.outputs.frontmatter = @(Get-ChildItem -LiteralPath $FrontmatterRoot -File | Sort-Object Name | ForEach-Object {
            $_.Name
        })
    }

    if (Test-Path -LiteralPath $FinalRoot) {
        $summary.outputs.final = @(Get-ChildItem -LiteralPath $FinalRoot -File | Sort-Object Name | ForEach-Object {
            $_.Name
        })
    }

    if (Test-Path -LiteralPath $LayoutRoot) {
        $summary.outputs.layout = @(Get-ChildItem -LiteralPath $LayoutRoot -File | Sort-Object Name | ForEach-Object {
            $_.Name
        })
    }

    if (Test-Path -LiteralPath $MockupRoot) {
        $summary.outputs.mockup = @(Get-ChildItem -LiteralPath $MockupRoot -File | Sort-Object Name | ForEach-Object {
            $_.Name
        })
    }

    if (Test-Path -LiteralPath $ReviewPath) {
        $summary.review_file = Split-Path -Leaf $ReviewPath
    }

    return $summary
}

# =========================
# Resolve Paths
# =========================

$EnginePath     = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot       = Split-Path -Parent $EnginePath
$ClawRoot       = Split-Path -Parent $SageRoot

$WorkspaceRoot  = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot       = Join-Path $WorkspaceRoot "sagewrite\book"

$BriefRoot      = Join-Path $BookRoot "00_brief"
$OutlineRoot    = Join-Path $BookRoot "01_outline"
$CoverBaseRoot  = Join-Path $BookRoot "07_cover"
$LegacyCoverRoot = $CoverBaseRoot
$CoverRoot      = Join-Path $CoverBaseRoot $Edition
$CoverBriefRoot = Join-Path $CoverRoot "brief"
$DraftRoot      = Join-Path $CoverRoot "drafts"
$ReviewRoot     = Join-Path $CoverRoot "reviews"
$LayoutRoot     = Join-Path $CoverRoot "layout"
$MockupRoot     = Join-Path $CoverRoot "mockup"
$FinalRoot      = Join-Path $CoverRoot "final"
$FrontmatterBaseRoot = Join-Path $BookRoot "00_frontmatter"
$FrontmatterRoot = Join-Path $FrontmatterBaseRoot $Edition
$LogRoot        = Join-Path $BookRoot "logs"

$ObjectivePath  = Join-Path $BriefRoot "objective.md"
$TocPath        = Join-Path $OutlineRoot "toc.md"

$BriefJsonPath    = Join-Path $CoverBriefRoot "cover_brief.json"
$StrategyJsonPath = Join-Path $CoverBriefRoot "cover_strategy.json"
$CopyJsonPath     = Join-Path $CoverBriefRoot "cover_copy.json"
$ReviewJsonPath   = Join-Path $ReviewRoot "cover_review.json"
$SummaryJsonPath  = Join-Path $FinalRoot "cover_run_summary.json"
$script:LogPath   = Join-Path $LogRoot "08-cover.log"

$Module08a = Join-Path $EnginePath "08a-brief.ps1"
$Module08b = Join-Path $EnginePath "08b-strategy.ps1"
$Module08c = Join-Path $EnginePath "08c-generate.ps1"
$Module08d = Join-Path $EnginePath "08d-review.ps1"
$Module08e = Join-Path $EnginePath "08e-layout.ps1"
$Module08f = Join-Path $EnginePath "08f-mockup.ps1"
$Module08g = Join-Path $EnginePath "08g-copy.ps1"
$Module08h = Join-Path $EnginePath "08h-frontmatter.ps1"
$Module08z = Join-Path $EnginePath "08z-export.ps1"

# =========================
# Init
# =========================

Ensure-Directory -Path $LogRoot
Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $FrontmatterBaseRoot
Ensure-Directory -Path $FrontmatterRoot
Ensure-Directory -Path $CoverBriefRoot
Ensure-Directory -Path $DraftRoot
Ensure-Directory -Path $ReviewRoot
Ensure-Directory -Path $LayoutRoot
Ensure-Directory -Path $MockupRoot
Ensure-Directory -Path $FinalRoot

if (($Edition -eq "ebook") -and (-not $Force)) {
    Sync-LegacyEbookOutputs -LegacyRoot $LegacyCoverRoot -EditionRoot $CoverRoot
}

if (-not (Test-Path -LiteralPath $WorkspaceRoot)) {
    throw "Workspace not found: $WorkspaceRoot"
}
if (-not (Test-Path -LiteralPath $BookRoot)) {
    throw "Book root not found: $BookRoot"
}

Assert-FileExists -Path $ObjectivePath -Description "objective.md"
Assert-FileExists -Path $TocPath -Description "toc.md"

if ($Force) {
    Write-Stage "Force cleanup"
    Write-LogLine "Force mode enabled. Clearing previous cover outputs."

    Get-ChildItem -LiteralPath $CoverBriefRoot -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $DraftRoot      -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $ReviewRoot     -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $LayoutRoot     -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $MockupRoot     -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath $FinalRoot      -File -ErrorAction SilentlyContinue | Remove-Item -Force -ErrorAction SilentlyContinue
}

Write-Stage "Resolve metadata"

$DerivedTitle    = Read-ObjectiveValue -ObjectivePath $ObjectivePath -Key "title"
$DerivedAudience = Read-ObjectiveValue -ObjectivePath $ObjectivePath -Key "audience"
$DerivedType     = Read-ObjectiveValue -ObjectivePath $ObjectivePath -Key "type"
$DerivedStyle    = Read-ObjectiveValue -ObjectivePath $ObjectivePath -Key "style"

if ([string]::IsNullOrWhiteSpace($Title)) {
    $Title = $DerivedTitle
}

if ([string]::IsNullOrWhiteSpace($Title)) {
    throw "Title is missing. Provide -Title or ensure objective.md contains title."
}

Write-LogLine "BookName = $BookName"
Write-LogLine "Edition  = $Edition"
Write-LogLine "Title    = $Title"
if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
    Write-LogLine "Subtitle = $Subtitle"
}
if (-not [string]::IsNullOrWhiteSpace($Author)) {
    Write-LogLine "Author   = $Author"
}
if (-not [string]::IsNullOrWhiteSpace($DerivedType)) {
    Write-LogLine "Type     = $DerivedType"
}
if (-not [string]::IsNullOrWhiteSpace($DerivedAudience)) {
    Write-LogLine "Audience = $DerivedAudience"
}
if (-not [string]::IsNullOrWhiteSpace($DerivedStyle)) {
    Write-LogLine "Style    = $DerivedStyle"
}
Write-LogLine "Mode     = $Mode"
Write-LogLine "Variants = $Variants"

# =========================
# Run Modules
# =========================

try {
    Write-Stage "08a brief"
    Invoke-CoverModule -ScriptPath $Module08a -ModuleName "08a-brief" -Arguments @{
        BookName = $BookName
        Edition  = $Edition
        Title    = $Title
        Subtitle = $Subtitle
        Author   = $Author
        Force    = $Force
    }
    Assert-FileExists -Path $BriefJsonPath -Description "cover_brief.json"

    Write-Stage "08b strategy"
    Invoke-CoverModule -ScriptPath $Module08b -ModuleName "08b-strategy" -Arguments @{
        BookName = $BookName
        Edition  = $Edition
        Mode     = $Mode
        Force    = $Force
    }
    Assert-FileExists -Path $StrategyJsonPath -Description "cover_strategy.json"

    Write-Stage "08g copy"
    Invoke-CoverModule -ScriptPath $Module08g -ModuleName "08g-copy" -Arguments @{
        BookName = $BookName
        Edition  = $Edition
        Mode     = $Mode
        Force    = $Force
    }
    Assert-FileExists -Path $CopyJsonPath -Description "cover_copy.json"

    Write-Stage "08c generate"
    Invoke-CoverModule -ScriptPath $Module08c -ModuleName "08c-generate" -Arguments @{
        BookName = $BookName
        Edition  = $Edition
        Variants = $Variants
        Mode     = $Mode
        Force    = $Force
    }

    $generatedDrafts = Get-LatestFiles -Folder $DraftRoot -Extensions @("png", "jpg", "jpeg", "webp")
    if ($generatedDrafts.Count -lt 1) {
        throw "08c-generate completed, but no draft images were found in: $DraftRoot"
    }
    Write-LogLine ("Draft images found: " + $generatedDrafts.Count)

    Write-Stage "08d review"
    Invoke-CoverModule -ScriptPath $Module08d -ModuleName "08d-review" -Arguments @{
        BookName = $BookName
        Edition  = $Edition
        Mode     = $Mode
        Force    = $Force
    }
    Assert-FileExists -Path $ReviewJsonPath -Description "cover_review.json"

    if (-not $SkipLayout) {
        Write-Stage "08e layout"
        Invoke-CoverModule -ScriptPath $Module08e -ModuleName "08e-layout" -Arguments @{
            BookName = $BookName
            Edition  = $Edition
            Title    = $Title
            Subtitle = $Subtitle
            Author   = $Author
            Mode     = $Mode
            Force    = $Force
        }

        $layoutFiles = Get-LatestFiles -Folder $LayoutRoot -Extensions @("png", "jpg", "jpeg", "pdf")
        if ($layoutFiles.Count -lt 1) {
            throw "08e-layout completed, but no layout files were found in: $LayoutRoot"
        }
        Write-LogLine ("Layout files found: " + $layoutFiles.Count)
    }
    else {
        Write-LogLine "SkipLayout enabled. 08e-layout skipped."
    }

    if ((-not $SkipMockup) -and (-not $SkipLayout)) {
        Write-Stage "08f mockup"
        Invoke-CoverModule -ScriptPath $Module08f -ModuleName "08f-mockup" -Arguments @{
            BookName = $BookName
            Edition  = $Edition
            Mode     = $Mode
            Force    = $Force
        }

        $mockupFiles = Get-LatestFiles -Folder $MockupRoot -Extensions @("png", "jpg", "jpeg", "webp")
        if ($mockupFiles.Count -lt 1) {
            throw "08f-mockup completed, but no mockup files were found in: $MockupRoot"
        }
        Write-LogLine ("Mockup files found: " + $mockupFiles.Count)
    }
    elseif ($SkipMockup) {
        Write-LogLine "SkipMockup enabled. 08f-mockup skipped."
    }
    else {
        Write-LogLine "08f-mockup skipped because layout phase was skipped."
    }

    Write-Stage "08z export"
    Invoke-CoverModule -ScriptPath $Module08z -ModuleName "08z-export" -Arguments @{
        BookName   = $BookName
        Edition    = $Edition
        SkipLayout = $SkipLayout
        SkipMockup = $SkipMockup
        Force      = $Force
    }

    Write-Stage "08h frontmatter"
    Invoke-CoverModule -ScriptPath $Module08h -ModuleName "08h-frontmatter" -Arguments @{
        BookName = $BookName
        Edition  = $Edition
        Title    = $Title
        Subtitle = $Subtitle
        Author   = $Author
        Force    = $Force
    }

    $runSummary = Build-RunSummary -FinalRoot $FinalRoot -LayoutRoot $LayoutRoot -MockupRoot $MockupRoot -FrontmatterRoot $FrontmatterRoot -ReviewPath $ReviewJsonPath
    Save-JsonUtf8 -Data $runSummary -Path $SummaryJsonPath

    Write-Stage "Completed"
    Write-LogLine "08-cover completed successfully."
    Write-LogLine "Summary file: $SummaryJsonPath"

    if (Test-Path -LiteralPath $FinalRoot) {
        $finalFiles = Get-ChildItem -LiteralPath $FinalRoot -File | Sort-Object Name
        if ($finalFiles.Count -gt 0) {
            Write-Host ""
            Write-Host "Final outputs:"
            foreach ($file in $finalFiles) {
                Write-Host (" - " + $file.Name)
            }
        }
        else {
            Write-Host ""
            Write-Host "No files were found under final/. Check module outputs."
        }
    }

    if (Test-Path -LiteralPath $FrontmatterRoot) {
        $frontmatterFiles = Get-ChildItem -LiteralPath $FrontmatterRoot -File | Sort-Object Name
        if ($frontmatterFiles.Count -gt 0) {
            Write-Host ""
            Write-Host "Frontmatter outputs:"
            foreach ($file in $frontmatterFiles) {
                Write-Host (" - " + $file.Name)
            }
        }
    }
}
catch {
    Write-LogLine ("ERROR: " + $_.Exception.Message)
    throw
}
