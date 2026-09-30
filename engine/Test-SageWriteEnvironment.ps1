param(
    [ValidateSet('All','Core','Writing','Web','Pdf','Epub','Mcp','Images','SimpleDocx')]
    [string]$Profile = 'All',
    [string]$WorkspaceRoot,
    [string]$ReportDirectory,
    [switch]$Json
)

$ErrorActionPreference = 'Stop'
$Checks = [Collections.Generic.List[object]]::new()
function Add-Check($Id, $Area, $Status, $Detail, $Next) {
    $Checks.Add([pscustomobject]@{id=$Id; area=$Area; status=$Status; detail=$Detail; next_action=$Next})
}
function Test-Tool($Name, $Area) {
    $Command = Get-Command $Name -CommandType Application -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($Command) {
        Add-Check "tool.$Name" $Area 'pass' 'Executable found on PATH; execution not tested.' ''
    } else {
        Add-Check "tool.$Name" $Area 'fail' 'Executable not found on PATH.' "Install $Name from its official distribution, then reopen the terminal."
    }
}

Add-Check 'platform.windows' 'Core' $(if($env:OS -eq 'Windows_NT'){'pass'}else{'fail'}) 'The complete workflow targets Windows.' 'Use Windows for Word COM export and Windows PowerShell entry points.'
Test-Tool 'powershell.exe' 'Core'
if (!$WorkspaceRoot) { $WorkspaceRoot = $env:SAGEWRITE_WORKSPACE_ROOT }
if (!$WorkspaceRoot) { $WorkspaceRoot = Split-Path (Split-Path $PSScriptRoot -Parent) -Parent }
try {
    $WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
    if (Test-Path -LiteralPath $WorkspaceRoot -PathType Container) {
        Add-Check 'workspace.exists' 'Core' 'pass' 'Workspace parent directory exists.' ''
    } else {
        Add-Check 'workspace.exists' 'Core' 'warn' 'Workspace parent directory does not exist.' 'Create a writable parent directory and set SAGEWRITE_WORKSPACE_ROOT.'
    }
    Add-Check 'workspace.write_access' 'Core' 'unverified' 'No probe file was created; write access is not proven.' 'Validate initialization in a disposable workspace before using a real manuscript.'
} catch {
    Add-Check 'workspace.exists' 'Core' 'fail' 'Workspace path is invalid or inaccessible.' 'Check WorkspaceRoot or SAGEWRITE_WORKSPACE_ROOT.'
}

# Reuse the adapter precedence without invoking a model or displaying its values.
$ConfigFile = $env:SAGE_LLM_CONFIG
if (!$ConfigFile) { $ConfigFile = Join-Path $PSScriptRoot 'llm-config.json' }
$ConfigValid = $true
if (Test-Path -LiteralPath $ConfigFile -PathType Leaf) {
    try {
        $Settings = Get-Content -LiteralPath $ConfigFile -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($null -eq $Settings -or $Settings -isnot [pscustomobject]) { throw 'Not an object' }
        Add-Check 'llm.file' 'Writing' 'pass' 'Shared model configuration is a JSON object.' ''
    } catch {
        $ConfigValid = $false
        Add-Check 'llm.file' 'Writing' 'fail' 'Shared model configuration is not a valid JSON object.' 'Repair llm-config.json or the file selected by SAGE_LLM_CONFIG. Values are intentionally hidden.'
    }
} elseif ($env:SAGE_LLM_CONFIG) {
    $ConfigValid = $false
    Add-Check 'llm.file' 'Writing' 'fail' 'Explicit SAGE_LLM_CONFIG file is missing.' 'Correct the file path or remove the override intentionally.'
} else {
    Add-Check 'llm.file' 'Writing' 'warn' 'No shared model file; adapter environment/defaults will apply.' 'Review LLM-CONFIG.md before generation.'
}
if ($ConfigValid) {
    try {
        . (Join-Path $PSScriptRoot '00-llm.ps1')
        $Config = Get-SageLlmConfig
        if ($Config.Provider -in @('codex_agent','codex','openai','openai-compatible')) {
            Add-Check 'llm.config' 'Writing' 'pass' ("Adapter configuration accepted: " + $Config.Provider + '.') ''
        } else {
            Add-Check 'llm.config' 'Writing' 'warn' 'Custom provider configuration accepted by the adapter.' 'Verify provider compatibility; names alone do not establish support.'
        }
        if ($Config.Provider -eq 'codex_agent') {
            Add-Check 'llm.runtime' 'Writing' 'unverified' 'Current Agent must consume requests and return responses; no automatic background wake-up.' 'Use an active Agent session with workspace access. This check did not generate text.'
        } elseif ($Config.Provider -eq 'codex') {
            Add-Check 'llm.runtime' 'Writing' 'unverified' 'CLI and directory accepted; login and model permissions were not tested.' 'Verify CLI authentication separately; no CLI process was launched.'
        } else {
            $Uri = $null
            if (![uri]::TryCreate($Config.Endpoint, [UriKind]::Absolute, [ref]$Uri) -or $Uri.Scheme -notin @('http','https')) {
                Add-Check 'llm.endpoint' 'Writing' 'fail' 'Endpoint must be an absolute HTTP(S) URL.' 'Correct SAGE_LLM_ENDPOINT or SAGE_LLM_BASE_URL.'
            } elseif ($Uri.UserInfo -or $Uri.Query -or $Uri.Fragment) {
                Add-Check 'llm.endpoint' 'Writing' 'warn' 'Endpoint contains user information, query or fragment; value hidden.' 'Review endpoint security and provider format. Prefer credentials in headers.'
            } elseif ($Uri.Scheme -eq 'http' -and !$Uri.IsLoopback) {
                Add-Check 'llm.endpoint' 'Writing' 'warn' 'Non-local endpoint uses unencrypted HTTP.' 'Use HTTPS for remote model services.'
            } else { Add-Check 'llm.endpoint' 'Writing' 'pass' 'Endpoint syntax accepted; no network request made.' '' }
            if ([string]::IsNullOrWhiteSpace($Config.Model)) {
                Add-Check 'llm.model' 'Writing' 'fail' 'HTTP adapter has no model name.' 'Set SAGE_LLM_MODEL to a model supported by the provider.'
            }
            Add-Check 'llm.runtime' 'Writing' 'unverified' 'Credential configured, but connectivity, validity, model access and quota are untested.' 'Only an explicitly authorized model smoke test can verify these.'
        }
    } catch {
        Add-Check 'llm.config' 'Writing' 'fail' 'Model adapter rejected configuration; raw error suppressed to protect credentials.' 'Check provider/API style, credential presence, endpoint, timeout and CLI settings in LLM-CONFIG.md.'
    } finally { $Config = $null; $Settings = $null }
}

Test-Tool 'node' 'Web'
$WebPath = Join-Path $PSScriptRoot 'sagewrite-web.config.psd1'
if (Test-Path -LiteralPath $WebPath -PathType Leaf) {
    try {
        $Tokens = $null; $ParseErrors = $null
        $Ast = [Management.Automation.Language.Parser]::ParseFile($WebPath, [ref]$Tokens, [ref]$ParseErrors)
        if ($ParseErrors -or $Ast.EndBlock.Statements.Count -ne 1) { throw 'Invalid data file' }
        $Expression = $Ast.EndBlock.Statements[0].PipelineElements[0].Expression
        if ($Expression -isnot [Management.Automation.Language.HashtableAst]) { throw 'Expected data hashtable' }
        $Web = $Expression.SafeGetValue()
        if ($Web.WorkspaceRoot -and [IO.Path]::GetFullPath($Web.WorkspaceRoot) -ne $WorkspaceRoot) {
            Add-Check 'web.workspace' 'Web' 'warn' 'Web and PS1 workspace parents differ.' 'Align Web WorkspaceRoot and SAGEWRITE_WORKSPACE_ROOT intentionally before editing books.'
        } else { Add-Check 'web.workspace' 'Web' 'pass' 'No workspace-parent mismatch detected.' '' }
        if ($Web.HostName -notin @('127.0.0.1','localhost','::1') -and $Web.AuthMode -notin @('password','users')) {
            Add-Check 'web.exposure' 'Web' 'fail' 'Non-loopback listener has no recognized authentication mode.' 'Use localhost or configure authentication before exposing the service.'
        } else { Add-Check 'web.exposure' 'Web' 'pass' 'Listener/auth mode combination accepted; credentials not validated.' '' }
    } catch { Add-Check 'web.config' 'Web' 'fail' 'Local Web configuration is unreadable or invalid; raw error hidden.' 'Review the local PSD1 configuration without sharing its secrets.' }
} else { Add-Check 'web.config' 'Web' 'warn' 'No standalone Web configuration found; direct 06-web usage may still be possible.' 'Use the standalone installer DryRun without secret arguments if this route is needed.' }
Add-Check 'web.runtime' 'Web' 'unverified' 'Server startup, port availability and login were not tested.' 'Start the local Web service deliberately and verify access.'
Test-Tool 'pandoc' 'Pdf'
Test-Tool 'pandoc' 'Epub'
Test-Tool 'python' 'SimpleDocx'
Add-Check 'python.docx' 'SimpleDocx' 'unverified' 'python-docx import was not executed.' 'In the intended Python environment, run: python -c "import docx; print(docx.__version__)"'
Test-Tool 'magick' 'Images'
try {
    $Word = [Type]::GetTypeFromProgID('Word.Application')
    Add-Check 'word.registration' 'Pdf' $(if($Word){'pass'}else{'fail'}) 'Checks Word COM registration only; Word was not started.' 'Install desktop Microsoft Word if registration is missing.'
} catch { Add-Check 'word.registration' 'Pdf' 'fail' 'Unable to inspect Word COM registration.' 'Check desktop Word installation on Windows.' }
Add-Check 'word.export' 'Pdf' 'unverified' 'Word activation, fonts and actual export were not tested.' 'Open Word to finish activation/setup; render a disposable document and inspect its PDF.'
Add-Check 'fonts' 'Pdf' 'unverified' 'No book selected; required fonts cannot be inferred.' 'Check the book layout specification and actual rendered PDF for font substitution.'

Test-Tool 'node' 'Mcp'
foreach ($Package in @('@modelcontextprotocol/server','zod')) {
    $Path = Join-Path $PSScriptRoot ("mcp-server/node_modules/$Package/package.json")
    Add-Check ("mcp.package." + $Package) 'Mcp' $(if(Test-Path -LiteralPath $Path -PathType Leaf){'pass'}else{'fail'}) 'Package manifest presence only; module loading not tested.' 'Install dependencies from mcp-server/pnpm-lock.yaml using pnpm install --frozen-lockfile; then run its tests.'
}
$McpPath = Join-Path (Split-Path $PSScriptRoot -Parent) '.mcp.json'
if (Test-Path -LiteralPath $McpPath) {
    try {
        $Mcp = Get-Content -LiteralPath $McpPath -Raw -Encoding UTF8 | ConvertFrom-Json
        $Server = $Mcp.mcpServers.sagewrite
        if (!$Server -or !$Server.command) { throw 'Missing server' }
        $Command = Get-Command $Server.command -CommandType Application -ErrorAction SilentlyContinue
        Add-Check 'mcp.command' 'Mcp' $(if($Command){'pass'}else{'fail'}) 'Configured MCP command resolution checked; value hidden.' 'Replace other-machine paths in .mcp.json with this machine configuration; do not enable automatically.'
        $Missing = @($Server.args | Where-Object { [IO.Path]::IsPathRooted([string]$_) -and !(Test-Path -LiteralPath $_) })
        Add-Check 'mcp.paths' 'Mcp' $(if($Missing.Count){'fail'}else{'pass'}) 'Checked absolute argument paths only.' 'Resolve relative paths against the host working directory and verify the MCP handshake.'
        if ($Server.env.SAGEWRITE_WORKSPACE_ROOT -and !(Test-Path -LiteralPath $Server.env.SAGEWRITE_WORKSPACE_ROOT -PathType Container)) {
            Add-Check 'mcp.workspace' 'Mcp' 'warn' 'MCP-configured workspace parent does not exist locally.' 'Adapt SAGEWRITE_WORKSPACE_ROOT in the client configuration.'
        }
    } catch { Add-Check 'mcp.config' 'Mcp' 'fail' 'MCP configuration cannot be interpreted; contents hidden.' 'Review the sagewrite entry in .mcp.json.' }
} else { Add-Check 'mcp.config' 'Mcp' 'warn' 'No repository .mcp.json; host may have separate configuration.' 'Use mcp-server/mcp-config.example.json and adapt paths for the host.' }
Add-Check 'mcp.handshake' 'Mcp' 'unverified' 'MCP was not started or registered in any client.' 'Run protocol tests after installing dependencies and configuring local paths.'

$Selected = @($Checks | Where-Object { $Profile -eq 'All' -or $_.area -eq 'Core' -or $_.area -eq $Profile })
$Areas = @($Selected.area | Select-Object -Unique)
$Capabilities = foreach ($Area in $Areas) {
    $Items = @($Selected | Where-Object { $_.area -eq 'Core' -or $_.area -eq $Area })
    $State = if (@($Items | Where-Object status -eq 'fail').Count) { 'blocked' } else { 'requires_validation' }
    [pscustomobject]@{area=$Area; state=$State}
}
$Report = [ordered]@{
    schema_version=1; generated_at=[DateTime]::UtcNow.ToString('o'); profile=$Profile
    scope='Static local preflight; no models, installation, service startup, credential output or workspace writes.'
    capabilities=@($Capabilities); checks=$Selected
    counts=@{pass=@($Selected|Where-Object status -eq 'pass').Count; fail=@($Selected|Where-Object status -eq 'fail').Count; warn=@($Selected|Where-Object status -eq 'warn').Count; unverified=@($Selected|Where-Object status -eq 'unverified').Count}
}
$Text = $Report | ConvertTo-Json -Depth 8
if ($ReportDirectory) {
    [void][IO.Directory]::CreateDirectory([IO.Path]::GetFullPath($ReportDirectory))
    $Destination = Join-Path $ReportDirectory ('environment-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss') + '-' + [guid]::NewGuid().ToString('N') + '.json')
    $Stream = [IO.File]::Open($Destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write)
    try { $Bytes=[Text.Encoding]::UTF8.GetBytes($Text); $Stream.Write($Bytes,0,$Bytes.Length) } finally { $Stream.Dispose() }
    if (!$Json) { Write-Output "Report: $Destination" }
}
if ($Json) { Write-Output $Text } else {
    Write-Output "SageWrite environment: $Profile (static checks, not end-to-end certification)"
    foreach ($Check in $Selected) {
        Write-Output "[$($Check.status)] $($Check.area) / $($Check.id): $($Check.detail)"
        if ($Check.next_action -and $Check.status -ne 'pass') { Write-Output "  Next: $($Check.next_action)" }
    }
}
if ($Report.counts.fail -gt 0) { exit 1 }
exit 0
