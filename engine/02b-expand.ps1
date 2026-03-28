param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,

    [int]$Chapter,

    [switch]$All,

    [int]$StartChapter,
    [int]$EndChapter,

    [int]$MinSubsections = 3,
    [int]$MaxSubsections = 5,

    [string]$Model = "gpt-4o-mini"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "expand" -Data @{
    mode = if ($All) { "all" } elseif ($Chapter) { "chapter" } else { "range" }
    chapter = $Chapter
    start_chapter = $StartChapter
    end_chapter = $EndChapter
    model = $Model
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

if (-not $env:OPENAI_API_KEY) {
    Fail-SageStep -Context $Context -Step "expand" -Message "OPENAI_API_KEY not set." -Data @{}
    Write-Output "ERROR: OPENAI_API_KEY not set."
    exit 1
}

function Invoke-OpenAIResponse($Prompt) {
    $BodyObject = @{
        model = $Model
        input = $Prompt
    }

    $Json = $BodyObject | ConvertTo-Json -Depth 10 -Compress
    $Bytes = [System.Text.Encoding]::UTF8.GetBytes($Json)

    $Response = Invoke-RestMethod `
        -Uri "https://api.openai.com/v1/responses" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
            "Content-Type"  = "application/json; charset=utf-8"
        } `
        -Body $Bytes

    return $Response.output[0].content[0].text
}

$ObjectiveContent = Get-Content $ObjectivePath -Raw
$TocContent       = Get-Content $TocPath -Raw

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
            $Result = Invoke-OpenAIResponse $Prompt
        }
        catch {
            Fail-SageStep -Context $Context -Step "expand" -Message "OpenAI request failed during subsection expansion." -Data @{
                chapter_index = $chIndex
                section = $sec
                error = $_.Exception.Message
            }
            Write-Output "ERROR: OpenAI request failed."
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
    model = $Model
}

Write-Output "SUCCESS: toc2.md updated."
