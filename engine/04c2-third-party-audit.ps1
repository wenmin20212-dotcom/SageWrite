param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [Parameter(Mandatory=$true)]
    [string]$AuditPath,

    [string]$SourceName = "Third-party editorial audit",

    [string]$EditorialRunPath,

    [int]$Chapter,

    [int]$StartChapter,

    [int]$EndChapter,

    [string]$AuthorModel = "",

    [int]$RewriteMaxTokens = 7000,

    [switch]$NoEditorialLoopReports,

    [switch]$NoExportRevisionPlan,

    [switch]$ApplyRewrite,

    [switch]$Force
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

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [string]$Key
    )

    $Normalized = $Content -replace "`r", ""
    if (-not $Normalized.StartsWith("---`n")) {
        return ""
    }

    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---")
    if (-not $Match.Success) {
        return ""
    }

    foreach ($Line in ($Match.Groups[1].Value -split "`n")) {
        if ($Line -match "^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$") {
            return $Matches[1].Trim().Trim('"')
        }
    }

    return ""
}

function Get-FirstMarkdownHeadingTitle {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Match = [regex]::Match($Content, '(?m)^\s*#{1,6}\s+(.+?)\s*$')
    if ($Match.Success) {
        return $Match.Groups[1].Value.Trim()
    }

    return ""
}

function Resolve-ExistingPath {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Path
    )

    $Resolved = Resolve-Path -LiteralPath $Path -ErrorAction Stop
    return [System.IO.Path]::GetFullPath($Resolved.Path)
}

function Get-ShortText {
    param(
        [string]$Text,
        [int]$MaxChars = 280,
        [int]$MaxLines = 3
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return ""
    }

    $Lines = ($Text -replace "`r", "") -split "`n" |
        ForEach-Object { $_.Trim() } |
        Where-Object {
            -not [string]::IsNullOrWhiteSpace($_) -and
            $_ -ne "---" -and
            $_ -notmatch '^\|?\s*-{3,}'
        } |
        Select-Object -First $MaxLines

    $Joined = [string]::Join(" ", $Lines)
    $Joined = $Joined -replace '\s+', ' '
    if ($Joined.Length -gt $MaxChars) {
        return ($Joined.Substring(0, $MaxChars).TrimEnd() + "...")
    }

    return $Joined
}

function Escape-MarkdownTableCell {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return ""
    }

    return (($Value -replace "`r?`n", " ") -replace "\|", "\|").Trim()
}

function Get-AuditSections {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Matches = [regex]::Matches($Content, '(?m)^\s{0,3}(#{1,6})\s+(.+?)\s*$')
    $Sections = @()

    if ($Matches.Count -gt 0 -and $Matches[0].Index -gt 0) {
        $Preamble = $Content.Substring(0, $Matches[0].Index).Trim()
        if (-not [string]::IsNullOrWhiteSpace($Preamble)) {
            $Sections += [pscustomobject]@{
                Level = 1
                Title = "总体结论"
                Body  = $Preamble
                Order = 0
            }
        }
    }

    for ($i = 0; $i -lt $Matches.Count; $i++) {
        $Match = $Matches[$i]
        $Start = $Match.Index + $Match.Length
        $End = if ($i + 1 -lt $Matches.Count) { $Matches[$i + 1].Index } else { $Content.Length }
        $Length = [Math]::Max(0, $End - $Start)
        $Body = $Content.Substring($Start, $Length).Trim()

        $Sections += [pscustomobject]@{
            Level = $Match.Groups[1].Value.Length
            Title = $Match.Groups[2].Value.Trim()
            Body  = $Body
            Order = $i + 1
        }
    }

    if ($Sections.Count -eq 0) {
        $Sections += [pscustomobject]@{
            Level = 1
            Title = "第三方编辑审计报告"
            Body  = $Content.Trim()
            Order = 0
        }
    }

    return $Sections
}

function Get-AuditPriority {
    param(
        [string]$Title,
        [string]$Body
    )

    $Text = "$Title`n$Body"
    if ($Text -match "第一优先级|必须|硬任务|最大结构问题|一定要|不建议继续增加|正式出版前") {
        return "P0"
    }
    if ($Text -match "需要|建议|缺|容易|风险|不宜|混淆|重写|统一") {
        return "P1"
    }

    return "P2"
}

function Get-AuditCategory {
    param(
        [string]$Title,
        [string]$Body
    )

    $Text = "$Title`n$Body"
    if ($Text -match "字数|减法|删|合并|三级标题|目录|篇幅|重排|重组") {
        return "结构与篇幅"
    }
    if ($Text -match "C部分|COCVI|创造五观|模型太多|主模型|LTC|MCAR|GOAL|DIGIT") {
        return "模型体系"
    }
    if ($Text -match "学术|参考文献|依据|证据|引用|原创|理论来源|实证") {
        return "学术依据"
    }
    if ($Text -match "语言|句式|作者声音|模板|叙述|文风|节奏") {
        return "语言风格"
    }
    if ($Text -match "第一章|开头|第一页|开篇") {
        return "开篇设计"
    }
    if ($Text -match "标题|绝对判断|传播性") {
        return "标题风险"
    }
    if ($Text -match "案例|人物|场景|中学生|教师|工程师|创业者") {
        return "案例系统"
    }
    if ($Text -match "图|图示|模型图|视觉|IP") {
        return "视觉模型"
    }
    if ($Text -match "部首|第一部|第二部|第三部|Part") {
        return "部结构"
    }
    if ($Text -match "术语|学力|学习力|技术能力|Transfer|Interface Agency|Instrumental Agility|Techno-Ethical") {
        return "术语统一"
    }
    if ($Text -match "前言|结语|索引|出版组件|参考文献|术语表") {
        return "出版组件"
    }

    return "综合编辑"
}

function Convert-AuditToItems {
    param(
        [Parameter(Mandatory=$true)]
        [array]$Sections
    )

    $MajorSections = $Sections | Where-Object {
        $_.Title -eq "总体结论" -or
        $_.Title -match '^[一二三四五六七八九十]+、' -or
        $_.Title -match '^我作为'
    }

    $Items = @()
    $Index = 1
    foreach ($Section in $MajorSections) {
        $Priority = Get-AuditPriority -Title $Section.Title -Body $Section.Body
        $Category = Get-AuditCategory -Title $Section.Title -Body $Section.Body
        $Excerpt = Get-ShortText -Text $Section.Body -MaxChars 360 -MaxLines 4

        $Items += [pscustomobject]@{
            Id       = ("TP-{0:D2}" -f $Index)
            Priority = $Priority
            Category = $Category
            Title    = $Section.Title
            Excerpt  = $Excerpt
            SourceOrder = $Section.Order
        }
        $Index++
    }

    return $Items
}

function Get-KeyActions {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [array]$Items
    )

    $Actions = @()
    $Matches = [regex]::Matches($Content, '(?m)^\s*\d+\.\s+\*\*(.+?)\*\*')
    foreach ($Match in $Matches) {
        $Text = $Match.Groups[1].Value.Trim().TrimEnd("；", ";", "。", ".")
        if (-not [string]::IsNullOrWhiteSpace($Text) -and $Actions -notcontains $Text) {
            $Actions += $Text
        }
    }

    if ($Actions.Count -eq 0) {
        $Actions = $Items |
            Where-Object { $_.Priority -in @("P0", "P1") } |
            Select-Object -First 8 -ExpandProperty Title
    }

    return $Actions
}

function Get-LatestEditorialArtifacts {
    param(
        [Parameter(Mandatory=$true)]
        [hashtable]$Context,

        [string]$RunPath,

        [switch]$Disabled
    )

    if ($Disabled) {
        return @{
            source = ""
            reports = @()
            revision_plans = @()
        }
    }

    $CandidateRunPath = $RunPath
    $Source = ""

    if ([string]::IsNullOrWhiteSpace($CandidateRunPath)) {
        $LatestPath = Join-Path $Context.LogRoot "editorial_loop\latest.json"
        if (Test-Path -LiteralPath $LatestPath) {
            $Latest = Get-Content -LiteralPath $LatestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($Latest.run_root) {
                $CandidateRunPath = [string]$Latest.run_root
                $Source = $LatestPath
            }
            elseif ($Latest.reports -or $Latest.revision_plans) {
                $Reports = @()
                $Plans = @()
                if ($Latest.reports) {
                    foreach ($Path in $Latest.reports) {
                        if (Test-Path -LiteralPath $Path) {
                            $Reports += [string]$Path
                        }
                    }
                }
                if ($Latest.revision_plans) {
                    foreach ($Path in $Latest.revision_plans) {
                        if (Test-Path -LiteralPath $Path) {
                            $Plans += [string]$Path
                        }
                    }
                }

                return @{
                    source = $LatestPath
                    reports = @($Reports)
                    revision_plans = @($Plans)
                }
            }
        }
    }
    else {
        $CandidateRunPath = Resolve-ExistingPath -Path $CandidateRunPath
        $Source = $CandidateRunPath
    }

    $Reports = @()
    $Plans = @()
    if (-not [string]::IsNullOrWhiteSpace($CandidateRunPath) -and (Test-Path -LiteralPath $CandidateRunPath)) {
        $ManifestPath = Join-Path $CandidateRunPath "manifest.json"
        if (Test-Path -LiteralPath $ManifestPath) {
            $Manifest = Get-Content -LiteralPath $ManifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
            if ($Manifest.reports) {
                foreach ($Path in $Manifest.reports) {
                    if (Test-Path -LiteralPath $Path) {
                        $Reports += [string]$Path
                    }
                }
            }
            if ($Manifest.revision_plans) {
                foreach ($Path in $Manifest.revision_plans) {
                    if (Test-Path -LiteralPath $Path) {
                        $Plans += [string]$Path
                    }
                }
            }
            $Source = $ManifestPath
        }
        else {
            $Reports = Get-ChildItem -LiteralPath $CandidateRunPath -Filter "editorial_report_*.md" -File |
                Sort-Object Name |
                Select-Object -ExpandProperty FullName
            $Plans = Get-ChildItem -LiteralPath $CandidateRunPath -Filter "revision_plan_*.md" -File |
                Sort-Object Name |
                Select-Object -ExpandProperty FullName
        }
    }

    return @{
        source = $Source
        reports = @($Reports)
        revision_plans = @($Plans)
    }
}

function New-MasterReport {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookTitle,

        [Parameter(Mandatory=$true)]
        [string]$SourceName,

        [Parameter(Mandatory=$true)]
        [string]$AuditSourcePath,

        [Parameter(Mandatory=$true)]
        [string]$ArchivedAuditPath,

        [Parameter(Mandatory=$true)]
        [array]$Items,

        [Parameter(Mandatory=$true)]
        [array]$KeyActions,

        [Parameter(Mandatory=$true)]
        [hashtable]$EditorialArtifacts,

        [string]$ObjectiveExcerpt,

        [string]$ConstitutionPath
    )

    $Sb = [System.Text.StringBuilder]::new()
    [void]$Sb.AppendLine("# 第三方编辑审计总报告")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("书名：$BookTitle")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("外部来源：$SourceName")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("导入时间：$(Get-Date -Format "yyyy-MM-dd HH:mm:ss")")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("原始报告：$AuditSourcePath")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("归档报告：$ArchivedAuditPath")
    [void]$Sb.AppendLine("")
    if (-not [string]::IsNullOrWhiteSpace($ConstitutionPath)) {
        [void]$Sb.AppendLine("作品宪法：$ConstitutionPath")
        [void]$Sb.AppendLine("")
    }
    [void]$Sb.AppendLine("## 一、合并原则")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("第三方审计意见作为独立外部来源进入 SageWrite 的总编辑系统。它不自动覆盖作品宪法，也不直接替作者决定改稿方向；作者AI必须对每条高优先级意见做接受、部分接受或 Author Override。")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("总报告采用三层判断：作品宪法固定核心命题；第三方报告提供出版级外部审计；04C内部编辑报告负责继续做结构、逻辑、读者体验和文字层面的复核。")
    [void]$Sb.AppendLine("")

    if (-not [string]::IsNullOrWhiteSpace($ObjectiveExcerpt)) {
        [void]$Sb.AppendLine("## 二、当前写作目标摘录")
        [void]$Sb.AppendLine("")
        [void]$Sb.AppendLine($ObjectiveExcerpt)
        [void]$Sb.AppendLine("")
    }

    [void]$Sb.AppendLine("## 三、第三方报告的核心退修意见")
    [void]$Sb.AppendLine("")
    if ($KeyActions.Count -gt 0) {
        $ActionIndex = 1
        foreach ($Action in $KeyActions) {
            [void]$Sb.AppendLine("$ActionIndex. $Action")
            $ActionIndex++
        }
    }
    else {
        [void]$Sb.AppendLine("未提取到明确编号的核心退修意见，请以行动矩阵为准。")
    }
    [void]$Sb.AppendLine("")

    [void]$Sb.AppendLine("## 四、行动矩阵")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("| ID | 优先级 | 类别 | 第三方意见 | 摘要 |")
    [void]$Sb.AppendLine("|---|---|---|---|---|")
    foreach ($Item in $Items) {
        [void]$Sb.AppendLine("| $($Item.Id) | $($Item.Priority) | $(Escape-MarkdownTableCell $Item.Category) | $(Escape-MarkdownTableCell $Item.Title) | $(Escape-MarkdownTableCell $Item.Excerpt) |")
    }
    [void]$Sb.AppendLine("")

    [void]$Sb.AppendLine("## 五、与04C编辑报告的关系")
    [void]$Sb.AppendLine("")
    if ($EditorialArtifacts.reports.Count -gt 0) {
        [void]$Sb.AppendLine("已发现可合并的04C内部编辑报告：")
        [void]$Sb.AppendLine("")
        foreach ($Report in $EditorialArtifacts.reports) {
            [void]$Sb.AppendLine("- $Report")
        }
        [void]$Sb.AppendLine("")
    }
    else {
        [void]$Sb.AppendLine("当前没有发现可合并的04C内部编辑报告。后续运行04C时，将自动读取本次生成的外部审计简报。")
        [void]$Sb.AppendLine("")
    }
    if ($EditorialArtifacts.revision_plans.Count -gt 0) {
        [void]$Sb.AppendLine("已发现04C作者修订计划：")
        [void]$Sb.AppendLine("")
        foreach ($Plan in $EditorialArtifacts.revision_plans) {
            [void]$Sb.AppendLine("- $Plan")
        }
        [void]$Sb.AppendLine("")
    }
    [void]$Sb.AppendLine("合并时应优先处理 P0 项，再处理 P1 项；凡涉及删减、合并、章节重排、术语统一和参考文献建设的意见，必须进入作者AI的 Revision Plan。")
    [void]$Sb.AppendLine("")

    [void]$Sb.AppendLine("## 六、建议执行顺序")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("1. 先确认本报告中的 P0/P1 意见哪些接受、哪些部分接受、哪些需要 Author Override。")
    [void]$Sb.AppendLine("2. 再运行04C的 Developmental 或 FullDiagnostic，让内部编辑AI带着外部审计简报复核全书。")
    [void]$Sb.AppendLine("3. 形成最终 Revision Plan 后，再决定是否调用03进行章节重写。")
    [void]$Sb.AppendLine("4. 重写后重新生成PDF/EPUB，并再次检查目录层级、章节起页、页眉页脚、参考文献和图表位置。")
    [void]$Sb.AppendLine("")

    return $Sb.ToString()
}

function New-ExternalBrief {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookTitle,

        [Parameter(Mandatory=$true)]
        [string]$SourceName,

        [Parameter(Mandatory=$true)]
        [string]$ArchivedAuditPath,

        [Parameter(Mandatory=$true)]
        [array]$Items,

        [Parameter(Mandatory=$true)]
        [array]$KeyActions
    )

    $Sb = [System.Text.StringBuilder]::new()
    [void]$Sb.AppendLine("# 外部编辑审计简报")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("书名：$BookTitle")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("来源：$SourceName")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("归档原文：$ArchivedAuditPath")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("使用规则：这是第三方责任编辑视角的外部审计，不是作品宪法。编辑AI必须严肃参考；作者AI必须逐项判断接受、部分接受或 Author Override。")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("## 核心退修意见")
    [void]$Sb.AppendLine("")
    $ActionIndex = 1
    foreach ($Action in $KeyActions) {
        [void]$Sb.AppendLine("$ActionIndex. $Action")
        $ActionIndex++
    }
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("## 高优先级行动")
    [void]$Sb.AppendLine("")
    foreach ($Item in ($Items | Where-Object { $_.Priority -in @("P0", "P1") })) {
        [void]$Sb.AppendLine("- [$($Item.Priority)] $($Item.Category)：$($Item.Title)")
        if (-not [string]::IsNullOrWhiteSpace($Item.Excerpt)) {
            [void]$Sb.AppendLine("  摘要：$($Item.Excerpt)")
        }
    }
    [void]$Sb.AppendLine("")

    return $Sb.ToString()
}

function New-RevisionPlan {
    param(
        [Parameter(Mandatory=$true)]
        [string]$BookTitle,

        [Parameter(Mandatory=$true)]
        [string]$MasterReportPath,

        [Parameter(Mandatory=$true)]
        [array]$Items,

        [Parameter(Mandatory=$true)]
        [array]$KeyActions
    )

    $P0Items = @($Items | Where-Object { $_.Priority -eq "P0" })
    $P1Items = @($Items | Where-Object { $_.Priority -eq "P1" })

    $Sb = [System.Text.StringBuilder]::new()
    [void]$Sb.AppendLine("# 第三方编辑审计退修计划")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("书名：$BookTitle")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("来源总报告：$MasterReportPath")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("## 1. 处理原则")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("本计划来自第三方责任编辑审计。作者AI不能机械服从，但必须对每条 P0/P1 意见给出明确处理：接受、部分接受或 Author Override。")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("## 2. P0 必须处理项")
    [void]$Sb.AppendLine("")
    foreach ($Item in $P0Items) {
        [void]$Sb.AppendLine("- $($Item.Id) $($Item.Category)：$($Item.Title)")
        if (-not [string]::IsNullOrWhiteSpace($Item.Excerpt)) {
            [void]$Sb.AppendLine("  审计摘要：$($Item.Excerpt)")
        }
    }
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("## 3. P1 优先处理项")
    [void]$Sb.AppendLine("")
    foreach ($Item in $P1Items) {
        [void]$Sb.AppendLine("- $($Item.Id) $($Item.Category)：$($Item.Title)")
    }
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("## 4. 核心退修动作")
    [void]$Sb.AppendLine("")
    if ($KeyActions.Count -gt 0) {
        $ActionIndex = 1
        foreach ($Action in $KeyActions) {
            [void]$Sb.AppendLine("$ActionIndex. $Action")
            $ActionIndex++
        }
    }
    else {
        [void]$Sb.AppendLine("以 P0/P1 行动矩阵为准。")
    }
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("## 5. 03-write 操作指令")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("重写时请把全书从完整理论稿推进为正式出版稿：先做删减、合并和重排，再做术语统一、证据补强、标题降风险、案例体系化和语言去模板化。")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("必须保留 LTC 的核心IP和作者观点，但要降低不必要的绝对判断，明确理论来源、原创边界和未经实证验证的部分。")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("C部分必须重新审视模型负担：优先把 COCVI 与创造五观看作同一核心模型的理论名和中文教学表达，避免让读者误以为 C 部分有多个并列主模型。")
    [void]$Sb.AppendLine("")
    [void]$Sb.AppendLine("第一章开头、终章高潮、部首、模型图、参考文献、术语表和出版组件，必须作为正式出版前的结构工程来处理。")
    [void]$Sb.AppendLine("")

    return $Sb.ToString()
}

function Get-ScopedChapterFiles {
    param(
        [Parameter(Mandatory=$true)]
        [string]$ChapterRoot,

        [int]$Chapter,

        [int]$StartChapter,

        [int]$EndChapter
    )

    if (!(Test-Path -LiteralPath $ChapterRoot)) {
        throw "Chapter folder not found: $ChapterRoot"
    }

    $AllFiles = @(Get-ChildItem -LiteralPath $ChapterRoot -Filter "*.md" -File |
        Where-Object { $_.Name -notmatch "^_" -and $_.FullName -notmatch "\\back\\" } |
        Sort-Object Name)

    if ($AllFiles.Count -eq 0) {
        throw "No chapter markdown files found in $ChapterRoot"
    }

    if ($Chapter -gt 0) {
        if ($Chapter -gt $AllFiles.Count) {
            throw "Chapter index $Chapter is outside available chapter count $($AllFiles.Count)."
        }
        return @($AllFiles[$Chapter - 1])
    }

    if ($StartChapter -gt 0 -or $EndChapter -gt 0) {
        $Start = if ($StartChapter -gt 0) { $StartChapter } else { 1 }
        $End = if ($EndChapter -gt 0) { $EndChapter } else { $AllFiles.Count }
        if ($Start -lt 1 -or $End -gt $AllFiles.Count -or $Start -gt $End) {
            throw "Invalid chapter range $Start-$End for available chapter count $($AllFiles.Count)."
        }

        return @($AllFiles[($Start - 1)..($End - 1)])
    }

    return $AllFiles
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "third_party_editorial_audit" -Data @{
    audit_path = $AuditPath
    source_name = $SourceName
    apply_rewrite = [bool]$ApplyRewrite
}

try {
    $BookRoot = $Context.BookRoot
    $ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
    $TocPath = Join-Path $BookRoot "01_outline\toc.md"
    $ConstitutionPath = Join-Path $BookRoot "00_brief\book_constitution.md"
    $ChapterRoot = Join-Path $BookRoot "02_chapters"
    $BriefRoot = Join-Path $BookRoot "00_brief"
    $RevisionPlanRoot = Join-Path $BriefRoot "revision_plans"
    $ThirdPartyRoot = Join-Path $BriefRoot "third_party_audits"
    $LoopRoot = Join-Path $Context.LogRoot "editorial_loop"
    $RunStamp = Get-Date -Format "yyyyMMdd_HHmmss"
    $RunRoot = Join-Path $LoopRoot ("{0}_third_party" -f $RunStamp)

    if (!(Test-Path -LiteralPath $BookRoot)) {
        throw "Book workspace not found: $BookRoot"
    }

    $ResolvedAuditPath = Resolve-ExistingPath -Path $AuditPath
    $AuditContent = Read-Utf8File -Path $ResolvedAuditPath
    if ([string]::IsNullOrWhiteSpace($AuditContent)) {
        throw "Third-party audit report is empty: $ResolvedAuditPath"
    }

    New-Item -ItemType Directory -Path $RunRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $ThirdPartyRoot -Force | Out-Null
    New-Item -ItemType Directory -Path $RevisionPlanRoot -Force | Out-Null

    $OriginalExtension = [System.IO.Path]::GetExtension($ResolvedAuditPath)
    if ([string]::IsNullOrWhiteSpace($OriginalExtension)) {
        $OriginalExtension = ".txt"
    }
    $SourceCopyPath = Join-Path $RunRoot ("source_audit{0}" -f $OriginalExtension)
    Copy-Item -LiteralPath $ResolvedAuditPath -Destination $SourceCopyPath -Force

    $ArchivedAuditPath = Join-Path $ThirdPartyRoot ("{0}_third_party_audit.md" -f $RunStamp)
    Save-Utf8File -Path $ArchivedAuditPath -Content $AuditContent

    $ObjectiveContent = if (Test-Path -LiteralPath $ObjectivePath) { Get-Content -LiteralPath $ObjectivePath -Raw -Encoding UTF8 } else { "" }
    $TocContent = if (Test-Path -LiteralPath $TocPath) { Get-Content -LiteralPath $TocPath -Raw -Encoding UTF8 } else { "" }
    $BookTitle = Get-FrontMatterValue -Content $ObjectiveContent -Key "title"
    if ([string]::IsNullOrWhiteSpace($BookTitle)) {
        $BookTitle = Get-FirstMarkdownHeadingTitle -Content $ObjectiveContent
    }
    if ([string]::IsNullOrWhiteSpace($BookTitle)) {
        $BookTitle = $BookName
    }

    $ObjectiveExcerpt = Get-ShortText -Text $ObjectiveContent -MaxChars 600 -MaxLines 8
    $Sections = Get-AuditSections -Content $AuditContent
    $Items = Convert-AuditToItems -Sections $Sections
    $KeyActions = Get-KeyActions -Content $AuditContent -Items $Items
    $EditorialArtifacts = Get-LatestEditorialArtifacts -Context $Context -RunPath $EditorialRunPath -Disabled:$NoEditorialLoopReports

    $MasterReportPath = Join-Path $RunRoot "master_editorial_report.md"
    $MasterReport = New-MasterReport `
        -BookTitle $BookTitle `
        -SourceName $SourceName `
        -AuditSourcePath $ResolvedAuditPath `
        -ArchivedAuditPath $ArchivedAuditPath `
        -Items $Items `
        -KeyActions $KeyActions `
        -EditorialArtifacts $EditorialArtifacts `
        -ObjectiveExcerpt $ObjectiveExcerpt `
        -ConstitutionPath $(if (Test-Path -LiteralPath $ConstitutionPath) { $ConstitutionPath } else { "" })
    Save-Utf8File -Path $MasterReportPath -Content $MasterReport

    $CurrentMasterPath = Join-Path $BriefRoot "editorial_master_report.md"
    Save-Utf8File -Path $CurrentMasterPath -Content $MasterReport

    $ExternalBriefPath = Join-Path $BriefRoot "external_editorial_brief.md"
    $ExternalBrief = New-ExternalBrief `
        -BookTitle $BookTitle `
        -SourceName $SourceName `
        -ArchivedAuditPath $ArchivedAuditPath `
        -Items $Items `
        -KeyActions $KeyActions
    Save-Utf8File -Path $ExternalBriefPath -Content $ExternalBrief

    $RevisionPlanPath = Join-Path $RunRoot "third_party_revision_plan.md"
    $RevisionPlan = New-RevisionPlan `
        -BookTitle $BookTitle `
        -MasterReportPath $MasterReportPath `
        -Items $Items `
        -KeyActions $KeyActions
    Save-Utf8File -Path $RevisionPlanPath -Content $RevisionPlan

    $BriefRevisionPlanPath = ""
    if (-not $NoExportRevisionPlan) {
        $BriefRevisionPlanPath = Join-Path $RevisionPlanRoot ("{0}_third_party_audit.md" -f $RunStamp)
        Save-Utf8File -Path $BriefRevisionPlanPath -Content $RevisionPlan
    }

    $AppliedRewrite = $false
    $RewriteBackupRoot = ""
    if ($ApplyRewrite) {
        $ScopedFiles = Get-ScopedChapterFiles -ChapterRoot $ChapterRoot -Chapter $Chapter -StartChapter $StartChapter -EndChapter $EndChapter
        $FirstIndex = [Array]::IndexOf(@(Get-ChildItem -LiteralPath $ChapterRoot -Filter "*.md" -File | Where-Object { $_.Name -notmatch "^_" -and $_.FullName -notmatch "\\back\\" } | Sort-Object Name), $ScopedFiles[0]) + 1
        $LastIndex = [Array]::IndexOf(@(Get-ChildItem -LiteralPath $ChapterRoot -Filter "*.md" -File | Where-Object { $_.Name -notmatch "^_" -and $_.FullName -notmatch "\\back\\" } | Sort-Object Name), $ScopedFiles[$ScopedFiles.Count - 1]) + 1
        $ScopeText = "chapter_files=$($ScopedFiles.Count); range=$FirstIndex-$LastIndex; files=" + (($ScopedFiles | Select-Object -ExpandProperty Name) -join ", ")

        $RewriteInstructions = @"
# Third Party Editorial Rewrite Instructions

Scope:
$ScopeText

Use the third-party editorial audit revision plan below as rewrite guidance.
Do not mechanically obey every suggestion; preserve the book constitution and use Author Override where an external suggestion damages the core thesis.

$RevisionPlan
"@

        $BackupRoot = Join-Path $ChapterRoot "back"
        $RewriteBackupRoot = Join-Path $BackupRoot ("third_party_audit_rewrite_{0}" -f $RunStamp)
        New-Item -ItemType Directory -Path $RewriteBackupRoot -Force | Out-Null
        foreach ($File in $ScopedFiles) {
            Copy-Item -LiteralPath $File.FullName -Destination (Join-Path $RewriteBackupRoot $File.Name) -Force
        }

        $WriteScript = Join-Path $Context.EnginePath "03-write.ps1"
        $WriteArgs = @(
            "-BookName", $BookName,
            "-Model", $AuthorModel,
            "-MaxTokens", ([string]$RewriteMaxTokens),
            "-AdditionalInstructions", $RewriteInstructions,
            "-Force"
        )
        if ($Chapter) {
            $WriteArgs += @("-Chapter", ([string]$Chapter))
        }
        elseif ($StartChapter -gt 0 -or $EndChapter -gt 0) {
            $WriteArgs += @("-StartChapter", ([string]$FirstIndex), "-EndChapter", ([string]$LastIndex))
        }

        Write-Output "Applying third-party audit rewrite through 03-write.ps1..."
        & $WriteScript @WriteArgs
        if ($LASTEXITCODE -ne 0) {
            throw "03-write.ps1 failed during third-party audit rewrite."
        }
        $AppliedRewrite = $true
    }

    $AuditHash = (Get-FileHash -LiteralPath $ResolvedAuditPath -Algorithm SHA256).Hash
    $ManifestPath = Join-Path $RunRoot "manifest.json"
    $Manifest = [ordered]@{
        generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        book_name = $BookName
        book_title = $BookTitle
        source_name = $SourceName
        source_audit = $ResolvedAuditPath
        source_sha256 = $AuditHash
        archived_audit = $ArchivedAuditPath
        master_report = $MasterReportPath
        current_master_report = $CurrentMasterPath
        external_editorial_brief = $ExternalBriefPath
        revision_plan = $RevisionPlanPath
        exported_revision_plan = $BriefRevisionPlanPath
        editorial_artifact_source = $EditorialArtifacts.source
        editorial_reports = $EditorialArtifacts.reports
        editorial_revision_plans = $EditorialArtifacts.revision_plans
        item_count = $Items.Count
        p0_count = @($Items | Where-Object { $_.Priority -eq "P0" }).Count
        p1_count = @($Items | Where-Object { $_.Priority -eq "P1" }).Count
        apply_rewrite = [bool]$ApplyRewrite
        applied_rewrite = $AppliedRewrite
        rewrite_backup = $RewriteBackupRoot
        run_root = $RunRoot
    }
    $Manifest | ConvertTo-Json -Depth 10 | Out-File $ManifestPath -Encoding utf8

    $LatestThirdPartyPath = Join-Path $LoopRoot "latest_third_party.json"
    $LatestObject = [ordered]@{
        generated_at = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        book_name = $BookName
        source_name = $SourceName
        manifest = $ManifestPath
        master_report = $MasterReportPath
        current_master_report = $CurrentMasterPath
        external_editorial_brief = $ExternalBriefPath
        revision_plan = $RevisionPlanPath
        exported_revision_plan = $BriefRevisionPlanPath
        run_root = $RunRoot
    }
    $LatestObject | ConvertTo-Json -Depth 10 | Out-File $LatestThirdPartyPath -Encoding utf8

    Complete-SageStep -Context $Context -Step "third_party_editorial_audit" -State "success" -Message "Third-party editorial audit imported." -Data @{
        master_report = $MasterReportPath
        external_editorial_brief = $ExternalBriefPath
        revision_plan = $RevisionPlanPath
        manifest = $ManifestPath
        apply_rewrite = [bool]$ApplyRewrite
    }

    Write-Output "SUCCESS: Third-party editorial audit imported."
    Write-Output "Run folder: $RunRoot"
    Write-Output "Master report: $MasterReportPath"
    Write-Output "Current master report: $CurrentMasterPath"
    Write-Output "External brief for 04C: $ExternalBriefPath"
    Write-Output "Revision plan: $RevisionPlanPath"
    if (-not [string]::IsNullOrWhiteSpace($BriefRevisionPlanPath)) {
        Write-Output "Exported revision plan: $BriefRevisionPlanPath"
    }
    if ($AppliedRewrite) {
        Write-Output "Rewrite backup saved: $RewriteBackupRoot"
    }
}
catch {
    $Message = $_.Exception.Message
    Fail-SageStep -Context $Context -Step "third_party_editorial_audit" -Message $Message -Data @{
        audit_path = $AuditPath
        apply_rewrite = [bool]$ApplyRewrite
    }
    Write-Error $Message
    exit 1
}
