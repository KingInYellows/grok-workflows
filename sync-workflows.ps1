# Copy workflows and runtime helpers into explicitly selected Grok homes.
# Usage: .\sync-workflows.ps1 [-DryRun] [-Prune] [-Destination <additional Grok homes>]
[CmdletBinding()]
param(
    [switch]$DryRun,
    [switch]$Prune,
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

Write-Host "source  $Repo ($($Sources.Count) workflows)"
$seen = @{}
foreach ($dest in $Dests) {
    if ($seen.ContainsKey($dest)) { continue }
    $seen[$dest] = $true
    Sync-One -Dest (Join-Path $dest "workflows")
    Sync-Support -GrokHome $dest
}
