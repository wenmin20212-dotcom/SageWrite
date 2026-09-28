param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [Parameter(Mandatory = $true)]
    [string]$SourcePath,

    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$CommonPath = Join-Path $PSScriptRoot "00-common.ps1"
. $CommonPath

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
$ResolvedSource = [System.IO.Path]::GetFullPath($SourcePath)
if (!(Test-Path -LiteralPath $ResolvedSource -PathType Leaf)) {
    throw "Cover source image not found: $ResolvedSource"
}

$AllowedExtensions = @('.png', '.jpg', '.jpeg', '.webp')
$Extension = [System.IO.Path]::GetExtension($ResolvedSource).ToLowerInvariant()
if ($Extension -notin $AllowedExtensions) {
    throw "Cover source must be PNG, JPG, JPEG, or WEBP: $ResolvedSource"
}

Add-Type -AssemblyName System.Drawing
$Image = $null
try {
    $Image = [System.Drawing.Image]::FromFile($ResolvedSource)
    if ($Image.Width -lt 600 -or $Image.Height -lt 900) {
        throw "Cover image is too small ($($Image.Width)x$($Image.Height)); minimum is 600x900 pixels."
    }
    $Width = $Image.Width
    $Height = $Image.Height
}
finally {
    if ($null -ne $Image) { $Image.Dispose() }
}

$IntakeRoot = Join-Path $Context.BookRoot '00_intake'
$TargetPath = Join-Path $IntakeRoot 'cover.png'
$BackupPath = $null
New-Item -ItemType Directory -Path $IntakeRoot -Force | Out-Null

if (Test-Path -LiteralPath $TargetPath) {
    if (-not $Force) {
        throw "A publication cover already exists. Use -Force only after approving replacement: $TargetPath"
    }
    $BackupRoot = Join-Path $Context.BookRoot 'back\cover'
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
    $BackupPath = Join-Path $BackupRoot ("cover_{0}.png" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    Copy-Item -LiteralPath $TargetPath -Destination $BackupPath -Force
}

$SourceImage = [System.Drawing.Image]::FromFile($ResolvedSource)
try {
    $Bitmap = New-Object System.Drawing.Bitmap($SourceImage.Width, $SourceImage.Height)
    try {
        $Graphics = [System.Drawing.Graphics]::FromImage($Bitmap)
        try { $Graphics.DrawImage($SourceImage, 0, 0, $SourceImage.Width, $SourceImage.Height) }
        finally { $Graphics.Dispose() }
        $Bitmap.Save($TargetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    }
    finally { $Bitmap.Dispose() }
}
finally { $SourceImage.Dispose() }

Write-Host "Publication cover installed successfully:"
Write-Host $TargetPath
Write-Host "Dimensions: $Width x $Height"
if ($BackupPath) {
    Write-Host "Previous cover backup:"
    Write-Host $BackupPath
}
Write-Host "Format preflight is now stale. Run 04F.ps1 -Mode Check before stage 05 export."
