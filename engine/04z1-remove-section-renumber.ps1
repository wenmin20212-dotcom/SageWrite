param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [ValidateRange(1, 9999)]
    [int]$SectionIndex,

    [string]$ExpectedHeading,

    [int]$EndIndex,

    [string]$ScopeName = "remove_section_renumber",

    [switch]$DryRun
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Save-Utf8File {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $Parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($Parent) -and !(Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
}

function Read-Utf8File {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function ConvertTo-Crlf {
    param([AllowEmptyString()][string]$Text)

    $Normalized = $Text -replace "`r", ""
    return $Normalized -replace "`n", "`r`n"
}

function Get-SectionFileName {
    param([Parameter(Mandatory=$true)][int]$Index)

    return "{0:D2}.md" -f $Index
}

function Get-SectionPath {
    param(
        [Parameter(Mandatory=$true)][string]$ChapterRoot,
        [Parameter(Mandatory=$true)][int]$Index
    )

    return Join-Path $ChapterRoot (Get-SectionFileName -Index $Index)
}

function Get-TocSections {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    $Lines = @($Normalized -split "`n")
    $Sections = New-Object System.Collections.ArrayList
    $CurrentParent = ""

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^##\s+(.+?)\s*$') {
            $CurrentParent = $Matches[1].Trim()
            continue
        }

        if ($Lines[$i] -match '^###\s+(.+?)\s*$') {
            $Sections.Add([pscustomobject]@{
                Index = $Sections.Count + 1
                Title = $Matches[1].Trim()
                LineIndex = $i
                Parent = $CurrentParent
            }) | Out-Null
        }
    }

    return @($Sections)
}

function Remove-TocSectionAndRenumberSiblings {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [int]$Index,

        [string]$ExpectedHeading
    )

    $Normalized = $Content -replace "`r", ""
    $Lines = @($Normalized -split "`n")
    $Sections = @(Get-TocSections -Content $Normalized)

    if ($Sections.Count -eq 0) {
        throw "No ### writing sections detected in toc.md."
    }
    if ($Index -lt 1 -or $Index -gt $Sections.Count) {
        throw "SectionIndex $Index is outside available writing section count $($Sections.Count)."
    }

    $Selected = $Sections[$Index - 1]
    $SelectedTitle = $Selected.Title

    if (-not [string]::IsNullOrWhiteSpace($ExpectedHeading)) {
        $Expected = ($ExpectedHeading -replace '^\s*###\s+', '').Trim()
        if ($Expected -ne $SelectedTitle) {
            throw "ExpectedHeading mismatch. Requested '$Expected', but section $Index is '$SelectedTitle'."
        }
    }

    $RemoveStart = [int]$Selected.LineIndex
    $RemoveEnd = $Lines.Count
    for ($i = $RemoveStart + 1; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match '^(#{1,3})\s+') {
            $RemoveEnd = $i
            break
        }
    }

    $RemovedLines = New-Object System.Collections.ArrayList
    for ($i = $RemoveStart; $i -lt $RemoveEnd; $i++) {
        $RemovedLines.Add($Lines[$i]) | Out-Null
    }

    $NewLines = New-Object System.Collections.ArrayList
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($i -lt $RemoveStart -or $i -ge $RemoveEnd) {
            $NewLines.Add($Lines[$i]) | Out-Null
        }
    }

    $RenumberedMajor = $null
    if ($SelectedTitle -match '^(\d+)\.(\d+)\s+(.+)$') {
        $RenumberedMajor = $Matches[1]
        $Minor = 1
        for ($i = 0; $i -lt $NewLines.Count; $i++) {
            $Pattern = '^###\s+' + [regex]::Escape($RenumberedMajor) + '\.\d+\s+(.+?)\s*$'
            if ($NewLines[$i] -match $Pattern) {
                $NewLines[$i] = "### $RenumberedMajor.$Minor $($Matches[1].Trim())"
                $Minor++
            }
        }
    }

    $NewContent = (($NewLines -join "`n").TrimEnd()) + "`n"
    $NewSections = @(Get-TocSections -Content $NewContent)

    if ($NewSections.Count -ne ($Sections.Count - 1)) {
        throw "Internal TOC rewrite error. Expected $($Sections.Count - 1) sections, got $($NewSections.Count)."
    }

    return [pscustomobject]@{
        OriginalSectionCount = $Sections.Count
        NewSectionCount = $NewSections.Count
        RemovedTitle = $SelectedTitle
        RemovedParent = $Selected.Parent
        RemovedBlock = (($RemovedLines -join "`n").TrimEnd()) + "`n"
        RenumberedMajor = $RenumberedMajor
        NewContent = $NewContent
        NewSections = $NewSections
    }
}

function Get-TopLevelNumericMarkdownNumbers {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ChapterRoot
    )

    $Items = @(Get-ChildItem -LiteralPath $ChapterRoot -Filter "*.md" -File |
        Where-Object { $_.BaseName -match '^\d+$' } |
        ForEach-Object {
            [pscustomobject]@{
                Number = [int]$_.BaseName
                Name = $_.Name
                FullName = $_.FullName
            }
        } |
        Sort-Object Number)

    return $Items
}

function Get-DefaultShiftEndIndex {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ChapterRoot,

        [Parameter(Mandatory=$true)]
        [int]$StartIndex
    )

    $Index = $StartIndex + 1
    while (Test-Path -LiteralPath (Get-SectionPath -ChapterRoot $ChapterRoot -Index $Index)) {
        $Index++
    }

    return $Index - 1
}

function ConvertTo-YamlQuotedString {
    param([AllowEmptyString()][string]$Value)

    $Escaped = $Value.Replace('\', '\\').Replace('"', '\"')
    return '"' + $Escaped + '"'
}

function Set-YamlScalarLine {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$FrontMatter,

        [Parameter(Mandatory=$true)]
        [string]$Key,

        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$ValueText
    )

    $Lines = New-Object System.Collections.ArrayList
    foreach ($Line in @($FrontMatter -split "`n")) {
        $Lines.Add($Line) | Out-Null
    }

    $Found = $false
    $Pattern = '^\s*' + [regex]::Escape($Key) + '\s*:'
    for ($i = 0; $i -lt $Lines.Count; $i++) {
        if ($Lines[$i] -match $Pattern) {
            $Lines[$i] = "${Key}: $ValueText"
            $Found = $true
            break
        }
    }

    if (-not $Found) {
        $Lines.Add("${Key}: $ValueText") | Out-Null
    }

    return ($Lines -join "`n").TrimEnd()
}

function Set-FirstSectionHeading {
    param(
        [Parameter(Mandatory=$true)]
        [AllowEmptyString()]
        [string]$Body,

        [Parameter(Mandatory=$true)]
        [string]$Title
    )

    $Heading = "### $Title"
    $Match = [regex]::Match($Body, '(?m)^###\s+.+?\s*$')
    if ($Match.Success) {
        return $Body.Substring(0, $Match.Index) + $Heading + $Body.Substring($Match.Index + $Match.Length)
    }

    return $Heading + "`n`n" + $Body.TrimStart()
}

function Update-SectionFileMetadata {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path,

        [Parameter(Mandatory=$true)]
        [int]$Index,

        [Parameter(Mandatory=$true)]
        [string]$Title
    )

    $Raw = Read-Utf8File -Path $Path
    $Normalized = $Raw -replace "`r", ""
    $FrontMatter = $null
    $Body = $Normalized

    $FrontMatterMatch = [regex]::Match($Normalized, '(?s)^---\n(.*?)\n---\n?')
    if ($FrontMatterMatch.Success) {
        $FrontMatter = $FrontMatterMatch.Groups[1].Value
        $Body = $Normalized.Substring($FrontMatterMatch.Length)
    }

    $Body = Set-FirstSectionHeading -Body $Body -Title $Title

    if ($null -ne $FrontMatter) {
        $FrontMatter = Set-YamlScalarLine -FrontMatter $FrontMatter -Key "chapter_index" -ValueText ([string]$Index)
        $FrontMatter = Set-YamlScalarLine -FrontMatter $FrontMatter -Key "title" -ValueText (ConvertTo-YamlQuotedString -Value $Title)
        $Updated = "---`n$FrontMatter`n---`n$Body"
    }
    else {
        $Updated = $Body
    }

    Save-Utf8File -Path $Path -Content (ConvertTo-Crlf -Text (($Updated.TrimEnd()) + "`n"))
}

function Get-ImageReferences {
    param(
        [Parameter(Mandatory=$true)]
        [string[]]$Paths
    )

    $Refs = New-Object System.Collections.ArrayList
    foreach ($Path in $Paths) {
        if (!(Test-Path -LiteralPath $Path)) {
            continue
        }
        $Matches = @(Select-String -LiteralPath $Path -Pattern '!\[|<img|03_assets|figures|\.png|\.jpg|\.jpeg|\.svg|\.webp' -Encoding UTF8)
        foreach ($Match in $Matches) {
            $Refs.Add(("{0}:{1}: {2}" -f (Split-Path -Leaf $Path), $Match.LineNumber, $Match.Line.Trim())) | Out-Null
        }
    }

    return @($Refs)
}

function New-Report {
    param(
        [Parameter(Mandatory=$true)][hashtable]$Data
    )

    $Lines = New-Object System.Collections.ArrayList
    $Lines.Add("# 04Z1 remove-section renumber report") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("- book: $($Data.BookName)") | Out-Null
    $Lines.Add("- dry_run: $($Data.DryRun)") | Out-Null
    $Lines.Add("- section_index_removed: $($Data.SectionIndex)") | Out-Null
    $Lines.Add("- removed_title: $($Data.RemovedTitle)") | Out-Null
    $Lines.Add("- removed_parent: $($Data.RemovedParent)") | Out-Null
    $Lines.Add("- original_toc_sections: $($Data.OriginalSectionCount)") | Out-Null
    $Lines.Add("- new_toc_sections: $($Data.NewSectionCount)") | Out-Null
    $Lines.Add("- shift_end_index: $($Data.ShiftEnd)") | Out-Null
    $Lines.Add("- shifted_file_count: $($Data.ShiftedFileCount)") | Out-Null
    $Lines.Add("") | Out-Null
    $Lines.Add("## File operations") | Out-Null
    if ($Data.FileOperations.Count -eq 0) {
        $Lines.Add("- No chapter file shifts are required.") | Out-Null
    }
    else {
        foreach ($Op in $Data.FileOperations) {
            $Lines.Add("- $Op") | Out-Null
        }
    }
    if ($Data.Warnings.Count -gt 0) {
        $Lines.Add("") | Out-Null
        $Lines.Add("## Warnings") | Out-Null
        foreach ($Warning in $Data.Warnings) {
            $Lines.Add("- $Warning") | Out-Null
        }
    }
    if ($Data.ImageReferences.Count -gt 0) {
        $Lines.Add("") | Out-Null
        $Lines.Add("## Image references in affected files") | Out-Null
        foreach ($Ref in $Data.ImageReferences) {
            $Lines.Add("- $Ref") | Out-Null
        }
    }
    $Lines.Add("") | Out-Null
    $Lines.Add("## Removed TOC block") | Out-Null
    $Lines.Add('```markdown') | Out-Null
    $Lines.Add(($Data.RemovedBlock.TrimEnd())) | Out-Null
    $Lines.Add('```') | Out-Null

    return ($Lines -join "`r`n") + "`r`n"
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "04z1-remove-section-renumber" -Data @{
    book = $BookName
    section_index = $SectionIndex
    dry_run = [bool]$DryRun
}

try {
    $BookRoot = $Context.BookRoot
    $TocPath = Join-Path $BookRoot "01_outline\toc.md"
    $ChapterRoot = Join-Path $BookRoot "02_chapters"
    $BriefRoot = Join-Path $BookRoot "00_brief"

    if (!(Test-Path -LiteralPath $BookRoot)) {
        throw "Book root not found: $BookRoot"
    }
    if (!(Test-Path -LiteralPath $TocPath)) {
        throw "toc.md not found: $TocPath"
    }
    if (!(Test-Path -LiteralPath $ChapterRoot)) {
        throw "02_chapters folder not found: $ChapterRoot"
    }

    $OriginalToc = Read-Utf8File -Path $TocPath
    $TocRewrite = Remove-TocSectionAndRenumberSiblings -Content $OriginalToc -Index $SectionIndex -ExpectedHeading $ExpectedHeading
    $NewSections = @($TocRewrite.NewSections)

    $RemovePath = Get-SectionPath -ChapterRoot $ChapterRoot -Index $SectionIndex
    if (!(Test-Path -LiteralPath $RemovePath)) {
        throw "Section file to remove not found: $(Get-SectionFileName -Index $SectionIndex)"
    }

    $ShiftEnd = if ($EndIndex -gt 0) {
        if ($EndIndex -lt $SectionIndex) {
            throw "EndIndex must be greater than or equal to SectionIndex."
        }
        for ($i = $SectionIndex; $i -le $EndIndex; $i++) {
            $Path = Get-SectionPath -ChapterRoot $ChapterRoot -Index $i
            if (!(Test-Path -LiteralPath $Path)) {
                throw "Cannot shift through missing file: $(Get-SectionFileName -Index $i). Use a smaller EndIndex or fill the gap first."
            }
        }
        $EndIndex
    }
    else {
        Get-DefaultShiftEndIndex -ChapterRoot $ChapterRoot -StartIndex $SectionIndex
    }

    $FileOperations = New-Object System.Collections.ArrayList
    $FileOperations.Add(("archive removed file: {0}" -f (Get-SectionFileName -Index $SectionIndex))) | Out-Null
    for ($i = $SectionIndex + 1; $i -le $ShiftEnd; $i++) {
        $FileOperations.Add(("{0} -> {1}" -f (Get-SectionFileName -Index $i), (Get-SectionFileName -Index ($i - 1)))) | Out-Null
    }

    $AffectedPaths = New-Object System.Collections.ArrayList
    for ($i = $SectionIndex; $i -le $ShiftEnd; $i++) {
        $AffectedPaths.Add((Get-SectionPath -ChapterRoot $ChapterRoot -Index $i)) | Out-Null
    }
    $ImageRefs = @(Get-ImageReferences -Paths @($AffectedPaths))

    $Warnings = New-Object System.Collections.ArrayList
    if ($EndIndex -le 0) {
        $AllNumbers = @(Get-TopLevelNumericMarkdownNumbers -ChapterRoot $ChapterRoot)
        $LaterAfterGap = @($AllNumbers | Where-Object { $_.Number -gt ($ShiftEnd + 1) })
        if ($LaterAfterGap.Count -gt 0) {
            $Warnings.Add(("Detected later top-level numeric files after the first gap: {0}. They are not shifted by default." -f (($LaterAfterGap | Select-Object -First 12 | ForEach-Object { $_.Name }) -join ", "))) | Out-Null
        }
    }

    $ShiftedFileCount = [Math]::Max(0, $ShiftEnd - $SectionIndex)
    $ReportData = @{
        BookName = $BookName
        DryRun = [bool]$DryRun
        SectionIndex = $SectionIndex
        RemovedTitle = $TocRewrite.RemovedTitle
        RemovedParent = $TocRewrite.RemovedParent
        OriginalSectionCount = $TocRewrite.OriginalSectionCount
        NewSectionCount = $TocRewrite.NewSectionCount
        ShiftEnd = $ShiftEnd
        ShiftedFileCount = $ShiftedFileCount
        FileOperations = @($FileOperations)
        Warnings = @($Warnings)
        ImageReferences = @($ImageRefs)
        RemovedBlock = $TocRewrite.RemovedBlock
    }
    $Report = New-Report -Data $ReportData

    Write-Output "[04Z1] Book: $BookName"
    Write-Output "[04Z1] Remove section ${SectionIndex}: $($TocRewrite.RemovedTitle)"
    Write-Output "[04Z1] TOC sections: $($TocRewrite.OriginalSectionCount) -> $($TocRewrite.NewSectionCount)"
    Write-Output "[04Z1] Shift range: $SectionIndex-$ShiftEnd"
    if ($DryRun) {
        Write-Output "[04Z1] Dry run only. No files changed."
        if ($Warnings.Count -gt 0) {
            foreach ($Warning in $Warnings) {
                Write-Output "[04Z1][warning] $Warning"
            }
        }
        Write-Output ""
        Write-Output $Report

        Complete-SageStep -Context $Context -Step "04z1-remove-section-renumber" -State "success" -Message "Dry run complete." -Data @{
            section_index = $SectionIndex
            removed_title = $TocRewrite.RemovedTitle
            shift_end = $ShiftEnd
            dry_run = $true
        }
        exit 0
    }

    $RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $RunRoot = Join-Path $Context.LogRoot ("04z1_remove_section_{0}" -f $RunStamp)
    $ArchiveRoot = Join-Path $ChapterRoot ("back\04z1_remove_section_{0}" -f $RunStamp)
    $OriginalFilesRoot = Join-Path $ArchiveRoot "original_files"
    $RemovedRoot = Join-Path $ArchiveRoot "removed"
    $TocBackRoot = Join-Path (Split-Path -Parent $TocPath) "back"

    New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $OriginalFilesRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $RemovedRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $TocBackRoot -Force | Out-Null

    $ChapterRootResolved = (Resolve-Path -LiteralPath $ChapterRoot).Path
    $ArchiveRootResolved = (Resolve-Path -LiteralPath $ArchiveRoot).Path
    if (-not $ArchiveRootResolved.StartsWith($ChapterRootResolved)) {
        throw "Archive root is outside 02_chapters: $ArchiveRootResolved"
    }

    $TocBackupPath = Join-Path $TocBackRoot ("toc.before_04z1_remove_section_{0}.md" -f $RunStamp)
    Copy-Item -LiteralPath $TocPath -Destination $TocBackupPath -Force
    Save-Utf8File -Path (Join-Path $RunRoot "removed_toc_block.md") -Content (ConvertTo-Crlf -Text $TocRewrite.RemovedBlock)
    Save-Utf8File -Path (Join-Path $RunRoot "toc.after_04z1_preview.md") -Content (ConvertTo-Crlf -Text $TocRewrite.NewContent)

    for ($i = $SectionIndex; $i -le $ShiftEnd; $i++) {
        $Path = Get-SectionPath -ChapterRoot $ChapterRoot -Index $i
        Copy-Item -LiteralPath $Path -Destination (Join-Path $OriginalFilesRoot (Get-SectionFileName -Index $i)) -Force
    }

    Move-Item -LiteralPath $RemovePath -Destination (Join-Path $RemovedRoot (Get-SectionFileName -Index $SectionIndex)) -Force

    for ($i = $SectionIndex + 1; $i -le $ShiftEnd; $i++) {
        $Source = Get-SectionPath -ChapterRoot $ChapterRoot -Index $i
        $Destination = Get-SectionPath -ChapterRoot $ChapterRoot -Index ($i - 1)
        Move-Item -LiteralPath $Source -Destination $Destination -Force
    }

    Save-Utf8File -Path $TocPath -Content (ConvertTo-Crlf -Text $TocRewrite.NewContent)

    for ($i = $SectionIndex; $i -le ($ShiftEnd - 1); $i++) {
        if ($i -gt $NewSections.Count) {
            $Warnings.Add("No TOC title exists for shifted file $(Get-SectionFileName -Index $i); metadata was not updated.") | Out-Null
            continue
        }
        $Path = Get-SectionPath -ChapterRoot $ChapterRoot -Index $i
        if (Test-Path -LiteralPath $Path) {
            Update-SectionFileMetadata -Path $Path -Index $i -Title $NewSections[$i - 1].Title
        }
    }

    $ReportData.Warnings = @($Warnings)
    $Report = New-Report -Data $ReportData
    $ReportPath = Join-Path $RunRoot "04z1_renumber_report.md"
    $StableReportPath = Join-Path $BriefRoot ("{0}_04z1_renumber_report.md" -f $ScopeName)
    Save-Utf8File -Path $ReportPath -Content $Report
    Save-Utf8File -Path $StableReportPath -Content $Report

    Write-Output "[04Z1] Completed."
    Write-Output "[04Z1] TOC backup: $TocBackupPath"
    Write-Output "[04Z1] Chapter archive: $ArchiveRoot"
    Write-Output "[04Z1] Report: $ReportPath"
    if ($Warnings.Count -gt 0) {
        foreach ($Warning in $Warnings) {
            Write-Output "[04Z1][warning] $Warning"
        }
    }

    Complete-SageStep -Context $Context -Step "04z1-remove-section-renumber" -State "success" -Message "Section removed and chapter files renumbered." -Data @{
        section_index = $SectionIndex
        removed_title = $TocRewrite.RemovedTitle
        shift_end = $ShiftEnd
        report = $ReportPath
        archive = $ArchiveRoot
        dry_run = $false
    }
}
catch {
    $Message = $_.Exception.Message
    Fail-SageStep -Context $Context -Step "04z1-remove-section-renumber" -Message $Message -Data @{
        section_index = $SectionIndex
        dry_run = [bool]$DryRun
    }
    throw
}
