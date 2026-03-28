param(
    [Parameter(Mandatory=$true)]
    [string]$BookName
)

# ===== UTF-8 Console =====
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ===== Resolve .openclaw root =====
$EnginePath = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot   = Split-Path -Parent $EnginePath
$ClawRoot   = Split-Path -Parent $SageRoot

$WorkspaceRoot = Join-Path $ClawRoot "workspace-$BookName"
$BookRoot = Join-Path $WorkspaceRoot "sagewrite\book"

$ObjectivePath = Join-Path $BookRoot "00_brief\objective.md"
$TocPath       = Join-Path $BookRoot "01_outline\toc.md"
$LogPath       = Join-Path $BookRoot "logs\run_history.json"

# ===== Validate =====
if (!(Test-Path $ObjectivePath)) {
    Write-Output "ERROR: objective.md not found."
    exit
}

if (-not $env:OPENAI_API_KEY) {
    Write-Output "ERROR: OPENAI_API_KEY not set."
    exit
}

# ===== Read objective =====
$ObjectiveContent = Get-Content $ObjectivePath -Raw

# ===== Prompt =====
$Prompt = @"
You are a professional academic book architect.

Below is the book definition:

$ObjectiveContent

Generate a complete professional table of contents.

Requirements:
- 10 to 20 chapters
- Each chapter has 3 to 6 sections
- Logical progression
- Suitable for publication
- Markdown format

Heading Rules:
- Use '## ' for chapter-level headings (e.g., '## Chapter 1: ...')
- Use exactly '### ' for all section headings under each chapter

Numbering Rules:
- Every section MUST include numeric indexing
- Format must be: ### [ChapterNumber].[SectionNumber] [Title]
- Example:
  ### 1.1 Introduction
  ### 1.2 Core Concepts
  ### 1.3 Applications

Strict Constraints:
- Every section line MUST start with '### ' followed immediately by numbering (e.g., '### 3.1 ')
- Do NOT omit numbering
- Do NOT use bullets or lists
- Do NOT use '####' or other heading levels
- Do NOT use '##' for sections
- Do NOT generate unnumbered section titles

IMPORTANT:
- The numbering must restart for each chapter (e.g., Chapter 2 starts from 2.1)
- Ensure numbering is continuous and correctly ordered within each chapter
- If numbering and '###' format are already correct, do not alter structure
"@
# ===== Build JSON (string) =====
$BodyObject = @{
    model = "gpt-5.2"
    input = $Prompt
}

$JsonString = $BodyObject | ConvertTo-Json -Depth 10 -Compress

# mem
$Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonString)

# ===== Call OpenAI =====
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
    Write-Output "ERROR: OpenAI request failed."
    Write-Output $_
    exit
}

# ===== Extract =====
if (-not $Response.output) {
    Write-Output "ERROR: Invalid API response."
    exit
}

$TocContent = $Response.output[0].content[0].text

if (-not $TocContent) {
    Write-Output "ERROR: No content returned."
    exit
}

# ===== Write toc.md =====
@"
---
file_role: toc
layer: structure
generated_at: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
---

# Table of Contents

$TocContent
"@ | Out-File $TocPath -Encoding utf8

# ===== Log =====
$LogEntry = @{
    step = "structure"
    time = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
}

$LogEntry | ConvertTo-Json -Depth 10 | Out-File $LogPath -Encoding utf8

Write-Output "SUCCESS: TOC generated at $TocPath"
