function Get-SageLlmSetting {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Name,

        [string]$Default = ""
    )

    $Value = [Environment]::GetEnvironmentVariable($Name)
    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Default
    }

    return $Value.Trim()
}

function Get-SageLlmConfig {
    $Provider = (Get-SageLlmSetting -Name "SAGE_LLM_PROVIDER" -Default "openai").ToLowerInvariant()
    $ModelDefault = if ($Provider -eq "openai") { "gpt-5.6" } else { "" }
    $Model = Get-SageLlmSetting -Name "SAGE_LLM_MODEL" -Default $ModelDefault
    $ApiStyleDefault = if ($Provider -eq "openai") {
        "responses"
    }
    elseif ($Provider -eq "codex") {
        "codex-exec"
    }
    else {
        "chat-completions"
    }
    $ApiStyle = (Get-SageLlmSetting -Name "SAGE_LLM_API_STYLE" -Default $ApiStyleDefault).ToLowerInvariant()
    $BaseUrlDefault = if ($Provider -eq "openai") { "https://api.openai.com/v1" } else { "" }
    $BaseUrl = Get-SageLlmSetting -Name "SAGE_LLM_BASE_URL" -Default $BaseUrlDefault
    $Endpoint = Get-SageLlmSetting -Name "SAGE_LLM_ENDPOINT"
    $CodexCommand = Get-SageLlmSetting -Name "SAGE_LLM_CODEX_COMMAND" -Default "codex"
    $CodexWorkDir = Get-SageLlmSetting -Name "SAGE_LLM_CODEX_WORKDIR" -Default ([Environment]::CurrentDirectory)
    $ApiKey = Get-SageLlmSetting -Name "SAGE_LLM_API_KEY"
    if ([string]::IsNullOrWhiteSpace($ApiKey)) {
        $ApiKey = Get-SageLlmSetting -Name "OPENAI_API_KEY"
    }

    if ($Provider -eq "codex") {
        if ($ApiStyle -ne "codex-exec") {
            throw "Provider 'codex' requires SAGE_LLM_API_STYLE 'codex-exec'."
        }
        if (-not (Get-Command $CodexCommand -ErrorAction SilentlyContinue)) {
            throw "Codex command not found: $CodexCommand"
        }
        if (-not (Test-Path -LiteralPath $CodexWorkDir -PathType Container)) {
            throw "SAGE_LLM_CODEX_WORKDIR does not exist: $CodexWorkDir"
        }
    }
    elseif ($ApiStyle -notin @("responses", "chat-completions")) {
        throw "Unsupported SAGE_LLM_API_STYLE '$ApiStyle'. Use 'responses' or 'chat-completions'."
    }
    if ($Provider -ne "codex" -and [string]::IsNullOrWhiteSpace($Endpoint)) {
        if ([string]::IsNullOrWhiteSpace($BaseUrl)) {
            throw "SAGE_LLM_BASE_URL or SAGE_LLM_ENDPOINT must be set for provider '$Provider'."
        }
        $Endpoint = if ($ApiStyle -eq "responses") {
            $BaseUrl.TrimEnd('/') + "/responses"
        }
        else {
            $BaseUrl.TrimEnd('/') + "/chat/completions"
        }
    }
    if ($Provider -ne "codex" -and [string]::IsNullOrWhiteSpace($ApiKey)) {
        throw "SAGE_LLM_API_KEY is not set. OPENAI_API_KEY is accepted as a compatibility fallback."
    }

    $TimeoutText = Get-SageLlmSetting -Name "SAGE_LLM_TIMEOUT_SEC" -Default "180"
    $TimeoutSec = 180
    if (-not [int]::TryParse($TimeoutText, [ref]$TimeoutSec) -or $TimeoutSec -le 0) {
        throw "SAGE_LLM_TIMEOUT_SEC must be a positive integer."
    }

    return @{
        Provider = $Provider
        Model = $Model
        ApiStyle = $ApiStyle
        Endpoint = $Endpoint
        ApiKey = $ApiKey
        TimeoutSec = $TimeoutSec
        CodexCommand = $CodexCommand
        CodexWorkDir = $CodexWorkDir
    }
}

function Invoke-SageCodexText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,

        [Parameter(Mandatory=$true)]
        [hashtable]$Config
    )

    if ($Config.CodexWorkDir.Contains('"')) {
        throw "SAGE_LLM_CODEX_WORKDIR cannot contain a double quote."
    }
    if (-not [string]::IsNullOrWhiteSpace($Config.Model) -and $Config.Model.Contains('"')) {
        throw "SAGE_LLM_MODEL cannot contain a double quote."
    }

    $CommandInfo = Get-Command $Config.CodexCommand -ErrorAction Stop
    $ExecutablePath = if (-not [string]::IsNullOrWhiteSpace($CommandInfo.Path)) {
        $CommandInfo.Path
    }
    else {
        $CommandInfo.Source
    }
    $ArgumentText = 'exec --ephemeral --skip-git-repo-check --sandbox read-only --color never --cd "' + $Config.CodexWorkDir + '"'
    if (-not [string]::IsNullOrWhiteSpace($Config.Model)) {
        $ArgumentText += ' --model "' + $Config.Model + '"'
    }
    $ArgumentText += ' -'

    $ProcessInfo = New-Object System.Diagnostics.ProcessStartInfo
    $ProcessInfo.FileName = $ExecutablePath
    $ProcessInfo.Arguments = $ArgumentText
    $ProcessInfo.WorkingDirectory = $Config.CodexWorkDir
    $ProcessInfo.UseShellExecute = $false
    $ProcessInfo.CreateNoWindow = $true
    $ProcessInfo.RedirectStandardInput = $true
    $ProcessInfo.RedirectStandardOutput = $true
    $ProcessInfo.RedirectStandardError = $true
    $ProcessInfo.StandardOutputEncoding = [System.Text.UTF8Encoding]::new($false)
    $ProcessInfo.StandardErrorEncoding = [System.Text.UTF8Encoding]::new($false)

    $Process = New-Object System.Diagnostics.Process
    $Process.StartInfo = $ProcessInfo
    try {
        if (-not $Process.Start()) {
            throw "Unable to start codex exec."
        }
        $OutputTask = $Process.StandardOutput.ReadToEndAsync()
        $ErrorTask = $Process.StandardError.ReadToEndAsync()
        $PromptBytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Prompt)
        $Process.StandardInput.BaseStream.Write($PromptBytes, 0, $PromptBytes.Length)
        $Process.StandardInput.BaseStream.Flush()
        $Process.StandardInput.BaseStream.Close()
        $Process.WaitForExit()
        $Output = $OutputTask.Result
        $ErrorText = $ErrorTask.Result

        if ($Process.ExitCode -ne 0) {
            throw "codex exec failed with exit code $($Process.ExitCode). $($ErrorText.Trim())"
        }

        $Text = $Output.Trim()
        if ([string]::IsNullOrWhiteSpace($Text)) {
            throw "codex exec did not return text."
        }
        return $Text
    }
    finally {
        $Process.Dispose()
    }
}

function Get-SageLlmResponseText {
    param(
        [Parameter(Mandatory=$true)]
        $Response,

        [Parameter(Mandatory=$true)]
        [string]$ApiStyle
    )

    if ($ApiStyle -eq "chat-completions") {
        return [string]$Response.choices[0].message.content
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Response.output_text)) {
        return [string]$Response.output_text
    }

    $Parts = @()
    foreach ($OutputItem in @($Response.output)) {
        foreach ($ContentItem in @($OutputItem.content)) {
            if (-not [string]::IsNullOrWhiteSpace([string]$ContentItem.text)) {
                $Parts += [string]$ContentItem.text
            }
        }
    }
    return ($Parts -join "`n").Trim()
}

function Invoke-SageLlmText {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Prompt,

        [hashtable]$Config = (Get-SageLlmConfig),

        [int]$MaxOutputTokens = 0
    )

    $SystemPrompt = Get-SageLlmSetting -Name "SAGE_LLM_SYSTEM_PROMPT"
    if ($Config.Provider -eq "codex") {
        $CodexPrompt = if ([string]::IsNullOrWhiteSpace($SystemPrompt)) {
            $Prompt
        }
        else {
            "$SystemPrompt`n`n$Prompt"
        }
        return Invoke-SageCodexText -Prompt $CodexPrompt -Config $Config
    }

    $BodyObject = if ($Config.ApiStyle -eq "responses") {
        $Body = @{
            model = $Config.Model
            input = $Prompt
        }
        if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
            $Body.instructions = $SystemPrompt
        }
        if ($MaxOutputTokens -gt 0) {
            $Body.max_output_tokens = $MaxOutputTokens
        }
        $Body
    }
    else {
        $Messages = @()
        if (-not [string]::IsNullOrWhiteSpace($SystemPrompt)) {
            $Messages += @{ role = "system"; content = $SystemPrompt }
        }
        $Messages += @{ role = "user"; content = $Prompt }
        $Body = @{
            model = $Config.Model
            messages = $Messages
        }
        if ($MaxOutputTokens -gt 0) {
            $Body.max_tokens = $MaxOutputTokens
        }
        $Body
    }

    $JsonString = $BodyObject | ConvertTo-Json -Depth 20 -Compress
    $Utf8Bytes = [System.Text.Encoding]::UTF8.GetBytes($JsonString)
    $Response = Invoke-RestMethod `
        -Uri $Config.Endpoint `
        -Method Post `
        -Headers @{
            "Authorization" = "Bearer $($Config.ApiKey)"
            "Content-Type" = "application/json; charset=utf-8"
        } `
        -Body $Utf8Bytes `
        -TimeoutSec $Config.TimeoutSec

    $Text = Get-SageLlmResponseText -Response $Response -ApiStyle $Config.ApiStyle
    if ([string]::IsNullOrWhiteSpace($Text)) {
        throw "The LLM response did not contain text."
    }

    return $Text
}
