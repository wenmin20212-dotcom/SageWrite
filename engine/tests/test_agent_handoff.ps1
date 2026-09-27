$ErrorActionPreference = 'Stop'
$Engine = Split-Path -Parent $PSScriptRoot
. (Join-Path $Engine '00-llm.ps1')
$TestRoot = Join-Path $Engine ('work\agent-test-' + [guid]::NewGuid().ToString('N'))
[IO.Directory]::CreateDirectory($TestRoot) | Out-Null
foreach ($Name in @('SAGE_LLM_PROVIDER','SAGE_LLM_MODEL','SAGE_LLM_API_STYLE','SAGE_LLM_CONFIG','SAGE_LLM_API_KEY','OPENAI_API_KEY')) {
    [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
}
$env:SAGE_LLM_AGENT_REQUEST_ROOT = Join-Path $TestRoot 'queue'
function Invoke-RestMethod { throw 'Unexpected HTTP request' }
function Invoke-SageCodexText { throw 'Unexpected Codex subprocess' }
function Assert($Condition, $Message) { if (-not $Condition) { throw $Message } }
function Save-Json($Path, $Value) {
    [IO.File]::WriteAllText($Path, ($Value | ConvertTo-Json -Depth 12), [Text.UTF8Encoding]::new($false))
}
$Config = Get-SageLlmConfig
Assert ($Config.Provider -eq 'codex_agent' -and $Config.ApiStyle -eq 'agent-handoff') 'Shared default not loaded'
try { Invoke-SageLlmText -Prompt 'Write one section.' -Config $Config; throw 'Expected pending' }
catch { Assert ($_.Exception.Message -like 'SAGE_AGENT_PENDING:*') 'Wrong pending result' }
$RequestFile = @(Get-ChildItem $env:SAGE_LLM_AGENT_REQUEST_ROOT -Filter request.json -Recurse)[0]
$Request = Get-Content $RequestFile.FullName -Raw | ConvertFrom-Json
$ResponsePath = Join-Path $RequestFile.DirectoryName 'response.json'
Save-Json $ResponsePath @{request_id='wrong';provider='codex_agent';status='completed';text='Wrong answer'}
try { Invoke-SageLlmText -Prompt 'Write one section.' -Config $Config; throw 'Expected invalid response' }
catch { Assert ($_.Exception.Message -like 'Invalid agent response:*') 'Wrong ID was not rejected' }
Save-Json $ResponsePath @{request_id=$Request.request_id;provider='codex_agent';status='completed';text='Verified answer'}
$Config.Model = 'ui-model-override'
Assert ((Invoke-SageLlmText -Prompt 'Write one section.' -Config $Config) -eq 'Verified answer') 'Response did not round trip'
try { Invoke-SageLlmText -Prompt 'A different section.' -Config $Config; throw 'Expected pending' }
catch { Assert ($_.Exception.Message -like 'SAGE_AGENT_PENDING:*') 'Answer leaked to changed prompt' }
$env:SAGE_LLM_PROVIDER = 'openai'
$env:SAGE_LLM_API_KEY = 'test-only-not-a-real-key'
$env:SAGE_LLM_MODEL = 'test-api-model'
$ApiConfig = Get-SageLlmConfig
Assert ($ApiConfig.Provider -eq 'openai' -and $ApiConfig.Model -eq 'test-api-model' -and $ApiConfig.ApiStyle -eq 'responses') 'Environment override failed'
foreach ($Name in @('SAGE_LLM_PROVIDER','SAGE_LLM_MODEL','SAGE_LLM_API_KEY','SAGE_LLM_AGENT_REQUEST_ROOT')) {
    [Environment]::SetEnvironmentVariable($Name, $null, 'Process')
}

# Exercise the real structure script without HTTP, credentials or book edits.
$env:SAGEWRITE_WORKSPACE_ROOT = Join-Path $TestRoot 'books'
$BookRoot = Join-Path $env:SAGEWRITE_WORKSPACE_ROOT 'workspace-AgentTest\sagewrite\book'
[IO.Directory]::CreateDirectory((Join-Path $BookRoot '00_brief')) | Out-Null
[IO.Directory]::CreateDirectory((Join-Path $BookRoot '01_outline')) | Out-Null
[IO.File]::WriteAllText((Join-Path $BookRoot '00_brief\objective.md'), '# One test chapter')
$PowerShell = Join-Path $PSHOME 'powershell.exe'
& $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Engine '02-structure.ps1') -BookName AgentTest
Assert ($LASTEXITCODE -ne 0) 'Pending script unexpectedly succeeded'
Assert (-not (Test-Path (Join-Path $BookRoot '01_outline\toc.md'))) 'Pending script wrote a manuscript'
$State = Get-Content (Join-Path $BookRoot 'logs\status.json') -Raw | ConvertFrom-Json
Assert ($State.current.state -eq 'waiting_for_agent') 'Pending state incorrectly recorded'
$BookRequestFile = @(Get-ChildItem (Join-Path $BookRoot 'logs\agent_requests') -Filter request.json -Recurse)[0]
$BookRequest = Get-Content $BookRequestFile.FullName -Raw | ConvertFrom-Json
Save-Json (Join-Path $BookRequestFile.DirectoryName 'response.json') @{
    request_id=$BookRequest.request_id;provider='codex_agent';status='completed';text="## Test company`n`n### 1.1 Test section"
}
& $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Engine '02-structure.ps1') -BookName AgentTest
Assert ($LASTEXITCODE -eq 0) 'Structure resume failed'
$Toc = Get-Content (Join-Path $BookRoot '01_outline\toc.md') -Raw
Assert ($Toc.Contains('### 1.1 Test section')) 'Completed text not saved by original script'

& $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Engine '03-write.ps1') -BookName AgentTest -Chapter 1 -Model old-ui-model -AdditionalInstructions 'Only write this section.'
Assert ($LASTEXITCODE -ne 0) 'Writer should wait for its own response'
$WriteRequestFile = Get-ChildItem (Join-Path $BookRoot 'logs\agent_requests') -Filter request.json -Recurse | Where-Object {
    (Get-Content $_.FullName -Raw | ConvertFrom-Json).prompt -like '*Current writing section:*'
} | Select-Object -First 1
$WriteRequest = Get-Content $WriteRequestFile.FullName -Raw | ConvertFrom-Json
Save-Json (Join-Path $WriteRequestFile.DirectoryName 'response.json') @{
    request_id=$WriteRequest.request_id;provider='codex_agent';status='completed';text="### 1.1 Test section`n`nThis is a test paragraph."
}
Start-Sleep -Seconds 1
& $PowerShell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $Engine '03-write.ps1') -BookName AgentTest -Chapter 1 -Model old-ui-model -AdditionalInstructions 'Only write this section.'
Assert ($LASTEXITCODE -eq 0) 'Writer prompt changed during resume'
$Chapter = Get-Content (Join-Path $BookRoot '02_chapters\01.md') -Raw
Assert ($Chapter.Contains('provider: codex_agent') -and $Chapter.Contains('model: current-session') -and $Chapter.Contains('### 1.1 Test section')) 'Writer provenance or content incorrect'
Write-Output 'PASS: shared config, no HTTP/CLI, pending, response validation, prompt isolation, environment override, real structure and writer handoff/resume.'
