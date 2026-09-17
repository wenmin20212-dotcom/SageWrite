. (Join-Path $PSScriptRoot '00-layout.ps1')
function Get-FormatText([string]$Path) {
    return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8).Replace("`r`n", "`n").TrimStart([char]0xfeff)
}
function Get-FormatDigest([string]$Text) {
    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)))).Replace('-','').ToLowerInvariant() }
    finally { $sha.Dispose() }
}
function Save-FormatJson([string]$Path, $Data) {
    [IO.Directory]::CreateDirectory((Split-Path -Parent $Path)) | Out-Null
    [IO.File]::WriteAllText($Path, ($Data | ConvertTo-Json -Depth 70), [Text.UTF8Encoding]::new($true))
}
function Get-FormatFileDigest([string]$Path) {
    $sha=[Security.Cryptography.SHA256]::Create(); $stream=[IO.File]::OpenRead($Path)
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-','') }
    finally { $stream.Dispose(); $sha.Dispose() }
}
function Convert-FormatSection([string]$Text) {
    $lines = $Text -split "`n", 0, 'SimpleMatch'
    $section = ''; $counts = @(0,0,0); $changes = @(); $issues = @(); $fence = ''; $front = $false
    for ($i=0; $i -lt $lines.Count; $i++) {
        $line = $lines[$i]
        if ($i -eq 0 -and $line -eq '---') { $front=$true; continue }
        if ($front) { if ($line -eq '---') { $front=$false }; continue }
        if ($line -match '^\s*(`{3,}|~{3,})') {
            $mark=$Matches[1]
            if (!$fence) { $fence=$mark }
            elseif ($mark[0] -eq $fence[0] -and $mark.Length -ge $fence.Length) { $fence='' }
            continue
        }
        if ($fence) { continue }
        if ($line -match '^###\s+(\d+\.\d+)\b') { $section=$Matches[1]; $counts=@(0,0,0); continue }
        if (!$section) { continue }
        if ($line -match '^(#{4,6})\s+(.+?)\s*$') {
            $hashes=$Matches[1]; $title=$Matches[2]; $level=$hashes.Length-4
            if ($level -gt 0 -and $counts[$level-1] -eq 0) {
                $issues += [pscustomobject]@{line=$i+1;kind='hierarchy';message='Heading skips a parent level.'}; continue
            }
            $counts[$level]++
            for($j=$level+1;$j -lt 3;$j++) { $counts[$j]=0 }
            $title=[regex]::Replace($title, '^\d+(?:\.\d+){1,}[、.．:：]?\s*', '')
            $title=[regex]::Replace($title, '^(?:第[一二三四五六七八九十百\d]+(?:步|层|点|部分)?[，、:：.．]\s*|[（(][一二三四五六七八九十百\d]+[）)]\s*|[一二三四五六七八九十百\d]+[、.．]\s*)', '')
            if ([string]::IsNullOrWhiteSpace($title)) { $issues += [pscustomobject]@{line=$i+1;kind='empty_heading';message='Heading has no title.'}; continue }
            $number = $section + '.' + (($counts[0..$level]) -join '.')
            $new = "$hashes $number $title"
            if ($new -cne $line) { $changes += [pscustomobject]@{line=$i+1;before=$line;after=$new}; $lines[$i]=$new }
        }
        elseif ($line -match '^#{1,3}\s|^#{7,}\s') {
            $issues += [pscustomobject]@{line=$i+1;kind='heading_level';message='Unexpected heading level inside a section.'}
        }
        elseif ($line -match '^#{4,6}\S' -or ($line -match '^(?:\*\*[^*]{1,70}\*\*|[一二三四五六七八九十]+[、．.].{1,60}|\d+[、．].{1,60})\s*$' -and $line -notmatch '[。！？；]')) {
            $issues += [pscustomobject]@{line=$i+1;kind='ambiguous_heading';message='Possible plain/bold heading. Mark as #### or an explicit Markdown list; no automatic promotion.'}
        }
    }
    if ($fence) { $issues += [pscustomobject]@{line=$lines.Count;kind='unclosed_fence';message='Unclosed code fence.'} }
    return [pscustomobject]@{text=($lines -join "`n");changes=@($changes);issues=@($issues)}
}
function Get-FormatSnapshot([string]$Root) {
    $paths = @('01_outline/toc.md','01_outline/layout_spec.md','00_brief/objective.md','00_brief/references/reference_state.json')
    $paths += @(Get-ChildItem -LiteralPath (Join-Path $Root '02_chapters') -Filter '*.md' -File | Where-Object {$_.Name -notmatch '^_'} | ForEach-Object {'02_chapters/'+$_.Name})
    foreach ($dir in @('03_assets')) {
        $assetRoot=Join-Path $Root $dir
        if (Test-Path -LiteralPath $assetRoot) {
            $paths += @(Get-ChildItem -LiteralPath $assetRoot -Recurse -File | ForEach-Object { $_.FullName.Substring($Root.TrimEnd('\').Length+1).Replace('\','/') })
        }
    }
    $paths += @('cover.png','cover.jpg','cover.jpeg','cover.webp')
    $items = foreach($relative in ($paths | Sort-Object -Unique)) {
        $p=Join-Path $Root $relative
        if (Test-Path -LiteralPath $p -PathType Leaf) { [pscustomobject]@{path=$relative;sha256=(Get-FormatFileDigest $p)} }
    }
    foreach($name in @('00-common.ps1','00-layout.ps1','04-edit.ps1','04F.ps1','04f-format-common.ps1','04R.ps1','05-build.ps1','05b-epub.ps1','05ca-print-docx.ps1','05c-pdf.ps1','05cc-print-pdf.ps1')) {
        $items += [pscustomobject]@{path='engine/'+$name;sha256=(Get-FormatFileDigest (Join-Path $PSScriptRoot $name))}
    }
    return @($items)
}
function Test-FormatBook([string]$Root) {
    $issues=@(); $warnings=@(); $edits=@(); $expected=@(); $chapter=''; $layoutAdjustments=@(); $singlePolicy='keep'
    $toc=Join-Path $Root '01_outline/toc.md'
    if (!(Test-Path -LiteralPath $toc)) { throw 'Missing 01_outline/toc.md.' }
    $tocText=Get-FormatText $toc
    if ($tocText -match '(?m)^references_toc_depth:\s*(.+?)\s*$' -and $Matches[1] -notin @('1','2')) { throw 'references_toc_depth must be 1 or 2.' }
    if ($tocText -match '(?m)^toc_depth:\s*(.+?)\s*$' -and $Matches[1] -notin @('2','3')) { throw 'toc_depth must be 2 or 3.' }
    if ($tocText -match '(?m)^single_subheading_policy:\s*(.+?)\s*$') {
        $singlePolicy=$Matches[1]
        if ($singlePolicy -notin @('body','keep')) { throw 'single_subheading_policy must be body or keep.' }
    }
    if ($tocText -match '(?m)^frontmatter_heading_depth:\s*(.+?)\s*$' -and $Matches[1] -notin @('2','3')) { throw 'frontmatter_heading_depth must be 2 or 3.' }
    foreach($line in $tocText -split "`n") {
        if ($line -match '^##\s+(.+)$') { $chapter=$Matches[1] }
        elseif ($line -match '^###\s+(.+)$') {
            $sectionTitle=$Matches[1].Trim()
            if (!$chapter) { throw 'TOC section has no parent chapter.' }
            if ($chapter -match '^附录') { $warnings += "Deferred TOC appendix: $sectionTitle"; continue }
            $expected += $sectionTitle
        }
    }
    if (!$expected.Count) { throw 'TOC has no sections.' }
    $files=@(Get-ChildItem -LiteralPath (Join-Path $Root '02_chapters') -Filter '*.md' -File | Where-Object {$_.Name -notmatch '^_'})
    $numeric=@($files | Where-Object {$_.BaseName -match '^\d+$'})
    if ($numeric.Count -ne $expected.Count) { $issues += [pscustomobject]@{file='toc.md';line=0;kind='file_count';message='TOC section and numeric file counts differ.'} }
    foreach($f in $files | Where-Object {$_.BaseName -notmatch '^\d+$' -and $_.Name -ne 'references.md'}) { $issues += [pscustomobject]@{file=$f.Name;line=0;kind='extra_file';message='Unexpected buildable Markdown file.'} }
    for($i=0;$i -lt $expected.Count;$i++) {
        $name='{0:D2}.md' -f ($i+1); $path=Join-Path $Root ('02_chapters/'+$name)
        if (!(Test-Path -LiteralPath $path)) { $issues += [pscustomobject]@{file=$name;line=0;kind='missing_file';message='Missing section file.'}; continue }
        $t=Get-FormatText $path
        $body=[regex]::Replace($t,'\A---\n.*?\n---\n?','',[Text.RegularExpressions.RegexOptions]::Singleline)
        $heading=[regex]::Match($body,'(?m)^###\s+(.+?)\s*$')
        if (!$heading.Success -or $heading.Groups[1].Value.Trim() -cne $expected[$i] -or [regex]::Matches($body,'(?m)^###\s').Count -ne 1) {
            $issues += [pscustomobject]@{file=$name;line=0;kind='toc_mapping';message='Section heading differs from TOC or is duplicated.'}
        }
        $r=Convert-FormatSection $t
        if ($singlePolicy -eq 'body' -and (Convert-SageSingleSubheading -Content $body) -cne $body) {
            $layoutAdjustments += [pscustomobject]@{file=$name;section=$expected[$i];rule='single_subheading_as_body';message='Single third-level heading (and descendants) will be unnumbered body cues in the build; source is preserved.'}
        }
        foreach($issue in $r.issues) { $issue | Add-Member -NotePropertyName file -NotePropertyValue $name; $issues += $issue }
        if ($r.changes.Count) { $edits += [pscustomobject]@{file=$name;before=$t;after=$r.text;changes=$r.changes} }
        if ($body -notmatch '(?m)^####\s') { $warnings += "$name has no subheadings; continuous prose is allowed and not automatically divided." }
        foreach($m in [regex]::Matches($body,'!\[[^\]]*\]\(([^)]+)\)')) {
            $link=$m.Groups[1].Value
            if ($link -match '^https?://') { continue }
            $image=[IO.Path]::GetFullPath((Join-Path (Split-Path $path) $link))
            if (!$image.StartsWith($Root.TrimEnd('\')+'\',[StringComparison]::OrdinalIgnoreCase) -or !(Test-Path -LiteralPath $image)) {
                $issues += [pscustomobject]@{file=$name;line=0;kind='image';message="Missing or external-workspace image: $link"}
            }
        }
    }
    $refpath=Join-Path $Root '02_chapters/references.md'; $labels=@{}
    if (Test-Path -LiteralPath $refpath) {
        foreach($m in [regex]::Matches((Get-FormatText $refpath),'(?m)^\[((?:前|\d+)-\d+)\]')) {
            $label=$m.Groups[1].Value
            if ($labels.ContainsKey($label)) { $issues += [pscustomobject]@{file='references.md';line=0;kind='duplicate_reference';message=$label} }
            $labels[$label]=$true
        }
    }
    foreach($f in $numeric) {
        foreach($m in [regex]::Matches((Get-FormatText $f.FullName),'\[((?:前|\d+)-\d+)\]')) {
            if (!$labels.ContainsKey($m.Groups[1].Value)) { $issues += [pscustomobject]@{file=$f.Name;line=0;kind='missing_reference';message=$m.Value} }
        }
    }
    return [pscustomobject]@{issues=@($issues);warnings=@($warnings);edits=@($edits);sections=$expected.Count;layout_adjustments=@($layoutAdjustments)}
}
