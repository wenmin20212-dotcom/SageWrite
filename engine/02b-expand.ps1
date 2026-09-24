param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$Chapter,

    [switch]$All,

    [int]$StartChapter,
    [int]$EndChapter,

    [int]$MinSubsections = 3,
    [int]$MaxSubsections = 5,

    [string]$Model = ""
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath
$LlmPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-llm.ps1"
. $LlmPath

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
try {
    $LlmConfig = Get-SageLlmConfig
    if (-not [string]::IsNullOrWhiteSpace($Model)) {
        $LlmConfig.Model = $Model
    }
}
catch {
    Fail-SageStep -Context $Context -Step "expand" -Message "LLM configuration is invalid." -Data @{ error = $_.Exception.Message }
    Write-Output "ERROR: LLM configuration is invalid."
    Write-Output $_.Exception.Message
    exit 1
}
Set-SageCurrentStep -Context $Context -Step "expand" -Data @{
    mode = if ($All) { "all" } elseif ($Chapter) { "chapter" } else { "range" }
    chapter = $Chapter
    start_chapter = $StartChapter
    end_chapter = $EndChapter
    provider = $LlmConfig.Provider
    model = $LlmConfig.Model
    api_style = $LlmConfig.ApiStyle
}

$BookRoot = $Context.BookRoot

$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
$TocPath       = Join-Path $BookRoot "01_outline\toc.md"
$Toc2Path      = Join-Path $BookRoot "01_outline\toc2.md"

if (!(Test-Path $ObjectivePath)) {
    Fail-SageStep -Context $Context -Step "expand" -Message "objective.md not found." -Data @{ objective = $ObjectivePath }
    Write-Output "ERROR: objective.md not found."
    exit 1
}

if (!(Test-Path $TocPath)) {
    Fail-SageStep -Context $Context -Step "expand" -Message "toc.md not found." -Data @{ toc = $TocPath }
    Write-Output "ERROR: toc.md not found."
    exit 1
}

$ObjectiveContent = Get-Content $ObjectivePath -Raw -Encoding UTF8
$TocContent       = Get-Content $TocPath -Raw -Encoding UTF8

$Lines = $TocContent -split "`n"
$Chapters = @()
$CurrentChapter = ""
$Sections = @()

foreach ($line in $Lines) {
    if ($line -match '^##\s+(.+)$') {
        if ($CurrentChapter -ne "") {
            $Chapters += @{
                title = $CurrentChapter
                sections = $Sections
            }
        }

        $CurrentChapter = $Matches[1]
        $Sections = @()
        continue
    }

    if ($line -match '^###\s+(.+)$') {
        $Sections += $Matches[1]
    }
}

if ($CurrentChapter -ne "") {
    $Chapters += @{
        title = $CurrentChapter
        sections = $Sections
    }
}

$ChapterCount = $Chapters.Count
$ChapterList = @()

if ($All) {
    for ($i = 1; $i -le $ChapterCount; $i++) {
        $ChapterList += $i
    }
}
elseif ($StartChapter -and $EndChapter) {
    if ($StartChapter -lt 1 -or $EndChapter -gt $ChapterCount) {
        Fail-SageStep -Context $Context -Step "expand" -Message "Chapter range invalid." -Data @{
            start_chapter = $StartChapter
            end_chapter = $EndChapter
            chapter_count = $ChapterCount
        }
        Write-Output "ERROR: Chapter range invalid."
        exit 1
    }

    for ($i = $StartChapter; $i -le $EndChapter; $i++) {
        $ChapterList += $i
    }
}
elseif ($Chapter) {
    if ($Chapter -lt 1 -or $Chapter -gt $ChapterCount) {
        Fail-SageStep -Context $Context -Step "expand" -Message "Invalid chapter number." -Data @{
            chapter = $Chapter
            chapter_count = $ChapterCount
        }
        Write-Output "ERROR: Invalid chapter number."
        exit 1
    }

    $ChapterList += $Chapter
}
else {
    Fail-SageStep -Context $Context -Step "expand" -Message "No valid chapter selection provided." -Data @{}
    Write-Output "ERROR: Specify -Chapter, -All, or -StartChapter -EndChapter."
    exit 1
}

$OutputLines = @()
$OutputLines += "# Table of Contents"
$OutputLines += ""

foreach ($chIndex in $ChapterList) {
    $ch = $Chapters[$chIndex - 1]

    Write-Output "Expanding Chapter $chIndex : $($ch.title)"

    $OutputLines += "## $($ch.title)"
    $OutputLines += ""

    $secIndex = 0

    foreach ($sec in $ch.sections) {
        $secIndex++
        $OutputLines += "### $sec"

        $Prompt = @"
You are a professional academic book architect.

Book objective:
$ObjectiveContent

Chapter:
$($ch.title)

Section:
$sec

Generate $MinSubsections to $MaxSubsections subsections.

Output only titles, one per line.
"@

        try {
            $Result = Invoke-SageLlmText -Prompt $Prompt -Config $LlmConfig
        }
        catch {
            Fail-SageStep -Context $Context -Step "expand" -Message "LLM request failed during subsection expansion." -Data @{
                chapter_index = $chIndex
                section = $sec
                error = $_.Exception.Message
            }
            Write-Output "ERROR: LLM request failed."
            exit 1
        }

        $SubLines = $Result -split "`n"
        $subIndex = 0

        foreach ($s in $SubLines) {
            if ($s.Trim() -eq "") {
                continue
            }

            $subIndex++
            $OutputLines += "#### $chIndex.$secIndex.$subIndex $($s.Trim())"
        }

        $OutputLines += ""
    }
}

$OutputLines | Out-File $Toc2Path -Encoding utf8

Complete-SageStep -Context $Context -Step "expand" -State "success" -Message "Expanded TOC generated." -Data @{
    toc2 = $Toc2Path
    chapter_count = $ChapterList.Count
    min_subsections = $MinSubsections
    max_subsections = $MaxSubsections
    provider = $LlmConfig.Provider
    model = $LlmConfig.Model
    api_style = $LlmConfig.ApiStyle
}

Write-Output "SUCCESS: toc2.md updated."
