param(
    [string]$InputFile,
    [string]$InputDir
)

# mem
# mem
# mem
$CommentReplacement = "mem"

if (-not $InputFile -and -not $InputDir) {
    Write-Host "Please specify -InputFile or -InputDir"
    exit
}

function Has-CjkOrGarble {
    param([string]$Text)

    if ([string]::IsNullOrEmpty($Text)) {
        return $false
    }

# mem
    if ($Text -match '[\u4e00-\u9fff]') {
        return $true
    }

# mem
    if ($Text -match '[^\u0000-\u007F]') {
        return $true
    }

    return $false
}

function Get-ReplacedCommentLine {
    param(
        [string]$CodePart,
        [string]$Replacement
    )

    if ($Replacement -eq "") {
        if ($CodePart.Trim() -eq "") {
            return $null
        }
        return $CodePart.TrimEnd()
    }

    if ($CodePart.Trim() -eq "") {
        return "# $Replacement"
    }

    return ($CodePart.TrimEnd() + " # " + $Replacement)
}

function Clean-Code {
    param([string]$FilePath)

    if (!(Test-Path $FilePath)) {
        Write-Host "File not found: $FilePath"
        return
    }

    $Code = Get-Content $FilePath -Raw -Encoding UTF8
    $Code = $Code -replace "`r`n", "`n"

# mem
    $Code = [regex]::Replace(
        $Code,
        '<#(.|\n)*?#>',
        {
            param($m)

            if (Has-CjkOrGarble $m.Value) {
                if ($CommentReplacement -eq "") {
                    return ''
                } else {
                    return "<# $CommentReplacement #>"
                }
            }

            return $m.Value
        },
        [System.Text.RegularExpressions.RegexOptions]::Singleline
    )

    $Lines = $Code -split "`n"
    $Processed = @()

    foreach ($line in $Lines) {
        $inSingle = $false
        $inDouble = $false
        $result = ""
        $comment = $null
        $hitComment = $false

        for ($i = 0; $i -lt $line.Length; $i++) {
            $c = $line[$i]

            if ($c -eq "'" -and -not $inDouble) {
                $inSingle = -not $inSingle
            }
            elseif ($c -eq '"' -and -not $inSingle) {
                $inDouble = -not $inDouble
            }

            if ($c -eq "#" -and -not $inSingle -and -not $inDouble) {
                $hitComment = $true
                $comment = $line.Substring($i + 1) # mem
                break
            }

            $result += $c
        }

        if ($hitComment) {
            if (Has-CjkOrGarble $comment) {
                $newLine = Get-ReplacedCommentLine -CodePart $result -Replacement $CommentReplacement
                if ($null -ne $newLine) {
                    $Processed += $newLine
                }
            }
            else {
                $Processed += $line
            }
        }
        else {
            $Processed += $line
        }
    }

    $NewCode = ($Processed -join "`n")
    $NewCode = [regex]::Replace($NewCode, "`n{3,}", "`n`n")

    Set-Content $FilePath $NewCode -Encoding UTF8

    Write-Host "Cleaned:" $FilePath
}

if ($InputFile) {
    Clean-Code $InputFile
}

if ($InputDir) {
    if (!(Test-Path $InputDir)) {
        Write-Host "Directory not found"
        exit
    }

    $Files = Get-ChildItem -Path $InputDir -Filter *.ps1 -File

    if ($Files.Count -eq 0) {
        Write-Host "No .ps1 files found"
        exit
    }

    foreach ($file in $Files) {
        Clean-Code $file.FullName
    }

    Write-Host ""
    Write-Host "Batch clean completed."
}
