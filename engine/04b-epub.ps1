param(
    [Parameter(Mandatory = $true)]
    [string]$BookName
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"
chcp 65001 | Out-Null
Add-Type -AssemblyName System.IO.Compression.FileSystem

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Add-Issue {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Type,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [string]$File = ""
    )

    $script:Issues += [PSCustomObject]@{
        Type    = $Type
        File    = $File
        Message = $Message
    }
}

function Add-CheckResult {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Pass", "Warning", "Error", "Info")]
        [string]$Status,

        [Parameter(Mandatory = $true)]
        [string]$Detail
    )

    $script:Checks += [PSCustomObject]@{
        Name   = $Name
        Status = $Status
        Detail = $Detail
    }
}

function Get-LocalizedStatus {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    switch ($Status) {
        "Pass"    { "PASS" }
        "Warning" { "WARNING" }
        "Error"   { "ERROR" }
        "Info"    { "INFO" }
        default   { $Status }
    }
}

function Read-ZipEntryText {
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Compression.ZipArchive]$Zip,

        [Parameter(Mandatory = $true)]
        [string]$EntryName
    )

    $Entry = $Zip.Entries | Where-Object FullName -eq $EntryName | Select-Object -First 1
    if ($null -eq $Entry) {
        return $null
    }

    $Reader = New-Object System.IO.StreamReader($Entry.Open())
    try {
        return $Reader.ReadToEnd()
    }
    finally {
        $Reader.Dispose()
    }
}

function Get-PlainText {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Html
    )

    $Text = $Html -replace '(?is)<script.*?</script>', ''
    $Text = $Text -replace '(?is)<style.*?</style>', ''
    $Text = $Text -replace '(?is)<[^>]+>', ' '
    $Text = [System.Net.WebUtility]::HtmlDecode($Text)
    return ($Text -replace '\s+', ' ').Trim()
}

function Test-ContainsCjk {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Text
    )

    return $Text -match '[\p{IsCJKUnifiedIdeographs}]'
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "edit_epub" -Data @{}

$WorkspaceRoot = $Context.WorkspaceRoot
$BookRoot = $Context.BookRoot
$OutputRoot = Join-Path $BookRoot "04_output"
$LogRoot = $Context.LogRoot
$EpubPath = Join-Path $OutputRoot "$BookName`_full.epub"

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$script:Issues = @()
$script:Checks = @()

if (!(Test-Path $WorkspaceRoot)) {
    Fail-SageStep -Context $Context -Step "edit_epub" -Message "Workspace not found." -Data @{ workspace = $WorkspaceRoot }
    Write-Error "Workspace not found: $WorkspaceRoot"
    exit 1
}

Add-CheckResult -Name "1. Workspace check" -Status "Pass" -Detail "Workspace found: $WorkspaceRoot"

if (!(Test-Path $OutputRoot)) {
    Add-Issue -Type "Error" -Message "04_output folder not found." -File $OutputRoot
    Add-CheckResult -Name "2. Output folder check" -Status "Error" -Detail "04_output folder not found."
}
else {
    Add-CheckResult -Name "2. Output folder check" -Status "Pass" -Detail "Output folder found: $OutputRoot"
}

if (!(Test-Path $EpubPath)) {
    Add-Issue -Type "Error" -Message "EPUB output file not found." -File $EpubPath
    Add-CheckResult -Name "3. EPUB file check" -Status "Error" -Detail "EPUB output file not found."
}
else {
    Add-CheckResult -Name "3. EPUB file check" -Status "Pass" -Detail "EPUB file found: $EpubPath"
}

$Zip = $null
$ContentOpf = $null
$NavXhtml = $null
$TitlePageXhtml = $null
$SpineRefs = @()
$ManifestHrefMap = @{}
$ChapterEntries = @()
$TitleText = ""
$CreatorText = ""
$LanguageText = ""
$TocHrefTargets = @()

if (Test-Path $EpubPath) {
    try {
        $Zip = [System.IO.Compression.ZipFile]::OpenRead($EpubPath)
        Add-CheckResult -Name "4. EPUB archive integrity check" -Status "Pass" -Detail "EPUB archive opened successfully."

        $RequiredEntries = @(
            "mimetype",
            "META-INF/container.xml",
            "EPUB/content.opf",
            "EPUB/nav.xhtml",
            "EPUB/toc.ncx",
            "EPUB/text/title_page.xhtml"
        )

        $MissingEntries = @()
        foreach ($EntryName in $RequiredEntries) {
            if (-not ($Zip.Entries | Where-Object FullName -eq $EntryName)) {
                $MissingEntries += $EntryName
                Add-Issue -Type "Error" -Message "Required EPUB entry is missing." -File $EntryName
            }
        }

        if ($MissingEntries.Count -gt 0) {
            Add-CheckResult -Name "5. Required EPUB files check" -Status "Error" -Detail ("Missing EPUB entries: " + ($MissingEntries -join ", "))
        }
        else {
            Add-CheckResult -Name "5. Required EPUB files check" -Status "Pass" -Detail "All required EPUB entries are present."
        }

        $ContentOpf = Read-ZipEntryText -Zip $Zip -EntryName "EPUB/content.opf"
        $NavXhtml = Read-ZipEntryText -Zip $Zip -EntryName "EPUB/nav.xhtml"
        $TitlePageXhtml = Read-ZipEntryText -Zip $Zip -EntryName "EPUB/text/title_page.xhtml"

        if ($ContentOpf) {
            [xml]$OpfXml = $ContentOpf
            $OpfNs = New-Object System.Xml.XmlNamespaceManager($OpfXml.NameTable)
            $OpfNs.AddNamespace("opf", "http://www.idpf.org/2007/opf")
            $OpfNs.AddNamespace("dc", "http://purl.org/dc/elements/1.1/")

            $TitleNode = $OpfXml.SelectSingleNode("/opf:package/opf:metadata/dc:title", $OpfNs)
            $CreatorNode = $OpfXml.SelectSingleNode("/opf:package/opf:metadata/dc:creator", $OpfNs)
            $LanguageNode = $OpfXml.SelectSingleNode("/opf:package/opf:metadata/dc:language", $OpfNs)

            $TitleText = if ($TitleNode) { $TitleNode.InnerText.Trim() } else { "" }
            $CreatorText = if ($CreatorNode) { $CreatorNode.InnerText.Trim() } else { "" }
            $LanguageText = if ($LanguageNode) { $LanguageNode.InnerText.Trim() } else { "" }

            $MetadataProblems = @()
            if ([string]::IsNullOrWhiteSpace($TitleText)) {
                $MetadataProblems += "title"
                Add-Issue -Type "Error" -Message "EPUB metadata title is missing." -File "EPUB/content.opf"
            }
            if ([string]::IsNullOrWhiteSpace($CreatorText)) {
                $MetadataProblems += "creator"
                Add-Issue -Type "Warning" -Message "EPUB metadata creator is missing." -File "EPUB/content.opf"
            }
            if ([string]::IsNullOrWhiteSpace($LanguageText)) {
                $MetadataProblems += "language"
                Add-Issue -Type "Warning" -Message "EPUB metadata language is missing." -File "EPUB/content.opf"
            }

            if ((Test-ContainsCjk -Text ($TitleText + $CreatorText)) -and $LanguageText -match '^en') {
                Add-Issue -Type "Warning" -Message "EPUB language metadata is English while the book content is Chinese." -File "EPUB/content.opf"
                $MetadataProblems += "language-mismatch"
            }

            if ($MetadataProblems.Count -gt 0) {
                Add-CheckResult -Name "6. Package metadata check" -Status "Warning" -Detail ("Metadata issues: " + ($MetadataProblems -join ", ") + ". title=$TitleText; creator=$CreatorText; language=$LanguageText")
            }
            else {
                Add-CheckResult -Name "6. Package metadata check" -Status "Pass" -Detail ("Metadata looks valid. title=$TitleText; creator=$CreatorText; language=$LanguageText")
            }

            $ManifestItems = @($OpfXml.SelectNodes("/opf:package/opf:manifest/opf:item", $OpfNs))
            foreach ($ManifestItem in $ManifestItems) {
                $Id = $ManifestItem.GetAttribute("id")
                $Href = $ManifestItem.GetAttribute("href")
                if ($Id -and $Href) {
                    $ManifestHrefMap[$Id] = $Href
                }
            }

            $SpineItems = @($OpfXml.SelectNodes("/opf:package/opf:spine/opf:itemref", $OpfNs))
            $SpineRefs = @($SpineItems | ForEach-Object { $_.GetAttribute("idref") })

            $SpineProblems = @()
            foreach ($SpineRef in $SpineRefs) {
                if (-not $ManifestHrefMap.ContainsKey($SpineRef)) {
                    $SpineProblems += $SpineRef
                    Add-Issue -Type "Error" -Message "Spine item does not resolve to a manifest entry." -File $SpineRef
                }
            }

            if ($SpineRefs.Count -lt 3) {
                Add-Issue -Type "Error" -Message "Spine contains too few readable items." -File "EPUB/content.opf"
                $SpineProblems += "too-short"
            }

            if ($SpineRefs.Count -ge 2) {
                if ($SpineRefs[0] -ne "title_page_xhtml") {
                    Add-Issue -Type "Warning" -Message "EPUB spine does not start with title_page.xhtml." -File $SpineRefs[0]
                    $SpineProblems += "title-page-order"
                }
                if ($SpineRefs[1] -ne "nav") {
                    Add-Issue -Type "Warning" -Message "EPUB spine does not place nav.xhtml immediately after the title page." -File $SpineRefs[1]
                    $SpineProblems += "nav-order"
                }
            }

            if ($SpineProblems.Count -gt 0) {
                Add-CheckResult -Name "7. Spine order and resolution check" -Status "Warning" -Detail ("Spine issues: " + ($SpineProblems -join ", "))
            }
            else {
                Add-CheckResult -Name "7. Spine order and resolution check" -Status "Pass" -Detail ("Spine order is valid: " + ($SpineRefs -join " -> "))
            }
        }
        else {
            Add-Issue -Type "Error" -Message "content.opf could not be read." -File "EPUB/content.opf"
            Add-CheckResult -Name "6. Package metadata check" -Status "Error" -Detail "content.opf could not be read."
            Add-CheckResult -Name "7. Spine order and resolution check" -Status "Error" -Detail "Spine could not be validated because content.opf could not be read."
        }

        if ($NavXhtml) {
            $HrefMatches = [regex]::Matches($NavXhtml, 'href="([^"]+)"')
            $TocHrefTargets = @($HrefMatches | ForEach-Object { $_.Groups[1].Value } | Where-Object { $_ -notmatch '^#' } | Sort-Object -Unique)
            if ($TocHrefTargets.Count -gt 0) {
                Add-CheckResult -Name "8. Navigation document check" -Status "Pass" -Detail ("Navigation document contains $($TocHrefTargets.Count) unique href target(s).")
            }
            else {
                Add-Issue -Type "Error" -Message "Navigation document does not contain usable TOC links." -File "EPUB/nav.xhtml"
                Add-CheckResult -Name "8. Navigation document check" -Status "Error" -Detail "Navigation document does not contain usable TOC links."
            }
        }
        else {
            Add-Issue -Type "Error" -Message "nav.xhtml could not be read." -File "EPUB/nav.xhtml"
            Add-CheckResult -Name "8. Navigation document check" -Status "Error" -Detail "nav.xhtml could not be read."
        }

        if ($TitlePageXhtml) {
            $TitlePageText = Get-PlainText -Html $TitlePageXhtml
            $TitlePageProblems = @()
            if ($TitleText -and ($TitlePageText -notlike "*$TitleText*")) {
                $TitlePageProblems += "title-missing"
                Add-Issue -Type "Warning" -Message "Title page does not visibly contain the EPUB title." -File "EPUB/text/title_page.xhtml"
            }
            if ($CreatorText -and ($TitlePageText -notlike "*$CreatorText*")) {
                $TitlePageProblems += "author-missing"
                Add-Issue -Type "Warning" -Message "Title page does not visibly contain the EPUB creator." -File "EPUB/text/title_page.xhtml"
            }
            if ($TitlePageProblems.Count -gt 0) {
                Add-CheckResult -Name "9. Title page content check" -Status "Warning" -Detail ("Title page issues: " + ($TitlePageProblems -join ", "))
            }
            else {
                Add-CheckResult -Name "9. Title page content check" -Status "Pass" -Detail "Title page contains the title and author."
            }
        }
        else {
            Add-Issue -Type "Error" -Message "title_page.xhtml could not be read." -File "EPUB/text/title_page.xhtml"
            Add-CheckResult -Name "9. Title page content check" -Status "Error" -Detail "title_page.xhtml could not be read."
        }

        $ChapterEntries = @($Zip.Entries | Where-Object { $_.FullName -match '^EPUB/text/ch\d{3}\.xhtml$' } | Sort-Object FullName)
        if ($ChapterEntries.Count -eq 0) {
            Add-Issue -Type "Error" -Message "No chapter XHTML files were found in EPUB/text." -File "EPUB/text"
            Add-CheckResult -Name "10. Chapter XHTML sequence check" -Status "Error" -Detail "No chapter XHTML files were found in EPUB/text."
        }
        else {
            $ExpectedIndex = 1
            $MissingChapters = @()
            foreach ($ChapterEntry in $ChapterEntries) {
                if ($ChapterEntry.Name -match '^ch(\d{3})\.xhtml$') {
                    $CurrentIndex = [int]$Matches[1]
                    while ($ExpectedIndex -lt $CurrentIndex) {
                        $MissingChapters += ("ch{0:D3}.xhtml" -f $ExpectedIndex)
                        $ExpectedIndex++
                    }
                    $ExpectedIndex = $CurrentIndex + 1
                }
            }

            if ($MissingChapters.Count -gt 0) {
                foreach ($MissingChapter in $MissingChapters) {
                    Add-Issue -Type "Error" -Message "Chapter XHTML file is missing from the EPUB sequence." -File $MissingChapter
                }
                Add-CheckResult -Name "10. Chapter XHTML sequence check" -Status "Error" -Detail ("Missing chapter XHTML files: " + ($MissingChapters -join ", "))
            }
            else {
                Add-CheckResult -Name "10. Chapter XHTML sequence check" -Status "Pass" -Detail ("Found a continuous chapter XHTML sequence from ch001 to " + $ChapterEntries[-1].Name)
            }

            $EmptyChapterFiles = @()
            foreach ($ChapterEntry in $ChapterEntries) {
                $ChapterHtml = Read-ZipEntryText -Zip $Zip -EntryName $ChapterEntry.FullName
                $ChapterText = Get-PlainText -Html $ChapterHtml
                if ([string]::IsNullOrWhiteSpace($ChapterText) -or $ChapterText.Length -lt 80) {
                    $EmptyChapterFiles += $ChapterEntry.Name
                    Add-Issue -Type "Warning" -Message "Chapter XHTML content looks empty or unusually short." -File $ChapterEntry.Name
                }
            }

            if ($EmptyChapterFiles.Count -gt 0) {
                Add-CheckResult -Name "11. Chapter XHTML body check" -Status "Warning" -Detail ("Potentially empty chapter XHTML files: " + ($EmptyChapterFiles -join ", "))
            }
            else {
                Add-CheckResult -Name "11. Chapter XHTML body check" -Status "Pass" -Detail "All chapter XHTML files contain readable body text."
            }
        }

        $TargetProblems = @()
        $AllEntryNames = @($Zip.Entries | Select-Object -ExpandProperty FullName)
        foreach ($HrefTarget in $TocHrefTargets) {
            $SplitTarget = $HrefTarget.Split('#')[0]
            if ([string]::IsNullOrWhiteSpace($SplitTarget)) {
                continue
            }

            $EntryPath = if ($SplitTarget.StartsWith("text/")) {
                "EPUB/$SplitTarget"
            }
            else {
                "EPUB/$SplitTarget"
            }

            if ($AllEntryNames -notcontains $EntryPath) {
                $TargetProblems += $HrefTarget
                Add-Issue -Type "Error" -Message "TOC link target does not exist inside the EPUB package." -File $HrefTarget
            }
        }

        if ($TargetProblems.Count -gt 0) {
            Add-CheckResult -Name "12. TOC target validation check" -Status "Error" -Detail ("Broken TOC href targets: " + ($TargetProblems -join ", "))
        }
        else {
            Add-CheckResult -Name "12. TOC target validation check" -Status "Pass" -Detail "All TOC href targets resolve to existing EPUB entries."
        }
    }
    catch {
        Add-Issue -Type "Error" -Message ("EPUB archive could not be inspected: " + $_.Exception.Message) -File $EpubPath
        Add-CheckResult -Name "4. EPUB archive integrity check" -Status "Error" -Detail ("EPUB archive could not be inspected: " + $_.Exception.Message)
    }
    finally {
        if ($null -ne $Zip) {
            $Zip.Dispose()
        }
    }
}

$ErrorCount = [int](($Issues | Where-Object { $_.Type -eq "Error" }).Count)
$WarningCount = [int](($Issues | Where-Object { $_.Type -eq "Warning" }).Count)
$InfoCount = [int](($Issues | Where-Object { $_.Type -eq "Info" }).Count)

$ReportPath = Join-Path $LogRoot "epub_report.txt"
$JsonReportPath = Join-Path $LogRoot "epub_report.json"
$ReportHistoryRoot = Join-Path $LogRoot "epub_report_history"
$ReportStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$ArchivedReportPath = Join-Path $ReportHistoryRoot ("epub_report_{0}.txt" -f $ReportStamp)
$ArchivedJsonReportPath = Join-Path $ReportHistoryRoot ("epub_report_{0}.json" -f $ReportStamp)

if (!(Test-Path $ReportHistoryRoot)) {
    New-Item -ItemType Directory -Path $ReportHistoryRoot -Force | Out-Null
}

$BuildReadyText = if ($ErrorCount -gt 0) { "NO" } elseif ($WarningCount -gt 0) { "YES (with warnings)" } else { "YES" }
$RunTimeText = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$ReportLines = @()
$ReportLines += "SageWrite EPUB Integrity Check"
$ReportLines += "BookName: $BookName"
$ReportLines += "Run Time: $RunTimeText"
$ReportLines += ""
$ReportLines += "Summary"
$ReportLines += "Errors: $ErrorCount"
$ReportLines += "Warnings: $WarningCount"
$ReportLines += "Infos: $InfoCount"
$ReportLines += "EPUB Ready: $BuildReadyText"
$ReportLines += ""
$ReportLines += "Checklist"

foreach ($Check in $Checks) {
    $ReportLines += "[$($Check.Status)] $($Check.Name)"
    $ReportLines += "  $($Check.Detail)"
    $ReportLines += ""
}

$ReportLines += "Issues"
if ($Issues.Count -eq 0) {
    $ReportLines += "No issues found."
}
else {
    foreach ($Issue in $Issues) {
        $Location = if ($Issue.File) { $Issue.File } else { "-" }
        $ReportLines += "[$($Issue.Type)] [$Location] $($Issue.Message)"
    }
}

$ReportLines | Out-File $ReportPath -Encoding utf8
$ReportLines | Out-File $ArchivedReportPath -Encoding utf8

$JsonPayload = [PSCustomObject]@{
    book = $BookName
    run_time = $RunTimeText
    epub_file = $EpubPath
    summary = [PSCustomObject]@{
        errors = $ErrorCount
        warnings = $WarningCount
        infos = $InfoCount
        epub_ready = $BuildReadyText
        chapter_xhtml_files = $ChapterEntries.Count
        metadata_title = $TitleText
        metadata_creator = $CreatorText
        metadata_language = $LanguageText
    }
    checks = @(
        $Checks | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Status = $_.Status
                Detail = $_.Detail
                LocalizedStatus = Get-LocalizedStatus -Status $_.Status
            }
        }
    )
    issues = @(
        $Issues | ForEach-Object {
            [PSCustomObject]@{
                Type = $_.Type
                File = $_.File
                Message = $_.Message
                LocalizedType = Get-LocalizedStatus -Status $_.Type
            }
        }
    )
    spine = $SpineRefs
    toc_targets = $TocHrefTargets
}

$JsonPayload | ConvertTo-Json -Depth 10 | Out-File $JsonReportPath -Encoding utf8
$JsonPayload | ConvertTo-Json -Depth 10 | Out-File $ArchivedJsonReportPath -Encoding utf8

Write-Host ""
Write-Host "EPUB integrity check completed"
Write-Host "Errors: $ErrorCount"
Write-Host "Warnings: $WarningCount"
Write-Host "Report saved to:"
Write-Host $ReportPath

$State = if ($ErrorCount -gt 0) { "failed" } else { "success" }
$Message = if ($ErrorCount -gt 0) {
    "EPUB integrity check found blocking issues."
}
else {
    "EPUB integrity check completed."
}

Complete-SageStep -Context $Context -Step "edit_epub" -State $State -Message $Message -Data @{
    report = $ReportPath
    archived_report = $ArchivedReportPath
    json_report = $JsonReportPath
    archived_json_report = $ArchivedJsonReportPath
    warning_count = $WarningCount
    error_count = $ErrorCount
    epub_file = $EpubPath
}

if ($ErrorCount -gt 0) {
    exit 1
}

exit 0
