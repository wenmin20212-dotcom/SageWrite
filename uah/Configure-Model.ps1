param(
  [ValidateSet('openai-compatible','openai','codex')][string]$Provider = 'openai-compatible',
  [string]$Model,
  [string]$BaseUrl
)
$ErrorActionPreference = 'Stop'
$config = @{ SAGE_LLM_PROVIDER = $Provider }
if ($Provider -ne 'codex') {
  if (!$Model) { $Model = Read-Host 'Writing model name' }
  if (!$BaseUrl) { $BaseUrl = Read-Host 'Model endpoint, for example https://provider.example/v1' }
  if (!$Model -or !$BaseUrl) { throw 'Model and endpoint are required' }
  $config.SAGE_LLM_MODEL = $Model
  $config.SAGE_LLM_BASE_URL = $BaseUrl
  $config.SAGE_LLM_API_STYLE = 'chat-completions'
  $secret = Read-Host 'API key (saved only on this machine)' -AsSecureString
  $pointer = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
  try { $config.SAGE_LLM_API_KEY = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer) }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer) }
}
[IO.File]::WriteAllText((Join-Path $PSScriptRoot 'model.local.json'), ($config | ConvertTo-Json), [Text.UTF8Encoding]::new($false))
Write-Host 'Writing model configured. Restart this SageWrite instance.'
