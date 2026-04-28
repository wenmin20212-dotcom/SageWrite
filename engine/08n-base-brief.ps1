param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [switch]$Force
)

. "$PSScriptRoot\08n-common.ps1"

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$ObjectivePath = Join-Path $Roots.brief "objective.md"
$TocPath = Join-Path $Roots.outline "toc.md"
$BriefJsonPath = Join-Path $Roots.base "base_brief.json"
$BriefMdPath = Join-Path $Roots.base "base_brief.md"
$LogPath = Join-Path $Roots.logs "08n-base-brief.log"

Assert-FileExists -Path $ObjectivePath -Description "objective.md"

if ((Test-Path -LiteralPath $BriefJsonPath) -and (-not $Force)) {
    Write-Host "base_brief.json already exists. Use -Force to regenerate."
    exit 0
}

$DerivedTitle = Read-FrontMatterValue -Path $ObjectivePath -Key "title"
$DerivedAudience = Read-FrontMatterValue -Path $ObjectivePath -Key "audience"
$DerivedType = Read-FrontMatterValue -Path $ObjectivePath -Key "type"
$DerivedThesis = Read-FrontMatterValue -Path $ObjectivePath -Key "core_thesis"
$DerivedScope = Read-FrontMatterValue -Path $ObjectivePath -Key "scope"
$DerivedStyle = Read-FrontMatterValue -Path $ObjectivePath -Key "style"

if ([string]::IsNullOrWhiteSpace($Title)) { $Title = $DerivedTitle }
if ([string]::IsNullOrWhiteSpace($Title)) { throw "Title is missing. Provide -Title or ensure objective.md contains title." }

$ChapterTitles = Get-TocChapterTitles -Path $TocPath
$Brief = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    edition = $Edition
    cover_text = [ordered]@{
        title = $Title
        subtitle = $Subtitle
        author = $Author
    }
    source = [ordered]@{
        objective_file = $ObjectivePath
        toc_file = if (Test-Path -LiteralPath $TocPath) { $TocPath } else { $null }
    }
    book_context = [ordered]@{
        audience = $DerivedAudience
        book_type = $DerivedType
        core_thesis = $DerivedThesis
        scope = $DerivedScope
        style = $DerivedStyle
        chapter_count = $ChapterTitles.Count
        chapter_titles = @($ChapterTitles)
    }
    base_image_rules = [ordered]@{
        no_text = $true
        text_policy = "The generated base image must contain no title, subtitle, author name, letters, words, numbers, logos, watermarks, labels, captions, UI text, or pseudo-typography."
        whitespace_policy = "Reserve generous clean negative space for later title, subtitle, author, back-cover copy, barcode area, and spine layout."
        rendering_goal = "High-impact, cinematic, polished, richly rendered image-only background suitable for premium nonfiction publishing."
        layout_goal = "Create a front-cover-ready image that remains useful when expanded into a full KDP print cover."
    }
    preferred_models = @("Midjourney", "Imagen 2")
}

$MarkdownLines = @(
    "# 08N Base Image Brief",
    "",
    "- BookName: $BookName",
    "- Edition: $Edition",
    "- Title for later layout: $Title",
    "- Subtitle for later layout: $Subtitle",
    "- Author for later layout: $Author",
    "",
    "## Base Image Rules",
    "",
    "- No text of any kind inside the generated image.",
    "- Preserve generous negative space for later typography.",
    "- Render a strong, polished, high-impact visual background.",
    "- Treat Midjourney / Imagen output as image-only art, not final cover typography.",
    "",
    "## Book Context",
    "",
    "- Audience: $DerivedAudience",
    "- Type: $DerivedType",
    "- Thesis: $DerivedThesis",
    "- Scope: $DerivedScope",
    "- Style: $DerivedStyle",
    "",
    "## Chapter Signals"
)

foreach ($chapter in $ChapterTitles) {
    $MarkdownLines += "- $chapter"
}

Write-JsonUtf8 -Data $Brief -Path $BriefJsonPath
Write-TextUtf8 -Content ($MarkdownLines -join "`r`n") -Path $BriefMdPath
Write-TextUtf8 -Content ("[{0}] 08n-base-brief completed: {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $BriefJsonPath) -Path $LogPath

Write-Host ""
Write-Host "08n-base-brief completed successfully."
Write-Host "JSON: $BriefJsonPath"
Write-Host "Markdown: $BriefMdPath"
