param(
    [Parameter(Mandatory = $true)]
    [string]$BookName,

    [Parameter(Mandatory = $true)]
    [string]$Request,

    [string]$Title,
    [string]$Subtitle,
    [string]$Author,

    [ValidateSet("ebook", "print")]
    [string]$Edition = "ebook",

    [string]$Model = "gpt-5.2"
)

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$ErrorActionPreference = "Stop"

function Ensure-Directory {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-JsonUtf8Safe {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        $raw = Get-Content -LiteralPath $Path -Raw -Encoding UTF8
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $null
        }
        return $raw | ConvertFrom-Json
    }
    catch {
        return $null
    }
}

function Write-JsonUtf8 {
    param(
        [Parameter(Mandatory = $true)]
        $Data,
        [Parameter(Mandatory = $true)]
        [string]$Path
    )
    $json = $Data | ConvertTo-Json -Depth 50
    Set-Content -LiteralPath $Path -Value $json -Encoding UTF8
}

function Get-StringValue {
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )
    if ($null -eq $Value) {
        return ""
    }
    return "$Value".Trim()
}

function Get-StringArray {
    param(
        [Parameter(Mandatory = $true)]
        $Value
    )
    if ($null -eq $Value) {
        return @()
    }
    if ($Value -is [System.Array]) {
        return @($Value | ForEach-Object { Get-StringValue -Value $_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $text = Get-StringValue -Value $Value
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }
    return @($text)
}

function Join-Items {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Items,
        [int]$MaxCount = 8
    )
    return (@($Items | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -First $MaxCount) -join ", ")
}

function Get-ResponseText {
    param(
        [Parameter(Mandatory = $true)]
        $Response
    )

    if ($Response.output_text) {
        return "$($Response.output_text)".Trim()
    }

    $text = ""
    foreach ($item in $Response.output) {
        foreach ($content in $item.content) {
            if ($content.type -eq "output_text") {
                $text += $content.text
            }
        }
    }
    return $text.Trim()
}

$EnginePath            = Split-Path -Parent $MyInvocation.MyCommand.Path
$SageRoot              = Split-Path -Parent $EnginePath
$ClawRoot              = Split-Path -Parent $SageRoot
$WorkspaceParentRoot   = if (-not [string]::IsNullOrWhiteSpace($env:SAGEWRITE_WORKSPACE_ROOT)) { [System.IO.Path]::GetFullPath($env:SAGEWRITE_WORKSPACE_ROOT) } else { $ClawRoot }
$WorkspaceRoot         = Join-Path $WorkspaceParentRoot "workspace-$BookName"
$BookRoot              = Join-Path $WorkspaceRoot "sagewrite\book"
$CoverBaseRoot         = Join-Path $BookRoot "07_cover"
$CoverRoot             = Join-Path $CoverBaseRoot $Edition
$CoverBriefRoot        = Join-Path $CoverRoot "brief"
$BriefJsonPath         = Join-Path $CoverBriefRoot "cover_brief.json"
$StrategyJsonPath      = Join-Path $CoverBriefRoot "cover_strategy.json"
$CopyJsonPath          = Join-Path $CoverBriefRoot "cover_copy.json"
$AssistantJsonPath     = Join-Path $CoverBriefRoot "cover_assistant_last.json"
$AssistantMarkdownPath = Join-Path $CoverBriefRoot "cover_assistant_last.md"
$NextCoverRoot         = Join-Path $CoverBaseRoot "next\$Edition"
$WorkbenchStatePath    = Join-Path $NextCoverRoot "workbench_state.json"

Ensure-Directory -Path $CoverBaseRoot
Ensure-Directory -Path $CoverRoot
Ensure-Directory -Path $CoverBriefRoot
Ensure-Directory -Path $NextCoverRoot

if ([string]::IsNullOrWhiteSpace($Request)) {
    throw "Request is required."
}

if (-not $env:OPENAI_API_KEY) {
    throw "OPENAI_API_KEY not set."
}

$Brief = Read-JsonUtf8Safe -Path $BriefJsonPath
$Strategy = Read-JsonUtf8Safe -Path $StrategyJsonPath
$Copy = Read-JsonUtf8Safe -Path $CopyJsonPath

$ResolvedTitle = if (-not [string]::IsNullOrWhiteSpace($Title)) { $Title } elseif ($Brief) { Get-StringValue -Value $Brief.cover_text.title } elseif ($Strategy) { Get-StringValue -Value $Strategy.cover_text.title } else { "" }
$ResolvedSubtitle = if (-not [string]::IsNullOrWhiteSpace($Subtitle)) { $Subtitle } elseif ($Copy) { Get-StringValue -Value $Copy.selected.subtitle } elseif ($Brief) { Get-StringValue -Value $Brief.cover_text.subtitle } elseif ($Strategy) { Get-StringValue -Value $Strategy.cover_text.subtitle } else { "" }
$ResolvedAuthor = if (-not [string]::IsNullOrWhiteSpace($Author)) { $Author } elseif ($Brief) { Get-StringValue -Value $Brief.cover_text.author } elseif ($Strategy) { Get-StringValue -Value $Strategy.cover_text.author } else { "" }

$Audience = if ($Brief) { Get-StringValue -Value $Brief.metadata.audience } else { "" }
$BookType = if ($Brief) { Get-StringValue -Value $Brief.metadata.book_type } else { "" }
$CoreThesis = if ($Brief) { Get-StringValue -Value $Brief.metadata.core_thesis } else { "" }
$Scope = if ($Brief) { Get-StringValue -Value $Brief.metadata.scope } else { "" }
$Style = if ($Brief) { Get-StringValue -Value $Brief.metadata.style } else { "" }
$Keywords = if ($Brief) { Get-StringArray -Value $Brief.metadata.top_keywords } else { @() }

$PrimaryRouteLabel = if ($Strategy) { Get-StringValue -Value $Strategy.primary_strategy.route_label } else { "" }
$PrimaryVisuals = if ($Strategy) { Get-StringArray -Value $Strategy.primary_strategy.main_visual } else { @() }
$PrimaryColors = if ($Strategy) { Get-StringArray -Value $Strategy.primary_strategy.color_direction } else { @() }
$PrimaryComposition = if ($Strategy) { Get-StringValue -Value $Strategy.primary_strategy.composition } else { "" }
$NegativePrompt = if ($Strategy) { Get-StringArray -Value $Strategy.generation_plan.prompt_package.negative_prompt } else { @() }
$BasePrompt = if ($Strategy) { Get-StringValue -Value $Strategy.generation_plan.prompt_package.base_prompt } else { "" }

$CoverContext = @(
    "Book title: $(if ($ResolvedTitle) { $ResolvedTitle } else { '(empty)' })",
    "Subtitle: $(if ($ResolvedSubtitle) { $ResolvedSubtitle } else { '(empty)' })",
    "Author: $(if ($ResolvedAuthor) { $ResolvedAuthor } else { '(empty)' })",
    "Audience: $(if ($Audience) { $Audience } else { '(empty)' })",
    "Book type: $(if ($BookType) { $BookType } else { '(empty)' })",
    "Core thesis: $(if ($CoreThesis) { $CoreThesis } else { '(empty)' })",
    "Scope: $(if ($Scope) { $Scope } else { '(empty)' })",
    "Style: $(if ($Style) { $Style } else { '(empty)' })",
    "Top keywords: $(if ($Keywords.Count -gt 0) { Join-Items -Items $Keywords -MaxCount 12 } else { '(empty)' })",
    "Primary route: $(if ($PrimaryRouteLabel) { $PrimaryRouteLabel } else { '(empty)' })",
    "Primary visuals: $(if ($PrimaryVisuals.Count -gt 0) { Join-Items -Items $PrimaryVisuals -MaxCount 10 } else { '(empty)' })",
    "Primary colors: $(if ($PrimaryColors.Count -gt 0) { Join-Items -Items $PrimaryColors -MaxCount 8 } else { '(empty)' })",
    "Primary composition: $(if ($PrimaryComposition) { $PrimaryComposition } else { '(empty)' })",
    "Base prompt seed: $(if ($BasePrompt) { $BasePrompt } else { '(empty)' })",
    "Negative prompt: $(if ($NegativePrompt.Count -gt 0) { Join-Items -Items $NegativePrompt -MaxCount 14 } else { '(empty)' })",
    "Selected subtitle candidate: $(if ($Copy) { Get-StringValue -Value $Copy.selected.subtitle } else { '(empty)' })",
    "Selected back-cover hook: $(if ($Copy) { Get-StringValue -Value $Copy.selected.back_cover_hook } else { '(empty)' })"
) -join "`n"

$Prompt = @"
You are an AI assistant for book-cover ideation, cover prompt writing, and visual concept support.

Reply in Chinese unless the user explicitly asks for another language.
Use the cover context when it helps.
If the user asks for a MidJourney prompt, return a ready-to-copy English prompt.
For cover base-image prompts, use image-only guidance. The image must contain absolutely no text of any kind: no title, no author name, no typography, no letters, no numbers, no Chinese characters, no logos, no watermarks, and no marks that look like writing.

Current cover context:
$CoverContext

User request:
$Request
"@

$BodyObject = @{
    model = $Model
    input = $Prompt
    max_output_tokens = 1600
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
    throw "07a-cover-assist API request failed: $($_.Exception.Message)"
}

$ResponseText = Get-ResponseText -Response $Response
if ([string]::IsNullOrWhiteSpace($ResponseText)) {
    throw "07a-cover-assist returned empty text."
}

$AssistantResult = [ordered]@{
    generated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    book_name    = $BookName
    edition      = $Edition
    model        = $Model
    request      = $Request
    response     = $ResponseText
    context = [ordered]@{
        title           = $ResolvedTitle
        subtitle        = $ResolvedSubtitle
        author          = $ResolvedAuthor
        audience        = $Audience
        book_type       = $BookType
        core_thesis     = $CoreThesis
        scope           = $Scope
        style           = $Style
        primary_route   = $PrimaryRouteLabel
        primary_visuals = @($PrimaryVisuals)
        primary_colors  = @($PrimaryColors)
    }
}

Write-JsonUtf8 -Data $AssistantResult -Path $AssistantJsonPath
Set-Content -LiteralPath $AssistantMarkdownPath -Value $ResponseText -Encoding UTF8

$WorkbenchState = Read-JsonUtf8Safe -Path $WorkbenchStatePath
$NextWorkbenchState = [ordered]@{
    updated_at = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    assistant_request = $Request
    assistant_response_path = $AssistantMarkdownPath
}
if ($WorkbenchState) {
    foreach ($property in $WorkbenchState.PSObject.Properties) {
        if (-not $NextWorkbenchState.Contains($property.Name)) {
            $NextWorkbenchState[$property.Name] = $property.Value
        }
    }
}
Write-JsonUtf8 -Data $NextWorkbenchState -Path $WorkbenchStatePath

Write-Host "07a-cover-assist completed successfully."
Write-Host ("Result JSON: " + $AssistantJsonPath)
Write-Host ""
Write-Host $ResponseText
