param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [ValidateSet('Check','Normalize','Verify')][string]$Mode='Check',
    [string]$BookRoot,
    [string]$Language='zh'
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot '04f-format-common.ps1')
if (!$BookRoot) {
    . (Join-Path $PSScriptRoot '00-common.ps1')
    $BookRoot=(Get-SageContext -ScriptPath $PSCommandPath -BookName $BookName).BookRoot
    if ($Language -ne 'zh') { $BookRoot=Join-Path $BookRoot ('03_translation/'+$Language) }
}
$BookRoot=(Resolve-Path -LiteralPath $BookRoot).Path.TrimEnd('\')
$stampPath=Join-Path $BookRoot '00_brief/format_preflight.json'
$reportPath=Join-Path $BookRoot '04_output/editorial_audits/format_preflight.json'
$statePath=Join-Path $BookRoot '00_brief/references/reference_state.json'
$reportWritten=$false
try {
    if ($Mode -eq 'Verify') {
        if (!(Test-Path -LiteralPath $stampPath)) { throw 'No format approval. Run 04F.ps1 -Mode Check (or Normalize) first.' }
        $stamp=Get-FormatText $stampPath | ConvertFrom-Json
        if ($stamp.schema_version -ne 1 -or $stamp.passed -ne $true -or $stamp.book_root -cne $BookRoot) { throw 'Invalid format approval.' }
        $now=Get-FormatSnapshot $BookRoot
        if (($now|ConvertTo-Json -Depth 8 -Compress) -cne ($stamp.inputs|ConvertTo-Json -Depth 8 -Compress)) { throw 'Format approval is stale: manuscript, TOC, assets, references or program changed. Run 04F again.' }
        Write-Output 'Format approval verified against current inputs.'
        exit 0
    }
    if (Test-Path -LiteralPath $stampPath) { Remove-Item -LiteralPath $stampPath }
    $initial=Get-FormatSnapshot $BookRoot
    $result=Test-FormatBook $BookRoot
    $state=$null
    if (Test-Path -LiteralPath $statePath) {
        & (Join-Path $PSScriptRoot '04R.ps1') -BookName $BookName -BookRoot $BookRoot -Mode Check
        if ($LASTEXITCODE -ne 0) { throw 'Reference check failed; do not rebaseline unrelated manuscript edits.' }
        $state=Get-FormatText $statePath | ConvertFrom-Json
        if (@($state.sections).Count -ne $result.sections) { throw 'Reference processing is incomplete for this TOC.' }
    }
    $backup=''; $changed=@()
    if ($Mode -eq 'Normalize' -and !$result.issues.Count -and $result.edits.Count) {
        if (((Get-FormatSnapshot $BookRoot)|ConvertTo-Json -Depth 8 -Compress) -cne ($initial|ConvertTo-Json -Depth 8 -Compress)) { throw 'Inputs changed during validation.' }
        $backup=Join-Path $BookRoot ('back/format_'+(Get-Date -Format 'yyyyMMdd_HHmmss_ffff'))
        [IO.Directory]::CreateDirectory((Join-Path $backup '02_chapters'))|Out-Null
        foreach($e in $result.edits) { Copy-Item -LiteralPath (Join-Path $BookRoot ('02_chapters/'+$e.file)) -Destination (Join-Path $backup ('02_chapters/'+$e.file)) }
        if ($state) { Copy-Item -LiteralPath $statePath -Destination (Join-Path $backup 'reference_state.json') }
        try {
            foreach($e in $result.edits) {
                # Only the deterministic heading transform is allowed to rebaseline 04R.
                if ((Convert-FormatSection $e.before).text -cne $e.after) { throw 'Non-format edit rejected.' }
                [IO.File]::WriteAllText((Join-Path $BookRoot ('02_chapters/'+$e.file)), $e.after,[Text.UTF8Encoding]::new($true))
                $changed += [pscustomobject]@{file=$e.file;changes=$e.changes;before_sha256=(Get-FormatDigest $e.before);after_sha256=(Get-FormatDigest $e.after)}
                if ($state) {
                    $item=@($state.sections|Where-Object {$_.file -ceq $e.file})
                    if ($item.Count -ne 1 -or $item[0].after_sha256 -cne (Get-FormatDigest $e.before)) { throw 'Reference baseline mismatch.' }
                    $item[0].after_sha256=Get-FormatDigest $e.after
                }
            }
            if ($state) {
                $history=@(); if ($state.PSObject.Properties['format_history']) { $history=@($state.format_history) }
                $history += [pscustomobject]@{at=(Get-Date -Format o);backup=$backup;files=$changed}
                $state|Add-Member -NotePropertyName format_history -NotePropertyValue $history -Force
                Save-FormatJson $statePath $state
                & (Join-Path $PSScriptRoot '04R.ps1') -BookName $BookName -BookRoot $BookRoot -Mode Check
                if ($LASTEXITCODE -ne 0) { throw 'Post-format reference validation failed.' }
            }
        } catch {
            foreach($e in $result.edits) { Copy-Item -LiteralPath (Join-Path $backup ('02_chapters/'+$e.file)) -Destination (Join-Path $BookRoot ('02_chapters/'+$e.file)) -Force }
            if ($state) { Copy-Item -LiteralPath (Join-Path $backup 'reference_state.json') -Destination $statePath -Force }
            throw
        }
        $result=Test-FormatBook $BookRoot
    }
    $passed=(!$result.issues.Count -and !$result.edits.Count)
    $report=[ordered]@{schema_version=1;passed=$passed;mode=$Mode;at=(Get-Date -Format o);book_root=$BookRoot;sections=$result.sections;backup=$backup;changed=$changed;issues=$result.issues;pending_headings=@($result.edits|ForEach-Object {[pscustomobject]@{file=$_.file;changes=$_.changes}});warnings=$result.warnings}
    $report['layout_adjustments']=$result.layout_adjustments
    Save-FormatJson $reportPath $report
    $reportWritten=$true
    if (!$passed) { throw "Format check blocked: $($result.issues.Count) issues; $($result.edits.Count) files require heading normalization. Report: $reportPath" }
    Save-FormatJson $stampPath ([ordered]@{schema_version=1;passed=$true;at=(Get-Date -Format o);book_root=$BookRoot;inputs=@(Get-FormatSnapshot $BookRoot)})
    Write-Output "Format passed: $($result.sections) sections; changed $($changed.Count) files. Report: $reportPath"
} catch {
    if (Test-Path -LiteralPath $stampPath) { Remove-Item -LiteralPath $stampPath }
    if ($Mode -ne 'Verify' -and !$reportWritten) {
        Save-FormatJson $reportPath ([ordered]@{schema_version=1;passed=$false;mode=$Mode;at=(Get-Date -Format o);book_root=$BookRoot;error=$_.Exception.Message})
    }
    Write-Error $_
    exit 1
}
