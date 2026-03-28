param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [string]$Title,

    [Parameter(Mandatory=$true)]
    [string]$Audience,

    [Parameter(Mandatory=$true)]
    [string]$Type,

    [Parameter(Mandatory=$true)]
    [string]$CoreThesis,

    [Parameter(Mandatory=$true)]
    [string]$Scope,

    [Parameter(Mandatory=$true)]
    [string]$Style
)

$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot   = Split-Path -Parent $EnginePath
$ClawRoot   = Split-Path -Parent $SageRoot

$WorkspaceRoot = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot      = Join-Path $WorkspaceRoot "sagewrite\book"

$Folders = @(
    "00_brief",
    "01_outline",
    "02_chapters",
    "03_assets",
    "04_glossary",
    "05_style",
    "06_build",
    "logs"
)

foreach ($folder in $Folders) {
    $path = Join-Path $BookRoot $folder
    if (!(Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
}

$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"

$ObjectiveContent = @"
---
file_role: objective
layer: constitution
title: $Title
audience: $Audience
type: $Type
core_thesis: $CoreThesis
scope: $Scope
style: $Style
created_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
---
"@

[System.IO.File]::WriteAllText(
    $ObjectivePath,
    $ObjectiveContent,
    [System.Text.UTF8Encoding]::new($true)
)

$StylePath = Join-Path $BookRoot "05_style\style_guide.md"

$StyleContent = @"
---
file_role: style
layer: constitution
writing_style: $Style
audience: $Audience
book_type: $Type
created_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
---
"@

[System.IO.File]::WriteAllText(
    $StylePath,
    $StyleContent,
    [System.Text.UTF8Encoding]::new($true)
)

$LogPath = Join-Path $BookRoot "logs\run_history.json"

if (!(Test-Path $LogPath)) {
    [System.IO.File]::WriteAllText(
        $LogPath,
        "[]",
        [System.Text.UTF8Encoding]::new($true)
    )
}

Write-Host "SageWrite intake initialization completed."
Write-Host "Workspace: $WorkspaceRoot"