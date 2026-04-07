param(
    [Parameter(Mandatory=$true)]
    [string]$BookName,
    [switch]$Strict
)

$ErrorActionPreference = "Stop"

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Get-LocText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Key
    )

    $map = @{
        pass = "6YCa6L+H"
        warning = "6K2m5ZGK"
        error = "6ZSZ6K+v"
        info = "5L+h5oGv"
        check1 = "5bel5L2c5Yy65qOA5p+l"
        check2 = "56ug6IqC55uu5b2V5qOA5p+l"
        check3 = "5Y+v5p6E5bu656ug6IqC5paH5Lu25qOA5p+l"
        check4 = "UGFuZG9jIOeOr+Wig+ajgOafpQ=="
        check5 = "56ug6IqC55uu5b2V5Li05pe25paH5Lu25qOA5p+l"
        check6 = "6L6T5Ye655uu5b2V5Li05pe25paH5Lu25qOA5p+l"
        check7 = "56ug6IqC5ZG95ZCN6KeE6IyD5qOA5p+l"
        check8 = "56ug6IqC6L+e57ut5oCn5qOA5p+l"
        check9 = "5paH5Lu25o6S5bqP5LiA6Ie05oCn5qOA5p+l"
        check10 = "56ug6IqC5q2j5paH6Z2e56m65qOA5p+l"
        check11 = "56ug6IqC6ZW/5bqm5ZCI55CG5oCn5qOA5p+l"
        check12 = "56ug6IqCIFRva2VuIOS4iumZkOaIquaWreajgOafpQ=="
        check13 = "VE9ETyDljaDkvY3nrKbmo4Dmn6U="
        report = "U2FnZVdyaXRlIOaehOW7uuWJjeajgOafpeaKpeWRig=="
        book = "5Lmm5ZCN5Luj5Y+377ya"
        runtime = "5qOA5p+l5pe26Ze077ya"
        summary = "5pGY6KaB"
        errors = "6ZSZ6K+v77ya"
        warnings = "6K2m5ZGK77ya"
        infos = "5L+h5oGv77ya"
        build = "5Y+v5p6E5bu654q25oCB77ya"
        build_no = "5LiN5Y+v55u05o6l5p6E5bu6"
        build_warn = "5Y+v5p6E5bu677yI5L2G5pyJ6K2m5ZGK77yJ"
        build_yes = "5Y+v55u05o6l5p6E5bu6"
        checklist = "5qOA5p+l5riF5Y2V"
        issues = "6Zeu6aKY5piO57uG"
        noissues = "5pyq5Y+R546w6Zeu6aKY44CC"
        workspace_found = "5bey5om+5Yiw5bel5L2c5Yy677ya"
        chapter_found = "5bey5om+5Yiw56ug6IqC55uu5b2V77ya"
        found = "5om+5YiwIA=="
        buildable_suffix = "IOS4quWPr+eUqOS6juaehOW7uueahCBNYXJrZG93biDnq6DoioLmlofku7bjgII="
        pandoc_yes = "UGFuZG9jIOW3suWcqCBQQVRIIOS4reWPr+eUqOOAgg=="
        pandoc_no = "5pyq5om+5YiwIFBhbmRvY++8jDA1LWJ1aWxkLnBzMSDlsIbkvJrlpLHotKXjgII="
        temp_chapter_yes = "5ZyoIDAyX2NoYXB0ZXJzIOS4reajgOa1i+WIsOS4tOaXtuaWh+S7tu+8mg=="
        temp_chapter_no = "5ZyoIDAyX2NoYXB0ZXJzIOS4reacquajgOa1i+WIsOS4tOaXtuaWh+S7tuOAgg=="
        temp_output_yes = "5ZyoIDA0X291dHB1dCDkuK3mo4DmtYvliLAgV29yZCDkuLTml7bmlofku7bvvJo="
        temp_output_no = "5Zyo6L6T5Ye655uu5b2V5Lit5pyq5qOA5rWL5YiwIFdvcmQg5Li05pe25paH5Lu244CC"
        non_numeric = "5qOA5rWL5Yiw6Z2e5pWw5a2X5ZG95ZCN55qE5Y+v5p6E5bu6IE1hcmtkb3duIOaWh+S7tu+8mg=="
        all_numeric = "5omA5pyJ5Y+v5p6E5bu6IE1hcmtkb3duIOaWh+S7tumDveS9v+eUqOaVsOWtl+eroOiKguWRveWQjeOAgg=="
        missing = "57y65aSx56ug6IqC77ya"
        dup_suffix = "77yb5ZCM5pe25qOA5rWL5Yiw6YeN5aSN5oiW5Lmx5bqP57yW5Y+344CC"
        dup_only = "5qOA5rWL5Yiw6YeN5aSN5oiW5Lmx5bqP56ug6IqC57yW5Y+344CC"
        continuity = "5pWw5a2X56ug6IqC5bqP5YiX6L+e57ut44CC"
        sort_bad = "5paH5Lu25ZCN5a2X5YW45bqP5LiO5pWw5a2X56ug6IqC6aG65bqP5LiN5LiA6Ie044CC"
        sort_ok = "5paH5Lu25ZCN5o6S5bqP5LiO5pWw5a2X56ug6IqC6aG65bqP5LiA6Ie044CC"
        no_numeric_cont = "5rKh5pyJ5Y+v55So5LqO6L+e57ut5oCn5qCh6aqM55qE5pWw5a2X56ug6IqC5paH5Lu244CC"
        no_numeric_sort = "5rKh5pyJ5Y+v55So5LqO5o6S5bqP5qCh6aqM55qE5pWw5a2X56ug6IqC5paH5Lu244CC"
        empty = "5Lul5LiL56ug6IqC5Li656m65oiW5LuF5YyF5ZCrIGZyb250IG1hdHRlcu+8mg=="
        body_ok = "5omA5pyJ5Y+v5p6E5bu656ug6IqC5paH5Lu26YO95YyF5ZCr5q2j5paH5YaF5a6544CC"
        short = "5Lul5LiL56ug6IqC56+H5bmF6L+H55+t77yM5Y+v6IO95YaF5a655LiN5a6M5pW077ya"
        short_ok = "5rKh5pyJ56ug6IqC5Zug56+H5bmF6L+H55+t6ICM6KKr5qCH6K6w44CC"
        token_hit = "5Lul5LiL56ug6IqC6L6+5Yiw5oiW6LS06L+RIG1heF90b2tlbnMg5LiK6ZmQ77ya"
        token_hit_exact = "5Lul5LiL56ug6IqC6L6+5YiwIG1heF90b2tlbnMg5LiK6ZmQ77ya"
        token_hit_none = "5pyq5Y+R546w56ug6IqC6L6+5YiwIG1heF90b2tlbnMg5LiK6ZmQ44CC"
        token_meta_missing = "5Lul5LiL56ug6IqC57y65bCRIHRva2VuIOeUqOmHj+WFg+aVsOaNru+8mg=="
        todo = "5Lul5LiL56ug6IqC5Lit5Y+R546wIFRPRE8g5Y2g5L2N56ym77ya"
        todo_ok = "5Y+v5p6E5bu656ug6IqC5paH5Lu25Lit5pyq5Y+R546wIFRPRE8g5Y2g5L2N56ym44CC"
        issue_no_build = "5ZyoIDAyX2NoYXB0ZXJzIOS4reacquaJvuWIsOWPr+eUqOS6juaehOW7uueahCBNYXJrZG93biDnq6DoioLmlofku7bjgII="
        issue_temp_chapter = "5Zyo56ug6IqC55uu5b2V5Lit5qOA5rWL5Yiw5Li05pe25paH5Lu25oiW556s5oCB5paH5Lu244CC"
        issue_temp_output = "5Zyo6L6T5Ye655uu5b2V5Lit5qOA5rWL5YiwIFdvcmQg5Li05pe25paH5Lu244CC"
        issue_non_numeric = "5Y+v5p6E5bu6IE1hcmtkb3duIOaWh+S7tuacquS9v+eUqOaVsOWtl+WRveWQje+8jDA1LWJ1aWxkLnBzMSDlj6/og73kvJrmiorlroPmlL7liLDmnIDlkI7jgII="
        issue_missing_before = "5Zyo6K+l5paH5Lu25LmL5YmN55qE5pWw5a2X56ug6IqC5bqP5YiX5Lit5a2Y5Zyo57y65aSx5paH5Lu244CC"
        issue_missing_expected = "MDJfY2hhcHRlcnMg5Lit57y65bCR6aKE5pyf55qE56ug6IqC5paH5Lu244CC"
        issue_duplicate = "5qOA5rWL5Yiw6YeN5aSN5oiW5Lmx5bqP55qE56ug6IqC57yW5Y+344CC"
        issue_empty = "56ug6IqC5paH5Lu25Li656m677yM5oiW5LuF5YyF5ZCrIGZyb250IG1hdHRlcuOAgg=="
        issue_short = "56ug6IqC5YaF5a655byC5bi4566A55+t77yM5Y+v6IO95bCa5pyq5a6M5oiQ44CC"
        issue_token_missing = "56ug6IqC57y65bCRIHRva2VuIOeUqOmHj+WFg+aVsOaNru+8jOaXoOazleWIpOaWreaYr+WQpuinpui+vuS4iumZkOOAgg=="
        issue_token_hit = "56ug6IqC6L6T5Ye6IHRva2VuIOi+vuWIsCBtYXhfdG9rZW5zIOS4iumZkO+8jOWPr+iDveacqueUn+aIkOWujOOAgg=="
        issue_todo = "5Y+R546wIFRPRE8g5Y2g5L2N56ym44CC"
    }

    if ($map.ContainsKey($Key)) {
        return [System.Text.Encoding]::UTF8.GetString([System.Convert]::FromBase64String($map[$Key]))
    }

    return $Key
}

function Get-LocalizedStatus {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Status
    )

    switch ($Status) {
        "Pass" { return (Get-LocText "pass") }
        "Warning" { return (Get-LocText "warning") }
        "Error" { return (Get-LocText "error") }
        "Info" { return (Get-LocText "info") }
        default { return $Status }
    }
}

function Get-LocalizedCheckName {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name
    )

    switch ($Name) {
        "1. Workspace check" { return "1. $(Get-LocText 'check1')" }
        "2. Chapter folder check" { return "2. $(Get-LocText 'check2')" }
        "3. Buildable chapter files check" { return "3. $(Get-LocText 'check3')" }
        "4. Pandoc availability check" { return "4. $(Get-LocText 'check4')" }
        "5. Chapter temp-file check" { return "5. $(Get-LocText 'check5')" }
        "6. Output temp-file check" { return "6. $(Get-LocText 'check6')" }
        "7. Chapter naming check" { return "7. $(Get-LocText 'check7')" }
        "8. Chapter continuity check" { return "8. $(Get-LocText 'check8')" }
        "9. File sort-order check" { return "9. $(Get-LocText 'check9')" }
        "10. Chapter body presence check" { return "10. $(Get-LocText 'check10')" }
        "11. Chapter length sanity check" { return "11. $(Get-LocText 'check11')" }
        "12. Token-limit truncation check" { return "12. $(Get-LocText 'check12')" }
        "13. TODO marker check" { return "13. $(Get-LocText 'check13')" }
        "14. Whole-document fenced markdown check" { return "14. æ•´ç«  Markdown ä»£ç å—åŒ…è£¹æ£€æŸ¥" }
        default { return $Name }
    }
}
function Get-LocalizedCheckDetail {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Detail
    )

    if ($Detail -match '^Workspace found:\s+(.+)$') {
        return "$(Get-LocText 'workspace_found')$($Matches[1])"
    }
    if ($Detail -match '^Chapter folder found:\s+(.+)$') {
        return "$(Get-LocText 'chapter_found')$($Matches[1])"
    }
    if ($Detail -match '^Found\s+(\d+)\s+buildable markdown chapter file\(s\)\.$') {
        return "$(Get-LocText 'found')$($Matches[1])$(Get-LocText 'buildable_suffix')"
    }
    if ($Detail -eq "Pandoc is available in PATH.") {
        return (Get-LocText 'pandoc_yes')
    }
    if ($Detail -eq "Pandoc not found. 05-build.ps1 will fail.") {
        return (Get-LocText 'pandoc_no')
    }
    if ($Detail -match '^Temporary files detected in 02_chapters:\s+(.+)$') {
        return "$(Get-LocText 'temp_chapter_yes')$($Matches[1])"
    }
    if ($Detail -eq "No temporary or transient files detected in 02_chapters.") {
        return (Get-LocText 'temp_chapter_no')
    }
    if ($Detail -match '^Word temporary files detected in 04_output:\s+(.+)$') {
        return "$(Get-LocText 'temp_output_yes')$($Matches[1])"
    }
    if ($Detail -eq "No Word temporary files detected in output folder.") {
        return (Get-LocText 'temp_output_no')
    }
    if ($Detail -match '^Non-numeric buildable markdown files:\s+(.+)$') {
        return "$(Get-LocText 'non_numeric')$($Matches[1])"
    }
    if ($Detail -eq "All buildable markdown files use numeric chapter naming.") {
        return (Get-LocText 'all_numeric')
    }
    if ($Detail -match '^Missing chapters:\s+(.+)\s+Duplicate or unsorted numbering detected\.$') {
        return "$(Get-LocText 'missing')$($Matches[1])$(Get-LocText 'dup_suffix')"
    }
    if ($Detail -match '^Missing chapters:\s+(.+)$') {
        return "$(Get-LocText 'missing')$($Matches[1])"
    }
    if ($Detail -eq "Duplicate or unsorted numbering detected.") {
        return (Get-LocText 'dup_only')
    }
    if ($Detail -eq "Numeric chapter sequence is continuous.") {
        return (Get-LocText 'continuity')
    }
    if ($Detail -eq "Filename sort order does not match numeric chapter order.") {
        return (Get-LocText 'sort_bad')
    }
    if ($Detail -eq "Filename sort order matches numeric chapter order.") {
        return (Get-LocText 'sort_ok')
    }
    if ($Detail -eq "No numeric chapter files available for continuity validation.") {
        return (Get-LocText 'no_numeric_cont')
    }
    if ($Detail -eq "No numeric chapter files available for sort-order validation.") {
        return (Get-LocText 'no_numeric_sort')
    }
    if ($Detail -match '^Empty or front-matter-only chapter files:\s+(.+)$') {
        return "$(Get-LocText 'empty')$($Matches[1])"
    }
    if ($Detail -eq "All buildable chapter files contain body content.") {
        return (Get-LocText 'body_ok')
    }
    if ($Detail -match '^Potentially incomplete short chapters:\s+(.+)$') {
        return "$(Get-LocText 'short')$($Matches[1])"
    }
    if ($Detail -eq "No chapter files were flagged as unusually short.") {
        return (Get-LocText 'short_ok')
    }
    if ($Detail -match '^Chapters that reached max_tokens:\s+(.+)$') {
        return "$(Get-LocText 'token_hit_exact')$($Matches[1])"
    }
    if ($Detail -match '^Token usage metadata missing in:\s+(.+)$') {
        return "$(Get-LocText 'token_meta_missing')$($Matches[1])"
    }
    if ($Detail -eq "No chapters were flagged as hitting the max token limit.") {
        return (Get-LocText 'token_hit_none')
    }
    if ($Detail -match '^TODO markers found in:\s+(.+)$') {
        return "$(Get-LocText 'todo')$($Matches[1])"
    }
    if ($Detail -eq "No TODO markers found in buildable chapter files.") {
        return (Get-LocText 'todo_ok')
    }
    if ($Detail -match '^Chapters wrapped in whole-document markdown fences:\s+(.+)$') {
        return "以下章节被整章 markdown 代码块包裹：$($Matches[1])"
    }
    if ($Detail -eq "No chapters were wrapped in whole-document markdown fences.") {
        return "未发现整章被 Markdown 代码块整体包裹的章节。"
    }

    return $Detail
}

function Get-LocalizedIssueMessage {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Message
    )

    switch ($Message) {
        "No buildable markdown chapter files found in 02_chapters." { return (Get-LocText 'issue_no_build') }
        "Pandoc not found. 05-build.ps1 will fail." { return (Get-LocText 'pandoc_no') }
        "Temporary or transient file detected in chapter folder." { return (Get-LocText 'issue_temp_chapter') }
        "Word temporary file detected in output folder." { return (Get-LocText 'issue_temp_output') }
        "Buildable markdown file does not use numeric chapter naming. 05-build.ps1 may place it at the end." { return (Get-LocText 'issue_non_numeric') }
        "Missing chapter file in numeric sequence before this file." { return (Get-LocText 'issue_missing_before') }
        "Expected chapter file is missing from 02_chapters." { return (Get-LocText 'issue_missing_expected') }
        "Duplicate or unsorted chapter numbering detected." { return (Get-LocText 'issue_duplicate') }
        "Chapter file is empty or contains only front matter." { return (Get-LocText 'issue_empty') }
        "Chapter content looks unusually short and may be incomplete." { return (Get-LocText 'issue_short') }
        "Token usage metadata missing; token-limit check could not be verified." { return (Get-LocText 'issue_token_missing') }
        "Chapter output tokens reached max_tokens and may be truncated." { return (Get-LocText 'issue_token_hit') }
        "Found TODO marker." { return (Get-LocText 'issue_todo') }
        "Chapter body is wrapped in a whole-document markdown code fence." { return "章节正文被整章 Markdown 代码块包裹，标题可能无法进入目录。" }
        default { return $Message }
    }
}
$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "edit" -Data @{
    strict = [bool]$Strict
}

$WorkspaceRoot = $Context.WorkspaceRoot
$BookRoot = $Context.BookRoot
$ChapterRoot = Join-Path $BookRoot "02_chapters"
$OutputRoot = Join-Path $BookRoot "04_output"
$LogRoot = $Context.LogRoot

function Add-Issue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Type,

        [Parameter(Mandatory=$true)]
        [string]$Message,

        [string]$File = "",

        [int]$Line = 0
    )

    $script:issues += [PSCustomObject]@{
        Type = $Type
        File = $File
        Line = $Line
        Message = $Message
    }
}

function Add-CheckResult {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [Parameter(Mandatory=$true)]
        [ValidateSet("Pass", "Warning", "Error", "Info")]
        [string]$Status,

        [Parameter(Mandatory=$true)]
        [string]$Detail
    )

    $script:checks += [PSCustomObject]@{
        Name = $Name
        Status = $Status
        Detail = $Detail
    }
}

function Get-MarkdownBodyText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    if ($Normalized.StartsWith("---`n")) {
        $Match = [regex]::Match($Normalized, "(?s)^---\n.*?\n---\n?")
        if ($Match.Success) {
            return $Normalized.Substring($Match.Length).Trim()
        }
    }

    return $Normalized.Trim()
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
        return $null
    }

    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---\n?")
    if (-not $Match.Success) {
        return $null
    }

    $Pattern = "(?m)^" + [regex]::Escape($Key) + ":\s*(.+?)\s*$"
    $ValueMatch = [regex]::Match($Match.Groups[1].Value, $Pattern)
    if (-not $ValueMatch.Success) {
        return $null
    }

    return $ValueMatch.Groups[1].Value.Trim().Trim('"')
}

function Test-WholeDocumentMarkdownFence {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content
    )

    $Normalized = $Content -replace "`r", ""
    return [regex]::IsMatch($Normalized.Trim(), '^(?:```markdown|```md|```)\s*\n[\s\S]*\n```$')
}

if (!(Test-Path $WorkspaceRoot)) {
    Fail-SageStep -Context $Context -Step "edit" -Message "Workspace not found." -Data @{
        workspace = $WorkspaceRoot
    }
    Write-Error "Workspace not found: $WorkspaceRoot"
    exit 1
}

if (!(Test-Path $ChapterRoot)) {
    Fail-SageStep -Context $Context -Step "edit" -Message "02_chapters folder not found." -Data @{
        chapter_root = $ChapterRoot
    }
    Write-Error "02_chapters folder not found"
    exit 1
}

if (!(Test-Path $LogRoot)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
}

$issues = @()
$checks = @()

Add-CheckResult -Name "1. Workspace check" -Status "Pass" -Detail "Workspace found: $WorkspaceRoot"
Add-CheckResult -Name "2. Chapter folder check" -Status "Pass" -Detail "Chapter folder found: $ChapterRoot"

$allChapterItems = Get-ChildItem $ChapterRoot -Force | Sort-Object Name
$markdownFiles = Get-ChildItem $ChapterRoot -Filter *.md -File | Sort-Object Name
$buildFiles = $markdownFiles | Where-Object { $_.Name -notmatch "^_" -and $_.Name -notmatch "^~\$" }

if ($buildFiles.Count -eq 0) {
    Add-Issue -Type "Error" -Message "No buildable markdown chapter files found in 02_chapters." -File $ChapterRoot
    Add-CheckResult -Name "3. Buildable chapter files check" -Status "Error" -Detail "No buildable markdown chapter files found in 02_chapters."
}
else {
    Add-CheckResult -Name "3. Buildable chapter files check" -Status "Pass" -Detail "Found $($buildFiles.Count) buildable markdown chapter file(s)."
}

if (!(Get-Command pandoc -ErrorAction SilentlyContinue)) {
    Add-Issue -Type "Error" -Message "Pandoc not found. 05-build.ps1 will fail." -File "pandoc"
    Add-CheckResult -Name "4. Pandoc availability check" -Status "Error" -Detail "Pandoc not found. 05-build.ps1 will fail."
}
else {
    Add-CheckResult -Name "4. Pandoc availability check" -Status "Pass" -Detail "Pandoc is available in PATH."
}

$tempPatterns = @(
    '^_metadata\.yaml$',
    '^~\$',
    '\.tmp$',
    '\.temp$',
    '\.bak$',
    '\.backup$'
)

$chapterTempHits = @()
foreach ($item in $allChapterItems) {
    foreach ($pattern in $tempPatterns) {
        if ($item.Name -match $pattern) {
            Add-Issue -Type "Warning" -Message "Temporary or transient file detected in chapter folder." -File $item.Name
            $chapterTempHits += $item.Name
            break
        }
    }
}

if ($chapterTempHits.Count -gt 0) {
    $uniqueChapterTempHits = @($chapterTempHits | Sort-Object -Unique)
    Add-CheckResult -Name "5. Chapter temp-file check" -Status "Warning" -Detail ("Temporary files detected in 02_chapters: " + ($uniqueChapterTempHits -join ", "))
}
else {
    Add-CheckResult -Name "5. Chapter temp-file check" -Status "Pass" -Detail "No temporary or transient files detected in 02_chapters."
}

$wordTempFiles = @()
if (Test-Path $OutputRoot) {
    $wordTempFiles = @(Get-ChildItem $OutputRoot -Force | Where-Object { $_.Name -match '^~\$' })
    foreach ($tempFile in $wordTempFiles) {
        Add-Issue -Type "Warning" -Message "Word temporary file detected in output folder." -File $tempFile.FullName
    }
}

if ($wordTempFiles.Count -gt 0) {
    Add-CheckResult -Name "6. Output temp-file check" -Status "Warning" -Detail ("Word temporary files detected in 04_output: " + (($wordTempFiles | Select-Object -ExpandProperty Name) -join ", "))
}
else {
    Add-CheckResult -Name "6. Output temp-file check" -Status "Pass" -Detail "No Word temporary files detected in output folder."
}

$numberedFiles = @()
$nonNumberedBuildFiles = @()
foreach ($file in $buildFiles) {
    if ($file.BaseName -match '^\d+$') {
        $numberedFiles += [PSCustomObject]@{
            Name = $file.Name
            Number = [int]$file.BaseName
            FullName = $file.FullName
        }
    }
    else {
        $nonNumberedBuildFiles += $file
        Add-Issue -Type "Warning" -Message "Buildable markdown file does not use numeric chapter naming. 05-build.ps1 may place it at the end." -File $file.Name
    }
}

if ($nonNumberedBuildFiles.Count -gt 0) {
    Add-CheckResult -Name "7. Chapter naming check" -Status "Warning" -Detail ("Non-numeric buildable markdown files: " + (($nonNumberedBuildFiles | Select-Object -ExpandProperty Name) -join ", "))
}
elseif ($buildFiles.Count -gt 0) {
    Add-CheckResult -Name "7. Chapter naming check" -Status "Pass" -Detail "All buildable markdown files use numeric chapter naming."
}

if ($numberedFiles.Count -gt 0) {
    $sortedNumbers = $numberedFiles | Sort-Object Number
    $expected = 1
    $missingChapterNames = @()
    $hasDuplicateOrUnsortedNumbers = $false

    foreach ($item in $sortedNumbers) {
        if ($item.Number -gt $expected) {
            Add-Issue -Type "Error" -Message "Missing chapter file in numeric sequence before this file." -File $item.Name
            while ($expected -lt $item.Number) {
                $missingName = ("{0:D2}.md" -f $expected)
                Add-Issue -Type "Error" -Message "Expected chapter file is missing from 02_chapters." -File $missingName
                $missingChapterNames += $missingName
                $expected++
            }
        }

        if ($item.Number -lt $expected) {
            Add-Issue -Type "Error" -Message "Duplicate or unsorted chapter numbering detected." -File $item.Name
            $hasDuplicateOrUnsortedNumbers = $true
        }

        $expected = [Math]::Max($expected, $item.Number + 1)
    }

    if ($missingChapterNames.Count -gt 0 -or $hasDuplicateOrUnsortedNumbers) {
        $continuityDetails = @()
        if ($missingChapterNames.Count -gt 0) {
            $continuityDetails += "Missing chapters: $($missingChapterNames -join ', ')"
        }
        if ($hasDuplicateOrUnsortedNumbers) {
            $continuityDetails += "Duplicate or unsorted numbering detected."
        }
        Add-CheckResult -Name "8. Chapter continuity check" -Status "Error" -Detail ($continuityDetails -join " ")
    }
    else {
        Add-CheckResult -Name "8. Chapter continuity check" -Status "Pass" -Detail "Numeric chapter sequence is continuous."
    }

    $sortedByName = $numberedFiles | Sort-Object Name | Select-Object -ExpandProperty Number
    $sortedByNumber = $numberedFiles | Sort-Object Number | Select-Object -ExpandProperty Number
    if ((@($sortedByName) -join ",") -ne (@($sortedByNumber) -join ",")) {
        Add-Issue -Type "Warning" -Message "Filename sort order does not match numeric chapter order." -File $ChapterRoot
        Add-CheckResult -Name "9. File sort-order check" -Status "Warning" -Detail "Filename sort order does not match numeric chapter order."
    }
    else {
        Add-CheckResult -Name "9. File sort-order check" -Status "Pass" -Detail "Filename sort order matches numeric chapter order."
    }
}
elseif ($buildFiles.Count -gt 0) {
    Add-CheckResult -Name "8. Chapter continuity check" -Status "Warning" -Detail "No numeric chapter files available for continuity validation."
    Add-CheckResult -Name "9. File sort-order check" -Status "Warning" -Detail "No numeric chapter files available for sort-order validation."
}

$emptyFiles = @()
$shortFiles = @()
$tokenLimitedFiles = @()
$tokenMetadataMissingFiles = @()
$todoFiles = @()
$wholeDocumentFencedFiles = @()
foreach ($file in $buildFiles) {
    $raw = Get-Content $file.FullName -Raw
    $body = Get-MarkdownBodyText -Content $raw
    $maxTokensRaw = Get-FrontMatterValue -Content $raw -Key "max_tokens"
    $outputTokensRaw = Get-FrontMatterValue -Content $raw -Key "output_tokens"

    if ([string]::IsNullOrWhiteSpace($body)) {
        Add-Issue -Type "Error" -Message "Chapter file is empty or contains only front matter." -File $file.Name
        $emptyFiles += $file.Name
        continue
    }

    $lineCount = ($body -split "`r?`n").Count
    $charCount = $body.Length

    if ($charCount -lt 200 -or $lineCount -lt 5) {
        Add-Issue -Type "Warning" -Message "Chapter content looks unusually short and may be incomplete." -File $file.Name
        $shortFiles += $file.Name
    }

    if (Test-WholeDocumentMarkdownFence -Content $body) {
        Add-Issue -Type "Error" -Message "Chapter body is wrapped in a whole-document markdown code fence." -File $file.Name
        $wholeDocumentFencedFiles += $file.Name
    }

    $maxTokens = 0
    $outputTokens = 0
    $hasMaxTokens = [int]::TryParse([string]$maxTokensRaw, [ref]$maxTokens)
    $hasOutputTokens = [int]::TryParse([string]$outputTokensRaw, [ref]$outputTokens)

    if ($hasMaxTokens -and $hasOutputTokens -and $maxTokens -gt 0) {
        if ($outputTokens -ge $maxTokens) {
            Add-Issue -Type "Error" -Message "Chapter output tokens reached max_tokens and may be truncated." -File $file.Name
            $tokenLimitedFiles += ("{0} ({1}/{2})" -f $file.Name, $outputTokens, $maxTokens)
        }
    }
    else {
        Add-Issue -Type "Warning" -Message "Token usage metadata missing; token-limit check could not be verified." -File $file.Name
        $tokenMetadataMissingFiles += $file.Name
    }

    if ($raw.Contains("TODO")) {
        Add-Issue -Type "Warning" -Message "Found TODO marker." -File $file.Name
        $todoFiles += $file.Name
    }
}

if ($emptyFiles.Count -gt 0) {
    Add-CheckResult -Name "10. Chapter body presence check" -Status "Error" -Detail ("Empty or front-matter-only chapter files: " + ($emptyFiles -join ", "))
}
else {
    Add-CheckResult -Name "10. Chapter body presence check" -Status "Pass" -Detail "All buildable chapter files contain body content."
}

if ($shortFiles.Count -gt 0) {
    Add-CheckResult -Name "11. Chapter length sanity check" -Status "Warning" -Detail ("Potentially incomplete short chapters: " + ($shortFiles -join ", "))
}
else {
    Add-CheckResult -Name "11. Chapter length sanity check" -Status "Pass" -Detail "No chapter files were flagged as unusually short."
}

if ($tokenLimitedFiles.Count -gt 0) {
    Add-CheckResult -Name "12. Token-limit truncation check" -Status "Error" -Detail ("Chapters that reached max_tokens: " + ($tokenLimitedFiles -join ", "))
}
elseif ($tokenMetadataMissingFiles.Count -gt 0) {
    Add-CheckResult -Name "12. Token-limit truncation check" -Status "Warning" -Detail ("Token usage metadata missing in: " + ($tokenMetadataMissingFiles -join ", "))
}
else {
    Add-CheckResult -Name "12. Token-limit truncation check" -Status "Pass" -Detail "No chapters were flagged as hitting the max token limit."
}

if ($todoFiles.Count -gt 0) {
    Add-CheckResult -Name "13. TODO marker check" -Status "Warning" -Detail ("TODO markers found in: " + ($todoFiles -join ", "))
}
else {
    Add-CheckResult -Name "13. TODO marker check" -Status "Pass" -Detail "No TODO markers found in buildable chapter files."
}

if ($wholeDocumentFencedFiles.Count -gt 0) {
    Add-CheckResult -Name "14. Whole-document fenced markdown check" -Status "Error" -Detail ("Chapters wrapped in whole-document markdown fences: " + ($wholeDocumentFencedFiles -join ", "))
}
else {
    Add-CheckResult -Name "14. Whole-document fenced markdown check" -Status "Pass" -Detail "No chapters were wrapped in whole-document markdown fences."
}

$errorCount = [int](($issues | Where-Object { $_.Type -eq "Error" }).Count)
$warnCount = [int](($issues | Where-Object { $_.Type -eq "Warning" }).Count)
$infoCount = [int](($issues | Where-Object { $_.Type -eq "Info" }).Count)

$reportPath = Join-Path $LogRoot "edit_report.txt"
$jsonReportPath = Join-Path $LogRoot "edit_report.json"
$ReportHistoryRoot = Join-Path $LogRoot "edit_report_history"
$ReportStamp = Get-Date -Format "yyyyMMdd_HHmmss"
$archivedReportPath = Join-Path $ReportHistoryRoot ("edit_report_{0}.txt" -f $ReportStamp)
$archivedJsonReportPath = Join-Path $ReportHistoryRoot ("edit_report_{0}.json" -f $ReportStamp)

$buildReadyText = "YES"
if ($errorCount -gt 0) {
    $buildReadyText = "NO"
}
elseif ($warnCount -gt 0) {
    $buildReadyText = "YES (with warnings)"
}

$buildReadyLocalized = Get-LocText "build_yes"
if ($buildReadyText -eq "NO") {
    $buildReadyLocalized = Get-LocText "build_no"
}
elseif ($buildReadyText -eq "YES (with warnings)") {
    $buildReadyLocalized = Get-LocText "build_warn"
}

$runTimeText = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$reportLines = @()
$reportLines += "SageWrite Build Preflight Check"
$reportLines += (Get-LocText "report")
$reportLines += "BookName: $BookName"
$reportLines += "$(Get-LocText 'book')$BookName"
$reportLines += "Run Time: $runTimeText"
$reportLines += "$(Get-LocText 'runtime')$runTimeText"
$reportLines += ""
$reportLines += "Summary"
$reportLines += (Get-LocText "summary")
$reportLines += "Errors: $errorCount"
$reportLines += "$(Get-LocText 'errors')$errorCount"
$reportLines += "Warnings: $warnCount"
$reportLines += "$(Get-LocText 'warnings')$warnCount"
$reportLines += "Infos: $infoCount"
$reportLines += "$(Get-LocText 'infos')$infoCount"
$reportLines += "Build Ready: $buildReadyText"
$reportLines += "$(Get-LocText 'build')$buildReadyLocalized"
$reportLines += ""
$reportLines += "Checklist"
$reportLines += (Get-LocText "checklist")

foreach ($check in $checks) {
    $reportLines += "[$($check.Status)] $($check.Name)"
    $reportLines += "[$(Get-LocalizedStatus -Status $check.Status)] $(Get-LocalizedCheckName -Name $check.Name)"
    $reportLines += "  $($check.Detail)"
    $reportLines += "  $(Get-LocalizedCheckDetail -Detail $check.Detail)"
    $reportLines += ""
}

$reportLines += "Issues"
$reportLines += (Get-LocText "issues")
if ($issues.Count -eq 0) {
    $reportLines += "No issues found."
    $reportLines += (Get-LocText "noissues")
}
else {
    foreach ($issue in $issues) {
        $location = if ($issue.File) { $issue.File } else { "-" }
        if ($issue.Line -gt 0) {
            $location = "${location}:$($issue.Line)"
        }
        $reportLines += "[$($issue.Type)] [$location] $($issue.Message)"
        $reportLines += "[$(Get-LocalizedStatus -Status $issue.Type)] [$location] $(Get-LocalizedIssueMessage -Message $issue.Message)"
    }
}

$reportLines | Out-File $reportPath -Encoding utf8
if (!(Test-Path $ReportHistoryRoot)) {
    New-Item -ItemType Directory -Path $ReportHistoryRoot -Force | Out-Null
}
$reportLines | Out-File $archivedReportPath -Encoding utf8

$jsonPayload = [PSCustomObject]@{
    book = $BookName
    run_time = $runTimeText
    summary = [PSCustomObject]@{
        errors = $errorCount
        warnings = $warnCount
        infos = $infoCount
        build_ready = $buildReadyText
        buildable_markdown_files = $buildFiles.Count
    }
    checks = @(
        $checks | ForEach-Object {
            [PSCustomObject]@{
                Name = $_.Name
                Status = $_.Status
                Detail = $_.Detail
                LocalizedStatus = Get-LocalizedStatus -Status $_.Status
                LocalizedName = Get-LocalizedCheckName -Name $_.Name
                LocalizedDetail = Get-LocalizedCheckDetail -Detail $_.Detail
            }
        }
    )
    issues = @(
        $issues | ForEach-Object {
            [PSCustomObject]@{
                Type = $_.Type
                File = $_.File
                Line = $_.Line
                Message = $_.Message
                LocalizedType = Get-LocalizedStatus -Status $_.Type
                LocalizedMessage = Get-LocalizedIssueMessage -Message $_.Message
            }
        }
    )
}

$jsonPayload | ConvertTo-Json -Depth 8 | Out-File $jsonReportPath -Encoding utf8
$jsonPayload | ConvertTo-Json -Depth 8 | Out-File $archivedJsonReportPath -Encoding utf8

Write-Host ""
Write-Host "Build preflight check completed"
Write-Host "Errors: $errorCount"
Write-Host "Warnings: $warnCount"
Write-Host "Report saved to:"
Write-Host $reportPath

$state = if ($errorCount -gt 0) { "failed" } else { "success" }
$message = if ($errorCount -gt 0) {
    "Build preflight found blocking issues."
} else {
    "Build preflight completed."
}

Complete-SageStep -Context $Context -Step "edit" -State $state -Message $message -Data @{
    report = $reportPath
    archived_report = $archivedReportPath
    json_report = $jsonReportPath
    archived_json_report = $archivedJsonReportPath
    warning_count = $warnCount
    error_count = $errorCount
    buildable_markdown_files = $buildFiles.Count
}

if ($errorCount -gt 0) {
    exit 1
}

exit 0
