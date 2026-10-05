# Copy *.rhai from this repo into Grok's real config directories.
# Usage: .\sync-workflows.ps1 [-DryRun] [-Prune]
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Prune
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

$Dests = New-Object System.Collections.Generic.List[string]
$Dests.Add((Join-Path $env:USERPROFILE ".grok\workflows")) | Out-Null

try {
    $wslHome = (wsl -d Ubuntu-24.04 -- bash -lc "printf %s `$HOME" 2>$null)
    if ($LASTEXITCODE -eq 0 -and $wslHome) {
        $unc = "\\wsl$\Ubuntu-24.04" + ($wslHome -replace "/", "\") + "\.grok\workflows"
        $Dests.Add($unc) | Out-Null
    }
} catch {
    # WSL not available from this shell; Windows dest is still synced.
}

Write-Host "source  $Repo ($($Sources.Count) workflows)"
$seen = @{}
foreach ($dest in $Dests) {
    if ($seen.ContainsKey($dest)) { continue }
    $seen[$dest] = $true
    Sync-One -Dest $dest
}
