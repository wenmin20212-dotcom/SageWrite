param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [Parameter(Mandatory=$true)][string]$SourcePath,
    [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
    [ValidateRange(1,6)][int]$ChapterHeadingLevel = 1,
    [string]$ChapterPattern = '',
    [string]$Title = '',
    [string]$Subtitle = '',
    [string]$Author = '',
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
        $ChapterTitle = $Match.Groups[1].Value.Trim()
        $Raw = $Markdown.Substring($Match.Index, $End - $Match.Index)
        $Chapters += [pscustomobject]@{ Number = $Index + 1; Title = $ChapterTitle; Content = (Rebase-ChapterHeadings -Content $Raw -OriginalLevel $ChapterHeadingLevel -Title $ChapterTitle) }
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
        Backup-Path -Path (Join-Path $BriefRoot 'objective.md') -BackupRoot $BackupRoot
        Backup-Path -Path (Join-Path $OutlineRoot 'toc.md') -BackupRoot $BackupRoot
        Backup-Path -Path (Join-Path $OutlineRoot 'writing_outline.md') -BackupRoot $BackupRoot
        Backup-Path -Path (Join-Path $OutlineRoot 'layout_spec.md') -BackupRoot $BackupRoot
        Backup-Path -Path (Join-Path $OutlineRoot 'document_split_manifest.json') -BackupRoot $BackupRoot
        foreach ($File in $ExistingNumeric) { Remove-Item -LiteralPath $File.FullName -Force }
    }

    New-Item -ItemType Directory -Path $ChapterRoot -Force | Out-Null
    $Width = [Math]::Max(2, $Chapters.Count.ToString().Length)
    $TocLines = @('---', 'file_role: toc', 'layer: structure', "generated_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '---', '', '# Table of Contents', '')
    $TaskLines = @('# Document Split Checklist', '')
    $OutlineLines = @('---', 'file_role: writing_outline', 'layer: structure', "generated_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '---', '', '# Writing Outline', '')
    foreach ($Chapter in $Chapters) {
        $FileName = $Chapter.Number.ToString("D$Width") + '.md'
        Write-Utf8File -Path (Join-Path $ChapterRoot $FileName) -Content $Chapter.Content
        $TocLines += "## $($Chapter.Title)"
        $OutlineLines += "## $($Chapter.Title)"
        $OutlineLines += ''
        $OutlineLines += "- Chapter file: $FileName"
        $OutlineLines += "- Character count: $($Chapter.Content.Length)"
        $SectionNumber = 0
        foreach ($Line in (($Chapter.Content -replace "`r", '') -split "`n")) {
            if ($Line -match '^##\s+(.+?)\s*$') {
                $SectionNumber++
                $TocLines += "### $($Chapter.Number).$SectionNumber $($Matches[1])"
                $OutlineLines += "- Section $($Chapter.Number).${SectionNumber}: $($Matches[1])"
            }
        }
        if ($SectionNumber -eq 0) { $OutlineLines += '- Sections: no explicit subheadings detected in the source chapter' }
        $OutlineLines += ''
        $TocLines += ''
        $TaskLines += "- [x] $FileName - $($Chapter.Title)"
    }

    if (-not [string]::IsNullOrWhiteSpace($Preamble)) { Write-Utf8File -Path (Join-Path $BriefRoot 'imported_frontmatter.md') -Content ($Preamble + "`r`n") }
    $ResolvedTitle = if ([string]::IsNullOrWhiteSpace($Title)) { $BookName } else { $Title.Trim() }
    $Objective = @(
        '---', 'file_role: objective', 'layer: constitution', "title: `"$ResolvedTitle`"", "subtitle: `"$Subtitle`"",
        "author: `"$Author`"", 'type: "imported complete manuscript"',
        'core_thesis: "Preserve the original manuscript while supporting chapter-level editing and final recombination."',
        "scope: `"Complete imported manuscript with $($Chapters.Count) chapters.`"",
        'style: "Preserve the original narrative voice, plot, terminology, and chapter order unless an editor explicitly requests a change."',
        "source: `"$ResolvedSource`"", "created_at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '---', '',
        "# $ResolvedTitle", '', '## Import Purpose', '',
        "This project contains a format-only chapter split of the supplied complete manuscript. The source prose was not rewritten during import.", '',
        '## Editing Principles', '',
        '- Preserve the original story, facts, names, chronology, and chapter order by default.',
        '- Perform later revisions chapter by chapter and record intentional editorial changes.',
        '- Rebuild the complete book from the numbered Markdown chapter files after review.', '',
        '## Structure', '', "- Total chapters: $($Chapters.Count)", '- Chapter files: `02_chapters/*.md`',
        '- Directory: `01_outline/toc.md`', '- Writing outline: `01_outline/writing_outline.md`'
    ) -join "`r`n"
    $LayoutSpec = @(
        '---', 'file_role: layout_spec', 'layer: production', 'schema_version: 1',
        'page_size: A4', 'margin_top_cm: 2.3', 'margin_bottom_cm: 2.3',
        'margin_inner_cm: 2.5', 'margin_outer_cm: 2.2',
        'body_font_zh: SimSun', 'body_font_western: Times New Roman',
        'body_font_size_pt: 12', 'line_spacing: 1.5', 'first_line_indent_chars: 2',
        'chapter_font_zh: SimHei', 'chapter_font_size_pt: 20',
        'chapter_alignment: center', 'chapter_page_break_before: true',
        'header_enabled: true', "header_left: `"$ResolvedTitle`"",
        'header_right: "{chapter_title}"', 'header_chapter_first_page: false',
        'footer_enabled: true', 'page_number_format: "Page {page} of {pages}"',
        'page_number_cover: false', 'cover_path: 00_intake/cover.png', '---', '',
        '# Default Layout Specification', '', '## Page', '',
        '- Use A4 paper with the margins declared above.',
        '- Start every chapter on a new page.', '', '## Body', '',
        '- Use 12 pt SimSun for Chinese and Times New Roman for Western text.',
        '- Use 1.5 line spacing, no extra paragraph spacing, and a two-character first-line indent.', '',
        '## Chapters', '', '- Use 20 pt SimHei chapter titles, centered.',
        '- Include chapter titles in a chapter-level table of contents.', '', '## Running Heads and Folios', '',
        '- Do not show a running head, footer, or folio on the cover.',
        '- Do not show a running head on the opening page of any chapter.',
        "- On later chapter pages, show the book title `$ResolvedTitle` at left and the current Heading 1 chapter title at right.",
        '- Center the current page and total page count in the footer.', '', '## Cover', '',
        '- Use `00_intake/cover.png`, preserve its aspect ratio, and center it on the cover page.'
    ) -join "`r`n"
    $Summary = @('# Imported Document Summary', '', "- Source: $ResolvedSource", "- Chapters: $($Chapters.Count)", "- Split heading level: $ChapterHeadingLevel", "- Imported at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')", '', 'This was a format-only split. Chapter prose was not rewritten by an LLM.') -join "`r`n"
    Write-Utf8File -Path (Join-Path $BriefRoot 'document_import_summary.md') -Content $Summary
    Write-Utf8File -Path (Join-Path $BriefRoot 'objective.md') -Content $Objective
    Write-Utf8File -Path (Join-Path $OutlineRoot 'toc.md') -Content ($TocLines -join "`r`n")
    Write-Utf8File -Path (Join-Path $OutlineRoot 'writing_outline.md') -Content ($OutlineLines -join "`r`n")
    Write-Utf8File -Path (Join-Path $OutlineRoot 'layout_spec.md') -Content $LayoutSpec
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
