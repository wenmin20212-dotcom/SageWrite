param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$Force
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-LanguageLabel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LanguageCode
    )

    switch ($LanguageCode.Trim().ToLowerInvariant()) {
        "zh" { return "Chinese" }
        "en" { return "English" }
        "fr" { return "French" }
        "de" { return "German" }
        "es" { return "Spanish" }
        "ms" { return "Malay" }
        "ja" { return "Japanese" }
        "ko" { return "Korean" }
        default { return $LanguageCode }
    }
}

function Get-CategorySuggestions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookType,

        [Parameter(Mandatory = $true)]
        [string]$ScopeText
    )

    $TypeText = $BookType.ToLowerInvariant()
    $Scope = $ScopeText.ToLowerInvariant()

    if ($TypeText -match "小说" -or $TypeText -match "fiction" -or $Scope -match "novel") {
        return @("Fiction", "Literary Fiction", "Contemporary")
    }

    if ($TypeText -match "教材" -or $TypeText -match "manual" -or $TypeText -match "guide") {
        return @("Education", "Reference", "Professional")
    }

    if ($TypeText -match "科普" -or $TypeText -match "nonfiction" -or $TypeText -match "思想") {
        return @("Nonfiction", "Technology & Society", "Writing & Publishing")
    }

    return @("Nonfiction", "General", "Digital Publishing")
}

function Get-PlatformRecommendedCategories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookType,

        [Parameter(Mandatory = $true)]
        [string]$Audience,

        [Parameter(Mandatory = $true)]
        [string]$ScopeText,

        [Parameter(Mandatory = $true)]
        [string]$CoreThesis
    )

    $Combined = @($BookType, $Audience, $ScopeText, $CoreThesis) -join " "
    $CombinedLower = $Combined.ToLowerInvariant()

    if ($Combined -match "小说|fiction|novel") {
        return [ordered]@{
            amazon = @(
                [ordered]@{ priority = 1; path = "Kindle Books > Literature & Fiction > Literary Fiction"; note = "Primary fiction placement" },
                [ordered]@{ priority = 2; path = "Kindle Books > Literature & Fiction > Contemporary Fiction"; note = "Secondary fiction placement" }
            )
            apple = @(
                [ordered]@{ priority = 1; path = "Fiction & Literature"; note = "Primary Apple Books fiction category" },
                [ordered]@{ priority = 2; path = "Literary Fiction"; note = "Secondary Apple Books fiction category" }
            )
            google = @(
                [ordered]@{ priority = 1; path = "Fiction / Literary"; note = "Primary Google Play Books fiction category" },
                [ordered]@{ priority = 2; path = "Fiction / General"; note = "Secondary Google Play Books fiction category" }
            )
        }
    }

    if ($Combined -match "教育|教材|teaching|education") {
        return [ordered]@{
            amazon = @(
                [ordered]@{ priority = 1; path = "Kindle Books > Education & Teaching > General"; note = "Primary education placement" },
                [ordered]@{ priority = 2; path = "Kindle Books > Education & Teaching > Schools & Teaching"; note = "Secondary education placement" },
                [ordered]@{ priority = 3; path = "Kindle Books > Reference > Writing, Research & Publishing Guides"; note = "Useful when the book includes method instruction" }
            )
            apple = @(
                [ordered]@{ priority = 1; path = "Education"; note = "Primary Apple Books education category" },
                [ordered]@{ priority = 2; path = "Professional & Technical"; note = "Secondary Apple Books technical education category" }
            )
            google = @(
                [ordered]@{ priority = 1; path = "Education / General"; note = "Primary Google Play Books education category" },
                [ordered]@{ priority = 2; path = "Study Aids / General"; note = "Secondary Google Play Books education category" }
            )
        }
    }

    if ($CombinedLower -match "ai|artificial intelligence|technology|digital|computer|sagewrite|writing") {
        return [ordered]@{
            amazon = @(
                [ordered]@{ priority = 1; path = "Kindle Books > Computers & Technology > Computer Science > General"; note = "Best primary fit for this AI and knowledge-production title" },
                [ordered]@{ priority = 2; path = "Kindle Books > Computers & Technology > Applications & Software"; note = "Useful when emphasizing system workflow and tooling" },
                [ordered]@{ priority = 3; path = "Kindle Books > Reference > Writing, Research & Publishing Guides"; note = "Useful when emphasizing writing method and publishing workflow" }
            )
            apple = @(
                [ordered]@{ priority = 1; path = "Computers & Internet"; note = "Primary Apple Books technology category" },
                [ordered]@{ priority = 2; path = "Professional & Technical"; note = "Secondary Apple Books technical nonfiction category" },
                [ordered]@{ priority = 3; path = "Education"; note = "Optional Apple Books category when emphasizing learning and pedagogy" }
            )
            google = @(
                [ordered]@{ priority = 1; path = "Computers / Artificial Intelligence / General"; note = "Primary Google Play Books AI category" },
                [ordered]@{ priority = 2; path = "Language Arts & Disciplines / Writing / General"; note = "Secondary Google Play Books writing-method category" },
                [ordered]@{ priority = 3; path = "Education / General"; note = "Optional Google Play Books category when emphasizing educational use" }
            )
        }
    }

    return [ordered]@{
        amazon = @(
            [ordered]@{ priority = 1; path = "Kindle Books > Nonfiction > General"; note = "Fallback Amazon placement" },
            [ordered]@{ priority = 2; path = "Kindle Books > Reference > Writing, Research & Publishing Guides"; note = "Fallback Amazon writing-method placement" }
        )
        apple = @(
            [ordered]@{ priority = 1; path = "Nonfiction"; note = "Fallback Apple Books category" },
            [ordered]@{ priority = 2; path = "Professional & Technical"; note = "Fallback Apple Books technical category" }
        )
        google = @(
            [ordered]@{ priority = 1; path = "Nonfiction / General"; note = "Fallback Google Play Books category" },
            [ordered]@{ priority = 2; path = "Language Arts & Disciplines / Writing / General"; note = "Fallback Google Play Books writing category" }
        )
    }
}

function Get-UniqueKeywords {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Seeds
    )

    $Seen = @{}
    $Output = @()
    foreach ($Seed in $Seeds) {
        $Value = "$Seed".Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) {
            continue
        }
        if (-not $Seen.ContainsKey($Value)) {
            $Seen[$Value] = $true
            $Output += $Value
        }
        if ($Output.Count -ge 12) {
            break
        }
    }
    return $Output
}

function Get-CleanKeywords {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Seeds
    )

    $Raw = Get-UniqueKeywords -Seeds $Seeds
    $Output = @()
    foreach ($Item in $Raw) {
        $Value = "$Item".Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) {
            continue
        }

        $Value = $Value -replace '[\r\n\t]+', ' '
        $Value = $Value -replace '^[\s\p{P}\p{S}]+', ''
        $Value = $Value -replace '[\s\p{P}\p{S}]+$', ''

        if ([string]::IsNullOrWhiteSpace($Value)) {
            continue
        }

        if ($Value -match '^第.+章$' -or $Value -match '^第.+章[:：]') {
            continue
        }

        if ($Value.Length -lt 2 -or $Value.Length -gt 28) {
            continue
        }

        $Output += $Value
        if ($Output.Count -ge 12) {
            break
        }
    }

    return Get-UniqueKeywords -Seeds $Output
}

function Get-KeywordSuggestions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Title,

        [Parameter(Mandatory = $true)]
        [string]$Subtitle,

        [Parameter(Mandatory = $true)]
        [string]$BookType,

        [Parameter(Mandatory = $true)]
        [string]$Audience,

        [Parameter(Mandatory = $true)]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [string]$CoreThesis,

        [Parameter(Mandatory = $true)]
        [string[]]$ExistingKeywords
    )

    $Seeds = @(
        $Title,
        $Subtitle,
        $BookType,
        "SageWrite",
        "AI writing",
        "artificial intelligence",
        "knowledge creation",
        "knowledge production",
        "human-AI collaboration",
        "structured writing",
        "digital publishing",
        "writing methodology"
    )

    $CleanExisting = @($ExistingKeywords | Where-Object {
        $Value = "$_".Trim()
        (-not [string]::IsNullOrWhiteSpace($Value)) -and
        ($Value.Length -ge 2) -and
        ($Value.Length -le 16) -and
        ($Value -notmatch '^第.+章') -and
        ($Value -notmatch '^第[一二三四五六七八九十0-9]+章') -and
        ($Value -notmatch '^的') -and
        ($Value -notmatch '^[0-9]+') -and
        ($Value -notmatch '篇幅') -and
        ($Value -notmatch '结语')
    })
    $Seeds += $CleanExisting

    return Get-CleanKeywords -Seeds $Seeds
}

function Build-LongDescription {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Hook,

        [Parameter(Mandatory = $true)]
        [string]$Blurb,

        [Parameter(Mandatory = $true)]
        [string]$Audience,

        [Parameter(Mandatory = $true)]
        [string]$Scope
    )

    $Parts = @()
    if ($Hook) {
        $Parts += $Hook.Trim()
    }
    if ($Blurb) {
        $Parts += $Blurb.Trim()
    }
    if ($Audience) {
        $Parts += ("Target readers: " + $Audience.Trim())
    }
    if ($Scope) {
        $Parts += ("Edition scope: " + $Scope.Trim())
    }

    return ($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n`r`n"
}

function Get-FormatAvailability {
    param(
        [Parameter(Mandatory = $true)]
        [psobject]$Files
    )

    $Formats = @()
    if ("$($Files.epub)") { $Formats += "EPUB" }
    if ("$($Files.pdf)") { $Formats += "PDF" }
    if ("$($Files.docx)") { $Formats += "DOCX" }
    return $Formats
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context

$LanguageCode = $Language.Trim().ToLowerInvariant()
if ([string]::IsNullOrWhiteSpace($LanguageCode)) {
    $LanguageCode = "zh"
}

Set-SageCurrentStep -Context $Context -Step "publish_metadata" -Data @{
    language = $LanguageCode
}

$BookRoot = $Context.BookRoot
$PublishRoot = Join-Path $BookRoot ("09_publish\" + $LanguageCode)
$AssetsPath = Join-Path $PublishRoot "publish_assets.json"
$MetadataJsonPath = Join-Path $PublishRoot "publish_metadata.json"
$MetadataMdPath = Join-Path $PublishRoot "publish_metadata.md"

if (-not (Test-Path -LiteralPath $AssetsPath)) {
    Fail-SageStep -Context $Context -Step "publish_metadata" -Message "publish_assets.json not found." -Data @{
        language = $LanguageCode
        assets = $AssetsPath
    }
    Write-Error "publish_assets.json not found: $AssetsPath"
    exit 1
}

if ((Test-Path -LiteralPath $MetadataJsonPath) -and (-not $Force)) {
    Write-Host "publish_metadata.json already exists. Use -Force to regenerate."
    exit 0
}

Ensure-Directory -Path $PublishRoot

$Assets = Get-Content -LiteralPath $AssetsPath -Raw -Encoding UTF8 | ConvertFrom-Json
$Book = $Assets.book
$Marketing = $Assets.marketing
$Discovery = $Assets.discovery

$Title = "$($Book.title)"
$Subtitle = "$($Marketing.subtitle)"
$Author = "$($Book.author)"
$Audience = "$($Book.audience)"
$BookType = "$($Book.type)"
$Style = "$($Book.style)"
$Scope = "$($Book.scope)"
$CoreThesis = "$($Book.core_thesis)"
$Hook = "$($Marketing.hook)"
$Blurb = "$($Marketing.blurb)"
$LanguageLabel = Get-LanguageLabel -LanguageCode $LanguageCode
$Publisher = "SageWrite Digital Publishing"
$Imprint = "SageWrite"
$PublicationDate = (Get-Date).ToString("yyyy-MM-dd")
$Keywords = Get-KeywordSuggestions -Title $Title -Subtitle $Subtitle -BookType $BookType -Audience $Audience -Scope $Scope -CoreThesis $CoreThesis -ExistingKeywords @($Discovery.keywords | ForEach-Object { "$_" })
$Categories = Get-CategorySuggestions -BookType $BookType -ScopeText $Scope
$PlatformRecommendedCategories = Get-PlatformRecommendedCategories -BookType $BookType -Audience $Audience -ScopeText $Scope -CoreThesis $CoreThesis
$LongDescription = Build-LongDescription -Hook $Hook -Blurb $Blurb -Audience $Audience -Scope $Scope
$RightsHolder = if ($Author) { $Author } else { $BookName }
$CopyrightYear = (Get-Date).Year
$RightsStatement = "Copyright (c) $((Get-Date).Year) $RightsHolder. All rights reserved."
$EditionType = "digital"
$Territory = "Worldwide"
$DistributionRights = "Global digital distribution"
$Formats = Get-FormatAvailability -Files $Assets.files
$ChapterCount = if ($null -ne $Discovery.chapter_count) { [int]$Discovery.chapter_count } else { 0 }
$ChapterTitles = @($Discovery.chapter_titles | ForEach-Object { "$_" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

$Metadata = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name = $BookName
    language = $LanguageCode
    language_name = $LanguageLabel
    title = $Title
    subtitle = $Subtitle
    author = $Author
    publisher = $Publisher
    imprint = $Imprint
    publication_date = $PublicationDate
    rights = $RightsStatement
    copyright_holder = $RightsHolder
    copyright_year = $CopyrightYear
    territory = $Territory
    distribution_rights = $DistributionRights
    edition_type = $EditionType
    audience = $Audience
    book_type = $BookType
    style = $Style
    scope = $Scope
    core_thesis = $CoreThesis
    short_description = $Hook
    long_description = $LongDescription
    marketing_tagline = "$($Marketing.tagline)"
    cover_hook = $Hook
    back_cover_blurb = $Blurb
    obi_copy = "$($Marketing.obi_copy)"
    author_bio = "$($Marketing.author_bio)"
    spine_text = "$($Marketing.spine_text)"
    keywords = @($Keywords)
    categories = @($Categories)
    platform_recommended_categories = $PlatformRecommendedCategories
    formats = @($Formats)
    identification = [ordered]@{
        title = $Title
        subtitle = $Subtitle
        author = $Author
        language = $LanguageCode
        language_name = $LanguageLabel
        edition_type = $EditionType
        publication_date = $PublicationDate
        publisher = $Publisher
        imprint = $Imprint
    }
    marketing = [ordered]@{
        tagline = "$($Marketing.tagline)"
        subtitle = $Subtitle
        short_description = $Hook
        long_description = $LongDescription
        cover_hook = $Hook
        back_cover_blurb = $Blurb
        obi_copy = "$($Marketing.obi_copy)"
        author_bio = "$($Marketing.author_bio)"
        spine_text = "$($Marketing.spine_text)"
    }
    rights_metadata = [ordered]@{
        copyright_holder = $RightsHolder
        copyright_year = $CopyrightYear
        rights_statement = $RightsStatement
        territory = $Territory
        distribution_rights = $DistributionRights
        license = "All rights reserved"
        publisher = $Publisher
        imprint = $Imprint
    }
    discovery = [ordered]@{
        keywords = @($Keywords)
        categories = @($Categories)
        platform_recommended_categories = $PlatformRecommendedCategories
        audience = $Audience
        book_type = $BookType
        core_thesis = $CoreThesis
        chapter_count = $ChapterCount
        chapter_titles = @($ChapterTitles)
    }
    distribution = [ordered]@{
        formats = @($Formats)
        primary_format = if ($Formats.Count -gt 0) { $Formats[0] } else { "" }
        target_platforms = @("amazon", "apple", "google")
    }
    source_files = [ordered]@{
        cover = "$($Assets.files.cover)"
        epub = "$($Assets.files.epub)"
        pdf = "$($Assets.files.pdf)"
        docx = "$($Assets.files.docx)"
        assets = "09_publish\$LanguageCode\publish_assets.json"
    }
}

$Metadata | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $MetadataJsonPath -Encoding UTF8

$MdLines = @()
$MdLines += "# Publish Metadata"
$MdLines += ""
$MdLines += "- Title: $Title"
$MdLines += "- Subtitle: $Subtitle"
$MdLines += "- Author: $Author"
$MdLines += "- Language: $LanguageCode ($LanguageLabel)"
$MdLines += "- Publisher: $Publisher"
$MdLines += "- Imprint: $Imprint"
$MdLines += "- Edition type: $EditionType"
$MdLines += "- Publication date: $PublicationDate"
$MdLines += ""
$MdLines += "## Rights"
$MdLines += ""
$MdLines += $RightsStatement
$MdLines += ""
$MdLines += "- Copyright holder: $RightsHolder"
$MdLines += "- Territory: $Territory"
$MdLines += "- Distribution rights: $DistributionRights"
$MdLines += ""
$MdLines += "## Marketing"
$MdLines += ""
$MdLines += "- Tagline: $($Marketing.tagline)"
$MdLines += "- OBI copy: $($Marketing.obi_copy)"
$MdLines += "- Spine text: $($Marketing.spine_text)"
$MdLines += ""
$MdLines += "## Short Description"
$MdLines += ""
$MdLines += $Hook
$MdLines += ""
$MdLines += "## Long Description"
$MdLines += ""
$MdLines += $LongDescription
$MdLines += ""
$MdLines += "## Keywords"
$MdLines += ""
$Keywords | ForEach-Object { $MdLines += "- $_" }
$MdLines += ""
$MdLines += "## Categories"
$MdLines += ""
$Categories | ForEach-Object { $MdLines += "- $_" }
$MdLines += ""
$MdLines += "## Platform Recommended Categories"
$MdLines += ""
$MdLines += "### Amazon"
$MdLines += ""
$PlatformRecommendedCategories.amazon | ForEach-Object { $MdLines += ("- [{0}] {1} - {2}" -f $_.priority, $_.path, $_.note) }
$MdLines += ""
$MdLines += "### Apple"
$MdLines += ""
$PlatformRecommendedCategories.apple | ForEach-Object { $MdLines += ("- [{0}] {1} - {2}" -f $_.priority, $_.path, $_.note) }
$MdLines += ""
$MdLines += "### Google"
$MdLines += ""
$PlatformRecommendedCategories.google | ForEach-Object { $MdLines += ("- [{0}] {1} - {2}" -f $_.priority, $_.path, $_.note) }
$MdLines += ""
$MdLines += "## Formats"
$MdLines += ""
$Formats | ForEach-Object { $MdLines += "- $_" }

$MdLines -join "`r`n" | Set-Content -LiteralPath $MetadataMdPath -Encoding UTF8

Write-Host ""
Write-Host "09b-metadata completed successfully."
Write-Host ("Metadata JSON: " + $MetadataJsonPath)
Write-Host ("Metadata MD:   " + $MetadataMdPath)

Complete-SageStep -Context $Context -Step "publish_metadata" -State "success" -Message "Publish metadata generated." -Data @{
    language = $LanguageCode
    metadata_json = $MetadataJsonPath
    metadata_md = $MetadataMdPath
    keyword_count = $Keywords.Count
    category_count = $Categories.Count
}
