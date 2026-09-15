param(
    [Parameter(Mandatory=$true)][string]$BookName,
    [ValidateSet('Plan','Apply','Check')][string]$Mode = 'Plan',
    [ValidateRange(0,999)][int]$StartChapter = 0,
    [ValidateRange(0,999)][int]$EndChapter = 999,
    [string]$PlanPath,
    [string]$BookRoot
)

$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
if (!$BookRoot) {
    . (Join-Path $PSScriptRoot '00-common.ps1')
    $BookRoot = (Get-SageContext -ScriptPath $PSCommandPath -BookName $BookName).BookRoot
}
$BookRoot = (Resolve-Path -LiteralPath $BookRoot).Path
if ($StartChapter -gt $EndChapter) { throw 'StartChapter must not exceed EndChapter.' }
function In-Book([string]$Relative) {
    $path = [IO.Path]::GetFullPath((Join-Path $BookRoot $Relative))
    if (!$path.StartsWith($BookRoot.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "Path leaves book workspace: $Relative"
    }
    return $path
}
function Read-Text([string]$Path) { return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) }
function Normalize([string]$Text) { return $Text.Replace("`r`n", "`n").TrimStart([char]0xfeff) }
function Digest([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Save-Text([string]$Path, [string]$Text) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, $Text, [Text.UTF8Encoding]::new($true))
}
function Save-Json([string]$Path, $Object) { Save-Text $Path ($Object | ConvertTo-Json -Depth 60) }
function Required($Object, [string[]]$Names) {
    foreach ($name in $Names) {
        if ($null -eq $Object.$name -or [string]::IsNullOrWhiteSpace([string]$Object.$name)) { throw "Missing required field: $name" }
    }
}
function Replace-Exact([string]$Text, [string]$Find, [string]$Replacement) {
    if ([string]::IsNullOrEmpty($Find)) { throw 'Empty edit anchor.' }
    $start = $Text.IndexOf($Find, [StringComparison]::Ordinal)
    if ($start -lt 0 -or $Text.IndexOf($Find, $start + $Find.Length, [StringComparison]::Ordinal) -ge 0) {
        throw "Edit anchor must occur exactly once: $($Find.Substring(0,[Math]::Min(65,$Find.Length)))"
    }
    return $Text.Substring(0,$start) + $Replacement + $Text.Substring($start+$Find.Length)
}
function Get-Sections {
    $parent = ''; $number = -1; $index = 0
    foreach ($line in (Normalize (Read-Text (In-Book '01_outline/toc.md'))) -split "`n") {
        if ($line -match '^##\s+(.+)$') {
            $parent=$Matches[1].Trim(); $number=-1
            if ($parent -eq '前言') { $number=0 }
            elseif ($parent -match '^第\s*(\d+)\s*章') { $number=[int]$Matches[1] }
        } elseif ($line -match '^###\s+(.+)$') {
            $index++
            if ($number -lt 0) { continue }
            [pscustomobject]@{ file=('{0:D2}.md' -f $index); title=$Matches[1].Trim(); chapter=$number; chapter_title=$parent }
        }
    }
}
function Source-Entry($Source) {
    $authors = @($Source.authors) -join ', '
    $publication = [string]$Source.publication
    if ($Source.volume) { $publication += ', ' + $Source.volume }
    if ($Source.issue) { $publication += '(' + $Source.issue + ')' }
    if ($Source.pages) { $publication += ': ' + $Source.pages }
    return "$authors. ($($Source.year)). $($Source.title). $publication. $($Source.url)"
}
function Reference-Text($State) {
    $lines = [Collections.Generic.List[string]]::new()
    $lines.Add("---`nfile_role: references`ngenerated_by: 04R`n---`n`n# 参考文献`n")
    foreach ($group in @($State.groups | Sort-Object { [int]$_.order })) {
        $lines.Add('## ' + $group.title + "`n")
        foreach ($entry in @($group.entries)) {
            $source = @($State.sources | Where-Object { $_.id -ceq $entry.source_id })
            if ($source.Count -ne 1) { throw 'Reference source missing or duplicated.' }
            $lines.Add('[' + $entry.label + '] ' + (Source-Entry $source[0]) + "`n")
        }
    }
    return ($lines -join "`n").TrimEnd() + "`n"
}

$ReferencePath = In-Book '02_chapters/references.md'
$StatePath = In-Book '00_brief/references/reference_state.json'
$sections = @(Get-Sections)
if ($Mode -eq 'Plan') {
    $selected = @($sections | Where-Object { $_.chapter -ge $StartChapter -and $_.chapter -le $EndChapter })
    if (!$selected.Count) { throw 'No TOC sections in this range.' }
    if (!$PlanPath) { $PlanPath = In-Book "00_brief/references/plan_${StartChapter}_${EndChapter}.json" }
    if (Test-Path -LiteralPath $PlanPath) { throw 'Plan already exists; choose another PlanPath to preserve reviewed work.' }
    $items = foreach ($section in $selected) {
        $path = In-Book ('02_chapters/' + $section.file)
        if (!(Test-Path -LiteralPath $path)) { throw "Section missing: $path" }
        $text = Normalize (Read-Text $path)
        $tail = ($text.TrimEnd() -split "`n\s*`n")[-1]
        $candidate = ''
        if ($tail -match '^(?:\*{0,2}学术|本节.*(?:研究来源|可参照)|相关依据|从(?:学术|研究)脉络|从已有研究看|这一判断可以从)') { $candidate=$tail }
        [pscustomobject]@{ file=$section.file; section_title=$section.title; chapter=$section.chapter; expected_sha256=(Digest $text); reviewed=$false; candidate_tail=$candidate; remove_blocks=@(); replacements=@(); citations=@() }
    }
    Save-Json $PlanPath ([ordered]@{ schema_version=1; reviewed=$false; sources=@(); groups=@(); sections=@($items); pending_notes=@() })
    Write-Output "Plan created (no manuscript changes): $PlanPath"
    exit 0
}

$state = [pscustomobject]@{ schema_version=1; sources=@(); groups=@(); sections=@() }
if (Test-Path -LiteralPath $StatePath) { $state=Read-Text $StatePath | ConvertFrom-Json }
if ($Mode -eq 'Check') {
    if (!(Test-Path -LiteralPath $StatePath)) { throw 'No applied reference state.' }
    foreach ($item in @($state.sections)) {
        $text=Normalize (Read-Text (In-Book ('02_chapters/' + $item.file)))
        if ((Digest $text) -cne $item.after_sha256) { throw "Manuscript changed since reference processing: $($item.file)" }
        foreach ($label in @($item.labels)) { if (!$text.Contains('['+$label+']')) { throw "Citation missing: $label" } }
    }
    if ((Normalize (Read-Text $ReferencePath)) -cne (Reference-Text $state)) { throw 'Reference output differs from source registry.' }
    Write-Output "Check passed: $(@($state.sections).Count) sections; $(@($state.groups).Count) groups; $(@($state.sources).Count) sources."
    exit 0
}

if (!$PlanPath) { throw 'Apply requires -PlanPath.' }
$planText = Normalize (Read-Text $PlanPath)
$planHash = Digest $planText
$plan = $planText | ConvertFrom-Json
if ($plan.schema_version -ne 1 -or $plan.reviewed -ne $true) { throw 'Plan must use schema 1 and be reviewed.' }
if (!@($plan.sections).Count) { throw 'Plan contains no sections.' }
if (@($plan.sources | Group-Object id | Where-Object Count -gt 1).Count -or @($plan.sections | Group-Object file | Where-Object Count -gt 1).Count -or @($plan.groups | Group-Object key | Where-Object Count -gt 1).Count) { throw 'Duplicate plan IDs.' }
foreach ($source in @($plan.sources)) {
    Required $source @('id','authors','title','year','publication','url','verified_at','verification_url','evidence_summary','limits')
    if ($source.verified -ne $true -or $source.url -notmatch '^https://' -or $source.verification_url -notmatch '^https://') { throw "Source is not verified: $($source.id)" }
    $existing=@($state.sources | Where-Object { $_.id -ceq $source.id })
    if ($existing.Count) {
        if ((Source-Entry $existing[0]) -cne (Source-Entry $source)) { throw 'Existing source metadata changed; review the registry before applying.' }
    } else { $state.sources=@($state.sources)+$source }
}
foreach ($group in @($plan.groups)) {
    Required $group @('key','title','prefix')
    if ($group.prefix -notmatch '^(前|\d+)$') { throw 'Citation prefix must be 前 or a chapter number.' }
    $current=@($state.groups | Where-Object { $_.key -ceq $group.key })
    if (!$current.Count) {
        $state.groups=@($state.groups)+[pscustomobject]@{key=$group.key;title=$group.title;prefix=$group.prefix;order=[int]$group.order;entries=@()}
    } elseif ($current[0].prefix -cne $group.prefix -or $current[0].title -cne $group.title) { throw 'Existing reference group identity changed.' }
}
$writes=[ordered]@{}
$changed=@()
foreach ($section in @($plan.sections)) {
    if ($section.file -notmatch '^\d{2,}\.md$' -or $section.reviewed -ne $true) { throw 'Invalid or unreviewed section.' }
    $toc=@($sections | Where-Object { $_.file -ceq $section.file })
    if ($toc.Count -ne 1 -or $toc[0].chapter -ne $section.chapter -or $toc[0].title -cne $section.section_title) { throw "TOC mapping mismatch: $($section.file)" }
    $path=In-Book ('02_chapters/' + $section.file)
    $old=Normalize (Read-Text $path)
    $prior=@($state.sections | Where-Object { $_.file -ceq $section.file })
    if ($prior.Count -and $prior[0].plan_sha256 -ceq $planHash -and (Digest $old) -ceq $prior[0].after_sha256) { continue }
    if ((Digest $old) -cne $section.expected_sha256) { throw "Stale manuscript: $($section.file); create a new reviewed plan." }
    $group=@($state.groups | Where-Object { [int]$_.order -eq [int]$section.chapter })
    if ($group.Count -ne 1) { throw 'Section must resolve to one reference group.' }
    $group=$group[0]; $new=$old
    foreach ($block in @($section.remove_blocks)) {
        if ([string]::IsNullOrWhiteSpace($block) -or !$new.TrimEnd().EndsWith($block,[StringComparison]::Ordinal)) { throw 'Removal is restricted to an exact final block.' }
        $new=Replace-Exact $new $block ''
        $new=$new.TrimEnd()+"`n"
    }
    foreach ($edit in @($section.replacements)) {
        Required $edit @('find','replace','reason')
        $new=Replace-Exact $new $edit.find $edit.replace
    }
    $labels=@()
    foreach ($cite in @($section.citations)) {
        Required $cite @('anchor','support_note')
        if (!@($cite.source_ids).Count) { throw 'Citation needs a source.' }
        $marks=''
        foreach ($id in @($cite.source_ids | Select-Object -Unique)) {
            if (!@($state.sources | Where-Object { $_.id -ceq $id }).Count) { throw "Unknown source: $id" }
            $entry=@($group.entries | Where-Object { $_.source_id -ceq $id })
            if (!$entry.Count) {
                $entry=@([pscustomobject]@{source_id=$id;label=($group.prefix+'-'+(@($group.entries).Count+1))})
                $group.entries=@($group.entries)+$entry[0]
            }
            $marks+='['+$entry[0].label+']'; $labels+=$entry[0].label
        }
        $new=Replace-Exact $new $cite.anchor ($cite.anchor+$marks)
    }
    if (!$labels.Count) { throw "No citations mapped: $($section.file)" }
    $oldHeadings=@([regex]::Matches($old,'(?m)^#{1,6}\s+.+$') | ForEach-Object Value) -join "`n"
    $newHeadings=@([regex]::Matches($new,'(?m)^#{1,6}\s+.+$') | ForEach-Object Value) -join "`n"
    if ($oldHeadings -cne $newHeadings) { throw 'Reference processing must preserve section headings.' }
    $writes[$path]=$new
    $state.sections=@($state.sections | Where-Object { $_.file -cne $section.file })+[pscustomobject]@{
        file=$section.file;chapter=$section.chapter;before_sha256=(Digest $old);after_sha256=(Digest $new);plan_sha256=$planHash;labels=@($labels | Select-Object -Unique);removed_blocks=@($section.remove_blocks)
    }
    $changed+=$section.file
}
if (!$changed.Count) {
    if (!(Test-Path -LiteralPath $ReferencePath) -or (Normalize (Read-Text $ReferencePath)) -cne (Reference-Text $state)) { throw 'No-op plan but reference output differs; run Check.' }
    Write-Output 'Already applied; no files changed.'
    exit 0
}
if ((Test-Path -LiteralPath $ReferencePath) -and !(Test-Path -LiteralPath $StatePath)) { throw 'Unmanaged references.md exists; refusing to overwrite.' }
if (Test-Path -LiteralPath $StatePath) {
    $previous=Read-Text $StatePath | ConvertFrom-Json
    if ((Normalize (Read-Text $ReferencePath)) -cne (Reference-Text $previous)) { throw 'Reference output was manually changed; refusing to overwrite.' }
}
$writes[$ReferencePath]=Reference-Text $state
$writes[$StatePath]=$state | ConvertTo-Json -Depth 60
$stamp=Get-Date -Format 'yyyyMMdd_HHmmss_ffff'
$backup=In-Book ('back/references_' + $stamp)
[IO.Directory]::CreateDirectory($backup) | Out-Null
$originals=@{}
foreach ($path in $writes.Keys) {
    if (Test-Path -LiteralPath $path) {
        $relative=$path.Substring($BookRoot.Length+1)
        $copy=Join-Path $backup $relative
        [IO.Directory]::CreateDirectory((Split-Path -Parent $copy)) | Out-Null
        Copy-Item -LiteralPath $path -Destination $copy
        $originals[$path]=$copy
    }
}
Copy-Item -LiteralPath $PlanPath -Destination (Join-Path $backup 'applied_plan.json')
try {
    foreach ($path in $writes.Keys) { Save-Text $path $writes[$path] }
} catch {
    foreach ($path in $writes.Keys) {
        if ($originals.ContainsKey($path)) { Copy-Item -LiteralPath $originals[$path] -Destination $path -Force }
        elseif (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    }
    throw
}
$report=[ordered]@{date=(Get-Date -Format o);plan_sha256=$planHash;changed_sections=$changed;backup=$backup;references=$ReferencePath;groups=$state.groups;pending_notes=@($plan.pending_notes)}
Save-Json (In-Book ('04_output/editorial_audits/references_'+$stamp+'.json')) $report
Write-Output "Applied: $($changed.Count) sections. Backup: $backup"
Write-Output "References: $ReferencePath"
