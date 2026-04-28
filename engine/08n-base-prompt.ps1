param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [ValidateSet("auto", "fast", "full")]
    [string]$Mode = "auto",

    [switch]$Force
)

. "$PSScriptRoot\08n-common.ps1"

$Roots = Get-NextCoverRoots -BookName $BookName -Edition $Edition
Initialize-NextCoverRoots -Roots $Roots

$BriefJsonPath = Join-Path $Roots.base "base_brief.json"
$PromptJsonPath = Join-Path $Roots.prompts "base_prompts.json"
$PromptMdPath = Join-Path $Roots.prompts "base_prompts.md"
$LogPath = Join-Path $Roots.logs "08n-base-prompt.log"

Assert-FileExists -Path $BriefJsonPath -Description "base_brief.json"

if ((Test-Path -LiteralPath $PromptJsonPath) -and (-not $Force)) {
    Write-Host "base_prompts.json already exists. Use -Force to regenerate."
    exit 0
}

$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$Title = Get-StringValue $Brief.cover_text.title
$Audience = Get-StringValue $Brief.book_context.audience
$BookType = Get-StringValue $Brief.book_context.book_type
$Thesis = Get-StringValue $Brief.book_context.core_thesis
$Scope = Get-StringValue $Brief.book_context.scope

$Routes = @(
    [ordered]@{
        id = "cinematic-knowledge-architecture"
        label = "Cinematic Knowledge Architecture"
        composition = "large quiet negative space in upper-left and lower third, luminous architectural layers, deep perspective, no visible writing"
        palette = "ivory, deep green, graphite, restrained gold light"
        mood = "premium nonfiction, intelligent, rigorous, calm but powerful"
    },
    [ordered]@{
        id = "human-ai-workflow-atrium"
        label = "Human AI Workflow Atrium"
        composition = "abstract atrium of light, modular workflow traces, one clear empty title zone, no letters or UI text"
        palette = "warm white, teal, charcoal, silver highlights"
        mood = "modern collaboration, disciplined creation, credible technology"
    },
    [ordered]@{
        id = "civilization-map-field"
        label = "Civilization Map Field"
        composition = "wide symbolic map-like field, layered grids without labels, strong blank panel for typography, no marks resembling words"
        palette = "deep blue, porcelain, muted copper, soft gray"
        mood = "civilization scale, structured knowledge, serious and memorable"
    }
)

$Prompts = @()
foreach ($route in $Routes) {
    $corePrompt = @(
        "Image-only base artwork for a serious nonfiction book cover."
        "No text of any kind, no typography, no letters, no numbers, no Chinese characters, no logos, no watermarks, no UI labels, no captions, no signage, no diagrams with labels, no marks that look like writing."
        "Book context: $BookType for $Audience."
        "Concept: $Thesis $Scope"
        "Visual route: $($route.label)."
        "Composition: $($route.composition)."
        "Palette: $($route.palette)."
        "Mood: $($route.mood)."
        "High-impact cinematic rendering, premium publishing polish, generous clean negative space for later title and author overlay."
        "Do not include book title or author in the image."
    ) -join " "

    $Prompts += [ordered]@{
        route_id = $route.id
        route_label = $route.label
        midjourney_prompt = "$corePrompt --ar 2:3 --style raw --v 6"
        imagen_prompt = $corePrompt
        negative_prompt = "text, typography, letters, words, numbers, Chinese characters, logo, watermark, caption, label, UI, signage, diagram labels, book title, author name, marks that look like writing, busy clutter, low quality"
    }
}

$PromptPackage = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    edition = $Edition
    mode = $Mode
    title_reserved_for_later_layout = $Title
    provider_note = "Use Midjourney or Imagen 2 to generate image-only base art. Import approved files into next/$Edition/imports before 08n-base-review, or use 08n-base-generate local placeholders."
    prompts = @($Prompts)
}

$MarkdownLines = @("# 08N Base Image Prompts", "", "Title is reserved for later local layout: $Title", "")
foreach ($prompt in $Prompts) {
    $MarkdownLines += "## $($prompt.route_label)"
    $MarkdownLines += ""
    $MarkdownLines += "### Midjourney"
    $MarkdownLines += ""
    $MarkdownLines += $prompt.midjourney_prompt
    $MarkdownLines += ""
    $MarkdownLines += "### Imagen 2"
    $MarkdownLines += ""
    $MarkdownLines += $prompt.imagen_prompt
    $MarkdownLines += ""
    $MarkdownLines += "### Negative Prompt"
    $MarkdownLines += ""
    $MarkdownLines += $prompt.negative_prompt
    $MarkdownLines += ""
}

Write-JsonUtf8 -Data $PromptPackage -Path $PromptJsonPath
Write-TextUtf8 -Content ($MarkdownLines -join "`r`n") -Path $PromptMdPath
Write-TextUtf8 -Content ("[{0}] 08n-base-prompt completed: {1}" -f (Get-Date).ToString("yyyy-MM-dd HH:mm:ss"), $PromptJsonPath) -Path $LogPath

Write-Host ""
Write-Host "08n-base-prompt completed successfully."
Write-Host "JSON: $PromptJsonPath"
Write-Host "Markdown: $PromptMdPath"
