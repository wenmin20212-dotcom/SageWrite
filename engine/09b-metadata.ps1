param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [string]$Language = "zh",

    [switch]$Force
)

[Console]::InputEncoding = [System.Text.Encoding]::UTF8
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

function New-TextFromCodePoints {
    param(
        [Parameter(Mandatory = $true)]
        [int[]]$CodePoints
    )

    return (-join ($CodePoints | ForEach-Object { [char]$_ }))
}

function Get-LanguageLabel {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LanguageCode
    )

    switch ($LanguageCode.Trim().ToLowerInvariant()) {
        "zh" { return (New-TextFromCodePoints @(0x4E2D, 0x6587)) }
        "en" { return "English" }
        "fr" { return "French" }
        "de" { return "German" }
        "es" { return "Spanish" }
        "ms" { return "Malay" }
        "ja" { return (New-TextFromCodePoints @(0x65E5, 0x672C, 0x8A9E)) }
        "ko" { return "Korean" }
        default { return $LanguageCode }
    }
}

function Get-LanguageProfile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LanguageCode,

        [Parameter(Mandatory = $true)]
        [hashtable]$ZhLexicon
    )

    switch ($LanguageCode.Trim().ToLowerInvariant()) {
        "zh" {
            return [ordered]@{
                publisher = $ZhLexicon.publisher
                imprint = $ZhLexicon.imprint
                edition_type = $ZhLexicon.edition_type
                territory = $ZhLexicon.territory
                distribution_rights = $ZhLexicon.distribution_rights
                rights_prefix = $ZhLexicon.copyright_reserved
                rights_suffix = $ZhLexicon.all_rights_reserved
                target_readers = $ZhLexicon.target_readers
                writing_scope = $ZhLexicon.writing_scope
            }
        }
        "ja" {
            return [ordered]@{
                publisher = "SageWrite Digital Publishing"
                imprint = "SageWrite"
                edition_type = New-TextFromCodePoints @(0x96FB, 0x5B50, 0x7248)
                territory = New-TextFromCodePoints @(0x4E16, 0x754C, 0x914D, 0x4FE1)
                distribution_rights = New-TextFromCodePoints @(0x30C7, 0x30B8, 0x30BF, 0x30EB, 0x914D, 0x4FE1, 0x6A29)
                rights_prefix = New-TextFromCodePoints @(0x8457, 0x4F5C, 0x6A29)
                rights_suffix = New-TextFromCodePoints @(0x7121, 0x65AD, 0x8EE2, 0x8F09, 0x7981, 0x6B62)
                target_readers = New-TextFromCodePoints @(0x60F3, 0x5B9A, 0x8AAD, 0x8005, 0xFF1A)
                writing_scope = New-TextFromCodePoints @(0x57F7, 0x7B46, 0x7BC4, 0x56F2, 0xFF1A)
            }
        }
        "ms" {
            return [ordered]@{
                publisher = "Penerbitan Digital SageWrite"
                imprint = "SageWrite"
                edition_type = "Edisi digital"
                territory = "Edaran global"
                distribution_rights = "Hak edaran digital"
                rights_prefix = "Hak cipta"
                rights_suffix = "Semua hak terpelihara"
                target_readers = "Pembaca sasaran:"
                writing_scope = "Skop penulisan:"
            }
        }
        default {
            return [ordered]@{
                publisher = "SageWrite Digital Publishing"
                imprint = "SageWrite"
                edition_type = "digital"
                territory = "Worldwide"
                distribution_rights = "Global digital distribution"
                rights_prefix = "Copyright"
                rights_suffix = "All rights reserved."
                target_readers = "Target readers:"
                writing_scope = "Edition scope:"
            }
        }
    }
}

function Get-ZhLexicon {
    return [ordered]@{
        target_readers = New-TextFromCodePoints @(0x76EE, 0x6807, 0x8BFB, 0x8005, 0xFF1A)
        writing_scope = New-TextFromCodePoints @(0x5199, 0x4F5C, 0x8303, 0x56F4, 0xFF1A)
        copyright_reserved = New-TextFromCodePoints @(0x7248, 0x6743, 0x6240, 0x6709)
        all_rights_reserved = New-TextFromCodePoints @(0x4FDD, 0x7559, 0x6240, 0x6709, 0x6743, 0x5229)
        publisher = "SageWrite" + (New-TextFromCodePoints @(0x6570, 0x5B57, 0x51FA, 0x7248))
        imprint = "SageWrite"
        edition_type = New-TextFromCodePoints @(0x6570, 0x5B57, 0x7248)
        territory = New-TextFromCodePoints @(0x5168, 0x7403, 0x53D1, 0x884C)
        distribution_rights = New-TextFromCodePoints @(0x6570, 0x5B57, 0x53D1, 0x884C, 0x6743)
        keyword_1 = New-TextFromCodePoints @(0x4EBA, 0x5DE5, 0x667A, 0x80FD, 0x5199, 0x4F5C)
        keyword_2 = New-TextFromCodePoints @(0x77E5, 0x8BC6, 0x521B, 0x4F5C)
        keyword_3 = New-TextFromCodePoints @(0x77E5, 0x8BC6, 0x751F, 0x4EA7)
        keyword_4 = New-TextFromCodePoints @(0x4EBA, 0x673A, 0x534F, 0x540C, 0x5199, 0x4F5C)
        keyword_5 = New-TextFromCodePoints @(0x7ED3, 0x6784, 0x5316, 0x5199, 0x4F5C)
        keyword_6 = New-TextFromCodePoints @(0x6570, 0x5B57, 0x51FA, 0x7248)
        keyword_7 = New-TextFromCodePoints @(0x5199, 0x4F5C, 0x65B9, 0x6CD5)
        keyword_8 = New-TextFromCodePoints @(0x5185, 0x5BB9, 0x751F, 0x6210)
        keyword_9 = New-TextFromCodePoints @(0x77E5, 0x8BC6, 0x5DE5, 0x4F5C)
        category_1 = New-TextFromCodePoints @(0x975E, 0x865A, 0x6784)
        category_2 = New-TextFromCodePoints @(0x4EBA, 0x5DE5, 0x667A, 0x80FD)
        category_3 = New-TextFromCodePoints @(0x5199, 0x4F5C, 0x65B9, 0x6CD5)
        category_4 = New-TextFromCodePoints @(0x6570, 0x5B57, 0x51FA, 0x7248)
        stop_preface = New-TextFromCodePoints @(0x524D, 0x8A00)
        stop_epilogue = New-TextFromCodePoints @(0x7ED3, 0x8BED)
        stop_length = New-TextFromCodePoints @(0x7BC7, 0x5E45, 0x7EA6)
    }
}

function Get-UniqueList {
    param(
        [AllowEmptyCollection()]
        [string[]]$Items
    )

    $Seen = @{}
    $Output = New-Object System.Collections.Generic.List[string]
    foreach ($Item in $Items) {
        $Value = "$Item".Trim()
        if ([string]::IsNullOrWhiteSpace($Value)) {
            continue
        }

        if (-not $Seen.ContainsKey($Value)) {
            $Seen[$Value] = $true
            $Output.Add($Value)
        }
    }

    return @($Output)
}

function Get-ChineseFragments {
    param(
        [AllowEmptyString()]
        [string[]]$Texts,

        [Parameter(Mandatory = $true)]
        [hashtable]$Lexicon
    )

    $Output = New-Object System.Collections.Generic.List[string]
    foreach ($Text in $Texts) {
        $Raw = "$Text".Trim()
        if ([string]::IsNullOrWhiteSpace($Raw)) {
            continue
        }

        $Normalized = $Raw -replace '^[^:]{1,24}[\uFF1A:]\s*', ''
        $Parts = [regex]::Split($Normalized, '[^\u3400-\u9FFF]+')
        foreach ($Part in $Parts) {
            $Value = "$Part".Trim()
            if ([string]::IsNullOrWhiteSpace($Value)) {
                continue
            }

            $Value = $Value -replace '^[\u7684\u4E0E\u53CA\u548C\u5411\u4E3A\u5176]+', ''
            $Value = $Value -replace '[\u7684\u4E0E\u53CA\u548C\u4EEC\u8005]+$', ''
            $Value = "$Value".Trim()

            if ([string]::IsNullOrWhiteSpace($Value)) {
                continue
            }

            if ($Value.Length -lt 2 -or $Value.Length -gt 16) {
                continue
            }

            if (@(
                    $Lexicon.stop_preface,
                    $Lexicon.stop_epilogue,
                    $Lexicon.stop_length
                ) -contains $Value) {
                continue
            }

            if ($Value -match '^[\u7B2C\u4E00-\u9FFF0-9]{1,8}\u7AE0$') {
                continue
            }

            $Output.Add($Value)
        }
    }

    return Get-UniqueList -Items @($Output)
}

function Get-GenericKeywordCandidates {
    param(
        [AllowEmptyString()]
        [string[]]$Texts
    )

    $Output = New-Object System.Collections.Generic.List[string]
    foreach ($Text in $Texts) {
        $RawValue = "$Text".Trim()
        if ([string]::IsNullOrWhiteSpace($RawValue)) {
            continue
        }

        $Candidates = New-Object System.Collections.Generic.List[string]
        $Candidates.Add($RawValue)

        if ($RawValue -match '[\uFF1A:]') {
            $Candidates.Add(($RawValue -replace '^[^:\uFF1A]{1,30}[\uFF1A:]\s*', ''))
        }

        foreach ($Candidate in $Candidates) {
            $Value = "$Candidate".Trim()
            if ([string]::IsNullOrWhiteSpace($Value)) {
                continue
            }

            $Value = $Value -replace '(?i)^(chapter|part|section|bab)\s+([0-9ivxlcdm]+|first|second|third|fourth|fifth|sixth|seventh|eighth|ninth|tenth|pertama|kedua|ketiga|keempat|kelima|keenam|ketujuh|kelapan|kesembilan|kesepuluh)[:.\-]?\s*', ''
            $Value = $Value -replace '^\d+(\.\d+)*\s*', ''
            $Value = $Value -replace '^[\u7B2C][0-9\u4E00-\u9FFF]{1,8}[\u7AE0][\uFF1A:]?\s*', ''
            $Value = $Value -replace '\s+', ' '
            $Value = "$Value".Trim()

            if ([string]::IsNullOrWhiteSpace($Value)) {
                continue
            }

            if ($Value.Length -gt 40) {
                $PrimarySegment = ([regex]::Split($Value, '\s*[,;.!?]\s*|\s+-\s+')[0]).Trim()
                if (-not [string]::IsNullOrWhiteSpace($PrimarySegment)) {
                    $Value = $PrimarySegment
                }
            }

            if ($Value.Length -gt 40) {
                $Value = $Value.Substring(0, 40).Trim()
                $Value = $Value -replace '\s+\S*$', ''
                $Value = "$Value".Trim()
            }

            if ($Value.Length -lt 2 -or $Value.Length -gt 40) {
                continue
            }

            $Output.Add($Value)
        }
    }

    return Get-UniqueList -Items @($Output)
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

    if ($CombinedLower -match "fiction|novel") {
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

    if ($CombinedLower -match "education|teaching") {
        return [ordered]@{
            amazon = @(
                [ordered]@{ priority = 1; path = "Kindle Books > Education & Teaching > General"; note = "Primary education placement" },
                [ordered]@{ priority = 2; path = "Kindle Books > Education & Teaching > Schools & Teaching"; note = "Secondary education placement" },
                [ordered]@{ priority = 3; path = "Kindle Books > Reference > Writing, Research & Publishing Guides"; note = "Method-oriented fallback" }
            )
            apple = @(
                [ordered]@{ priority = 1; path = "Education"; note = "Primary Apple Books education category" },
                [ordered]@{ priority = 2; path = "Professional & Technical"; note = "Secondary Apple Books technical category" }
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

function Get-KeywordSuggestions {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LanguageCode,

        [Parameter(Mandatory = $true)]
        [string]$Title,

        [AllowEmptyString()]
        [string]$Subtitle,

        [AllowEmptyString()]
        [string]$BookType,

        [AllowEmptyString()]
        [string]$Audience,

        [AllowEmptyString()]
        [string]$Scope,

        [AllowEmptyString()]
        [string]$CoreThesis,

        [AllowEmptyString()]
        [string]$Hook,

        [AllowEmptyString()]
        [string]$Blurb,

        [AllowEmptyCollection()]
        [string[]]$ChapterTitles,

        [AllowEmptyCollection()]
        [string[]]$ExistingKeywords,

        [Parameter(Mandatory = $true)]
        [hashtable]$Lexicon
    )

    $NormalizedLanguage = "$LanguageCode".Trim().ToLowerInvariant()
    if ($NormalizedLanguage -ne "zh") {
        $Localized = @()
        $Localized += Get-GenericKeywordCandidates -Texts @($Title, $Subtitle, $BookType)
        $Localized += Get-GenericKeywordCandidates -Texts $ExistingKeywords
        $Localized += Get-GenericKeywordCandidates -Texts @($Hook, $Blurb, $Audience, $Scope, $CoreThesis)
        $Localized += Get-GenericKeywordCandidates -Texts $ChapterTitles
        $Keywords = Get-UniqueList -Items $Localized

        if ($Keywords.Count -lt 9) {
            $FallbackKeywords = @()
            switch ($NormalizedLanguage) {
                "ms" {
                    $FallbackKeywords = @(
                        "penulisan AI",
                        "penciptaan pengetahuan",
                        "kolaborasi manusia mesin",
                        "aliran kerja penulisan",
                        "falsafah teknologi",
                        "pendidikan digital",
                        "struktur penulisan",
                        "inovasi pengetahuan",
                        "SageWrite"
                    )
                }
                "en" {
                    $FallbackKeywords = @(
                        "AI writing",
                        "knowledge creation",
                        "human AI collaboration",
                        "writing workflow",
                        "technology philosophy",
                        "digital publishing",
                        "structured writing",
                        "knowledge innovation",
                        "SageWrite"
                    )
                }
            }

            if ($FallbackKeywords.Count -gt 0) {
                $Keywords = Get-UniqueList -Items (@($Keywords) + @($FallbackKeywords))
            }
        }

        return @($Keywords | Select-Object -First 12)
    }

    $Preferred = @()
    $Preferred += Get-ChineseFragments -Texts @($Title, $Subtitle, $BookType) -Lexicon $Lexicon
    $Preferred += @(
        $Lexicon.keyword_1,
        $Lexicon.keyword_2,
        $Lexicon.keyword_3,
        $Lexicon.keyword_4,
        $Lexicon.keyword_5,
        $Lexicon.keyword_6,
        $Lexicon.keyword_7,
        $Lexicon.keyword_8,
        $Lexicon.keyword_9
    )
    $Preferred += Get-ChineseFragments -Texts @($Hook, $Blurb, $Audience, $Scope, $CoreThesis) -Lexicon $Lexicon
    $Preferred += Get-ChineseFragments -Texts $ChapterTitles -Lexicon $Lexicon
    $Preferred += Get-ChineseFragments -Texts $ExistingKeywords -Lexicon $Lexicon

    $Keywords = Get-UniqueList -Items $Preferred
    if ($Keywords.Count -lt 9) {
        $Keywords = Get-UniqueList -Items (@($Keywords) + @(
                $Lexicon.keyword_1,
                $Lexicon.keyword_2,
                $Lexicon.keyword_3,
                $Lexicon.keyword_4,
                $Lexicon.keyword_5,
                $Lexicon.keyword_6,
                $Lexicon.keyword_7,
                $Lexicon.keyword_8,
                $Lexicon.keyword_9
            ))
    }

    return @($Keywords | Select-Object -First 12)
}

function Get-SourceCategories {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LanguageCode,

        [Parameter(Mandatory = $true)]
        [string]$BookType,

        [Parameter(Mandatory = $true)]
        [string[]]$Keywords,

        [Parameter(Mandatory = $true)]
        [hashtable]$Lexicon
    )

    if ("$LanguageCode".Trim().ToLowerInvariant() -ne "zh") {
        return @((Get-UniqueList -Items (@($BookType) + @($Keywords | Select-Object -First 4))) | Select-Object -First 6)
    }

    $Categories = Get-UniqueList -Items @(
        $BookType,
        $Lexicon.category_1,
        $Lexicon.category_2,
        $Lexicon.category_3,
        $Lexicon.category_4,
        $Keywords[0],
        $Keywords[1]
    )

    return @($Categories | Select-Object -First 6)
}

function Build-LongDescription {
    param(
        [Parameter(Mandatory = $true)]
        [string]$LanguageCode,

        [AllowEmptyString()]
        [string]$Hook,

        [AllowEmptyString()]
        [string]$Blurb,

        [AllowEmptyString()]
        [string]$Audience,

        [AllowEmptyString()]
        [string]$Scope,

        [Parameter(Mandatory = $true)]
        [hashtable]$Lexicon
    )

    $Parts = New-Object System.Collections.Generic.List[string]

    foreach ($Value in @($Hook, $Blurb)) {
        $Text = "$Value".Trim()
        if (-not [string]::IsNullOrWhiteSpace($Text)) {
            $Parts.Add($Text)
        }
    }

    if ([string]::IsNullOrWhiteSpace($Audience) -eq $false) {
        if ("$LanguageCode".Trim().ToLowerInvariant() -eq "zh") {
            $Parts.Add(($Lexicon.target_readers + $Audience.Trim()))
        } else {
            $Parts.Add($Audience.Trim())
        }
    }

    if ([string]::IsNullOrWhiteSpace($Scope) -eq $false) {
        if ("$LanguageCode".Trim().ToLowerInvariant() -eq "zh") {
            $Parts.Add(($Lexicon.writing_scope + $Scope.Trim()))
        } else {
            $Parts.Add($Scope.Trim())
        }
    }

    return (($Parts | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }) -join "`r`n`r`n")
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

function Build-PublishMetadataMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Metadata
    )

    $Lines = @()
    $Lines += "# Publish Metadata"
    $Lines += ""
    $Lines += "- Title: $($Metadata.title)"
    $Lines += "- Subtitle: $($Metadata.subtitle)"
    $Lines += "- Author: $($Metadata.author)"
    $Lines += "- Language: $($Metadata.language)"
    $Lines += "- Publication Date: $($Metadata.publication_date)"
    $Lines += "- Publisher: $($Metadata.publisher)"
    $Lines += "- Imprint: $($Metadata.imprint)"
    $Lines += "- Edition Type: $($Metadata.edition_type)"
    $Lines += ""
    $Lines += "## Rights"
    $Lines += ""
    $Lines += "$($Metadata.rights)"
    $Lines += ""
    $Lines += "- Copyright Holder: $($Metadata.copyright_holder)"
    $Lines += "- Territory: $($Metadata.territory)"
    $Lines += "- Distribution Rights: $($Metadata.distribution_rights)"
    $Lines += ""
    $Lines += "## Marketing"
    $Lines += ""
    $Lines += "- Tagline: $($Metadata.marketing_tagline)"
    $Lines += "- Cover Hook: $($Metadata.cover_hook)"
    $Lines += "- OBI Copy: $($Metadata.obi_copy)"
    $Lines += "- Spine Text: $($Metadata.spine_text)"
    $Lines += ""
    $Lines += "## Short Description"
    $Lines += ""
    $Lines += "$($Metadata.short_description)"
    $Lines += ""
    $Lines += "## Long Description"
    $Lines += ""
    $Lines += "$($Metadata.long_description)"
    $Lines += ""
    $Lines += "## Back Cover Blurb"
    $Lines += ""
    $Lines += "$($Metadata.back_cover_blurb)"
    $Lines += ""
    $Lines += "## Author Bio"
    $Lines += ""
    $Lines += "$($Metadata.author_bio)"
    $Lines += ""
    $Lines += "## Keywords"
    $Lines += ""
    foreach ($Keyword in @($Metadata.keywords)) {
        $Lines += "- $Keyword"
    }
    $Lines += ""
    $Lines += "## Categories"
    $Lines += ""
    foreach ($Category in @($Metadata.categories)) {
        $Lines += "- $Category"
    }
    $Lines += ""
    $Lines += "## Formats"
    $Lines += ""
    foreach ($Format in @($Metadata.formats)) {
        $Lines += "- $Format"
    }

    return ($Lines -join "`r`n")
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
$Lexicon = Get-ZhLexicon

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
$LanguageProfile = Get-LanguageProfile -LanguageCode $LanguageCode -ZhLexicon $Lexicon
$Publisher = "$($LanguageProfile.publisher)"
$Imprint = "$($LanguageProfile.imprint)"
$PublicationDate = (Get-Date).ToString("yyyy-MM-dd")
$Formats = Get-FormatAvailability -Files $Assets.files
$ChapterCount = if ($null -ne $Discovery.chapter_count) { [int]$Discovery.chapter_count } else { 0 }
$ChapterTitles = @($Discovery.chapter_titles | ForEach-Object { "$_" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$ExistingKeywords = @($Discovery.keywords | ForEach-Object { "$_" } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$Keywords = Get-KeywordSuggestions -LanguageCode $LanguageCode -Title $Title -Subtitle $Subtitle -BookType $BookType -Audience $Audience -Scope $Scope -CoreThesis $CoreThesis -Hook $Hook -Blurb $Blurb -ChapterTitles $ChapterTitles -ExistingKeywords $ExistingKeywords -Lexicon $Lexicon
$Categories = Get-SourceCategories -LanguageCode $LanguageCode -BookType $BookType -Keywords $Keywords -Lexicon $Lexicon
$PlatformRecommendedCategories = Get-PlatformRecommendedCategories -BookType $BookType -Audience $Audience -ScopeText $Scope -CoreThesis $CoreThesis
$PlatformSelectedCategories = [ordered]@{
    amazon = if ($PlatformRecommendedCategories.amazon.Count -gt 0) { "$($PlatformRecommendedCategories.amazon[0].path)" } else { "" }
    apple = if ($PlatformRecommendedCategories.apple.Count -gt 0) { "$($PlatformRecommendedCategories.apple[0].path)" } else { "" }
    google = if ($PlatformRecommendedCategories.google.Count -gt 0) { "$($PlatformRecommendedCategories.google[0].path)" } else { "" }
}
$LongDescription = Build-LongDescription -LanguageCode $LanguageCode -Hook $Hook -Blurb $Blurb -Audience $Audience -Scope $Scope -Lexicon $Lexicon
$RightsHolder = if ($Author) { $Author } else { $BookName }
$CopyrightYear = (Get-Date).Year
$RightsStatement = "{0} (C) {1} {2} {3}" -f $LanguageProfile.rights_prefix, $CopyrightYear, $RightsHolder, $LanguageProfile.rights_suffix
$EditionType = "$($LanguageProfile.edition_type)"
$Territory = "$($LanguageProfile.territory)"
$DistributionRights = "$($LanguageProfile.distribution_rights)"

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
    platform_selected_categories = $PlatformSelectedCategories
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
        platform_selected_categories = $PlatformSelectedCategories
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
$MetadataMarkdown = Build-PublishMetadataMarkdown -Metadata $Metadata
$MetadataMarkdown | Set-Content -LiteralPath $MetadataMdPath -Encoding UTF8

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
