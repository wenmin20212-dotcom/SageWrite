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

# ========= 路径定义 =========
$WorkspaceRoot = "workspace-$BookName"
$SageRoot = Join-Path $WorkspaceRoot "sagewrite"
$BookRoot = Join-Path $SageRoot "book"

# ========= 系统文件目录（不是书目录） =========
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

# ========= objective.md =========
$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"

@"
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

# $Title

核心思想：$CoreThesis  
目标读者：$Audience  
书籍类型：$Type  
预期规模：$Scope  
文风：$Style  

"@ | Out-File $ObjectivePath -Encoding utf8

# ========= style_guide.md =========
$StylePath = Join-Path $BookRoot "05_style\style_guide.md"

@"
---
file_role: style
layer: constitution
---

写作风格：$Style
目标读者：$Audience
书籍类型：$Type

"@ | Out-File $StylePath -Encoding utf8

# ========= 日志文件 =========
$LogPath = Join-Path $BookRoot "logs\run_history.json"

if (!(Test-Path $LogPath)) {
    "[]" | Out-File $LogPath -Encoding utf8
}

Write-Host "SageWrite 第一章初始化完成。"
Write-Host "Workspace: $WorkspaceRoot"