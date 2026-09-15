param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$StartChapter = 1,

    [int]$EndChapter,

    [int]$BudgetMinPerSection = 1600,

    [int]$BudgetMaxPerSection = 2100,

    [string]$ScopeName = "part_budget_statistics"
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

function Remove-FrontMatter {
    param([string]$Content)

    $Normalized = $Content -replace "`r", ""
    return [regex]::Replace($Normalized, "(?s)^---\n.*?\n---\n?", "", 1)
}

function Count-Pattern {
    param(
        [string]$Text,
        [string]$Pattern
    )

    if ([string]::IsNullOrEmpty($Text)) {
        return 0
    }

    return ([regex]::Matches($Text, $Pattern)).Count
}

function Escape-MarkdownCell {
    param([string]$Value)

    if ($null -eq $Value) {
        return ""
    }

    return ([string]$Value) -replace "\|", "/"
}

function Parse-Number {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return 0
    }

    return [int](($Value -replace "[,，]", "").Trim())
}

function Parse-TocSections {
    param(
        [Parameter(Mandatory=$true)]
        [string]$TocPath,

        [Parameter(Mandatory=$true)]
        [int]$DefaultMin,

        [Parameter(Mandatory=$true)]
        [int]$DefaultMax
    )

    $Lines = (Read-Utf8File -Path $TocPath) -replace "`r", "" -split "`n"
    $Sections = @()
    $CurrentPart = ""
    $CurrentMajor = ""
    $LastSection = $null

    foreach ($Line in $Lines) {
        if ($Line -match "^#\s+(.+?)\s*$") {
            $Candidate = $Matches[1].Trim()
            if ($Candidate -notin @("Table of Contents", "写作总规范") -and $Candidate -notmatch "^LTC[：:]") {
                $CurrentPart = $Candidate
            }
            continue
        }

        if ($Line -match "^##\s+(.+?)\s*$") {
            $CurrentMajor = $Matches[1].Trim()
            continue
        }

        if ($Line -match "^###\s+(.+?)\s*$") {
            $Section = [ordered]@{
                index = [int]($Sections.Count + 1)
                title = $Matches[1].Trim()
                part = $CurrentPart
                major = $CurrentMajor
                target_min = [int]$DefaultMin
                target_max = [int]$DefaultMax
                target_source = "default"
            }
            $Sections += [pscustomobject]$Section
            $LastSection = $Sections[-1]
            continue
        }

        if ($null -ne $LastSection -and $Line -match "本节目标字数：\s*([0-9,，]+)\s*[-—]\s*([0-9,，]+)\s*字") {
            $LastSection.target_min = Parse-Number -Value $Matches[1]
            $LastSection.target_max = Parse-Number -Value $Matches[2]
            $LastSection.target_source = "toc"
            continue
        }
    }

    return @($Sections)
}

function Get-SectionMetrics {
    param(
        [Parameter(Mandatory=$true)]
        $Section,

        [Parameter(Mandatory=$true)]
        [string]$ChapterRoot
    )

    $FileName = "{0:D2}.md" -f [int]$Section.index
    $Path = Join-Path $ChapterRoot $FileName
    $Exists = Test-Path -LiteralPath $Path
    $CjkChars = 0
    $NonSpaceChars = 0
    $Heading = ""

    if ($Exists) {
        $Raw = Read-Utf8File -Path $Path
        $Body = Remove-FrontMatter -Content $Raw
        $CjkChars = Count-Pattern -Text $Body -Pattern "[\u4e00-\u9fff]"
        $NonSpaceChars = Count-Pattern -Text $Body -Pattern "\S"
        $HeadingMatch = [regex]::Match($Body, "(?m)^###\s+(.+?)\s*$")
        if ($HeadingMatch.Success) {
            $Heading = $HeadingMatch.Groups[1].Value.Trim()
        }
    }

    $TargetMin = [int]$Section.target_min
    $TargetMax = [int]$Section.target_max
    $OverMax = [Math]::Max(0, $CjkChars - $TargetMax)
    $BelowMin = [Math]::Max(0, $TargetMin - $CjkChars)
    $Status = if (-not $Exists) {
        "missing"
    }
    elseif ($CjkChars -lt $TargetMin) {
        "below_min"
    }
    elseif ($CjkChars -gt $TargetMax) {
        "over_max"
    }
    else {
        "within_budget"
    }

    return [pscustomobject][ordered]@{
        index = [int]$Section.index
        file = $FileName
        exists = [bool]$Exists
        title = if ([string]::IsNullOrWhiteSpace($Heading)) { [string]$Section.title } else { $Heading }
        toc_title = [string]$Section.title
        part = [string]$Section.part
        major = [string]$Section.major
        target_min = $TargetMin
        target_max = $TargetMax
        target_source = [string]$Section.target_source
        cjk_chars = [int]$CjkChars
        nonspace_chars = [int]$NonSpaceChars
        delta_to_min = [int]($CjkChars - $TargetMin)
        delta_to_max = [int]($CjkChars - $TargetMax)
        over_max = [int]$OverMax
        below_min = [int]$BelowMin
        status = $Status
    }
}

function New-Aggregate {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Items,

        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    $Existing = @($Items | Where-Object { $_.exists })
    $TotalActual = [int](($Existing | Measure-Object -Property cjk_chars -Sum).Sum)
    $TotalMin = [int](($Existing | Measure-Object -Property target_min -Sum).Sum)
    $TotalMax = [int](($Existing | Measure-Object -Property target_max -Sum).Sum)
    $OverItems = @($Existing | Where-Object { $_.status -eq "over_max" })
    $BelowItems = @($Existing | Where-Object { $_.status -eq "below_min" })
    $WithinItems = @($Existing | Where-Object { $_.status -eq "within_budget" })
    $OverAmount = [int](($Existing | Measure-Object -Property over_max -Sum).Sum)
    $BelowAmount = [int](($Existing | Measure-Object -Property below_min -Sum).Sum)
    $Average = if ($Existing.Count -gt 0) { [Math]::Round($TotalActual / $Existing.Count, 1) } else { 0 }
    $BudgetStatus = if ($TotalActual -lt $TotalMin) {
        "below_total_min"
    }
    elseif ($TotalActual -gt $TotalMax) {
        "over_total_max"
    }
    else {
        "within_total_budget"
    }

    return [pscustomobject][ordered]@{
        name = $Name
        section_count = [int]$Existing.Count
        total_cjk_chars = $TotalActual
        target_min = $TotalMin
        target_max = $TotalMax
        delta_to_target_min = [int]($TotalActual - $TotalMin)
        delta_to_target_max = [int]($TotalActual - $TotalMax)
        average_cjk_chars = $Average
        over_section_count = [int]$OverItems.Count
        within_section_count = [int]$WithinItems.Count
        below_section_count = [int]$BelowItems.Count
        total_over_max_chars = $OverAmount
        total_below_min_chars = $BelowAmount
        budget_status = $BudgetStatus
    }
}

function New-MajorAggregates {
    param([array]$Items)

    return @(
        $Items |
            Where-Object { $_.exists } |
            Group-Object -Property major |
            ForEach-Object {
                New-Aggregate -Items @($_.Group) -Name ([string]$_.Name)
            }
    )
}

function Format-RangeVerdict {
    param($Aggregate)

    if ($Aggregate.budget_status -eq "over_total_max") {
        return "超出上限 {0} 字" -f ([int]$Aggregate.delta_to_target_max)
    }

    if ($Aggregate.budget_status -eq "below_total_min") {
        return "低于下限 {0} 字" -f ([Math]::Abs([int]$Aggregate.delta_to_target_min))
    }

    return "在预算内，距上限还可增加 {0} 字" -f ([Math]::Abs([int]$Aggregate.delta_to_target_max))
}

function New-MarkdownReport {
    param(
        [Parameter(Mandatory=$true)]
        $Plan
    )

    $Lines = [System.Collections.Generic.List[string]]::new()
    $Lines.Add("# $($Plan.scope.name) 字数预算统计报告")
    $Lines.Add("")
    $Lines.Add("生成时间：$($Plan.generated_at)")
    $Lines.Add("")
    $Lines.Add("统计口径：中文字符数近似中文字数；不计 YAML front matter；章节标题计入正文统计。")
    $Lines.Add("")
    $Lines.Add("## 总体结论")
    $Lines.Add("")
    foreach ($Aggregate in $Plan.aggregates) {
        $Lines.Add("- $($Aggregate.name)：$($Aggregate.section_count) 个写作单元，实际 $($Aggregate.total_cjk_chars) 字；预算 $($Aggregate.target_min)-$($Aggregate.target_max) 字；$(Format-RangeVerdict -Aggregate $Aggregate)。")
        $Lines.Add("  局部状态：超上限小节 $($Aggregate.over_section_count) 个，累计超出 $($Aggregate.total_over_max_chars) 字；低于下限小节 $($Aggregate.below_section_count) 个，累计低于 $($Aggregate.total_below_min_chars) 字。")
    }
    $Lines.Add("")
    $Lines.Add("## 分章统计")
    $Lines.Add("")
    $Lines.Add("| 分章 | 单元数 | 实际字数 | 预算下限 | 预算上限 | 与上限差额 | 超上限小节 | 低于下限小节 |")
    $Lines.Add("|---|---:|---:|---:|---:|---:|---:|---:|")
    foreach ($Aggregate in $Plan.major_aggregates) {
        $Lines.Add("| $(Escape-MarkdownCell $Aggregate.name) | $($Aggregate.section_count) | $($Aggregate.total_cjk_chars) | $($Aggregate.target_min) | $($Aggregate.target_max) | $($Aggregate.delta_to_target_max) | $($Aggregate.over_section_count) | $($Aggregate.below_section_count) |")
    }
    $Lines.Add("")
    $Lines.Add("## 小节明细")
    $Lines.Add("")
    $Lines.Add("| 序号 | 文件 | 标题 | 实际字数 | 目标字数 | 状态 | 与上限差额 |")
    $Lines.Add("|---:|---|---|---:|---:|---|---:|")
    foreach ($Item in $Plan.items) {
        $Target = "{0}-{1}" -f $Item.target_min, $Item.target_max
        $Lines.Add("| $($Item.index) | $($Item.file) | $(Escape-MarkdownCell $Item.title) | $($Item.cjk_chars) | $Target | $($Item.status) | $($Item.delta_to_max) |")
    }
    $Lines.Add("")
    $Lines.Add("## 建议")
    $Lines.Add("")
    if (($Plan.aggregates | Where-Object { $_.name -eq "严格 Learn 第一部" }).budget_status -eq "over_total_max") {
        $Lines.Add("- Learn 第一部已经超出预算上限，下一轮编辑应优先处理 over_max 小节。")
    }
    else {
        $Lines.Add("- Learn 第一部总量仍在预算内，当前重点应放在局部超长小节和术语、占位语清理上。")
    }
    $Lines.Add("- 对大范围审核，建议先读本统计报告，再决定 04B33/04C44 的处理优先级。")

    return ($Lines -join "`r`n")
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context

$BookRoot = $Context.BookRoot
$BriefRoot = Join-Path $BookRoot "00_brief"
$TocPath = Join-Path $BookRoot "01_outline\toc.md"
$ChapterRoot = Join-Path $BookRoot "02_chapters"

if (!(Test-Path -LiteralPath $TocPath)) {
    throw "toc.md not found: $TocPath"
}
if (!(Test-Path -LiteralPath $ChapterRoot)) {
    throw "chapter root not found: $ChapterRoot"
}

$TocSections = Parse-TocSections -TocPath $TocPath -DefaultMin $BudgetMinPerSection -DefaultMax $BudgetMaxPerSection
if ($TocSections.Count -eq 0) {
    throw "No ### sections found in toc.md."
}

if (-not $EndChapter) {
    $EndChapter = $TocSections.Count
}
if ($StartChapter -lt 1 -or $EndChapter -lt $StartChapter) {
    throw "Invalid range: $StartChapter-$EndChapter"
}

$SelectedSections = @($TocSections | Where-Object { $_.index -ge $StartChapter -and $_.index -le $EndChapter })
if ($SelectedSections.Count -eq 0) {
    throw "No sections selected."
}

$Items = @($SelectedSections | ForEach-Object {
    Get-SectionMetrics -Section $_ -ChapterRoot $ChapterRoot
})

$LearnItems = @($Items | Where-Object { $_.index -ge 5 -and $_.index -le 35 })
$Aggregates = @(
    New-Aggregate -Items $Items -Name ("选定范围 {0}-{1}" -f $StartChapter, $EndChapter)
)
if ($LearnItems.Count -gt 0 -and ($StartChapter -ne 5 -or $EndChapter -ne 35)) {
    $Aggregates += New-Aggregate -Items $LearnItems -Name "严格 Learn 第一部"
}

$MajorAggregates = New-MajorAggregates -Items $Items
$RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$JsonPath = Join-Path $BriefRoot ("{0}_budget_statistics_{1}.json" -f $ScopeName, $RunStamp)
$StableJsonPath = Join-Path $BriefRoot ("{0}_budget_statistics.json" -f $ScopeName)
$ReportPath = Join-Path $BriefRoot ("{0}_budget_statistics_report_{1}.md" -f $ScopeName, $RunStamp)
$StableReportPath = Join-Path $BriefRoot ("{0}_budget_statistics_report.md" -f $ScopeName)

$Plan = [ordered]@{
    schema_version = "04B34.budget_statistics.v1"
    generated_by = "04b34-part-budget-statistics.ps1"
    generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    book_name = $BookName
    scope = [ordered]@{
        name = $ScopeName
        start_chapter = [int]$StartChapter
        end_chapter = [int]$EndChapter
        selected_count = [int]$Items.Count
    }
    budget_rules = [ordered]@{
        default_min_per_section = [int]$BudgetMinPerSection
        default_max_per_section = [int]$BudgetMaxPerSection
        full_book_target_min = 180000
        full_book_target_max = 220000
        source = $TocPath
    }
    paths = [ordered]@{
        book_root = $BookRoot
        toc = $TocPath
        chapter_root = $ChapterRoot
        dated_json = $JsonPath
        stable_json = $StableJsonPath
        dated_report = $ReportPath
        stable_report = $StableReportPath
    }
    aggregates = @($Aggregates)
    major_aggregates = @($MajorAggregates)
    items = @($Items)
}

$Json = $Plan | ConvertTo-Json -Depth 30
Save-Utf8File -Path $JsonPath -Content $Json
Save-Utf8File -Path $StableJsonPath -Content $Json

$Report = New-MarkdownReport -Plan $Plan
Save-Utf8File -Path $ReportPath -Content $Report
Save-Utf8File -Path $StableReportPath -Content $Report

Write-Output "SUCCESS: 04B34 budget statistics completed."
Write-Output "JSON: $JsonPath"
Write-Output "Stable JSON: $StableJsonPath"
Write-Output "Report: $ReportPath"
Write-Output "Stable report: $StableReportPath"
