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

    [string]$FillColor = "#07121b",

    [ValidateSet("Auto", "Solid")]
    [string]$FillMode = "Auto",

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\08n-common.ps1"

function Get-KdpFillRoots {
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
        fills = Join-Path $workRoot "fills"
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
        [string]$DefaultName = "kdp-fill.png"
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
    throw "Invalid fill rectangle. X/Y must be >= 0 and Width/Height must be > 0."
}

if ([string]::IsNullOrWhiteSpace($FillColor)) {
    $FillColor = "#07121b"
}
$FillColor = $FillColor.Trim()
if ($FillColor -notmatch '^#[0-9a-fA-F]{6}([0-9a-fA-F]{2})?$') {
    throw "FillColor must be a hex color like #07121b."
}

$Magick = Resolve-MagickPath

$Roots = $null
$State = $null
if (-not [string]::IsNullOrWhiteSpace($BookName)) {
    $Roots = Get-KdpFillRoots -BookName $BookName
    foreach ($key in @("acceptance", "work", "source", "fills", "reports")) {
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
        $OutputFile = "$sourceStem-fill-$stamp-x$X-y$Y-${Width}x$Height.png"
    }
    $safeOutputName = Get-SafeImageFileName -FileName $OutputFile -DefaultName "kdp-fill-$stamp.png"
    $OutputPath = Join-Path $Roots.fills $safeOutputName
}

$OutputDirectory = Split-Path -Parent $OutputPath
Ensure-Directory -Path $OutputDirectory
if ((Test-Path -LiteralPath $OutputPath) -and (-not $Force)) {
    throw "Output already exists: $OutputPath"
}

$SourceInfo = Get-ImageInfo -Magick $Magick -Path $InputPath
if (($X + $Width) -gt $SourceInfo.width -or ($Y + $Height) -gt $SourceInfo.height) {
    throw "Fill rectangle is outside source image. Source: $($SourceInfo.width) x $($SourceInfo.height), rect: x=$X y=$Y width=$Width height=$Height."
}

function New-TempImagePath {
    param([Parameter(Mandatory = $true)][string]$Suffix)
    return Join-Path ([System.IO.Path]::GetTempPath()) "kdp-fill-$([guid]::NewGuid().ToString('N'))-$Suffix.png"
}

function Invoke-CropStrip {
    param(
        [Parameter(Mandatory = $true)][string]$Geometry,
        [Parameter(Mandatory = $true)][string]$Output
    )
    & $Magick $InputPath -crop $Geometry +repage $Output
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick strip crop failed: $Geometry"
    }
}

$x2 = $X + $Width - 1
$y2 = $Y + $Height - 1
$PatchPath = ""
$TempPaths = @()

if ($FillMode -eq "Auto") {
    $strip = [int][Math]::Min([Math]::Max(8, [Math]::Ceiling($Width / 4)), 96)
    $sideStrips = @()
    $leftWidth = [int][Math]::Min($strip, $X)
    if ($leftWidth -gt 0) {
        $leftPath = New-TempImagePath -Suffix "left"
        $TempPaths += $leftPath
        Invoke-CropStrip -Geometry "${leftWidth}x${Height}+$($X - $leftWidth)+${Y}" -Output $leftPath
        $sideStrips += $leftPath
    }
    $rightAvailable = [int]($SourceInfo.width - ($X + $Width))
    $rightWidth = [int][Math]::Min($strip, [Math]::Max(0, $rightAvailable))
    if ($rightWidth -gt 0) {
        $rightPath = New-TempImagePath -Suffix "right"
        $TempPaths += $rightPath
        Invoke-CropStrip -Geometry "${rightWidth}x${Height}+$($X + $Width)+${Y}" -Output $rightPath
        $sideStrips += $rightPath
    }

    $PatchPath = New-TempImagePath -Suffix "patch"
    $TempPaths += $PatchPath
    if ($sideStrips.Count -gt 0) {
        $args = @($sideStrips) + @("+append", "-resize", "${Width}x${Height}!", "-blur", "0x2", $PatchPath)
        & $Magick @args
        if ($LASTEXITCODE -ne 0) {
            throw "ImageMagick auto-fill side patch failed."
        }
    } else {
        $verticalStrips = @()
        $topHeight = [int][Math]::Min($strip, $Y)
        if ($topHeight -gt 0) {
            $topPath = New-TempImagePath -Suffix "top"
            $TempPaths += $topPath
            Invoke-CropStrip -Geometry "${Width}x${topHeight}+${X}+$($Y - $topHeight)" -Output $topPath
            $verticalStrips += $topPath
        }
        $bottomAvailable = [int]($SourceInfo.height - ($Y + $Height))
        $bottomHeight = [int][Math]::Min($strip, [Math]::Max(0, $bottomAvailable))
        if ($bottomHeight -gt 0) {
            $bottomPath = New-TempImagePath -Suffix "bottom"
            $TempPaths += $bottomPath
            Invoke-CropStrip -Geometry "${Width}x${bottomHeight}+${X}+$($Y + $Height)" -Output $bottomPath
            $verticalStrips += $bottomPath
        }
        if ($verticalStrips.Count -gt 0) {
            $args = @($verticalStrips) + @("-append", "-resize", "${Width}x${Height}!", "-blur", "0x2", $PatchPath)
            & $Magick @args
            if ($LASTEXITCODE -ne 0) {
                throw "ImageMagick auto-fill vertical patch failed."
            }
        } else {
            $PatchPath = ""
        }
    }
}

if ($PatchPath -and (Test-Path -LiteralPath $PatchPath)) {
    & $Magick $InputPath $PatchPath -geometry "+$X+$Y" -composite -units PixelsPerInch -density 300 $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick auto-fill composite failed."
    }
} else {
    & $Magick $InputPath -fill $FillColor -draw "rectangle $X,$Y $x2,$y2" -units PixelsPerInch -density 300 $OutputPath
    if ($LASTEXITCODE -ne 0) {
        throw "ImageMagick solid fill failed."
    }
}

Remove-Item -LiteralPath $TempPaths -Force -ErrorAction SilentlyContinue

$OutputInfo = Get-ImageInfo -Magick $Magick -Path $OutputPath
$EndedAt = Get-Date
$Result = [ordered]@{
    generatedAt = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
    program = "kdp-fill-image-region.ps1"
    imagemagick = $Magick
    bookName = $BookName
    sourceFileName = [System.IO.Path]::GetFileName($InputPath)
    sourcePath = [System.IO.Path]::GetFullPath($InputPath)
    outputFileName = [System.IO.Path]::GetFileName($OutputPath)
    outputPath = [System.IO.Path]::GetFullPath($OutputPath)
    fillMode = $FillMode
    fillColor = $FillColor
    fill = [ordered]@{
        x = $X
        y = $Y
        width = $Width
        height = $Height
        rectangle = "$X,$Y $x2,$y2"
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
    $stateHash["latestFill"] = $Result
    $stateHash["latestFillFileName"] = $Result.outputFileName
    Write-JsonUtf8 -Data $stateHash -Path $Roots.state -Depth 50
}

$Result | ConvertTo-Json -Depth 50
