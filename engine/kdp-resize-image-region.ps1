param(
    [string]$BookName,

    [string]$InputFile,

    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [double]$ScalePercent,

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\08n-common.ps1"

function Get-KdpResizeRoots {
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
        acceptance = $acceptanceRoot
        work = $workRoot
        crops = Join-Path $workRoot "crops"
        state = Join-Path $workRoot "workbench_state.json"
    }
}

function Resolve-MagickPath {
    $command = Get-Command magick -ErrorAction SilentlyContinue
    if ($command) { return $command.Source }
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    foreach ($root in $roots) {
        $matches = Get-ChildItem -LiteralPath $root -Directory -Filter "ImageMagick*" -ErrorAction SilentlyContinue |
            ForEach-Object { Join-Path $_.FullName "magick.exe" } |
            Where-Object { Test-Path -LiteralPath $_ } |
            Sort-Object -Descending
        if ($matches) { return @($matches)[0] }
    }
    throw "ImageMagick command 'magick' was not found. Install ImageMagick or add magick.exe to PATH."
}

function Get-ImageInfo {
    param(
        [Parameter(Mandatory = $true)][string]$Magick,
        [Parameter(Mandatory = $true)][string]$Path
    )
    $text = & $Magick identify -format "%w|%h|%x|%y|%U" $Path
    if ($LASTEXITCODE -ne 0) { throw "ImageMagick identify failed: $Path" }
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
        [string]$DefaultName = "kdp-resize.png"
    )
    $name = [System.IO.Path]::GetFileName($FileName)
    if ([string]::IsNullOrWhiteSpace($name)) { $name = $DefaultName }
    $ext = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
    if ($ext -notin @(".png", ".jpg", ".jpeg", ".webp")) { throw "Unsupported image type: $ext" }
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $stem = ($stem -replace '[^\w.-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($stem)) { $stem = [System.IO.Path]::GetFileNameWithoutExtension($DefaultName) }
    if ($stem.Length -gt 90) { $stem = $stem.Substring(0, 90).TrimEnd('-', '.') }
    return "$stem$ext"
}

if ($ScalePercent -le 1 -or $ScalePercent -gt 400) {
    throw "ScalePercent must be > 1 and <= 400. Example: 95 or 105."
}

$Magick = Resolve-MagickPath
$Roots = $null
$State = $null
if (-not [string]::IsNullOrWhiteSpace($BookName)) {
    $Roots = Get-KdpResizeRoots -BookName $BookName
    foreach ($key in @("acceptance", "work", "crops")) { Ensure-Directory -Path $Roots[$key] }
    if (Test-Path -LiteralPath $Roots.state) {
        try { $State = Read-JsonUtf8 -Path $Roots.state } catch { $State = $null }
    }
}

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    if ([string]::IsNullOrWhiteSpace($BookName)) { throw "Either InputPath or BookName is required." }
    if ([string]::IsNullOrWhiteSpace($InputFile) -and $State -and $State.latestCropFileName) {
        $InputFile = "$($State.latestCropFileName)"
    }
    if ([string]::IsNullOrWhiteSpace($InputFile)) { throw "InputFile is required. Generate the cropped image first." }
    $InputPath = Join-Path $Roots.crops (Get-SafeImageFileName -FileName $InputFile -DefaultName "kdp-crop.png")
}
Assert-FileExists -Path $InputPath -Description "Input image"

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    if (-not $Roots) { throw "OutputPath is required when BookName mode is not used." }
    $stamp = (Get-Date).ToString("yyyyMMddHHmmss")
    $scaleTag = [int][Math]::Round($ScalePercent)
    if ([string]::IsNullOrWhiteSpace($OutputFile)) {
        $OutputFile = "kdp-resize-$stamp-p$scaleTag.png"
    }
    $OutputPath = Join-Path $Roots.crops (Get-SafeImageFileName -FileName $OutputFile -DefaultName "kdp-resize-$stamp.png")
}

Ensure-Directory -Path (Split-Path -Parent $OutputPath)
if ((Test-Path -LiteralPath $OutputPath) -and (-not $Force)) { throw "Output already exists: $OutputPath" }

$InputInfo = Get-ImageInfo -Magick $Magick -Path $InputPath
& $Magick $InputPath -resize "$ScalePercent%" -units PixelsPerInch -density 300 $OutputPath
if ($LASTEXITCODE -ne 0) { throw "ImageMagick resize failed." }
$OutputInfo = Get-ImageInfo -Magick $Magick -Path $OutputPath

$EndedAt = Get-Date
$Result = [ordered]@{
    generatedAt = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
    program = "kdp-resize-image-region.ps1"
    imagemagick = $Magick
    bookName = $BookName
    inputFileName = [System.IO.Path]::GetFileName($InputPath)
    inputPath = [System.IO.Path]::GetFullPath($InputPath)
    outputFileName = [System.IO.Path]::GetFileName($OutputPath)
    outputPath = [System.IO.Path]::GetFullPath($OutputPath)
    scalePercent = $ScalePercent
    input = $InputInfo
    output = $OutputInfo
}

if ($Roots) {
    $existing = if (Test-Path -LiteralPath $Roots.state) {
        try { Read-JsonUtf8 -Path $Roots.state } catch { [pscustomobject]@{} }
    } else {
        [pscustomobject]@{}
    }
    $stateHash = [ordered]@{}
    foreach ($property in $existing.PSObject.Properties) { $stateHash[$property.Name] = $property.Value }
    $stateHash["updatedAt"] = $Result.generatedAt
    $stateHash["latestResize"] = $Result
    $stateHash["latestCrop"] = [ordered]@{
        generatedAt = $Result.generatedAt
        program = $Result.program
        outputFileName = $Result.outputFileName
        outputPath = $Result.outputPath
        crop = if ($existing.latestCrop -and $existing.latestCrop.crop) { $existing.latestCrop.crop } else { $null }
        resizedFrom = $Result.inputFileName
        scalePercent = $ScalePercent
        output = $Result.output
    }
    $stateHash["latestCropFileName"] = $Result.outputFileName
    Write-JsonUtf8 -Data $stateHash -Path $Roots.state -Depth 50
}

$Result | ConvertTo-Json -Depth 50
