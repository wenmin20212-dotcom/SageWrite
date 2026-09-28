$ErrorActionPreference = 'Stop'
$Root = Join-Path ([IO.Path]::GetTempPath()) ('sage-rw-test-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($Root)
function Put($Path, $Text) {
    [void][IO.Directory]::CreateDirectory((Split-Path $Path -Parent))
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($false))
}
Copy-Item (Join-Path $PSScriptRoot '03RW.ps1') $Root
Copy-Item (Join-Path $PSScriptRoot '00-common.ps1') $Root
Put (Join-Path $Root '00-llm.ps1') @'
function Get-SageLlmConfig { @{ Provider='mock'; Model='mock' } }
function Copy-SageLlmConfig { param($Config,$ModelOverride) $Config }
function Invoke-SageLlmText {
    param($Prompt,$Config)
    if ($Prompt -match '(?s)<original_chapter>\s*(.*?)\s*</original_chapter>') { return $Matches[1] }
    return 'Mock audit: unchanged. Human review required.'
}
'@
$Book = Join-Path $Root 'book'
Put (Join-Path $Book '00_brief/writing_spec.md') 'Change language only.'
Put (Join-Path $Book '01_outline/toc.md') "# TOC`n## One`n## Two"
Put (Join-Path $Book '02_chapters/01.md') "# One`n`nFirst original paragraph."
Put (Join-Path $Book '02_chapters/02.md') "# Two`n`nSecond original paragraph."
$Script = Join-Path $Root '03RW.ps1'
& $Script -BookRoot $Book -CheckOnly
if (Test-Path (Join-Path $Book '03_rewrite')) { throw 'CheckOnly wrote files.' }
$Before = (Get-FileHash (Join-Path $Book '02_chapters/01.md')).Hash
& $Script -BookRoot $Book -Chapter 1
if (Test-Path (Join-Path $Book '03_rewrite/chapters/02.md')) { throw 'Chapter selection failed.' }
& $Script -BookRoot $Book -All
& $Script -BookRoot $Book -All
if ((Get-FileHash (Join-Path $Book '02_chapters/01.md')).Hash -ne $Before) { throw 'Source changed.' }
$Report = Get-Content (Join-Path $Book '03_rewrite/review/02.md.json') -Raw | ConvertFrom-Json
if ($Report.status -ne 'needs_human_review') { throw 'Review status missing.' }
Put (Join-Path $Book '00_brief/writing_spec.md') 'Changed specification'
$Rejected = $false
try { & $Script -BookRoot $Book -All } catch { $Rejected = $_.Exception.Message -match 'TOC/spec changed' }
if (!$Rejected) { throw 'Changed specification was accepted.' }
Write-Output "PASS: validation, selection, resume, source preservation, review status, spec guard. Fixtures: $Root"
