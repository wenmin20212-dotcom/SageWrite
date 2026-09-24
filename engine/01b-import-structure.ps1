param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
    [string]$Language = 'zh',
    [string]$Model = '',
    [int]$MaxOutputTokens = 16000,
    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'

. (Join-Path $PSScriptRoot '00-common.ps1')
. (Join-Path $PSScriptRoot '00-llm.ps1')

function Read-StructureSource {
    param([Parameter(Mandatory=$true)][string]$Path)

    $Resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $Extension = [System.IO.Path]::GetExtension($Resolved).ToLowerInvariant()
    if ($Extension -in @('.md', '.txt', '.json', '.yaml', '.yml')) {
        return [System.IO.File]::ReadAllText($Resolved, [System.Text.Encoding]::UTF8)
    }
    if ($Extension -eq '.docx') {
        $Pandoc = Get-Command pandoc -ErrorAction SilentlyContinue
        if ($null -eq $Pandoc) {
            throw 'DOCX input requires pandoc on PATH.'
        }
        $Text = & $Pandoc.Source $Resolved '-t' 'gfm' 2>&1
        if ($LASTEXITCODE -ne 0) { throw "pandoc could not read DOCX: $($Text -join "`n")" }
        return ($Text -join "`n")
    }
    throw "Unsupported source type '$Extension'. Use MD, TXT, JSON, YAML, or DOCX."
}

function ConvertFrom-LlmJson {
    param([Parameter(Mandatory=$true)][string]$Text)
    $Clean = $Text.Trim()
    if ($Clean -match '(?s)^```(?:json)?\s*(.*?)\s*```$') { $Clean = $Matches[1].Trim() }
    try { return $Clean | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "LLM output is not valid JSON: $($_.Exception.Message)" }
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $Parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Parent)) { New-Item -ItemType Directory -Path $Parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
}

function Backup-ExistingFile {
    param([string]$Path, [string]$BackupRoot)
    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
        Copy-Item -LiteralPath $Path -Destination (Join-Path $BackupRoot ([System.IO.Path]::GetFileName($Path))) -Force
    }
}

function Get-SafeCardName {
    param([int]$Index, [string]$Title)
    $Safe = $Title -replace '[\\/:*?"<>|]', '-' -replace '\s+', '-'
    $Safe = $Safe.Trim(' ', '.', '-')
    if ($Safe.Length -gt 60) { $Safe = $Safe.Substring(0, 60).TrimEnd('-') }
    if ([string]::IsNullOrWhiteSpace($Safe)) { $Safe = "chapter-$Index" }
    return ('{0:D3}-{1}.md' -f $Index, $Safe)
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
$ResolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
$SourceContent = Read-StructureSource -Path $ResolvedSource
if ([string]::IsNullOrWhiteSpace($SourceContent)) { throw 'The structure source file is empty.' }

$LlmConfig = Get-SageLlmConfig
if (-not [string]::IsNullOrWhiteSpace($Model)) { $LlmConfig.Model = $Model }
Set-SageCurrentStep -Context $Context -Step 'structure-import' -Data @{
    source = $ResolvedSource; mode = $Mode; language = $Language
    provider = $LlmConfig.Provider; model = $LlmConfig.Model
}

$Prompt = @"
You are a senior book architect. Transform the supplied structure document into a normalized SageWrite plan.

Language for all generated prose: $Language

SOURCE DOCUMENT (do not invent facts outside it):
--- SOURCE START ---
$SourceContent
--- SOURCE END ---

Return JSON only. Do not use Markdown fences. Use this exact shape:
{
  "title": "book title",
  "subtitle": "optional subtitle",
  "author": "optional author",
  "summary": "a concise overview of the complete work",
  "audience": "intended readers",
  "type": "work type",
  "core_thesis": "central thesis",
  "scope": "included and excluded scope",
  "style": "writing and organization style",
  "chapters": [
    {
      "number": 1,
      "title": "chapter title",
      "purpose": "what this chapter must accomplish",
      "source_basis": "which ideas from the source belong here",
      "sections": [
        { "number": "1.1", "title": "section title", "task": "specific writing task" }
      ]
    }
  ]
}

Rules:
- Preserve the source's intent, ordering, terminology, and boundaries.
- Consolidate duplicates but do not silently discard unique requirements.
- Every chapter needs at least one section.
- Chapter and section numbering must be continuous.
- Each task must be actionable enough for a writer or agent to execute.
"@

try {
    $RawResult = Invoke-SageLlmText -Prompt $Prompt -Config $LlmConfig -MaxOutputTokens $MaxOutputTokens
    $Plan = ConvertFrom-LlmJson -Text $RawResult
    if ($null -eq $Plan.chapters -or @($Plan.chapters).Count -eq 0) { throw 'The generated plan contains no chapters.' }
} catch {
    Fail-SageStep -Context $Context -Step 'structure-import' -Message 'Structure import failed.' -Data @{ error = $_.Exception.Message }
    throw
}

$ChapterLines = @()
$TaskLines = @('# Structure Rewrite Tasks', '')
$Cards = @()
$ChapterIndex = 0
foreach ($Chapter in @($Plan.chapters)) {
    $ChapterIndex++
    $ChapterTitle = [string]$Chapter.title
    if ([string]::IsNullOrWhiteSpace($ChapterTitle)) { throw "Chapter $ChapterIndex has no title." }
    $ChapterLines += "## $ChapterIndex $ChapterTitle"
    $TaskLines += "## $ChapterIndex $ChapterTitle"
    $TaskLines += "- [ ] Chapter purpose: $($Chapter.purpose)"
    $SectionIndex = 0
    $SectionLines = @()
    foreach ($Section in @($Chapter.sections)) {
        $SectionIndex++
        $Number = "$ChapterIndex.$SectionIndex"
        $SectionTitle = [string]$Section.title
        $ChapterLines += "### $Number $SectionTitle"
        $TaskLines += "- [ ] $Number $SectionTitle - $($Section.task)"
        $SectionLines += @("## $Number $SectionTitle", '', "**Writing task:** $($Section.task)", '')
    }
    if ($SectionIndex -eq 0) { throw "Chapter $ChapterIndex has no sections." }
    $ChapterLines += ''
    $TaskLines += ''
    $CardName = Get-SafeCardName -Index $ChapterIndex -Title $ChapterTitle
    $CardContent = @(
        '---', 'file_role: structure_card', "chapter: $ChapterIndex", "title: `"$ChapterTitle`"",
        "source: `"$ResolvedSource`"", '---', '', "# $ChapterIndex $ChapterTitle", '',
        '## Purpose', '', [string]$Chapter.purpose, '', '## Source Basis', '', [string]$Chapter.source_basis, ''
    ) + $SectionLines
    $Cards += [pscustomobject]@{ Name = $CardName; Content = ($CardContent -join "`r`n") }
}

$GeneratedAt = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
$SummaryContent = @"
---
file_role: imported_structure_summary
layer: constitution
source: "$ResolvedSource"
generated_at: $GeneratedAt
---

# $($Plan.title)

## Overview

$($Plan.summary)

## Audience

$($Plan.audience)

## Core Thesis

$($Plan.core_thesis)

## Scope

$($Plan.scope)

## Style

$($Plan.style)
"@
$ObjectiveContent = @"
---
file_role: objective
layer: constitution
title: $($Plan.title)
subtitle: $($Plan.subtitle)
author: $($Plan.author)
audience: $($Plan.audience)
type: $($Plan.type)
core_thesis: $($Plan.core_thesis)
scope: $($Plan.scope)
style: $($Plan.style)
created_at: $GeneratedAt
source: "$ResolvedSource"
---

# Book Definition

$($Plan.summary)
"@
$TocContent = @("---", 'file_role: toc', 'layer: structure', "generated_at: $GeneratedAt", '---', '', '# Table of Contents', '') + $ChapterLines

$PreviewRoot = Join-Path $Context.LogRoot ('structure-import-preview-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
$OutputRoot = if ($Mode -eq 'Apply') { $Context.BookRoot } else { $PreviewRoot }
$BriefRoot = Join-Path $OutputRoot '00_brief'
$OutlineRoot = Join-Path $OutputRoot '01_outline'
$CardRoot = Join-Path $OutlineRoot 'cards'

if ($Mode -eq 'Apply') {
    $Targets = @(
        (Join-Path $BriefRoot 'objective.md'), (Join-Path $OutlineRoot 'toc.md'),
        (Join-Path $OutlineRoot 'structure_summary.md'), (Join-Path $OutlineRoot 'structure_tasks.md')
    )
    $Conflicts = @($Targets | Where-Object { Test-Path -LiteralPath $_ })
    if ($Conflicts.Count -gt 0 -and -not $Force) {
        throw "Existing structure files found. Review Preview output, then rerun with -Mode Apply -Force."
    }
    $BackupRoot = Join-Path $Context.BookRoot ('back\structure-import-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
    foreach ($Target in $Targets) { Backup-ExistingFile -Path $Target -BackupRoot $BackupRoot }
    if ((Test-Path -LiteralPath $CardRoot) -and $Force) {
        Copy-Item -LiteralPath $CardRoot -Destination (Join-Path $BackupRoot 'cards') -Recurse -Force
    }
}

Write-Utf8File -Path (Join-Path $BriefRoot 'objective.md') -Content $ObjectiveContent
Write-Utf8File -Path (Join-Path $OutlineRoot 'structure_summary.md') -Content $SummaryContent
Write-Utf8File -Path (Join-Path $OutlineRoot 'toc.md') -Content ($TocContent -join "`r`n")
Write-Utf8File -Path (Join-Path $OutlineRoot 'structure_tasks.md') -Content ($TaskLines -join "`r`n")
foreach ($Card in $Cards) { Write-Utf8File -Path (Join-Path $CardRoot $Card.Name) -Content $Card.Content }

$Manifest = [ordered]@{
    mode = $Mode; source = $ResolvedSource; output_root = $OutputRoot
    chapter_count = $ChapterIndex; card_count = $Cards.Count
    provider = $LlmConfig.Provider; model = $LlmConfig.Model; generated_at = $GeneratedAt
}
Write-Utf8File -Path (Join-Path $OutlineRoot 'structure_import_manifest.json') -Content ($Manifest | ConvertTo-Json -Depth 8)
Complete-SageStep -Context $Context -Step 'structure-import' -State 'success' -Message 'Structure source split successfully.' -Data $Manifest

Write-Output "SUCCESS: Structure source split into $($Cards.Count) Markdown cards."
Write-Output "MODE: $Mode"
Write-Output "OUTPUT: $OutputRoot"
