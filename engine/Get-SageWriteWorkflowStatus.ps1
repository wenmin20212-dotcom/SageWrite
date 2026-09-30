param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [string]$BookRoot,
    [ValidatePattern('^[A-Za-z0-9-]{2,32}$')][string]$Language='zh',
    [switch]$SaveReport,
    [switch]$Details
)
$ErrorActionPreference='Stop'
[Console]::OutputEncoding=[Text.Encoding]::UTF8
. (Join-Path $PSScriptRoot '00-common.ps1')
. (Join-Path $PSScriptRoot '04f-format-common.ps1')
if ($BookName -match '[\\/:*?"<>|\r\n]' -or $BookName -in @('.','..')) { throw 'Invalid BookName.' }
if (!$BookRoot) {
    $BookRoot=(Get-SageContext -ScriptPath $PSCommandPath -BookName $BookName).BookRoot
    if ($Language -ne 'zh') { $BookRoot=Join-Path $BookRoot ('03_translation/'+$Language) }
}
$BookRoot=(Resolve-Path -LiteralPath $BookRoot).Path.TrimEnd('\','/')
if (!(Test-Path -LiteralPath $BookRoot -PathType Container)) { throw 'Book root must be a directory.' }
$warnings=New-Object 'System.Collections.Generic.List[string]'
function Read-BookJson([string]$Relative) {
    $p=Join-Path $BookRoot $Relative
    if (!(Test-Path -LiteralPath $p -PathType Leaf)) { return $null }
    try { return (Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json) }
    catch { $warnings.Add("Unreadable JSON: $Relative"); return $null }
}
function Get-Inventory {
    $paths=@('00_brief/objective.md','01_outline/toc.md','01_outline/layout_spec.md','00_brief/format_preflight.json','logs/status.json')
    foreach ($dir in @('02_chapters','00_brief/references','03_assets','04_output/editorial_audits')) {
        $p=Join-Path $BookRoot $dir
        if (Test-Path -LiteralPath $p -PathType Container) {
            $paths+=@(Get-ChildItem -LiteralPath $p -File -Recurse | ForEach-Object { $_.FullName.Substring($BookRoot.Length+1).Replace('\','/') })
        }
    }
    foreach($name in @('cover.png','cover.jpg','cover.jpeg','cover.webp','00_intake/cover.png','00_brief/writing_spec.md')) { $paths+=$name }
    $out=Join-Path $BookRoot '04_output'
    if (Test-Path -LiteralPath $out) {
        $paths+=@(Get-ChildItem -LiteralPath $out -File -Recurse | Where-Object { $_.Extension -in @('.pdf','.epub','.docx') -and $_.FullName -notmatch '[\\/]back[\\/]' } | ForEach-Object { $_.FullName.Substring($BookRoot.Length+1).Replace('\','/') })
    }
    foreach($relative in ($paths | Sort-Object -Unique)) {
        $p=Join-Path $BookRoot $relative
        $exists=Test-Path -LiteralPath $p -PathType Leaf
        $hash=$null
        if ($exists) { $hash=Get-FormatFileDigest $p }
        [pscustomobject]@{path=$relative;exists=$exists;algorithm='sha256-bytes';sha256=$hash}
    }
}
function Stage([string]$Id,[string]$State,[string]$Reason,$Evidence=@()) {
    [pscustomobject]@{id=$Id;state=$State;reason=$Reason;evidence=@($Evidence)}
}
$before=@(Get-Inventory)
$stages=@()
foreach($entry in @(@('definition','00_brief/objective.md'),@('outline','01_outline/toc.md'))) {
    $p=Join-Path $BookRoot $entry[1]
    $state='missing'; $reason='Required file is absent.'
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        if ([string]::IsNullOrWhiteSpace((Get-FormatText $p))) { $state='blocked'; $reason='Required file is empty.' }
        else { $state='present_unverified'; $reason='File exists; author acceptance is not inferred.' }
    }
    $stages+=Stage $entry[0] $state $reason @($entry[1])
}
# Match the stage-04F TOC mapping, including its appendix and chapter-mode rules.
$expected=@(); $tocPath=Join-Path $BookRoot '01_outline/toc.md'; $chapter=''; $orphan=$false
if (Test-Path -LiteralPath $tocPath) {
    $toc=Get-FormatText $tocPath
    foreach($line in $toc -split "`n") {
        if ($line -match '^##\s+(.+)$') { $chapter=$Matches[1] }
        elseif ($line -match '^###\s+(.+)$') {
            if (!$chapter) { $orphan=$true }
            if ($chapter -notmatch ('^'+[char]0x9644+[char]0x5F55)) { $expected+=$Matches[1].Trim() }
        }
    }
    $chapterMode=(!$expected.Count)
    if ($chapterMode) { $expected=@([regex]::Matches($toc,'(?m)^##\s+(.+?)\s*$') | ForEach-Object { $_.Groups[1].Value.Trim() }) }
    $writerCount=[regex]::Matches($toc,'(?m)^###[ \t]+(.+)').Count
    if ($writerCount -and $writerCount -ne $expected.Count) { $orphan=$true; $warnings.Add('03 writing and 04F appendix mappings differ; confirm scope before resuming.') }
} else { $chapterMode=$false }
$units=@()
for($i=0;$i -lt $expected.Count;$i++) {
    $file='02_chapters/{0:D2}.md' -f ($i+1); $p=Join-Path $BookRoot $file
    $state='missing'; $reason='No manuscript.'
    if (Test-Path -LiteralPath $p -PathType Leaf) {
        $body=[regex]::Replace((Get-FormatText $p),'\A---\n.*?\n---\n?','',[Text.RegularExpressions.RegexOptions]::Singleline)
        $pattern=if($chapterMode){'(?m)^#\s+(.+?)\s*$'}else{'(?m)^###\s+(.+?)\s*$'}
        $heads=[regex]::Matches($body,$pattern)
        $prose=[regex]::Replace($body,'(?m)^#{1,6}\s+.*$','').Trim()
        if (!$prose) { $state='blocked'; $reason='Empty or heading-only manuscript.' }
        elseif ($heads.Count -ne 1 -or $heads[0].Groups[1].Value.Trim() -cne $expected[$i]) { $state='blocked'; $reason='Heading does not match the TOC mapping.' }
        else { $state='present_unverified'; $reason='Mapped nonempty draft; not editorial acceptance.' }
    }
    $units+=[pscustomobject]@{index=$i+1;file=$file;title=$expected[$i];state=$state;reason=$reason}
}
$extras=@(); $chapterDir=Join-Path $BookRoot '02_chapters'
if (Test-Path -LiteralPath $chapterDir) {
    $extras=@(Get-ChildItem -LiteralPath $chapterDir -Filter '*.md' -File | Where-Object { $_.Name -notmatch '^_' -and $_.Name -ne 'references.md' -and ('02_chapters/'+$_.Name) -notin @($units.file) } | ForEach-Object { '02_chapters/'+$_.Name })
}
$written=@($units | Where-Object {$_.state -eq 'present_unverified'}).Count
$draftState='partial'; $draftReason='Some writing units are missing or invalid.'
if (!$expected.Count -or $orphan) { $draftState='blocked'; $draftReason='No usable TOC mapping or a section lacks its parent.' }
elseif ($extras.Count -or @($units | Where-Object {$_.state -eq 'blocked'}).Count) { $draftState='blocked'; $draftReason='Resolve extra files or invalid unit mappings.' }
elseif ($written -eq $expected.Count) { $draftState='present_unverified'; $draftReason='All units have mapped drafts; review is not implied.' }
elseif (!$written) { $draftState='missing'; $draftReason='No mapped drafts yet.' }
$stages+=Stage 'drafting' $draftState $draftReason @('01_outline/toc.md','02_chapters')
$reviewFiles=@($before | Where-Object {$_.exists -and $_.path -like '04_output/editorial_audits/*' -and $_.path -notlike '*format_preflight.json'} | ForEach-Object {$_.path})
$stages+=Stage 'editorial' $(if($reviewFiles.Count){'present_unverified'}else{'unknown'}) 'Review scope, decisions and baseline require their producer-specific interpretation.' $reviewFiles
$ref=Read-BookJson '00_brief/references/reference_state.json'
$refState='unknown'; $refReason='No readable reference state; applicability and scholarly verification are not inferred.'
if ($ref) {
    $refState='present_unverified'; $refReason='Reference state exists; metadata processing is not claim-level verification.'
    foreach($section in @($ref.sections)) {
        if (!$section.file -or !$section.after_sha256) { continue }
        if ($section.file -match '[\\/]' -or $section.file -notmatch '^\d+\.md$') { $refState='unknown'; continue }
        $p=Join-Path $chapterDir $section.file
        if (!(Test-Path -LiteralPath $p)) { $refState='stale'; $refReason='A reference-baseline manuscript is missing.'; break }
        # 04R Normalize/Digest use the same CRLF/BOM normalization as these helpers.
        if ((Get-FormatDigest (Get-FormatText $p)) -cne $section.after_sha256) { $refState='stale'; $refReason='A manuscript changed since native 04R reference processing.'; break }
    }
}
$stages+=Stage 'references' $refState $refReason @('00_brief/references/reference_state.json')
$assets=@($before | Where-Object {$_.exists -and ($_.path -like '03_assets/*' -or $_.path -match '(^|/)cover\.(png|jpg|jpeg|webp)$')} | ForEach-Object {$_.path})
$stages+=Stage 'assets' $(if($assets.Count){'present_unverified'}else{'unknown'}) 'Asset existence does not establish cover approval or complete image links.' $assets
$stamp=Read-BookJson '00_brief/format_preflight.json'
$formatState='missing'; $formatReason='No readable format approval.'; $nativeBefore=$null
if ($stamp) {
    $formatState='blocked'; $formatReason='Invalid or failed native approval.'
    if ($stamp.schema_version -eq 1 -and $stamp.passed -eq $true -and $stamp.book_root -ceq $BookRoot) {
        try {
            $nativeBefore=@(Get-FormatSnapshot $BookRoot)
            if (($nativeBefore|ConvertTo-Json -Depth 8 -Compress) -ceq ($stamp.inputs|ConvertTo-Json -Depth 8 -Compress)) { $formatState='current'; $formatReason='Native 04F input fingerprints match; no approval was changed.' }
            else { $formatState='stale'; $formatReason='Native 04F inputs changed; rerun approved preflight before export.' }
        } catch { $formatState='unknown'; $formatReason='Could not reproduce the native format snapshot.' }
    }
}
$stages+=Stage 'format' $formatState $formatReason @('00_brief/format_preflight.json')
$exports=@($before | Where-Object {$_.exists -and $_.path -match '\.(pdf|epub|docx)$'})
foreach($ext in @('pdf','epub','docx')) {
    $files=@($exports | Where-Object {$_.path -like "*.$ext"} | ForEach-Object {$_.path})
    $stages+=Stage $ext $(if($files.Count){'present_unverified'}else{'missing'}) 'Existing exports are not proof of current-source generation or visual/package acceptance.' $files
}
$log=Read-BookJson 'logs/status.json'
$runSummary=$null
if ($log) { $runSummary=[pscustomobject]@{updated_at=$log.updated_at;has_current=($null -ne $log.current);has_last_error=($null -ne $log.last_error);note='Historical telemetry only; current does not prove a live process.'} }
$after=@(Get-Inventory)
$stable=(($before|ConvertTo-Json -Depth 8 -Compress) -ceq ($after|ConvertTo-Json -Depth 8 -Compress))
if ($nativeBefore) {
    try { if (($nativeBefore|ConvertTo-Json -Depth 8 -Compress) -cne (@(Get-FormatSnapshot $BookRoot)|ConvertTo-Json -Depth 8 -Compress)) { $stable=$false } }
    catch { $stable=$false }
}
if (!$stable) { foreach($stage in $stages) { $stage.state='unknown'; $stage.reason='Files changed during inspection; retry when writers are idle.' } }
$next='Inspect review and reference evidence before requesting final preflight/export.'
if ($stages[0].state -in @('missing','blocked')) { $next='Define or repair objective.md via sagewrite-new-book with author authorization.' }
elseif (!$expected.Count -or $orphan) { $next='Confirm and repair TOC via sagewrite-generate-toc.' }
elseif ($draftState -eq 'blocked') { $next='Resolve manuscript mapping problems before writing or exporting.' }
elseif ($written -lt $expected.Count) { $next='Confirm outline acceptance, then write only the missing units via sagewrite-write-chapters.' }
if (!$stable) { $next='Wait for concurrent changes to finish and inspect again.' }
$report=[ordered]@{schema_version=1;record_type='sagewrite_workflow_advisory';observed_at=[DateTime]::UtcNow.ToString('o');book_root=$BookRoot;language=$Language;engine_root=$PSScriptRoot;stable=$stable;counts=@{expected=$expected.Count;drafts_present=$written;remaining=$expected.Count-$written;extra_files=$extras.Count};stages=@($stages);units=@($units);extra_files=@($extras);inputs=@($before);run_summary=$runSummary;next_action=$next;warnings=@($warnings.ToArray());limitations=@('No model calls, editorial judgments, human approvals or export acceptance inferred.','Reference and editorial legacy reports are inventoried, not semantically certified.','No automatic post-write hook; call again after a batch to refresh.');report_path=$null}
if ($SaveReport) {
    $dir=Join-Path $BookRoot 'logs/workflow_status'
    [IO.Directory]::CreateDirectory($dir)|Out-Null
    $report.report_path=Join-Path $dir (([DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfffZ'))+'_'+[Guid]::NewGuid().ToString('N')+'.json')
    $bytes=[Text.UTF8Encoding]::new($false).GetBytes(($report|ConvertTo-Json -Depth 30))
    $stream=[IO.File]::Open($report.report_path,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write)
    try { $stream.Write($bytes,0,$bytes.Length) } finally { $stream.Dispose() }
}
if (!$Details) {
    $report.Remove('inputs'); $report.Remove('units')
    foreach($stage in $stages) {
        $stage|Add-Member -NotePropertyName evidence_count -NotePropertyValue @($stage.evidence).Count
        $stage.evidence=@($stage.evidence|Select-Object -First 10)
    }
    $report['attention_units']=@($units|Where-Object {$_.state -ne 'present_unverified'}|Select-Object -First 20)
    $report['attention_truncated']=(@($units|Where-Object {$_.state -ne 'present_unverified'}).Count -gt 20)
}
$report|ConvertTo-Json -Depth 30
