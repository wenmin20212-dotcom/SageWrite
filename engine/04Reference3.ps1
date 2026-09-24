param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [Parameter(Mandatory=$true)][string]$PlanPath,
    [ValidateSet('Preview','Apply')][string]$Mode = 'Preview',
    [string]$BookRoot,
    [string[]]$TaskId
)
$ErrorActionPreference = 'Stop'
if (!$BookRoot) {
    . "$PSScriptRoot/00-common.ps1"
    $BookRoot = (Get-SageContext -ScriptPath $PSCommandPath -BookName $BookName).BookRoot
}
$BookRoot = (Resolve-Path -LiteralPath $BookRoot).Path.TrimEnd('\','/')
$PlanPath = (Resolve-Path -LiteralPath $PlanPath).Path
function Read-Json($p) { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
function Save-Text($p,$v) { [IO.File]::WriteAllText($p,$v,[Text.UTF8Encoding]::new($true)) }
function Save-Json($p,$v) { Save-Text $p ($v | ConvertTo-Json -Depth 60) }
function Hash($p) {
    $sha=[Security.Cryptography.SHA256]::Create(); $s=[IO.File]::OpenRead($p)
    try { return ([BitConverter]::ToString($sha.ComputeHash($s))).Replace('-','') }
    finally { $s.Dispose(); $sha.Dispose() }
}
function Equal-Json($a,$b) {
    return (ConvertTo-Json -InputObject $a -Depth 30 -Compress) -ceq (ConvertTo-Json -InputObject $b -Depth 30 -Compress)
}
function Book-File($relative) {
    $p=[IO.Path]::GetFullPath((Join-Path $BookRoot $relative))
    if (!$p.StartsWith($BookRoot+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)) { throw 'Path leaves book.' }
    return $p
}
function Check-Inputs($expected) {
    foreach($f in $expected) {
        $p=Book-File $f.path
        if (!(Test-Path -LiteralPath $p) -or (Hash $p) -cne $f.sha256) { throw "Stale input: $($f.path)" }
    }
    foreach($f in Get-ChildItem -LiteralPath (Book-File '02_chapters') -File -Filter '*.md') {
        if (('02_chapters/'+$f.Name) -notin @($expected.path)) { throw "New manuscript file: $($f.Name)" }
    }
}
function Check-04R {
    $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File "$PSScriptRoot/04R.ps1" -BookName $BookName -BookRoot $BookRoot -Mode Check 2>&1
    if ($LASTEXITCODE -ne 0) { throw "04R Check failed: $($output -join ' ')" }
    return ($output -join "`n")
}
function Reference-Text($state) {
    # Keep the canonical rendering identical to 04R; its post-check is mandatory.
    $lines=[Collections.Generic.List[string]]::new()
    $heading = -join @([char]0x53C2,[char]0x8003,[char]0x6587,[char]0x732E)
    $lines.Add("---`nfile_role: references`ngenerated_by: 04R`n---`n`n# $heading`n")
    foreach($g in @($state.groups | Sort-Object { [int]$_.order })) {
        $lines.Add('## '+$g.title+"`n")
        foreach($e in @($g.entries)) {
            $sources=@($state.sources | Where-Object {$_.id -ceq $e.source_id})
            if($sources.Count -ne 1) { throw 'Ambiguous source.' }
            $s=$sources[0]; $authors=@($s.authors) -join ', '; $pub=[string]$s.publication
            if($s.volume){$pub+=', '+$s.volume}; if($s.issue){$pub+='('+$s.issue+')'}; if($s.pages){$pub+=': '+$s.pages}
            $lines.Add('['+$e.label+"] $authors. ($($s.year)). $($s.title). $pub. $($s.url)`n")
        }
    }
    return ($lines -join "`n").TrimEnd()+"`n"
}
$plan=Read-Json $PlanPath
if($plan.schema -cne 'sagewrite.reference_changes' -or $plan.schema_version -ne 1 -or $plan.book_name -cne $BookName) { throw 'Invalid plan schema or book.' }
if($plan.run_id -notmatch '^\d{8}_\d{6}_[a-f0-9]{8}$') { throw 'Invalid RunId.' }
$run=Book-File ('04_output/editorial_audits/reference_rechecks/'+$plan.run_id)
$reviewPath=Join-Path $run 'plan.json'
if((Hash $reviewPath) -cne $plan.review_plan_sha256) { throw 'Review plan hash mismatch.' }
$review=Read-Json $reviewPath
if($review.book_name -cne $BookName -or $review.run_id -cne $plan.run_id -or !(Equal-Json $review.snapshots $plan.expected_files)) { throw 'Review identity or snapshot manifest mismatch.' }
foreach($required in @('00_brief/references/reference_state.json','02_chapters/references.md','01_outline/toc.md')) {
    if($required -notin @($review.snapshots.path)) { throw 'Missing required snapshot.' }
}
if(@($plan.actions | Group-Object task_id | Where-Object Count -gt 1).Count -or @($plan.actions).Count -ne @($review.tasks).Count) { throw 'Missing or duplicate task actions.' }
foreach($a in $plan.actions) {
    if(@($review.tasks | Where-Object {$_.id -ceq $a.task_id}).Count -ne 1) { throw 'Unknown task.' }
}
if($Mode -eq 'Apply') {
    if($TaskId) { throw 'Apply scope must come from approval.task_ids, not TaskId.' }
    if($plan.approval.approved -isnot [bool] -or $plan.approval.approved -ne $true -or [string]::IsNullOrWhiteSpace($plan.approval.approved_by)) { throw 'Explicit recorded approval is required.' }
    $date=[DateTimeOffset]::MinValue
    if(![DateTimeOffset]::TryParse($plan.approval.approved_at,[ref]$date) -or $date -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) { throw 'Invalid approval time.' }
    $selectedIds=@($plan.approval.task_ids)
    if(!$selectedIds.Count -or $null -eq $selectedIds[0]) { throw 'Approval requires explicit task_ids.' }
} elseif($TaskId) { $selectedIds=@($TaskId) }
elseif($plan.approval.task_ids) { $selectedIds=@($plan.approval.task_ids) }
else { $selectedIds=@($plan.actions | Where-Object {$_.action -in @('modify','no_change')} | ForEach-Object {$_.task_id}) }
if(!$selectedIds.Count -or @($selectedIds | Select-Object -Unique).Count -ne $selectedIds.Count) { throw 'Empty or duplicate selected scope.' }
$selected=@(foreach($id in $selectedIds){
    $match=@($plan.actions | Where-Object {$_.task_id -ceq $id})
    if($match.Count -ne 1){throw 'Unknown selected task.'}; $match[0]
})
$statePath=Book-File '00_brief/references/reference_state.json'
$referencePath=Book-File '02_chapters/references.md'
$formatPath=Book-File '00_brief/format_preflight.json'
$lockPath=Book-File '00_brief/references/reference3.lock'
$lock=$null
try {
    $lock=[IO.File]::Open($lockPath,[IO.FileMode]::CreateNew,[IO.FileAccess]::Write,[IO.FileShare]::None)
    Check-Inputs $review.snapshots
    $precheck=Check-04R
    $state=Read-Json $statePath
    $changes=@(); $keys=@()
    foreach($a in $selected) {
        if($a.action -cnotin @('modify','no_change')) { throw 'Pending/deferred actions cannot be executed.' }
        $task=@($review.tasks | Where-Object {$_.id -ceq $a.task_id})[0]
        if($a.source_id -cne $task.source_id -or $a.kind -cne $task.kind -or $a.file -cne $task.file -or $a.label -cne $task.label) { throw 'Action identity mismatch.' }
        if($a.target_path -cne '00_brief/references/reference_state.json' -or $a.selector.collection -cne 'sources' -or $a.selector.id -cne $a.source_id) { throw 'Unsupported target.' }
        $evidenceRelative='records/'+$a.task_id+'.json'
        if($a.evidence_path -cne $evidenceRelative) { throw 'Invalid evidence path.' }
        $ep=Join-Path $run $evidenceRelative
        if((Hash $ep) -cne $a.evidence_sha256) { throw 'Evidence hash mismatch.' }
        $record=Read-Json $ep
        if(!(Equal-Json $record.task $task) -or $record.evidence.task_id -cne $a.task_id -or $record.evidence.verdict -cne $a.review_status) { throw 'Evidence identity mismatch.' }
        $d=$record.evidence.decision
        if($d.action -cne $a.action -or $d.reason -cne $a.reason -or !(Equal-Json @($d.changes) @($a.changes))) { throw 'Action differs from reviewed evidence.' }
        if($a.action -eq 'no_change') { if(@($a.changes).Count){throw 'no_change cannot contain edits.'}; continue }
        if($a.kind -ne 'source' -or !@($a.changes).Count -or $record.evidence.access -eq 'unavailable' -or $record.evidence.verdict -eq 'unconfirmed') { throw 'Unsupported or unconfirmed modification.' }
        $sources=@($state.sources | Where-Object {$_.id -ceq $a.source_id})
        if($sources.Count -ne 1) { throw 'Source not uniquely resolved.' }
        $source=$sources[0]
        foreach($c in $a.changes) {
            if($c.field -cnotin @('url','verification_url','title','publication','year','volume','issue','pages','authors')) { throw 'Unsupported field.' }
            $key=$a.source_id+'/'+$c.field
            if($key -in $keys){throw 'Duplicate/conflicting target field.'}; $keys+=$key
            if([string]::IsNullOrWhiteSpace($c.reason) -or 'old_value' -notin $c.PSObject.Properties.Name -or 'new_value' -notin $c.PSObject.Properties.Name) { throw 'Incomplete edit.' }
            if(!(Equal-Json $source.($c.field) $c.old_value) -or !(Equal-Json $task.source.($c.field) $c.old_value)) { throw 'Old value mismatch.' }
            if($null -eq $c.new_value -or (Equal-Json $c.old_value $c.new_value)) { throw 'Invalid new value.' }
            if($c.field -eq 'authors') {
                if($c.new_value -isnot [array] -or !$c.new_value.Count -or @($c.new_value | Where-Object {$_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_)}).Count) {throw 'Invalid authors.'}
            } elseif($c.field -eq 'year') {
                if([string]$c.new_value -notmatch '^\d{4}$'){throw 'Invalid year.'}
            } elseif($c.new_value -isnot [string] -or [string]::IsNullOrWhiteSpace($c.new_value)){throw 'Invalid string value.'}
            if($c.field -in @('url','verification_url')) {
                $uri=$null
                if(![uri]::TryCreate($c.new_value,[UriKind]::Absolute,[ref]$uri) -or $uri.Scheme -ne 'https'){throw 'Invalid HTTPS URL.'}
            }
            $source | Add-Member -MemberType NoteProperty -Name $c.field -Value $c.new_value -Force
            $changes += [pscustomobject]@{task_id=$a.task_id;source_id=$a.source_id;field=$c.field;old_value=$c.old_value;new_value=$c.new_value;reason=$c.reason}
        }
    }
    $stamp=(Get-Date -Format 'yyyyMMdd_HHmmss')+'_'+[guid]::NewGuid().ToString('N').Substring(0,8)
    $out=Book-File ('04_output/editorial_audits/reference_executions/'+$stamp)
    [IO.Directory]::CreateDirectory($out) | Out-Null
    $report=[ordered]@{schema_version=1;book_name=$BookName;mode=$Mode;plan_sha256=(Hash $PlanPath);run_id=$plan.run_id;scope=$selectedIds;out_of_scope_count=(@($plan.actions).Count-$selected.Count);changes=$changes;status='preview';backup='';precheck=$precheck;postcheck='';error='';created_at=[DateTime]::UtcNow.ToString('o')}
    Copy-Item -LiteralPath $PlanPath -Destination (Join-Path $out 'input_plan.json')
    if($Mode -eq 'Apply' -and $changes.Count) {
        $backup=Book-File ('back/reference3_'+$stamp)
        [IO.Directory]::CreateDirectory($backup) | Out-Null
        $originals=@{}
        foreach($p in @($statePath,$referencePath,$formatPath)) {
            if(Test-Path -LiteralPath $p) {
                $dest=Join-Path $backup ([IO.Path]::GetFileName($p))
                Copy-Item -LiteralPath $p -Destination $dest
                $originals[$p]=$dest
            }
        }
        Copy-Item -LiteralPath $PlanPath -Destination (Join-Path $backup 'approved_plan.json')
        $report.backup=$backup
        Check-Inputs $review.snapshots
        try {
            Save-Json $statePath $state
            Save-Text $referencePath (Reference-Text $state)
            $report.postcheck=Check-04R
            foreach($snapshot in $review.snapshots | Where-Object {$_.path -notin @('00_brief/references/reference_state.json','02_chapters/references.md')}) {
                if((Hash (Book-File $snapshot.path)) -cne $snapshot.sha256){throw 'Unexpected manuscript change during execution.'}
            }
            if(Test-Path -LiteralPath $formatPath){Remove-Item -LiteralPath $formatPath}
            $report.status='applied'
        } catch {
            $report.error=$_.Exception.Message
            foreach($p in $originals.Keys){Copy-Item -LiteralPath $originals[$p] -Destination $p -Force}
            $report.status='rolled_back'
            Save-Json (Join-Path $out 'execution.json') $report
            throw "Execution failed; originals restored. Report: $out. $($report.error)"
        }
    } elseif($Mode -eq 'Apply'){ $report.status='no_changes' }
    Save-Json (Join-Path $out 'execution.json') $report
    $lines=@('# Reference modification execution', '', "Status: $($report.status)", "Mode: $Mode", "Scope: $($selectedIds -join ', ')", "Out of scope: $($report.out_of_scope_count)", "Backup: $($report.backup)", '', 'No manuscript edits are supported. Applied metadata changes require a new 04F check before export.', '')
    foreach($c in $changes){$lines+=('```json');$lines+=($c | ConvertTo-Json -Depth 10);$lines+='```'}
    Save-Text (Join-Path $out 'execution.md') ($lines -join "`r`n")
    Write-Output "Status: $($report.status); edits=$($changes.Count); report: $out"
} finally {
    if($lock){$lock.Dispose();Remove-Item -LiteralPath $lockPath -ErrorAction SilentlyContinue}
}
