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
