param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
    [ValidateRange(1,6)][int]$ChapterHeadingLevel = 1,
    [string]$ChapterPattern = '',
    [switch]$SkipFirstHeading,
    [switch]$Force
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot '00-common.ps1')

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    $Parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $Parent)) { New-Item -ItemType Directory -Path $Parent -Force | Out-Null }
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
}

function Convert-SourceToMarkdown {
    param([string]$Path, [string]$OutputRoot)
    $Resolved = (Resolve-Path -LiteralPath $Path -ErrorAction Stop).Path
    $Extension = [System.IO.Path]::GetExtension($Resolved).ToLowerInvariant()
    if ($Extension -in @('.md', '.markdown', '.txt')) {
        return [System.IO.File]::ReadAllText($Resolved, [System.Text.Encoding]::UTF8)
    }
    if ($Extension -ne '.docx') { throw "Unsupported source type '$Extension'. Use DOCX, MD, MARKDOWN, or TXT." }
    $PandocPath = $env:SAGEWRITE_PANDOC
    if ([string]::IsNullOrWhiteSpace($PandocPath)) {
        $Pandoc = Get-Command pandoc -ErrorAction SilentlyContinue
        if ($null -ne $Pandoc) { $PandocPath = $Pandoc.Source }
    }
    if ([string]::IsNullOrWhiteSpace($PandocPath)) {
        $Candidates = @(
            (Join-Path $env:LOCALAPPDATA 'Pandoc\pandoc.exe'),
            (Join-Path $env:ProgramFiles 'Pandoc\pandoc.exe')
        )
        $PandocPath = $Candidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } | Select-Object -First 1
    }
    if ([string]::IsNullOrWhiteSpace($PandocPath) -or -not (Test-Path -LiteralPath $PandocPath -PathType Leaf)) {
        throw 'DOCX input requires Pandoc. Install it or set SAGEWRITE_PANDOC to pandoc.exe.'
    }
    $MediaRoot = Join-Path $OutputRoot '03_assets\imported-document'
    New-Item -ItemType Directory -Path $MediaRoot -Force | Out-Null
    $TempMarkdown = Join-Path $OutputRoot '_converted-source.md'
    $PandocOutput = & $PandocPath $Resolved '--from=docx' '--to=gfm+footnotes' '--wrap=none' "--extract-media=$MediaRoot" '--output' $TempMarkdown 2>&1
    if ($LASTEXITCODE -ne 0) { throw "pandoc could not convert DOCX: $($PandocOutput -join "`n")" }
    $Markdown = [System.IO.File]::ReadAllText($TempMarkdown, [System.Text.Encoding]::UTF8)
    Remove-Item -LiteralPath $TempMarkdown -Force
    $ForwardMediaRoot = $MediaRoot -replace '\\', '/'
    $Markdown = $Markdown.Replace($ForwardMediaRoot, '../03_assets/imported-document')
    return $Markdown.Replace($MediaRoot, '../03_assets/imported-document')
}

function Rebase-ChapterHeadings {
    param([string]$Content, [int]$OriginalLevel, [string]$Title)
    $Lines = ($Content -replace "`r", '') -split "`n"
    $Result = @("# $Title")
    for ($Index = 1; $Index -lt $Lines.Count; $Index++) {
        $Line = $Lines[$Index]
        if ($Line -match '^(#{1,6})\s+(.+?)\s*$') {
            $OldLevel = $Matches[1].Length
            $NewLevel = [Math]::Min(6, [Math]::Max(2, $OldLevel - $OriginalLevel + 1))
            $Line = ('#' * $NewLevel) + ' ' + $Matches[2]
        }
        $Result += $Line
    }
    return (($Result -join "`r`n").Trim() + "`r`n")
}

function Backup-Path {
    param([string]$Path, [string]$BackupRoot)
    if (-not (Test-Path -LiteralPath $Path)) { return }
    if (-not (Test-Path -LiteralPath $BackupRoot)) { New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null }
    Copy-Item -LiteralPath $Path -Destination (Join-Path $BackupRoot ([System.IO.Path]::GetFileName($Path))) -Recurse -Force
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
$ResolvedSource = (Resolve-Path -LiteralPath $SourcePath -ErrorAction Stop).Path
$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$OutputRoot = if ($Mode -eq 'Apply') { $Context.BookRoot } else { Join-Path $Context.LogRoot "document-split-preview-$Stamp" }
New-Item -ItemType Directory -Path $OutputRoot -Force | Out-Null
Set-SageCurrentStep -Context $Context -Step 'document-split' -Data @{
    source = $ResolvedSource; mode = $Mode; chapter_heading_level = $ChapterHeadingLevel
    chapter_pattern = $ChapterPattern; skip_first_heading = [bool]$SkipFirstHeading
}

try {
    $Markdown = (Convert-SourceToMarkdown -Path $ResolvedSource -OutputRoot $OutputRoot) -replace "`r", ''
    if ([string]::IsNullOrWhiteSpace($Markdown)) { throw 'The converted document is empty.' }
    $HeadingMarks = '#' * $ChapterHeadingLevel
    $HeadingRegex = [regex]::new("(?m)^$([regex]::Escape($HeadingMarks))(?!#)\s+(.+?)\s*$")
    $Candidates = @($HeadingRegex.Matches($Markdown))
    if (-not [string]::IsNullOrWhiteSpace($ChapterPattern)) {
        try { $TitleRegex = [regex]::new($ChapterPattern) }
        catch { throw "ChapterPattern is not a valid regular expression: $($_.Exception.Message)" }
        $Candidates = @($Candidates | Where-Object { $TitleRegex.IsMatch($_.Groups[1].Value.Trim()) })
    }
    if ($SkipFirstHeading -and $Candidates.Count -gt 0) { $Candidates = @($Candidates | Select-Object -Skip 1) }
    if ($Candidates.Count -eq 0) { throw "No chapter headings found. Apply Word Heading $ChapterHeadingLevel to chapter titles, or adjust -ChapterHeadingLevel/-ChapterPattern." }

    $Chapters = @()
    for ($Index = 0; $Index -lt $Candidates.Count; $Index++) {
        $Match = $Candidates[$Index]
        $End = if ($Index + 1 -lt $Candidates.Count) { $Candidates[$Index + 1].Index } else { $Markdown.Length }
        $Title = $Match.Groups[1].Value.Trim()
        $Raw = $Markdown.Substring($Match.Index, $End - $Match.Index)
        $Chapters += [pscustomobject]@{ Number = $Index + 1; Title = $Title; Content = (Rebase-ChapterHeadings -Content $Raw -OriginalLevel $ChapterHeadingLevel -Title $Title) }
    }

    $Preamble = $Markdown.Substring(0, $Candidates[0].Index).Trim()
    $ChapterRoot = Join-Path $OutputRoot '02_chapters'
    $OutlineRoot = Join-Path $OutputRoot '01_outline'
    $BriefRoot = Join-Path $OutputRoot '00_brief'
    $ExistingNumeric = if (Test-Path -LiteralPath $ChapterRoot) { @(Get-ChildItem -LiteralPath $ChapterRoot -File -Filter '*.md' | Where-Object { $_.BaseName -match '^\d+$' }) } else { @() }
    if ($Mode -eq 'Apply' -and $ExistingNumeric.Count -gt 0 -and -not $Force) { throw "02_chapters already contains $($ExistingNumeric.Count) numeric chapter files. Rerun with -Force after reviewing Preview." }
    if ($Mode -eq 'Apply' -and $Force) {
        $BackupRoot = Join-Path $Context.BookRoot "back\document-split-$Stamp"
        Backup-Path -Path $ChapterRoot -BackupRoot $BackupRoot
        Backup-Path -Path (Join-Path $OutlineRoot 'toc.md') -BackupRoot $BackupRoot
        Backup-Path -Path (Join-Path $OutlineRoot 'document_split_manifest.json') -BackupRoot $BackupRoot
        foreach ($File in $ExistingNumeric) { Remove-Item -LiteralPath $File.FullName -Force }
    }

    New-Item -ItemType Directory -Path $ChapterRoot -Force | Out-Null
    $Width = [Math]::Max(2, $Chapters.Count.ToString().Length)
    $TocLines = @('---', 'file_role: toc', 'layer: structure', "generated_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '---', '', '# Table of Contents', '')
    $TaskLines = @('# Document Split Checklist', '')
    foreach ($Chapter in $Chapters) {
        $FileName = $Chapter.Number.ToString("D$Width") + '.md'
        Write-Utf8File -Path (Join-Path $ChapterRoot $FileName) -Content $Chapter.Content
        $TocLines += "## $($Chapter.Title)"
        $SectionNumber = 0
        foreach ($Line in (($Chapter.Content -replace "`r", '') -split "`n")) {
            if ($Line -match '^##\s+(.+?)\s*$') { $SectionNumber++; $TocLines += "### $($Chapter.Number).$SectionNumber $($Matches[1])" }
        }
        $TocLines += ''
        $TaskLines += "- [x] $FileName - $($Chapter.Title)"
    }

    if (-not [string]::IsNullOrWhiteSpace($Preamble)) { Write-Utf8File -Path (Join-Path $BriefRoot 'imported_frontmatter.md') -Content ($Preamble + "`r`n") }
    $Summary = @('# Imported Document Summary', '', "- Source: $ResolvedSource", "- Chapters: $($Chapters.Count)", "- Split heading level: $ChapterHeadingLevel", "- Imported at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '', 'This was a format-only split. Chapter prose was not rewritten by an LLM.') -join "`r`n"
    Write-Utf8File -Path (Join-Path $BriefRoot 'document_import_summary.md') -Content $Summary
    Write-Utf8File -Path (Join-Path $OutlineRoot 'toc.md') -Content ($TocLines -join "`r`n")
    Write-Utf8File -Path (Join-Path $OutlineRoot 'document_split_tasks.md') -Content ($TaskLines -join "`r`n")
    $Manifest = [ordered]@{
        mode = $Mode; source = $ResolvedSource; output_root = $OutputRoot; chapter_count = $Chapters.Count
        chapter_heading_level = $ChapterHeadingLevel; chapter_pattern = $ChapterPattern; used_llm = $false
        generated_at = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'); files = @($Chapters | ForEach-Object { $_.Number.ToString("D$Width") + '.md' })
    }
    Write-Utf8File -Path (Join-Path $OutlineRoot 'document_split_manifest.json') -Content ($Manifest | ConvertTo-Json -Depth 8)
    Complete-SageStep -Context $Context -Step 'document-split' -State 'success' -Message 'Document split into chapter Markdown files.' -Data $Manifest
    Write-Output "SUCCESS: Document split into $($Chapters.Count) chapter Markdown files."
    Write-Output "MODE: $Mode"
    Write-Output "OUTPUT: $OutputRoot"
} catch {
    Fail-SageStep -Context $Context -Step 'document-split' -Message 'Document split failed.' -Data @{ error = $_.Exception.Message }
    throw
}
