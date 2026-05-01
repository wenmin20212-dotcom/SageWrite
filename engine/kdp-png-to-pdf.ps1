param(
    [string]$BookName,

    [string]$InputFile,

    [string]$InputPath,

    [string]$OutputFile,

    [string]$OutputPath,

    [switch]$Force
)

$ErrorActionPreference = "Stop"
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

. "$PSScriptRoot\08n-common.ps1"

function Get-KdpPngToPdfRoots {
    param([Parameter(Mandatory = $true)][string]$BookName)
    $enginePath = $PSScriptRoot
    $sageRoot = Split-Path -Parent $enginePath
    $clawRoot = Split-Path -Parent $sageRoot
    $workspaceRoot = Join-Path $clawRoot "workspace-$BookName"
    $bookRoot = Join-Path $workspaceRoot "sagewrite\book"
    $acceptanceRoot = Join-Path $bookRoot "07_cover\kdp_acceptance"
    $workRoot = Join-Path $acceptanceRoot "fix_workbench"
    return [ordered]@{
        acceptance = $acceptanceRoot
        work = $workRoot
        composites = Join-Path $workRoot "composites"
        pdfs = Join-Path $workRoot "pdfs"
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

function Get-SafeFileName {
    param(
        [Parameter(Mandatory = $true)][string]$FileName,
        [Parameter(Mandatory = $true)][string]$Extension,
        [string]$DefaultStem = "kdp-output"
    )
    $name = [System.IO.Path]::GetFileName($FileName)
    $stem = [System.IO.Path]::GetFileNameWithoutExtension($name)
    $stem = ($stem -replace '[^\w.-]+', '-').Trim('-')
    if ([string]::IsNullOrWhiteSpace($stem)) { $stem = $DefaultStem }
    if ($stem.Length -gt 90) { $stem = $stem.Substring(0, 90).TrimEnd('-', '.') }
    return "$stem$Extension"
}

$Magick = Resolve-MagickPath
$Roots = $null
$State = $null
if (-not [string]::IsNullOrWhiteSpace($BookName)) {
    $Roots = Get-KdpPngToPdfRoots -BookName $BookName
    foreach ($key in @("acceptance", "work", "composites", "pdfs")) { Ensure-Directory -Path $Roots[$key] }
    if (Test-Path -LiteralPath $Roots.state) {
        try { $State = Read-JsonUtf8 -Path $Roots.state } catch { $State = $null }
    }
}

if ([string]::IsNullOrWhiteSpace($InputPath)) {
    if ([string]::IsNullOrWhiteSpace($BookName)) { throw "Either InputPath or BookName is required." }
    if ([string]::IsNullOrWhiteSpace($InputFile) -and $State -and $State.latestCompositeFileName) {
        $InputFile = "$($State.latestCompositeFileName)"
    }
    if ([string]::IsNullOrWhiteSpace($InputFile)) { throw "InputFile is required. Generate the composite PNG first." }
    $InputPath = Join-Path $Roots.composites (Get-SafeFileName -FileName $InputFile -Extension ".png" -DefaultStem "kdp-composite")
}

Assert-FileExists -Path $InputPath -Description "Input PNG"
if ([System.IO.Path]::GetExtension($InputPath).ToLowerInvariant() -ne ".png") {
    throw "Input file must be PNG: $InputPath"
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    if (-not $Roots) { throw "OutputPath is required when BookName mode is not used." }
    if ([string]::IsNullOrWhiteSpace($OutputFile)) {
        $OutputFile = Get-SafeFileName -FileName $InputPath -Extension ".pdf" -DefaultStem "kdp-composite"
    } else {
        $OutputFile = Get-SafeFileName -FileName $OutputFile -Extension ".pdf" -DefaultStem "kdp-composite"
    }
    $OutputPath = Join-Path $Roots.pdfs $OutputFile
}

Ensure-Directory -Path (Split-Path -Parent $OutputPath)
if ((Test-Path -LiteralPath $OutputPath) -and (-not $Force)) { throw "Output already exists: $OutputPath" }

$InputInfo = Get-ImageInfo -Magick $Magick -Path $InputPath
& $Magick $InputPath -units PixelsPerInch -density 300 -compress Zip $OutputPath
if ($LASTEXITCODE -ne 0) { throw "ImageMagick PNG to PDF conversion failed." }

$EndedAt = Get-Date
$Result = [ordered]@{
    generatedAt = $EndedAt.ToString("yyyy-MM-dd HH:mm:ss")
    program = "kdp-png-to-pdf.ps1"
    imagemagick = $Magick
    bookName = $BookName
    inputFileName = [System.IO.Path]::GetFileName($InputPath)
    inputPath = [System.IO.Path]::GetFullPath($InputPath)
    outputFileName = [System.IO.Path]::GetFileName($OutputPath)
    outputPath = [System.IO.Path]::GetFullPath($OutputPath)
    mode = "file-to-file"
    input = $InputInfo
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
    $stateHash["latestPdf"] = $Result
    $stateHash["latestPdfFileName"] = $Result.outputFileName
    Write-JsonUtf8 -Data $stateHash -Path $Roots.state -Depth 50
}

$Result | ConvertTo-Json -Depth 50
