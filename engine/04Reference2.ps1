param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [ValidateSet('Plan','Record','Report')][string]$Mode = 'Plan',
    [string]$BookRoot,
    [string]$RunId,
    [string]$EvidencePath
)
$ErrorActionPreference = 'Stop'
if (!$BookRoot) {
    . "$PSScriptRoot/00-common.ps1"
    $BookRoot = (Get-SageContext -ScriptPath $PSCommandPath -BookName $BookName).BookRoot
}
$BookRoot = (Resolve-Path -LiteralPath $BookRoot).Path
function Read-Json($p) { Get-Content -LiteralPath $p -Raw -Encoding UTF8 | ConvertFrom-Json }
function Save-Json($p, $v) { [IO.File]::WriteAllText($p, ($v | ConvertTo-Json -Depth 60), [Text.UTF8Encoding]::new($true)) }
function Hash($p) {
    $sha = [Security.Cryptography.SHA256]::Create()
    $stream = [IO.File]::OpenRead($p)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally { $stream.Dispose(); $sha.Dispose() }
}
function Book-File([string]$p) {
    $full = [IO.Path]::GetFullPath((Join-Path $BookRoot $p))
    if (!$full.StartsWith($BookRoot.TrimEnd('\','/') + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) { throw 'Path outside book.' }
    return $full
}
function Required($v, $fields) {
    foreach ($f in $fields) { if ([string]::IsNullOrWhiteSpace([string]$v.$f)) { throw "Missing field: $f" } }
}
function Validate-Decision($decision, $task) {
    if ($null -eq $decision) { return }
    Required $decision @('action','reason')
    if ($decision.action -cnotin @('modify','no_change','defer')) { throw 'Invalid decision action.' }
    $changes = @($decision.changes | Where-Object { $null -ne $_ })
    if ($decision.action -ne 'modify') {
        if ($changes.Count) { throw 'Only modify may contain changes.' }
        return
    }
    if ($task.kind -ne 'source') { throw 'Automatic changes only support source metadata; defer manuscript changes.' }
    if (!$changes.Count) { throw 'Modify requires explicit changes.' }
    $fields = @()
    foreach ($change in $changes) {
        Required $change @('field','reason')
        if ($change.field -cnotin @('url','verification_url','title','publication','year','volume','issue','pages','authors')) { throw 'Unsupported modification field.' }
        if ($change.field -in $fields) { throw 'Duplicate modification field.' }
        $fields += $change.field
        if ('old_value' -notin $change.PSObject.Properties.Name -or 'new_value' -notin $change.PSObject.Properties.Name) { throw 'Old and new values required.' }
        $old = ConvertTo-Json -InputObject $task.source.($change.field) -Compress -Depth 10
        $expected = ConvertTo-Json -InputObject $change.old_value -Compress -Depth 10
        $updated = ConvertTo-Json -InputObject $change.new_value -Compress -Depth 10
        if ($old -cne $expected) { throw 'Modification old_value does not match source snapshot.' }
        if ($expected -ceq $updated -or $null -eq $change.new_value) { throw 'Modification must supply a different non-null value.' }
        if ($change.field -eq 'authors') {
            if ($change.new_value -isnot [array] -or !$change.new_value.Count -or @($change.new_value | Where-Object { $_ -isnot [string] -or [string]::IsNullOrWhiteSpace($_) }).Count) { throw 'Authors must be a nonempty string array.' }
        } elseif ($change.field -eq 'year') {
            if ([string]$change.new_value -notmatch '^\d{4}$') { throw 'Year must have four digits.' }
        } elseif ($change.new_value -isnot [string] -or [string]::IsNullOrWhiteSpace($change.new_value)) { throw 'New field value must be a nonempty string.' }
        if ($change.field -in @('url','verification_url')) {
            $uri = $null
            if (![uri]::TryCreate($change.new_value, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -ne 'https') { throw 'Source URLs must use HTTPS.' }
        }
    }
}
function Export-Changes($reviewPlan) {
    $actions = @()
    foreach ($task in $reviewPlan.tasks) {
        $relative = 'records/' + $task.id + '.json'
        $path = Join-Path $run $relative
        $record = if (Test-Path -LiteralPath $path) { Read-Json $path } else { $null }
        $decision = if ($record) { $record.evidence.decision } else { $null }
        Validate-Decision $decision $task
        $actions += [pscustomobject]@{
            task_id=$task.id; kind=$task.kind; source_id=$task.source_id
            file=$task.file; label=$task.label
            review_status=$(if($record){$record.evidence.verdict}else{'pending'})
            action=$(if($decision){$decision.action}else{'pending'})
            reason=$(if($decision){$decision.reason}elseif($record){'Legacy evidence has no structured decision; do not infer from prose.'}else{'Not reviewed.'})
            changes=@($(if($decision){$decision.changes}) | Where-Object {$null -ne $_})
            target_path='00_brief/references/reference_state.json'
            selector=[pscustomobject]@{collection='sources';id=$task.source_id}
            evidence_path=$(if($record){$relative}else{$null})
            evidence_sha256=$(if($record){Hash $path}else{$null})
        }
    }
    $id = [guid]::NewGuid().ToString('N')
    $output = [ordered]@{
        schema='sagewrite.reference_changes'; schema_version=1
        export_id=$id; run_id=$RunId; book_name=$BookName
        generated_at=[DateTime]::UtcNow.ToString('o')
        review_plan_sha256=(Hash $planPath); expected_files=$reviewPlan.snapshots
        approval=[ordered]@{approved=$false;approved_by='';approved_at=''}
        execution_policy=[ordered]@{requires_explicit_approval=$true;allow_manuscript_edits=$false;rebuild_references_after_metadata_changes=$true;requires_04r_check=$true}
        counts=[ordered]@{
            total=$actions.Count;modify=@($actions | Where-Object action -eq 'modify').Count
            no_change=@($actions | Where-Object action -eq 'no_change').Count
            defer=@($actions | Where-Object action -eq 'defer').Count
            pending=@($actions | Where-Object action -eq 'pending').Count
        }
        actions=$actions
    }
    $history = Join-Path $run "modification_plan_$id.json"
    Save-Json $history $output
    # Replace the latest view only after the full immutable export exists.
    $latest = Join-Path $run 'modification_plan.json'
    $temp = Join-Path $run "$id.tmp"
    Copy-Item -LiteralPath $history -Destination $temp
    if (Test-Path -LiteralPath $latest) { [IO.File]::Replace($temp,$latest,(Join-Path $run "previous_latest_$id.json")) }
    else { [IO.File]::Move($temp,$latest) }
    Log "Modification plan exported (not approved): $latest"
}
function Log($message) {
    Add-Content -LiteralPath (Join-Path $run 'progress.jsonl') -Encoding UTF8 -Value (([ordered]@{time=[DateTime]::UtcNow.ToString('o');message=$message} | ConvertTo-Json -Compress))
    Write-Output $message
}
$root = Book-File '04_output/editorial_audits/reference_rechecks'
if ($Mode -eq 'Plan') {
    if ($RunId) { throw 'Plan generates a unique RunId; do not supply one.' }
    $RunId = (Get-Date -Format 'yyyyMMdd_HHmmss') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8)
} elseif (!$RunId -or $RunId -notmatch '^\d{8}_\d{6}_[a-f0-9]{8}$') { throw 'Supply the RunId printed by Plan.' }
$run = Join-Path $root $RunId
$planPath = Join-Path $run 'plan.json'
if ($Mode -eq 'Plan') {
    $stateRel = '00_brief/references/reference_state.json'
    $state = Read-Json (Book-File $stateRel)
    if (!$state.sources -or !$state.groups -or !$state.sections) { throw '04R applied reference state is required.' }
    $paths = @($stateRel, '02_chapters/references.md', '01_outline/toc.md')
    $paths += @(Get-ChildItem -LiteralPath (Book-File '02_chapters') -File -Filter '*.md' | ForEach-Object { '02_chapters/' + $_.Name })
    $snapshots = @($paths | Select-Object -Unique | ForEach-Object { [pscustomobject]@{path=$_;sha256=(Hash (Book-File $_))} })
    $tasks = @()
    foreach ($source in @($state.sources)) {
        $tasks += [pscustomobject]@{id=('T{0:D4}' -f ($tasks.Count+1));kind='source';source_id=$source.id;source=$source;file='';label='';claim=''}
    }
    foreach ($section in @($state.sections)) {
        if ($section.file -notmatch '^\d+\.md$') { throw 'Invalid section file in state.' }
        $body = Get-Content -LiteralPath (Book-File ('02_chapters/' + $section.file)) -Raw -Encoding UTF8
        foreach ($label in @($section.labels | Select-Object -Unique)) {
            $entries = @($state.groups | ForEach-Object { $_.entries } | Where-Object {$_.label -ceq $label})
            if ($entries.Count -ne 1) { throw "Ambiguous or missing label: $label" }
            $source = @($state.sources | Where-Object {$_.id -ceq $entries[0].source_id})
            if ($source.Count -ne 1) { throw "Missing or duplicate source: $label" }
            $paragraphs = @([regex]::Split($body, '\r?\n\s*\r?\n') | Where-Object { $_.Contains('['+$label+']') })
            if (!$paragraphs.Count) { throw "Citation missing: $label in $($section.file)" }
            foreach ($paragraph in $paragraphs) {
                $tasks += [pscustomobject]@{id=('T{0:D4}' -f ($tasks.Count+1));kind='claim';source_id=$source[0].id;source=$source[0];file=$section.file;label=$label;claim=$paragraph.Trim()}
            }
        }
    }
    [IO.Directory]::CreateDirectory((Join-Path $run 'records')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $run 'snapshots')) | Out-Null
    foreach ($s in $snapshots) {
        $target = Join-Path (Join-Path $run 'snapshots') $s.path
        [IO.Directory]::CreateDirectory((Split-Path $target -Parent)) | Out-Null
        Copy-Item -LiteralPath (Book-File $s.path) -Destination $target
    }
    Save-Json $planPath ([ordered]@{schema_version=1;run_id=$RunId;book_name=$BookName;created_at=[DateTime]::UtcNow.ToString('o');snapshots=$snapshots;tasks=$tasks})
    Save-Json (Join-Path $run 'evidence-template.json') ([ordered]@{task_id=$tasks[0].id;reviewer='';checked_at='';access='';verdict='';verification_url='';evidence='';locator='';limitations='';recommendation='';decision=[ordered]@{action='defer';reason='Awaiting review';changes=@()}})
    Log "Plan created: $RunId; tasks=$($tasks.Count). No sources have been reverified."
    Write-Output "Plan: $planPath"
    Export-Changes (Read-Json $planPath)
    exit 0
}
if (!(Test-Path -LiteralPath $planPath)) { throw 'Run not found.' }
$plan = Read-Json $planPath
if ($plan.book_name -cne $BookName -or $plan.run_id -cne $RunId) { throw 'Run identity mismatch.' }
$stale = @($plan.snapshots | Where-Object { !(Test-Path -LiteralPath (Book-File $_.path)) -or (Hash (Book-File $_.path)) -cne $_.sha256 })
$known = @($plan.snapshots | ForEach-Object {$_.path})
$extra = @(Get-ChildItem -LiteralPath (Book-File '02_chapters') -File -Filter '*.md' | Where-Object { ('02_chapters/' + $_.Name) -notin $known })
if ($stale.Count -or $extra.Count) { Log 'STALE: manuscript or reference inputs changed. Create a new Plan.'; throw 'Stale review run.' }
if ($Mode -eq 'Record') {
    if (!$EvidencePath) { throw 'Record requires EvidencePath.' }
    $e = Read-Json $EvidencePath
    Required $e @('task_id','reviewer','checked_at','access','verdict','evidence','limitations','recommendation')
    if (@($plan.tasks | Where-Object {$_.id -ceq $e.task_id}).Count -ne 1) { throw 'Unknown task_id.' }
    if ($e.access -notin @('full_text','abstract','metadata','unavailable')) { throw 'Invalid access.' }
    if ($e.verdict -notin @('pass','partial','unsupported','metadata_mismatch','unconfirmed')) { throw 'Invalid verdict.' }
    $date = [DateTimeOffset]::MinValue
    # PowerShell 7 may deserialize ISO JSON timestamps into DateTime values.
    $checkedAtText = if ($e.checked_at -is [DateTime] -or $e.checked_at -is [DateTimeOffset]) { $e.checked_at.ToString('o') } else { [string]$e.checked_at }
    if (![DateTimeOffset]::TryParse($checkedAtText, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::None, [ref]$date) -or $date -gt [DateTimeOffset]::UtcNow.AddMinutes(5)) { throw 'Invalid or future checked_at.' }
    if ($e.access -ne 'unavailable') {
        Required $e @('verification_url','locator')
        $uri = $null
        if (![uri]::TryCreate($e.verification_url, [UriKind]::Absolute, [ref]$uri) -or $uri.Scheme -notin @('http','https')) { throw 'Invalid verification URL.' }
    }
    $task = @($plan.tasks | Where-Object {$_.id -ceq $e.task_id})[0]
    if (($e.access -eq 'unavailable' -and $e.verdict -ne 'unconfirmed') -or ($task.kind -eq 'claim' -and $e.access -eq 'metadata' -and $e.verdict -in @('pass','partial'))) { throw 'Access level cannot support this verdict.' }
    Validate-Decision $e.decision $task
    if ($e.decision.action -eq 'modify' -and ($e.access -eq 'unavailable' -or $e.verdict -eq 'unconfirmed')) { throw 'Unconfirmed evidence cannot propose an executable modification.' }
    # Exclusive creation preserves all previous evidence; corrections use a new run.
    $recordPath = Join-Path (Join-Path $run 'records') ($e.task_id + '.json')
    $stream = [IO.File]::Open($recordPath, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $bytes = [Text.Encoding]::UTF8.GetBytes((([ordered]@{recorded_at=[DateTime]::UtcNow.ToString('o');task=$task;evidence=$e} | ConvertTo-Json -Depth 60)))
        $stream.Write($bytes,0,$bytes.Length)
    } finally { $stream.Dispose() }
    Log "Recorded $($e.task_id): $($e.verdict). Agent-supplied evidence; not an automatic academic certification."
}
$results = @()
foreach ($task in $plan.tasks) {
    $p = Join-Path (Join-Path $run 'records') ($task.id + '.json')
    $record = if (Test-Path -LiteralPath $p) { Read-Json $p } else { $null }
    $results += [pscustomobject]@{task=$task;status=$(if($record){$record.evidence.verdict}else{'pending'});record=$record}
}
$pending = @($results | Where-Object status -eq 'pending').Count
$issues = @($results | Where-Object {$_.status -notin @('pass','pending')}).Count
$status = if($pending){'incomplete'}elseif($issues){'needs_review'}else{'agent_reported_pass'}
$summary = [ordered]@{run_id=$RunId;status=$status;total=$results.Count;pending=$pending;issues=$issues;generated_at=[DateTime]::UtcNow.ToString('o');results=$results}
$stamp = [guid]::NewGuid().ToString('N')
Save-Json (Join-Path $run "report_$stamp.json") $summary
$lines = @('# Reference recheck report', '', "Run: $RunId", "Status: $status; total=$($results.Count); pending=$pending; issues=$issues", '', 'Evidence is supplied by a reviewer/Agent. Record completeness is not independent verification.', '')
foreach ($r in $results) {
    $lines += "## $($r.task.id) / $($r.task.kind) / $($r.status)"
    $lines += "Source: $($r.task.source_id); file: $($r.task.file); label: $($r.task.label)"
    $lines += $r.task.claim
    if ($r.record) { $lines += '```json'; $lines += ($r.record.evidence | ConvertTo-Json -Depth 20); $lines += '```' }
    $lines += ''
}
$report = Join-Path $run "report_$stamp.md"
[IO.File]::WriteAllText($report, ($lines -join "`r`n"), [Text.UTF8Encoding]::new($true))
Log "Report: $status; pending=$pending; issues=$issues; $report"
Export-Changes $plan
