param(
    [string]$BookName,

    [string]$BaseFile,

    [string]$OverlayFile,

    [string]$BasePath,

    [string]$OverlayPath,

    [Parameter(Mandatory = $true)]
    [int]$X,

    [Parameter(Mandatory = $true)]
    [int]$Y,

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\08n-common.ps1"

function Get-KdpCompositeRoots {
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
        crops = Join-Path $workRoot "crops"
        fills = Join-Path $workRoot "fills"
        composites = Join-Path $workRoot "composites"
        state = Join-Path $workRoot "workbench_state.json"
    }
}

function Resolve-MagickPath {
    $command = Get-Command magick -ErrorAction SilentlyContinue
    if ($command) {
        return $command.Source
    }
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
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
        [string]$DefaultName = "kdp-composite.png"
    )

    $name = [System.IO.Path]::GetFileName($FileName)
    if ([string]::IsNullOrWhiteSpace($name)) {
        $name = $DefaultName
    }
    $ext = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
    if ($ext -notin @(".png", ".jpg", ".jpeg", ".webp")) {
        throw "Unsupported image type: $ext"
    }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $stem = ($stem -replace '[^\w.-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($stem)) {
        $stem = [System.IO.Path]::GetFileNameWithoutExtension($DefaultName)
    }
    if ($stem.Length -gt 90) {
        $stem = $stem.Substring(0, 90).TrimEnd('-', '.')
    }
    return "$stem$ext"
}

if ($X -lt 0 -or $Y -lt 0) {
    throw "Composite X/Y must be >= 0."
}

$Magick = Resolve-MagickPath
$Roots = $null
$State = $null
if (-not [string]::IsNullOrWhiteSpace($BookName)) {
    $Roots = Get-KdpCompositeRoots -BookName $BookName
    foreach ($key in @("acceptance", "work", "crops", "fills", "composites")) {
        Ensure-Directory -Path $Roots[$key]
    }
    if (Test-Path -LiteralPath $Roots.state) {
        try { $State = Read-JsonUtf8 -Path $Roots.state } catch { $State = $null }
    }
}

if ([string]::IsNullOrWhiteSpace($BasePath)) {
    if ([string]::IsNullOrWhiteSpace($BookName)) {
        throw "Either BasePath or BookName is required."
    }
    if ([string]::IsNullOrWhiteSpace($BaseFile) -and $State -and $State.latestFillFileName) {
        $BaseFile = "$($State.latestFillFileName)"
    }
    if ([string]::IsNullOrWhiteSpace($BaseFile)) {
        throw "BaseFile is required. Generate the filled image in workarea 3 first."
    }
    $BasePath = Join-Path $Roots.fills (Get-SafeImageFileName -FileName $BaseFile -DefaultName "kdp-fill.png")
}

if ([string]::IsNullOrWhiteSpace($OverlayPath)) {
    if ([string]::IsNullOrWhiteSpace($BookName)) {
        throw "Either OverlayPath or BookName is required."
    }
    if ([string]::IsNullOrWhiteSpace($OverlayFile) -and $State -and $State.latestCropFileName) {
        $OverlayFile = "$($State.latestCropFileName)"
    }
    if ([string]::IsNullOrWhiteSpace($OverlayFile)) {
        throw "OverlayFile is required. Generate the cropped image in workarea 2 first."
    }
    $OverlayPath = Join-Path $Roots.crops (Get-SafeImageFileName -FileName $OverlayFile -DefaultName "kdp-crop.png")
}

Assert-FileExists -Path $BasePath -Description "Base image"
Assert-FileExists -Path $OverlayPath -Description "Overlay image"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    if (-not $Roots) {
        throw "OutputPath is required when BookName mode is not used."
    }
    $stamp = (Get-Date).ToString("yyyyMMddHHmmss")
    if ([string]::IsNullOrWhiteSpace($OutputFile)) {
        $OutputFile = "kdp-composite-$stamp-x$X-y$Y.png"
    }
    $OutputPath = Join-Path $Roots.composites (Get-SafeImageFileName -FileName $OutputFile -DefaultName "kdp-composite-$stamp.png")
}

Ensure-Directory -Path (Split-Path -Parent $OutputPath)
if ((Test-Path -LiteralPath $OutputPath) -and (-not $Force)) {
    throw "Output already exists: $OutputPath"
}

$BaseInfo = Get-ImageInfo -Magick $Magick -Path $BasePath
$OverlayInfo = Get-ImageInfo -Magick $Magick -Path $OverlayPath
if (($X + $OverlayInfo.width) -gt $BaseInfo.width -or ($Y + $OverlayInfo.height) -gt $BaseInfo.height) {
    throw "Overlay is outside base image. Base: $($BaseInfo.width) x $($BaseInfo.height), overlay: $($OverlayInfo.width) x $($OverlayInfo.height), position: x=$X y=$Y."
}

& $Magick $BasePath $OverlayPath -geometry "+$X+$Y" -composite -units PixelsPerInch -density 300 $OutputPath
if ($LASTEXITCODE -ne 0) {
    throw "ImageMagick composite failed."
}

$OutputInfo = Get-ImageInfo -Magick $Magick -Path $OutputPath
$EndedAt = Get-Date
$Result = [ordered]@{
    generatedAt = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
    program = "kdp-composite-image-region.ps1"
    imagemagick = $Magick
    bookName = $BookName
    baseFileName = [System.IO.Path]::GetFileName($BasePath)
    basePath = [System.IO.Path]::GetFullPath($BasePath)
    overlayFileName = [System.IO.Path]::GetFileName($OverlayPath)
    overlayPath = [System.IO.Path]::GetFullPath($OverlayPath)
    outputFileName = [System.IO.Path]::GetFileName($OutputPath)
    outputPath = [System.IO.Path]::GetFullPath($OutputPath)
    composite = [ordered]@{
        x = $X
        y = $Y
    }
    base = $BaseInfo
    overlay = $OverlayInfo
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
    $stateHash["latestComposite"] = $Result
    $stateHash["latestCompositeFileName"] = $Result.outputFileName
    Write-JsonUtf8 -Data $stateHash -Path $Roots.state -Depth 50
}

$Result | ConvertTo-Json -Depth 50
