param(
    [Parameter(Mandatory=$true)]
    [string]$BookName
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$CommonPath = Join-Path (Split-Path -Parent $MyInvocation.MyCommand.Path) "00-common.ps1"
. $CommonPath

function Get-FrontMatterValue {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [string]$Key
    )

    $Normalized = $Content -replace "`r", ""
    $Match = [regex]::Match($Normalized, "(?s)^---\n(.*?)\n---")
    if (-not $Match.Success) {
        return ""
    }

    foreach ($line in ($Match.Groups[1].Value -split "`n")) {
        if ($line -match "^\s*$([regex]::Escape($Key))\s*:\s*(.+?)\s*$") {
            return $Matches[1].Trim()
        }
    }

    return ""
}

function Get-MarkdownSectionBody {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Content,

        [Parameter(Mandatory=$true)]
        [string]$Heading
    )

    $Normalized = $Content -replace "`r", ""
    $EscapedHeading = [regex]::Escape($Heading)
    $Match = [regex]::Match($Normalized, "(?ms)^##\s+$EscapedHeading\s*\n(.*?)(?=^##\s+|\z)")
    if ($Match.Success) {
        return $Match.Groups[1].Value.Trim()
    }

    return ""
}

$Context = Get-SageContext -ScriptPath $MyInvocation.MyCommand.Path -BookName $BookName
Initialize-SageObservability -Context $Context
Set-SageCurrentStep -Context $Context -Step "structure" -Data @{
    script = "02-structure.ps1"
    model = "gpt-5.2"
}

$BookRoot = $Context.BookRoot

$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
$TocPath       = Join-Path $BookRoot "01_outline\toc.md"

if (!(Test-Path $ObjectivePath)) {
    Fail-SageStep -Context $Context -Step "structure" -Message "objective.md not found." -Data @{
        objective = $ObjectivePath
    }
    Write-Output "ERROR: objective.md not found."
    exit 1
}

if (-not $env:OPENAI_API_KEY) {
    Fail-SageStep -Context $Context -Step "structure" -Message "OPENAI_API_KEY not set." -Data @{}
    Write-Output "ERROR: OPENAI_API_KEY not set."
    exit 1
}

$ObjectiveContent = Get-Content $ObjectivePath -Raw
$StyleFromFrontMatter = Get-FrontMatterValue -Content $ObjectiveContent -Key "style"
$StyleGuideBody = Get-MarkdownSectionBody -Content $ObjectiveContent -Heading "风格指南"
$ResolvedStyleGuidance = if (-not [string]::IsNullOrWhiteSpace($StyleGuideBody)) {
    $StyleGuideBody.Trim()
} elseif (-not [string]::IsNullOrWhiteSpace($StyleFromFrontMatter)) {
    $StyleFromFrontMatter.Trim()
} else {
    ""
}
$HasObjectiveStyleGuidance = -not [string]::IsNullOrWhiteSpace($ResolvedStyleGuidance)

$StyleInstructionsBlock = if ($HasObjectiveStyleGuidance) {
@"

Style Guidance:
$ResolvedStyleGuidance

The table of contents must reflect this style guidance in chapter naming, section naming, level of formality, and overall organization.
"@
} else {
@"

Style Guidance:
Use a clear, professional, publication-ready table of contents style appropriate for a serious non-fiction book.
"@
}

$Prompt = @"
You are a professional academic book architect.

Below is the book definition (SOURCE OF TRUTH):

$ObjectiveContent
$StyleInstructionsBlock

Task:
Generate a complete professional table of contents.

Core Principle:
- The book definition above is the single source of truth.
- Do NOT override, reinterpret, or expand beyond it.

Binding Rules:
- Title must exactly reflect the defined book title
- Audience must align with the defined target readers
- Scope must strictly follow the defined content boundaries
- Chapter count and structure must follow the definition exactly
- Do not introduce new themes, topics, or expansions not present in the definition

Output Requirements:
- Logical progression
- Publication-level quality
- Markdown format

Heading Rules:
- Use '## ' for chapter-level headings
- Use exactly '### ' for section headings

Numbering Rules:
- Format: ### [Chapter].[Section] Title

Strict Constraints:
- Every section must start with '### '
- Numbering is mandatory and continuous
- Do not use bullets
- Do not use '####' or other heading levels
"@

$BodyObject = @{
    model = "gpt-5.2"
    input = $Prompt
}

$JsonString = $BodyObject | ConvertTo-Json -Depth 10 -Compress
$Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonString)

try {
    $Response = Invoke-RestMethod `
        -Uri "https://api.openai.com/v1/responses" `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $env:OPENAI_API_KEY"
            "Content-Type"  = "application/json; charset=utf-8"
        } `
        -Body $Utf8Bytes
}
catch {
    Fail-SageStep -Context $Context -Step "structure" -Message "OpenAI request failed." -Data @{
        error = $_.Exception.Message
    }
    Write-Output "ERROR: OpenAI request failed."
    Write-Output $_
    exit 1
}

if (-not $Response.output) {
    Fail-SageStep -Context $Context -Step "structure" -Message "Invalid API response." -Data @{}
    Write-Output "ERROR: Invalid API response."
    exit 1
}

$TocContent = $Response.output[0].content[0].text

if (-not $TocContent) {
    Fail-SageStep -Context $Context -Step "structure" -Message "No content returned." -Data @{}
    Write-Output "ERROR: No content returned."
    exit 1
}

@"
---
file_role: toc
layer: structure
generated_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
---

# Table of Contents

$TocContent
"@ | Out-File $TocPath -Encoding utf8

Complete-SageStep -Context $Context -Step "structure" -State "success" -Message "TOC generated." -Data @{
    toc = $TocPath
    model = "gpt-5.2"
    has_objective_style_guidance = $HasObjectiveStyleGuidance
}

Write-Output "SUCCESS: TOC generated at $TocPath"
