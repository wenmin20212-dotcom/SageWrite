function Convert-SageFrontmatterHeadings {
    param([string]$Content, [int]$MaxDepth = 3)
    if ($MaxDepth -ne 2) { return $Content }
    $lines=$Content.Replace("`r`n","`n") -split "`n"
    $fence=''
    for($i=0;$i -lt $lines.Count;$i++) {
        if ($lines[$i] -match '^\s*(`{3,}|~{3,})') {
            $mark=$Matches[1]
            if (!$fence) { $fence=$mark }
            elseif ($mark[0] -eq $fence[0] -and $mark.Length -ge $fence.Length) { $fence='' }
            continue
        }
        if (!$fence -and $lines[$i] -match '^#{4,6}\s+(.+?)\s*$') {
            $title=$Matches[1]
            $title=[regex]::Replace($title,'^(?:\d+(?:\.\d+)+[、.．:：]?\s*|[一二三四五六七八九十\d]+[、.．]\s*)','')
            $lines[$i]='**'+$title+'**'
        }
    }
    return $lines -join "`n"
}

function Convert-SageSingleSubheading {
    param([string]$Content)
    $fence=''; $count=0
    foreach($line in $Content.Replace("`r`n","`n") -split "`n") {
        if ($line -match '^\s*(`{3,}|~{3,})') {
            $mark=$Matches[1]
            if (!$fence) { $fence=$mark }
            elseif ($mark[0] -eq $fence[0] -and $mark.Length -ge $fence.Length) { $fence='' }
            continue
        }
        if (!$fence -and $line -match '^####\s+') { $count++ }
    }
    if ($count -eq 1) {
        # Descendants become body cues too, avoiding an orphaned heading hierarchy.
        return Convert-SageFrontmatterHeadings -Content $Content -MaxDepth 2
    }
    return $Content
}

function Convert-SageReferenceGroupHeadings {
    param([string]$Content)
    $lines=$Content.Replace("`r`n","`n") -split "`n"
    $fence=''
    for($i=0;$i -lt $lines.Count;$i++) {
        if ($lines[$i] -match '^\s*(`{3,}|~{3,})') {
            $mark=$Matches[1]
            if (!$fence) { $fence=$mark }
            elseif ($mark[0] -eq $fence[0] -and $mark.Length -ge $fence.Length) { $fence='' }
            continue
        }
        if (!$fence -and $lines[$i] -match '^#{2,6}\s+(.+?)\s*$') {
            $lines[$i]='**'+$Matches[1]+'**'
        }
    }
    return $lines -join "`n"
}
