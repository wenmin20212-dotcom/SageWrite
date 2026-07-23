param(
    [string]$BookName,

    [string]$SourceFile,

    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [int]$Y,

    [Parameter(Mandatory = $true)]
    [int]$Width,

    [Parameter(Mandatory = $true)]
    [int]$Height,

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\08n-common.ps1"

function Get-KdpCropRoots {
    param([Parameter(Mandatory = $true)][string]$BookName)

    $enginePath = $PSScriptRoot
    $sageRoot = Split-Path -Parent $enginePath
    $clawRoot = Split-Path -Parent $sageRoot
    $workspaceParentRoot = if (-not [string]::IsNullOrWhiteSpace($env:SAGEWRITE_WORKSPACE_ROOT)) { [System.IO.Path]::GetFullPath($env:SAGEWRITE_WORKSPACE_ROOT) } else { $clawRoot }
    $workspaceRoot = Join-Path $workspaceParentRoot "workspace-$BookName"
    $bookRoot = Join-Path $workspaceRoot "sagewrite\book"
    $acceptanceRoot = Join-Path $bookRoot "07_cover\kdp_acceptance"
    $workRoot = Join-Path $acceptanceRoot "fix_workbench"
    return [ordered]@{
        engine = $enginePath
        workspace = $workspaceRoot
        book = $bookRoot
        acceptance = $acceptanceRoot
        work = $workRoot
        source = Join-Path $workRoot "source"
        crops = Join-Path $workRoot "crops"
        reports = Join-Path $workRoot "reports"
        state = Join-Path $workRoot "workbench_state.json"
    }
}

function Get-ImageInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Magick,
        [Parameter(Mandatory = $true)][string]$Path
    )

    $format = "%w|%h|%x|%y|%U"
    $text = & $Magick identify -format $format $Path
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick identify failed: $Path"
    }
    $parts = "$text".Split("|")
    return [ordered]@{
        path = $Path
        width = [int]$parts[0]
        height = [int]$parts[1]
        densityX = "$($parts[2])"
        densityY = "$($parts[3])"
        units = "$($parts[4])"
    }
}

function Get-SafeImageFileName {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [string]$DefaultName = "kdp-crop.png"
    )

    $name = [System.IO.Path]::GetFileName($FileName)
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $DefaultName
    }
    $ext = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
    if ($ext -notin @(".png", ".jpg", ".jpeg", ".webp")) {
        throw "Unsupported image type: $ext"
    }
    return $name
}

function Resolve-MagickPath {
    $command = Get-Command magick -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }

    $roots = @(
        $env:ProgramFiles,
        ${env:ProgramFiles(x86)}
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($root in $roots) {
        $matches = Get-ChildItem -LiteralPath $root -Directory -Filter "ImageMagick*" -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "magick.exe" } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Sort-Object -Descending
        if ($matches) {
            return @($matches)[0]
        }
    }

    throw "ImageMagick command 'magick' was not found. Install ImageMagick or add magick.exe to PATH."
}

if ($X -lt 0 -or $Y -lt 0 -or $Width -le 0 -or $Height -le 0) {
    throw "Invalid crop rectangle. X/Y must be >= 0 and Width/Height must be > 0."
}

$Magick = Resolve-MagickPath

$Roots = $null
$State = $null
if (-not [string]::IsNullOrWhiteSpace($BookName)) {
    $Roots = Get-KdpCropRoots -BookName $BookName
    foreach ($key in @("acceptance", "work", "source", "crops", "reports")) {
        Ensure-Directory -Path $Roots[$key]
    }
    if (Test-Path -LiteralPath $Roots.state) {
        try { $State = Read-JsonUtf8 -Path $Roots.state } catch { $State = $null }
    }
}

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    if ([string]::IsNullOrWhiteSpace($BookName)) {
        throw "Either -InputPath or -BookName is required."
    }
    if ([string]::IsNullOrWhiteSpace($SourceFile) -and $State -and $State.sourceFileName) {
        $SourceFile = "$($State.sourceFileName)"
    }
    if ([string]::IsNullOrWhiteSpace($SourceFile)) {
        throw "SourceFile is required when InputPath is not supplied."
    }
    $safeSourceName = Get-SafeImageFileName -FileName $SourceFile -DefaultName "kdp-fix-source.png"
    $InputPath = Join-Path $Roots.source $safeSourceName
}

Assert-FileExists -Path $InputPath -Description "Source image"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    if (-not $Roots) {
        throw "OutputPath is required when BookName mode is not used."
    }
    $stamp = (Get-Date).ToString("yyyyMMddHHmmss")
    if ([string]::IsNullOrWhiteSpace($OutputFile)) {
        $sourceStem = [System.IO.Path]::GetFileNameWithoutExtension($InputPath)
        $OutputFile = "$sourceStem-crop-$stamp-x$X-y$Y-${Width}x$Height.png"
    }
    $safeOutputName = Get-SafeImageFileName -FileName $OutputFile -DefaultName "kdp-crop-$stamp.png"
    $OutputPath = Join-Path $Roots.crops $safeOutputName
}

$OutputDirectory = Split-Path -Parent $OutputPath
Ensure-Directory -Path $OutputDirectory
if ((Test-Path -LiteralPath $OutputPath) -and (-not $Force)) {
    throw "Output already exists: $OutputPath"
}

$SourceInfo = Get-ImageInfo -Magick $Magick -Path $InputPath
if (($X + $Width) -gt $SourceInfo.width -or ($Y + $Height) -gt $SourceInfo.height) {
    throw "Crop rectangle is outside source image. Source: $($SourceInfo.width) x $($SourceInfo.height), rect: x=$X y=$Y width=$Width height=$Height."
}

$geometry = "${Width}x${Height}+${X}+${Y}"
& $Magick $InputPath -crop $geometry +repage -units PixelsPerInch -density 300 $OutputPath
if ($LASTEXITCODE -ne 0) {
    throw "ImageMagick crop failed."
}

$OutputInfo = Get-ImageInfo -Magick $Magick -Path $OutputPath
$EndedAt = Get-Date
$Result = [ordered]@{
    generatedAt = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
    program = "kdp-crop-image-region.ps1"
    imagemagick = $Magick
    bookName = $BookName
    sourceFileName = [System.IO.Path]::GetFileName($InputPath)
    sourcePath = [System.IO.Path]::GetFullPath($InputPath)
    outputFileName = [System.IO.Path]::GetFileName($OutputPath)
    outputPath = [System.IO.Path]::GetFullPath($OutputPath)
    crop = [ordered]@{
        x = $X
        y = $Y
        width = $Width
        height = $Height
        geometry = $geometry
    }
    source = $SourceInfo
    output = $OutputInfo
}

if ($Roots) {
    $existing = if (Test-Path -LiteralPath $Roots.state) {
        try { Read-JsonUtf8 -Path $Roots.state } catch { [pscustomobject]@{} }
    } else {
        [pscustomobject]@{}
    }
    $stateHash = [ordered]@{}
    foreach ($property in $existing.PSObject.Properties) {
        $stateHash[$property.Name] = $property.Value
    }
    $stateHash["updatedAt"] = $Result.generatedAt
    $stateHash["latestCrop"] = $Result
    $stateHash["latestCropFileName"] = $Result.outputFileName
    Write-JsonUtf8 -Data $stateHash -Path $Roots.state -Depth 50
}

$Result | ConvertTo-Json -Depth 50
