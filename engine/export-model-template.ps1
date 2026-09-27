param([string]$Destination = (Join-Path $PSScriptRoot 'work/model-calling-template'))
$ErrorActionPreference = 'Stop'
$Repo = Split-Path $PSScriptRoot -Parent
$Destination = [IO.Path]::GetFullPath($Destination)
if (Test-Path -LiteralPath $Destination) {
    throw "Destination already exists; choose a new directory: $Destination"
}
# An explicit allowlist keeps books, local settings, credentials and queues out.
$Files = [ordered]@{
    'engine/00-llm.ps1' = 'engine/00-llm.ps1'
    'LICENSE' = 'LICENSE'
    'templates/model-calling/README.md' = 'README.md'
    'templates/model-calling/AGENTS.md' = 'AGENTS.md'
    'templates/model-calling/.gitignore' = '.gitignore'
    'templates/model-calling/llm-config.json' = 'engine/llm-config.json'
    'templates/model-calling/run.ps1' = 'run.ps1'
    'templates/model-calling/prompt.md' = 'prompt.md'
    'templates/model-calling/test.ps1' = 'tests/test.ps1'
    'templates/model-calling/test.yml' = '.github/workflows/test.yml'
}
foreach ($Source in $Files.Keys) {
    if (-not (Test-Path -LiteralPath (Join-Path $Repo $Source) -PathType Leaf)) {
        throw "Missing template source: $Source"
    }
}
foreach ($Source in $Files.Keys) {
    $Target = Join-Path $Destination $Files[$Source]
    [IO.Directory]::CreateDirectory((Split-Path $Target -Parent)) | Out-Null
    Copy-Item -LiteralPath (Join-Path $Repo $Source) -Destination $Target
}
Write-Output "Template exported: $Destination"
