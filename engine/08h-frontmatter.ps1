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

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Assert-FileExists {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Description
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "$Description not found: $Path"
    }
}

function Read-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Assert-FileExists -Path $Path -Description "JSON file"
    $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
    if ([string]::IsNullOrWhiteSpace($raw)) {
        throw "JSON file is empty: $Path"
    }
    return $raw | ConvertFrom-Json
}

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $json = $Data | ConvertTo-Json -Depth 40
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Write-TextUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Content,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Get-StringValue {
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )
    if ($null -eq $Value) {
        return ""
    }
    return "$Value"
}

function Read-FrontMatterValue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,
        [Parameter(Mandatory = $true)]
        [string]$Key
    )

    $pattern = '^\s*' + [Regex]::Escape($Key) + '\s*:\s*(.+?)\s*$'
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ($line -match $pattern) {
            return $Matches[1].Trim().Trim('"').Trim("'")
        }
    }
    return ""
}

function Get-DisplayAuthor {
    param(
        [string]$Primary,
        [string]$Fallback
    )
    if (-not [string]::IsNullOrWhiteSpace($Primary)) {
        return $Primary.Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($Fallback)) {
        return $Fallback.Trim()
    }
    return "Author TBD"
}

function Get-PreferredCoverAsset {
    param(
        [Parameter(Mandatory = $true)]
        [string]$BookRoot,
        [Parameter(Mandatory = $true)]
        [string]$CoverRoot
    )

    $candidatePaths = @(
        (Join-Path $CoverRoot "final\cover_final_front.png"),
        (Join-Path $CoverRoot "layout\cover_front_v1.png"),
        (Join-Path $CoverRoot "drafts\candidate_01.png")
    )

    foreach ($path in $candidatePaths) {
        if (Test-Path -LiteralPath $path) {
            $relative = $path.Substring($BookRoot.Length).TrimStart('\')
            return ($relative -replace '\\', '/')
        }
    }

    return ""
}

function Resolve-CoverInputRoot {
    param(
        [Parameter(Mandatory = $true)]
        [string]$CoverBaseRoot,
        [Parameter(Mandatory = $true)]
        [string]$Edition
    )

    $EditionRoot = Join-Path $CoverBaseRoot $Edition
    $EditionBrief = Join-Path $EditionRoot "brief\cover_brief.json"
    $LegacyBrief = Join-Path $CoverBaseRoot "brief\cover_brief.json"

    if (Test-Path -LiteralPath $EditionBrief) {
        return $EditionRoot
    }
    if (($Edition -eq "ebook") -and (Test-Path -LiteralPath $LegacyBrief)) {
        return $CoverBaseRoot
    }
    return $EditionRoot
}

function New-MetadataBlock {
    param(
        [Parameter(Mandatory = $true)]
        [hashtable]$Fields
    )

    $lines = @("---")
    foreach ($key in $Fields.Keys) {
        $value = Get-StringValue -Value $Fields[$key]
        $value = $value -replace '"', '\"'
        $lines += ("{0}: ""{1}""" -f $key, $value)
    }
    $lines += "---"
    return ($lines -join "`r`n")
}

function Build-CoverPageMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Edition,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Subtitle,
        [Parameter(Mandatory = $true)]
        [string]$Author,
        [string]$Tagline,
        [string]$CoverAsset
    )

    $meta = New-MetadataBlock -Fields @{
        page_role = "cover_page"
        edition = $Edition
        render_hint = "cover_page"
        preferred_cover_asset = $CoverAsset
        title = $Title
        subtitle = $Subtitle
        author = $Author
        tagline = $Tagline
    }

    $lines = @(
        $meta
    )

    if (-not [string]::IsNullOrWhiteSpace($CoverAsset)) {
        $lines += ""
        $lines += ("![{0}]({1})" -f $Title, $CoverAsset)
        $lines += ""
        $lines += "<div style=""text-align:center;"">"
        $lines += "<strong>$Title</strong>"
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
            $lines += ""
            $lines += "$Subtitle"
        }
        $lines += ""
        $lines += "$Author"
        if (-not [string]::IsNullOrWhiteSpace($Tagline)) {
            $lines += ""
            $lines += "$Tagline"
        }
        $lines += "</div>"
    }
    else {
        $lines += ""
        $lines += "# $Title"
        if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
            $lines += ""
            $lines += "## $Subtitle"
        }
        $lines += ""
        $lines += "$Author"
        if (-not [string]::IsNullOrWhiteSpace($Tagline)) {
            $lines += ""
            $lines += "> $Tagline"
        }
    }

    return ($lines -join "`r`n")
}

function Build-TitlePageMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Edition,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Subtitle,
        [Parameter(Mandatory = $true)]
        [string]$Author
    )

    $meta = New-MetadataBlock -Fields @{
        page_role = "title_page"
        edition = $Edition
        render_hint = "title_page"
        title = $Title
        subtitle = $Subtitle
        author = $Author
    }

    $lines = @(
        $meta,
        "",
        "# $Title"
    )

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        $lines += ""
        $lines += "## $Subtitle"
    }

    $lines += ""
    $lines += "Author: $Author"
    $lines += ""
    $lines += "SageWrite Ebook Edition"

    return ($lines -join "`r`n")
}

function Build-CopyrightPageMarkdown {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Edition,
        [Parameter(Mandatory = $true)]
        [string]$Title,
        [string]$Subtitle,
        [Parameter(Mandatory = $true)]
        [string]$Author,
        [Parameter(Mandatory = $true)]
        [string]$GeneratedAt,
        [Parameter(Mandatory = $true)]
        [string]$CopyrightYear
    )

    $meta = New-MetadataBlock -Fields @{
        page_role = "copyright_page"
        edition = $Edition
        render_hint = "copyright_page"
        title = $Title
        subtitle = $Subtitle
        author = $Author
        generated_at = $GeneratedAt
    }

    $lines = @(
        $meta,
        "",
        "# Copyright Page",
        "",
        "Title: $Title"
    )

    if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
        $lines += "Subtitle: $Subtitle"
    }

    $lines += "Author: $Author"
    $lines += "Edition: SageWrite Ebook Edition"
    $lines += "Generated at: $GeneratedAt"
    $lines += "System: SageWrite 08 Frontmatter"
    $lines += ""
    $lines += "Copyright (c) $CopyrightYear $Author"
    $lines += "All rights reserved."
    $lines += ""
    $lines += "This page is an ebook copyright-page draft. Add ISBN, publisher, CIP, printing details, or price later if the book enters formal publication."
    $lines += "No unauthorized copying, redistribution, or commercial use is permitted."

    return ($lines -join "`r`n")
}

$EnginePath            = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot              = Split-Path -Parent $EnginePath
$ClawRoot              = Split-Path -Parent $SageRoot
$WorkspaceRoot         = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot              = Join-Path $WorkspaceRoot "sagewrite\book"
$BriefRoot             = Join-Path $BookRoot "00_brief"
$CoverBaseRoot         = Join-Path $BookRoot "07_cover"
$CoverRoot             = Resolve-CoverInputRoot -CoverBaseRoot $CoverBaseRoot -Edition $Edition
$CoverBriefRoot        = Join-Path $CoverRoot "brief"
$FrontmatterBaseRoot   = Join-Path $BookRoot "00_frontmatter"
$FrontmatterRoot       = Join-Path $FrontmatterBaseRoot $Edition
$LogRoot               = Join-Path $BookRoot "logs"

$ObjectivePath         = Join-Path $BriefRoot "objective.md"
$BriefJsonPath         = Join-Path $CoverBriefRoot "cover_brief.json"
$CopyJsonPath          = Join-Path $CoverBriefRoot "cover_copy.json"
$ManifestPath          = Join-Path $FrontmatterRoot "frontmatter_manifest.json"
$CoverPagePath         = Join-Path $FrontmatterRoot "cover_page.md"
$TitlePagePath         = Join-Path $FrontmatterRoot "title_page.md"
$CopyrightPagePath     = Join-Path $FrontmatterRoot "copyright_page.md"
$LogPath               = Join-Path $LogRoot "08h-frontmatter.log"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $FrontmatterBaseRoot
Ensure-Directory -Path $FrontmatterRoot
Ensure-Directory -Path $LogRoot

Assert-FileExists -Path $ObjectivePath -Description "objective.md"
Assert-FileExists -Path $BriefJsonPath -Description "cover_brief.json"
Assert-FileExists -Path $CopyJsonPath -Description "cover_copy.json"

if ((Test-Path -LiteralPath $ManifestPath) -and (-not $Force)) {
    Write-Host "frontmatter_manifest.json already exists. Use -Force to regenerate."
    exit 0
}

$Brief = Read-JsonUtf8 -Path $BriefJsonPath
$Copy = Read-JsonUtf8 -Path $CopyJsonPath

$DerivedTitle = Read-FrontMatterValue -Path $ObjectivePath -Key "title"
$DerivedAuthor = Read-FrontMatterValue -Path $ObjectivePath -Key "author"

$ResolvedTitle = if (-not [string]::IsNullOrWhiteSpace($Title)) {
    $Title
} elseif (-not [string]::IsNullOrWhiteSpace((Get-StringValue -Value $Brief.cover_text.title))) {
    Get-StringValue -Value $Brief.cover_text.title
} else {
    $DerivedTitle
}

if ([string]::IsNullOrWhiteSpace($ResolvedTitle)) {
    throw "Unable to resolve frontmatter title."
}

$ResolvedSubtitle = if (-not [string]::IsNullOrWhiteSpace($Subtitle)) {
    $Subtitle
} elseif (-not [string]::IsNullOrWhiteSpace((Get-StringValue -Value $Copy.selected.subtitle))) {
    Get-StringValue -Value $Copy.selected.subtitle
} else {
    Get-StringValue -Value $Brief.cover_text.subtitle
}

$ResolvedAuthor = Get-DisplayAuthor -Primary $Author -Fallback $DerivedAuthor
$ResolvedTagline = Get-StringValue -Value $Copy.selected.marketing_tagline
$PreferredCoverAsset = Get-PreferredCoverAsset -BookRoot $BookRoot -CoverRoot $CoverRoot
$GeneratedAt = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
$CopyrightYear = (Get-Date).ToString("yyyy")

$CoverPageMarkdown = Build-CoverPageMarkdown `
    -Edition $Edition `
    -Title $ResolvedTitle `
    -Subtitle $ResolvedSubtitle `
    -Author $ResolvedAuthor `
    -Tagline $ResolvedTagline `
    -CoverAsset $PreferredCoverAsset

$TitlePageMarkdown = Build-TitlePageMarkdown `
    -Edition $Edition `
    -Title $ResolvedTitle `
    -Subtitle $ResolvedSubtitle `
    -Author $ResolvedAuthor

$CopyrightPageMarkdown = Build-CopyrightPageMarkdown `
    -Edition $Edition `
    -Title $ResolvedTitle `
    -Subtitle $ResolvedSubtitle `
    -Author $ResolvedAuthor `
    -GeneratedAt $GeneratedAt `
    -CopyrightYear $CopyrightYear

Write-TextUtf8 -Content $CoverPageMarkdown -Path $CoverPagePath
Write-TextUtf8 -Content $TitlePageMarkdown -Path $TitlePagePath
Write-TextUtf8 -Content $CopyrightPageMarkdown -Path $CopyrightPagePath

$Manifest = [ordered]@{
    generated_at = $GeneratedAt
    book_name = $BookName
    edition = $Edition
    preferred_cover_asset = $PreferredCoverAsset
    files = @(
        [ordered]@{ role = "cover_page"; file = "cover_page.md"; path = $CoverPagePath },
        [ordered]@{ role = "title_page"; file = "title_page.md"; path = $TitlePagePath },
        [ordered]@{ role = "copyright_page"; file = "copyright_page.md"; path = $CopyrightPagePath }
    )
}

Write-JsonUtf8 -Data $Manifest -Path $ManifestPath

Write-Host "Frontmatter pages generated:"
Write-Host (" - " + $CoverPagePath)
Write-Host (" - " + $TitlePagePath)
Write-Host (" - " + $CopyrightPagePath)
