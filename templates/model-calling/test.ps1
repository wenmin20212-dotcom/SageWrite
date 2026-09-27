$ErrorActionPreference = 'Stop'
$Root = Split-Path $PSScriptRoot -Parent
. (Join-Path $Root 'engine/00-llm.ps1')
$Saved = @{}
foreach ($Item in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
    if ($Item.Key -like 'SAGE_LLM_*' -or $Item.Key -eq 'OPENAI_API_KEY') {
        $Saved[$Item.Key] = $Item.Value
        [Environment]::SetEnvironmentVariable($Item.Key, $null)
    }
}
$Work = Join-Path $Root ('engine/work/test-' + [guid]::NewGuid().ToString('N'))
$env:SAGE_LLM_AGENT_REQUEST_ROOT = Join-Path $Work 'requests'
function Assert($Condition, $Message) {
    if (-not $Condition) { throw "FAIL: $Message" }
}
function Invoke-RestMethod { throw 'Unexpected HTTP call' }
function Invoke-SageCodexText { throw 'Unexpected Codex CLI call' }
function Pending([string]$Prompt, [int]$Budget = 2000) {
    try { $null = Invoke-SageLlmText -Prompt $Prompt -MaxOutputTokens $Budget }
    catch {
        if ($_.Exception.Message.StartsWith('SAGE_AGENT_PENDING: ')) {
            return $_.Exception.Message.Substring('SAGE_AGENT_PENDING: '.Length)
        }
        throw
    }
    throw 'Expected a pending request'
}
function Save-Response($Path, $Response) {
    [IO.File]::WriteAllText($Path, ($Response | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
}
try {
    Assert ((Get-SageLlmConfig).Provider -eq 'codex_agent') 'Default provider'
    $Path = Pending 'Test task'
    $Request = Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
    Assert ($Request.prompt -eq 'Test task') 'Exact prompt'
    Assert ($Request.max_output_tokens -eq 2000) 'Exact budget'
    Assert ((Pending 'Test task') -eq $Path) 'Stable request ID'
    $ResponsePath = Join-Path (Split-Path $Path -Parent) 'response.json'
    foreach ($Field in @('request_id', 'provider', 'status', 'text')) {
        $Response = @{request_id=$Request.request_id; provider='codex_agent'; status='completed'; text='Completed text'}
        $Response[$Field] = if ($Field -eq 'text') { '' } else { 'invalid' }
        Save-Response $ResponsePath $Response
        $Rejected = $false
        try { $null = Invoke-SageLlmText -Prompt 'Test task' -MaxOutputTokens 2000 }
        catch { $Rejected = $_.Exception.Message.StartsWith('Invalid agent response:') }
        Assert $Rejected "Reject invalid $Field"
    }
    Save-Response $ResponsePath @{request_id=$Request.request_id; provider='codex_agent'; status='completed'; text='Completed text'}
    Assert ((Invoke-SageLlmText -Prompt 'Test task' -MaxOutputTokens 2000) -eq 'Completed text') 'Round trip'
    Assert ((Pending 'Changed task') -ne $Path) 'Prompt isolation'
    Assert ((Pending 'Test task' 3000) -ne $Path) 'Budget isolation'
    $env:SAGE_LLM_SYSTEM_PROMPT = 'Changed system instructions'
    Assert ((Pending 'Test task') -ne $Path) 'System prompt isolation'
    [Environment]::SetEnvironmentVariable('SAGE_LLM_SYSTEM_PROMPT', $null)
    $env:SAGE_LLM_PROVIDER = 'openai'
    $env:SAGE_LLM_API_KEY = 'offline-test-not-a-real-key'
    Assert ((Get-SageLlmConfig).Provider -eq 'openai') 'Environment override'
    [Environment]::SetEnvironmentVariable('SAGE_LLM_PROVIDER', $null)
    [Environment]::SetEnvironmentVariable('SAGE_LLM_API_KEY', $null)

    # Exercise the exported command in a child shell, including its exit status.
    $Shell = (Get-Process -Id $PID).Path
    $Output = Join-Path $Work 'result.md'
    & $Shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'run.ps1') -OutputPath $Output
    Assert ($LASTEXITCODE -eq 2) 'Pending exit code'
    Assert (-not (Test-Path -LiteralPath $Output)) 'No fabricated result'
    $SamplePrompt = Get-Content -LiteralPath (Join-Path $Root 'prompt.md') -Raw -Encoding UTF8
    $SamplePath = Pending $SamplePrompt
    $Sample = Get-Content -LiteralPath $SamplePath -Raw -Encoding UTF8 | ConvertFrom-Json
    Save-Response (Join-Path (Split-Path $SamplePath -Parent) 'response.json') @{
        request_id=$Sample.request_id; provider='codex_agent'; status='completed'; text='Verified sample output'
    }
    & $Shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'run.ps1') -OutputPath $Output
    Assert ($LASTEXITCODE -eq 0) 'Successful replay exit code'
    Assert ((Get-Content -LiteralPath $Output -Raw -Encoding UTF8) -eq 'Verified sample output') 'Saved output'
    $ErrorActionPreference = 'Continue'
    & $Shell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Root 'run.ps1') -OutputPath $Output 2>$null
    $ErrorActionPreference = 'Stop'
    Assert ($LASTEXITCODE -ne 0) 'Refuse accidental overwrite'
    Write-Output 'PASS: offline handoff, validation, isolation, configuration and command replay'
}
finally {
    foreach ($Item in [Environment]::GetEnvironmentVariables().GetEnumerator()) {
        if ($Item.Key -like 'SAGE_LLM_*' -or $Item.Key -eq 'OPENAI_API_KEY') {
            [Environment]::SetEnvironmentVariable($Item.Key, $null)
        }
    }
    foreach ($Name in $Saved.Keys) { [Environment]::SetEnvironmentVariable($Name, $Saved[$Name]) }
}
