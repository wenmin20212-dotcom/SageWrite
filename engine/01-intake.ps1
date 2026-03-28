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

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "intake" -Data @{
    title = $Title
    audience = $Audience
    type = $Type
}

$WorkspaceRoot = $Context.WorkspaceRoot
$BookRoot      = $Context.BookRoot

$Folders = @(
    "00_brief",
    "01_outline",
    "02_chapters",
    "03_assets",
    "04_glossary",
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

# 书籍定义

- 书名标题：$Title
- 目标读者：$Audience
- 作品类型：$Type
- 核心论点：$CoreThesis
- 写作范围：$Scope

# 风格指南

- 写作风格：$Style
- 受众适配：正文表达必须始终面向 $Audience，避免偏离目标读者的理解水平与阅读期待。
- 类型一致性：全书必须保持 $Type 的表达方式与结构特征，不要偏离既定作品类型。
- 论点对齐：所有章节都应服务于以下核心论点，不得偏题或任意扩展：$CoreThesis
- 范围约束：内容必须严格受以下范围限制，不引入范围外主题：$Scope
"@

[System.IO.File]::WriteAllText(
    $ObjectivePath,
    $ObjectiveContent,
    [System.Text.UTF8Encoding]::new($true)
)

Complete-SageStep -Context $Context -Step "intake" -State "success" -Message "Workspace initialized." -Data @{
    workspace = $WorkspaceRoot
    objective = $ObjectivePath
}

Write-Host "SageWrite intake initialization completed."
Write-Host "Workspace: $WorkspaceRoot"
