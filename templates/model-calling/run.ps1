param(
    [string]$PromptPath = (Join-Path $PSScriptRoot 'prompt.md'),
    [string]$OutputPath = (Join-Path $PSScriptRoot 'output/result.md'),
    [ValidateRange(0, 2147483647)][int]$MaxOutputTokens = 2000,
    [switch]$Force
)
$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'engine/00-llm.ps1')
$OutputPath = [IO.Path]::GetFullPath($OutputPath)
if ((Test-Path -LiteralPath $OutputPath) -and -not $Force) {
    throw 'Output exists. Choose another OutputPath or explicitly pass -Force.'
}
$Prompt = Get-Content -LiteralPath $PromptPath -Raw -Encoding UTF8
try {
    $Text = Invoke-SageLlmText -Prompt $Prompt -MaxOutputTokens $MaxOutputTokens
}
catch {
    if ($_.Exception.Message.StartsWith('SAGE_AGENT_PENDING: ')) {
        Write-Host 'Waiting for the active assistant. Complete the request and rerun this exact command.'
        exit 2
    }
    throw
}
[IO.Directory]::CreateDirectory((Split-Path $OutputPath -Parent)) | Out-Null
[IO.File]::WriteAllText($OutputPath, $Text, [Text.UTF8Encoding]::new($false))
Write-Output "Saved: $OutputPath"
