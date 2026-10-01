param(
    [string]$WorkspaceRoot,
    [string]$BookName,
    [string]$Prompt,
    [string]$CodexCommand,
    [switch]$EnableWebSearch,
    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'
$EngineRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$RepoRoot = Split-Path -Parent $EngineRoot

function Resolve-CodexExecutable {
    param([string]$RequestedCommand)

    if (-not [string]::IsNullOrWhiteSpace($RequestedCommand)) {
        $Resolved = Get-Command $RequestedCommand -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
        if ($Resolved) { return $Resolved.Source }
        if (Test-Path -LiteralPath $RequestedCommand -PathType Leaf) {
            return [IO.Path]::GetFullPath($RequestedCommand)
        }
        throw "Codex executable was not found: $RequestedCommand"
    }

    $Command = Get-Command codex -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Command) { return $Command.Source }

    $InstallRoot = Join-Path $env:LOCALAPPDATA 'OpenAI\Codex\bin'
    $Candidate = Get-ChildItem -LiteralPath $InstallRoot -Filter codex.exe -File -Recurse -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1
    if ($Candidate) { return $Candidate.FullName }

    throw 'Codex CLI was not found. Install or repair the Codex desktop app, then retry.'
}

if ([string]::IsNullOrWhiteSpace($WorkspaceRoot)) {
    if (-not [string]::IsNullOrWhiteSpace($env:SAGEWRITE_WORKSPACE_ROOT)) {
        $WorkspaceRoot = $env:SAGEWRITE_WORKSPACE_ROOT
    } else {
        $WorkspaceRoot = Join-Path (Split-Path -Parent $RepoRoot) 'SageWriteWorkspaces'
    }
}

$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
if (-not (Test-Path -LiteralPath $WorkspaceRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $WorkspaceRoot -Force | Out-Null
}

$CodexExecutable = Resolve-CodexExecutable -RequestedCommand $CodexCommand
$env:SAGEWRITE_WORKSPACE_ROOT = $WorkspaceRoot
$env:SAGE_LLM_PROVIDER = 'codex_agent'

if ([string]::IsNullOrWhiteSpace($Prompt)) {
    $TargetText = if ([string]::IsNullOrWhiteSpace($BookName)) {
        'List the available books, then ask which book and workflow step I want to work on.'
    } else {
        "The target book is '$BookName'. Inspect its workflow status first, then ask what I want to do."
    }
    $Prompt = @"
You are the independent SageWrite Agent on this computer. Before doing any work, read AGENTS.md, engine/llm-config.json, engine/LLM-CONFIG.md, and docs/AGENT-CALLING-GUIDE.md completely.
Read skills/sagewrite-manage-environment/SKILL.md. Run its Writing environment inspection for the selected workspace before proceeding. Present the installation/readiness result and welcome message directly in this conversation using its Installation handoff rules. Do not infer installation completion from this launcher alone; distinguish existing setup, blockers and untested runtime features.
Use the book workspace selected by SAGEWRITE_WORKSPACE_ROOT. Preserve the existing objective, TOC, numeric manuscript files, review records, and build workflow. Keep the provider as codex_agent. When a script emits SAGE_AGENT_PENDING, handle the request in this same Agent session exactly as AGENTS.md requires; never report a pending handoff as completed. Do not run concurrent writers for one book. Do not rewrite an entire book, publish, or perform destructive actions without explicit confirmation. Respond in the user's language.
$TargetText
"@.Trim()
}

$Arguments = @(
    '--cd', $RepoRoot,
    '--add-dir', $WorkspaceRoot,
    '--sandbox', 'workspace-write',
    '--approve-for-me',
    '--no-alt-screen'
)
if ($EnableWebSearch) { $Arguments += '--search' }
$Arguments += $Prompt

Write-Host 'SageWrite Agent'
Write-Host "  Program: $CodexExecutable"
Write-Host "  Project: $RepoRoot"
Write-Host "  Books:   $WorkspaceRoot"
Write-Host "  Search:  $(if ($EnableWebSearch) { 'enabled' } else { 'disabled' })"

if ($DryRun) {
    Write-Host 'Validation completed. The Agent was not started.'
    exit 0
}

& $CodexExecutable @Arguments
exit $LASTEXITCODE
