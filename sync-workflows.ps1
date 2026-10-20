# Copy workflows, skill trees, and runtime helpers into explicitly selected Grok homes.
# Usage: .\sync-workflows.ps1 [-DryRun] [-Prune] [-PruneSkills] [-Destination <additional Grok homes>]
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Prune,
    [switch]$PruneSkills,
    [string[]]$Destination = @()
)

$ErrorActionPreference = "Stop"
$Repo = $PSScriptRoot
$Sources = @(Get-ChildItem -LiteralPath $Repo -Filter *.rhai -File)
if ($Sources.Count -eq 0) {
    throw "no *.rhai files in $Repo"
}

function Invoke-Step {
    param([scriptblock]$Action, [string]$Label)
    if ($DryRun) {
        Write-Host "dry-run: $Label"
        return
    }
    & $Action
}

function Sync-One {
    param([string]$Dest)

    Invoke-Step { New-Item -ItemType Directory -Force -Path $Dest | Out-Null } "mkdir $Dest"

    $added = 0
    $updated = 0
    $skipped = 0
    $pruned = 0

    foreach ($src in $Sources) {
        $target = Join-Path $Dest $src.Name
        if (Test-Path -LiteralPath $target) {
            $srcHash = (Get-FileHash -LiteralPath $src.FullName -Algorithm SHA256).Hash
            $dstHash = (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash
            if ($srcHash -eq $dstHash) {
                $skipped++
                continue
            }
            $updated++
            Write-Host "update  $target"
        } else {
            $added++
            Write-Host "add     $target"
        }
        Invoke-Step { Copy-Item -LiteralPath $src.FullName -Destination $target -Force } "copy $($src.Name) -> $target"
    }

    if ($Prune) {
        Get-ChildItem -LiteralPath $Dest -Filter *.rhai -File -ErrorAction SilentlyContinue | ForEach-Object {
            $repoCopy = Join-Path $Repo $_.Name
            if (-not (Test-Path -LiteralPath $repoCopy)) {
                $pruned++
                Write-Host "prune   $($_.FullName)"
                Invoke-Step { Remove-Item -LiteralPath $_.FullName -Force } "rm $($_.FullName)"
            }
        }
    }

    Write-Host "-> $Dest  added=$added updated=$updated unchanged=$skipped pruned=$pruned"
}

function Sync-Support {
    param([string]$GrokHome)
    $Support = Join-Path $Repo "workflow-support"
    Get-ChildItem -LiteralPath $Support -Recurse -File -Filter *.mjs | Where-Object { $_.Name -notlike '*.test.mjs' } | ForEach-Object {
        $relative = $_.FullName.Substring($Repo.Length).TrimStart([char[]]"\/")
        $target = Join-Path $GrokHome $relative
        $source = $_.FullName
        if ((Test-Path -LiteralPath $target) -and ((Get-FileHash -LiteralPath $source).Hash -eq (Get-FileHash -LiteralPath $target).Hash)) { return }
        Invoke-Step { New-Item -ItemType Directory -Force -Path (Split-Path -Parent $target) | Out-Null } "mkdir parent of $target"
        Invoke-Step { Copy-Item -LiteralPath $source -Destination $target -Force } "copy $source -> $target"
    }
}

$DefaultHome = if ($env:GROK_HOME) { $env:GROK_HOME } else { Join-Path $HOME ".grok" }
$Dests = @($DefaultHome) + $Destination
foreach ($dest in $Dests) {
    if ([string]::IsNullOrWhiteSpace($dest)) { throw "Destination must be a Grok home" }
}

function Test-SkillReparsePoint {
    param([string]$Path)
    $item = Get-Item -LiteralPath $Path -Force
    return [bool]($item.Attributes -band [IO.FileAttributes]::ReparsePoint)
}

function Get-SkillFiles {
    param([string]$Root, [switch]$SkipIgnored)
    $files = New-Object System.Collections.Generic.List[System.IO.FileInfo]
    $pending = New-Object System.Collections.Generic.Queue[string]
    $pending.Enqueue($Root)
    while ($pending.Count -gt 0) {
        $dir = $pending.Dequeue()
        foreach ($child in @(Get-ChildItem -LiteralPath $dir -Force)) {
            if (Test-SkillReparsePoint $child.FullName) {
                throw "refusing symlink: $($child.FullName)"
            }
            if ($child.PSIsContainer) {
                if ($SkipIgnored -and ($child.Name -eq "node_modules" -or $child.Name -eq ".git")) { continue }
                $pending.Enqueue($child.FullName)
            } else {
                $files.Add($child)
            }
        }
    }
    return $files
}

function Assert-SkillDestinationPath {
    param([string]$Root, [string]$Path)
    $current = $Path
    while ($true) {
        $item = $null
        try {
            $item = Get-Item -LiteralPath $current -Force -ErrorAction Stop
        } catch {
            $missing = $_.Exception -is [System.Management.Automation.ItemNotFoundException] -or
                $_.FullyQualifiedErrorId -like 'PathNotFound,*' -or
                $_.FullyQualifiedErrorId -like 'ItemNotFound,*'
            if (-not $missing) { throw }
        }
        if ($null -ne $item -and ($item.Attributes -band [IO.FileAttributes]::ReparsePoint)) {
            throw "refusing symlink: $current"
        }
        if ([string]::Equals($current, $Root, [StringComparison]::OrdinalIgnoreCase)) {
            break
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) {
            break
        }
        $current = $parent
    }
}

function Sync-Skills {
    param([string]$GrokHome)
    $srcRoot = Join-Path $Repo "skills"
    $destRoot = Join-Path $GrokHome "skills"
    $added = 0
    $updated = 0
    $skipped = 0
    $pruned = 0

    if (-not (Test-Path -LiteralPath $srcRoot -PathType Container)) {
        Write-Host "-> $destRoot  added=0 updated=0 unchanged=0 pruned=0"
        return
    }
    if (Test-SkillReparsePoint $srcRoot) {
        throw "refusing symlink: $srcRoot"
    }
    [void](Get-SkillFiles $srcRoot)

    $skillDirs = @(Get-ChildItem -LiteralPath $srcRoot -Directory -Force | Where-Object {
        $_.Name -ne "node_modules" -and $_.Name -ne ".git"
    })

    foreach ($skill in $skillDirs) {
        $manifest = Join-Path $skill.FullName "SKILL.md"
        if (-not (Test-Path -LiteralPath $manifest -PathType Leaf)) {
            Write-Host "skip    $($skill.FullName) (no SKILL.md)"
            continue
        }
        $prefix = $skill.FullName.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
        foreach ($src in @(Get-SkillFiles $skill.FullName -SkipIgnored)) {
            if (-not $src.FullName.StartsWith($prefix)) { throw "skill path escaped $($skill.FullName)" }
            $rel = $src.FullName.Substring($prefix.Length)
            $target = [IO.Path]::Combine((Join-Path $destRoot $skill.Name), $rel)
            Assert-SkillDestinationPath -Root $destRoot -Path $target
            if ((Test-Path -LiteralPath $target) -and (Test-SkillReparsePoint $target)) {
                throw "refusing symlink: $target"
            }
            if ((Test-Path -LiteralPath $target -PathType Leaf) -and
                ((Get-FileHash -LiteralPath $src.FullName -Algorithm SHA256).Hash -eq (Get-FileHash -LiteralPath $target -Algorithm SHA256).Hash)) {
                $skipped++
                continue
            }
            if (Test-Path -LiteralPath $target) {
                $updated++
                Write-Host "update  $target"
            } else {
                $added++
                Write-Host "add     $target"
            }
            $parent = Split-Path -Parent $target
            $sourcePath = $src.FullName
            Invoke-Step { New-Item -ItemType Directory -Force -Path $parent | Out-Null }.GetNewClosure() "mkdir $parent"
            Invoke-Step { Copy-Item -LiteralPath $sourcePath -Destination $target -Force }.GetNewClosure() "copy $sourcePath -> $target"
        }
    }

    if ($PruneSkills -and (Test-Path -LiteralPath $destRoot -PathType Container) -and -not (Test-SkillReparsePoint $destRoot)) {
        foreach ($destSkill in @(Get-ChildItem -LiteralPath $destRoot -Force | Where-Object { $_.PSIsContainer -or (Test-SkillReparsePoint $_.FullName) })) {
            if (Test-SkillReparsePoint $destSkill.FullName) {
                throw "refusing symlink: $($destSkill.FullName)"
            }
            $srcManifest = Join-Path (Join-Path $srcRoot $destSkill.Name) "SKILL.md"
            if (-not (Test-Path -LiteralPath $srcManifest -PathType Leaf)) {
                $pruned++
                Write-Host "prune   $($destSkill.FullName)"
                $removePath = $destSkill.FullName
                Invoke-Step { Remove-Item -LiteralPath $removePath -Recurse -Force }.GetNewClosure() "rm $removePath"
                continue
            }
            $keptRoot = $destSkill.FullName
            $srcSkill = Join-Path $srcRoot $destSkill.Name
            $keptPrefix = $keptRoot.TrimEnd('\', '/') + [IO.Path]::DirectorySeparatorChar
            foreach ($extra in @(Get-SkillFiles $keptRoot -SkipIgnored)) {
                if (-not $extra.FullName.StartsWith($keptPrefix)) { throw "skill path escaped $keptRoot" }
                $rel = $extra.FullName.Substring($keptPrefix.Length)
                $srcFile = [IO.Path]::Combine($srcSkill, $rel)
                if (-not (Test-Path -LiteralPath $srcFile -PathType Leaf)) {
                    $pruned++
                    Write-Host "prune   $($extra.FullName)"
                    $extraPath = $extra.FullName
                    Invoke-Step { Remove-Item -LiteralPath $extraPath -Force }.GetNewClosure() "rm $extraPath"
                }
            }
        }
    }

    Write-Host "-> $destRoot  added=$added updated=$updated unchanged=$skipped pruned=$pruned"
}

Write-Host "source  $Repo ($($Sources.Count) workflows)"
$seen = @{}
foreach ($dest in $Dests) {
    if ($seen.ContainsKey($dest)) { continue }
    $seen[$dest] = $true
    Sync-One -Dest (Join-Path $dest "workflows")
    Sync-Support -GrokHome $dest
    Sync-Skills -GrokHome $dest
}
