param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$StartChapter = 1,

    [int]$EndChapter = 999,

    [int]$MinSentenceLength = 18,

    [int]$DuplicateThreshold = 3,

    [string[]]$StockPatterns = @(
        "真正稀缺",
        "什么值得生成",
        "生成.*更容易",
        "更容易.*生成",
        "内容越容易",
        "生成门槛下降",
        "AI时代生成内容"
    ),

    [string]$ReportName = ""
)

[Console]::InputEncoding  = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Read-Utf8File {
    param([Parameter(Mandatory=$true)][string]$Path)
    return [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
}

function Save-Utf8File {
    param(
        [Parameter(Mandatory=$true)][string]$Path,
        [Parameter(Mandatory=$true)][AllowEmptyString()][string]$Content
    )

    $Parent = Split-Path -Parent $Path
    if (!(Test-Path -LiteralPath $Parent)) {
        New-Item -ItemType Directory -Path $Parent -Force | Out-Null
    }

    $Utf8Bom = New-Object System.Text.UTF8Encoding $true
    [System.IO.File]::WriteAllText($Path, $Content, $Utf8Bom)
}

function Remove-FrontMatter {
    param([string]$Content)
    $Normalized = $Content -replace "`r", ""
    return [regex]::Replace($Normalized, "(?s)^---\n.*?\n---\n?", "", 1)
}

function Escape-MarkdownCell {
    param([string]$Value)
    if ($null -eq $Value) { return "" }
    return (($Value -replace "\|", "/") -replace "`r?`n", " ").Trim()
}

function Shorten-Text {
    param(
        [string]$Text,
        [int]$MaxLength = 180
    )

    if ($null -eq $Text) { return "" }
    $Clean = (($Text -replace "\s+", " ").Trim())
    if ($Clean.Length -le $MaxLength) { return $Clean }
    return $Clean.Substring(0, $MaxLength) + "..."
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
$ChapterRoot = Join-Path $Context.BookRoot "02_chapters"
if (!(Test-Path -LiteralPath $ChapterRoot)) {
    throw "Chapter directory not found: $ChapterRoot"
}

$Files = Get-ChildItem -LiteralPath $ChapterRoot -File -Filter "*.md" |
    Where-Object { $_.BaseName -match "^\d+$" -and [int]$_.BaseName -ge $StartChapter -and [int]$_.BaseName -le $EndChapter } |
    Sort-Object { [int]$_.BaseName }

$SentenceRows = New-Object System.Collections.Generic.List[object]
$StockRows = New-Object System.Collections.Generic.List[object]

foreach ($File in $Files) {
    $Content = Remove-FrontMatter -Content (Read-Utf8File -Path $File.FullName)
    $BodyForSentence = [regex]::Replace($Content, "(?m)^#{1,6}\s+.*$", "")
    $Parts = [regex]::Split($BodyForSentence, "(?<=[。！？；!?;])\s*")

    foreach ($Part in $Parts) {
        $Sentence = (($Part -replace "\s+", "").Trim())
        if ($Sentence.Length -ge $MinSentenceLength) {
            $SentenceRows.Add([pscustomobject]@{
                Text = $Sentence
                File = $File.Name
            })
        }
    }

    $Lines = [System.IO.File]::ReadAllLines($File.FullName, [System.Text.Encoding]::UTF8)
    for ($Index = 0; $Index -lt $Lines.Count; $Index++) {
        foreach ($Pattern in $StockPatterns) {
            if ($Lines[$Index] -match $Pattern) {
                $StockRows.Add([pscustomobject]@{
                    File = $File.Name
                    Line = $Index + 1
                    Pattern = $Pattern
                    Text = $Lines[$Index].Trim()
                })
                break
            }
        }
    }
}

$DuplicateRows = $SentenceRows |
    Group-Object Text |
    Where-Object { $_.Count -ge $DuplicateThreshold } |
    Sort-Object Count -Descending |
    ForEach-Object {
        [pscustomobject]@{
            Count = $_.Count
            Files = (($_.Group | Select-Object -ExpandProperty File -Unique) -join ", ")
            Text = $_.Name
        }
    }

$Now = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$Stamp = Get-Date -Format "yyyyMMdd_HHmmss"
if ([string]::IsNullOrWhiteSpace($ReportName)) {
    $ReportName = "repeat_audit_$Stamp.md"
}
$ReportRoot = Join-Path $Context.BookRoot "04_output\editorial_audits"
$ReportPath = Join-Path $ReportRoot $ReportName

$LinesOut = New-Object System.Collections.Generic.List[string]
$LinesOut.Add("# 重复句与母句审计报告")
$LinesOut.Add("")
$LinesOut.Add("- 书名工程：$BookName")
$LinesOut.Add("- 审计范围：$StartChapter.md 到 $EndChapter.md")
$LinesOut.Add("- 生成时间：$Now")
$LinesOut.Add("- 最小句长：$MinSentenceLength")
$LinesOut.Add("- 重复阈值：同一句出现 $DuplicateThreshold 次及以上")
$LinesOut.Add("")
$LinesOut.Add("## 一、同句重复")
$LinesOut.Add("")
if ($DuplicateRows.Count -eq 0) {
    $LinesOut.Add("未发现同一句出现 $DuplicateThreshold 次及以上的问题。")
}
else {
    $LinesOut.Add("| 次数 | 文件 | 句子 |")
    $LinesOut.Add("|---:|---|---|")
    foreach ($Row in $DuplicateRows) {
        $LinesOut.Add("| $($Row.Count) | $(Escape-MarkdownCell $Row.Files) | $(Escape-MarkdownCell (Shorten-Text $Row.Text)) |")
    }
}

$LinesOut.Add("")
$LinesOut.Add("## 二、母句/高风险表达")
$LinesOut.Add("")
if ($StockRows.Count -eq 0) {
    $LinesOut.Add("未发现预设母句或高风险表达。")
}
else {
    $LinesOut.Add("| 文件 | 行号 | 命中模式 | 原句 |")
    $LinesOut.Add("|---|---:|---|---|")
    foreach ($Row in $StockRows) {
        $LinesOut.Add("| $($Row.File) | $($Row.Line) | $(Escape-MarkdownCell $Row.Pattern) | $(Escape-MarkdownCell (Shorten-Text $Row.Text)) |")
    }
}

$LinesOut.Add("")
$LinesOut.Add("## 三、编辑建议")
$LinesOut.Add("")
$LinesOut.Add("同一句不得第三次出现。对高风险表达，应改写为对应章节专属表达：前言写问题意识，L部分写输入能力，T部分写技术化输出，C部分写价值实现。")

Save-Utf8File -Path $ReportPath -Content ($LinesOut -join "`r`n")

Write-Host "Repeat audit completed."
Write-Host "Chapters: $($Files.Count)"
Write-Host "Duplicate sentence groups: $($DuplicateRows.Count)"
Write-Host "Stock phrase hits: $($StockRows.Count)"
Write-Host "Report: $ReportPath"
