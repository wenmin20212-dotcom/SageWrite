param(
  [string]$OutputRoot,
  [string]$Ref = "HEAD",
  [string]$VersionName,
  [switch]$Force
)

$ErrorActionPreference = "Stop"

$EngineRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $EngineRoot

if ([string]::IsNullOrWhiteSpace($OutputRoot)) {
  $OutputRoot = Join-Path $EngineRoot "release-packages"
}

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
  throw "git is required to create a standalone package."
}

$ShortSha = (& git -c "safe.directory=$RepoRoot" -C $RepoRoot rev-parse --short $Ref).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($ShortSha)) {
  throw "Unable to resolve git ref: $Ref"
}

if ([string]::IsNullOrWhiteSpace($VersionName)) {
  $VersionName = "single-user-standalone-$ShortSha"
}

New-Item -ItemType Directory -Force -Path $OutputRoot | Out-Null
$OutputPath = Join-Path $OutputRoot "SageWrite-$VersionName.zip"

if ((Test-Path -LiteralPath $OutputPath) -and !$Force) {
  throw "Package already exists: $OutputPath. Re-run with -Force to overwrite it."
}

if (Test-Path -LiteralPath $OutputPath) {
  Remove-Item -LiteralPath $OutputPath -Force
}

$Prefix = "SageWrite-$VersionName/"
& git -c "safe.directory=$RepoRoot" -C $RepoRoot archive --format=zip "--output=$OutputPath" "--prefix=$Prefix" $Ref engine
if ($LASTEXITCODE -ne 0) {
  throw "git archive failed."
}

Write-Host "Created standalone package: $OutputPath"
Write-Host "Ref: $Ref"
Write-Host "VersionName: $VersionName"
Write-Host "Install entry inside package: $Prefix`engine/Install-SageWrite-Standalone.ps1"
