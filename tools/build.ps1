#Requires -Version 5.1
<#
.SYNOPSIS
    Builds dist\MusicReplacer.zip for Vortex, and optionally deploys straight into the game.
.PARAMETER Deploy
    Copy the built files into the installed mod folder under -GameDir instead of reinstalling through Vortex. Never touches audio\.
.PARAMETER GameDir
    Darktide install directory. Defaults to the usual Steam location.
.PARAMETER OutDir
    Build output directory. Defaults to dist\ at the repo root.
#>
[CmdletBinding()]
param(
    [switch] $Deploy,
    [string] $GameDir = 'C:\Program Files (x86)\Steam\steamapps\common\Warhammer 40,000 DARKTIDE',
    [string] $OutDir
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ModName = 'MusicReplacer'
$SourceItems = @("$ModName.mod", 'info.json', 'scripts')
$AudioContexts = @('hub', 'mission_explore', 'mission_combat', 'mission_boss', 'mission_event', 'mission_last_stand', 'mission_victory', 'mission_defeat') # Keep in sync with CONTEXTS in library.lua.

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot 'dist'
}

$StageRoot = Join-Path $OutDir 'stage'
$StageMod  = Join-Path $StageRoot $ModName
$ZipPath   = Join-Path $OutDir "$ModName.zip"

$missing = @()
foreach ($item in $SourceItems) {
    if (-not (Test-Path -LiteralPath (Join-Path $RepoRoot $item))) {
        $missing += $item
    }
}
if ($missing.Count -gt 0) {
    throw "Missing from the repository root: $($missing -join ', '). Run this script from a full checkout."
}

if (Test-Path -LiteralPath $StageRoot) {
    Remove-Item -LiteralPath $StageRoot -Recurse -Force
}
New-Item -ItemType Directory -Path $StageMod -Force | Out-Null

foreach ($item in $SourceItems) {
    Copy-Item -LiteralPath (Join-Path $RepoRoot $item) -Destination $StageMod -Recurse -Force
}

# The commit and build time, with -dirty when the packaged files differ from that commit.
function Get-BuildStamp {
    $commit = 'unknown commit'
    if (Get-Command git -ErrorAction SilentlyContinue) {
        try {
            $hash = & git -C $RepoRoot rev-parse --short HEAD 2>$null
            if ($LASTEXITCODE -eq 0 -and $hash) {
                $commit = $hash
                $changes = & git -C $RepoRoot status --porcelain -- $SourceItems 2>$null
                if ($changes) {
                    $commit += '-dirty'
                }
            }
        }
        catch {
            $commit = 'unknown commit'
        }
    }
    return '{0}, built {1}' -f $commit, (Get-Date -Format 'yyyy-MM-dd HH:mm')
}

# DMF keeps unknown info.json keys, so the mod can read the stamp with mod:get_metadata("build").
# Only the staged copy is stamped. The repository's info.json stays unchanged.
$BuildStamp = Get-BuildStamp
$StagedInfo = Join-Path $StageMod 'info.json'
$infoText = [System.IO.File]::ReadAllText($StagedInfo)
$infoText = ([regex]'\{').Replace($infoText, "{`n  `"build`": `"$BuildStamp`",", 1)
[System.IO.File]::WriteAllText($StagedInfo, $infoText, (New-Object System.Text.UTF8Encoding $false)) # UTF-8 without a BOM, like the source file.

# Empty folders so a fresh install is ready to receive files immediately, without waiting for the mod's own runtime mkdir (library.lua) to run once first.
# Not tracked in git -- synthesized here instead, since git can't track an empty directory anyway.
foreach ($context in $AudioContexts) {
    New-Item -ItemType Directory -Path (Join-Path $StageMod "audio\$context") -Force | Out-Null
}

# Wrapper dir matters: MusicReplacer.mod's declared paths and io_dofile calls are resolved as mods\<path>, so the archive needs MusicReplacer\ as the first segment, not the files loose at the root.
Compress-Archive -Path $StageMod -DestinationPath $ZipPath -Force

$zipInfo = Get-Item -LiteralPath $ZipPath
Write-Host ""
Write-Host ("Built {0} ({1:N1} KB)" -f $zipInfo.FullName, ($zipInfo.Length / 1KB))
Write-Host ("Build stamp: {0}" -f $BuildStamp)
Write-Host ""

Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    foreach ($entry in $archive.Entries) {
        Write-Host ("  {0,8}  {1}" -f $entry.Length, $entry.FullName)
    }
}
finally {
    $archive.Dispose()
}
Write-Host ""

if (-not $Deploy) {
    Write-Host "Install in Vortex from the ZIP above, or re-run with -Deploy to copy into the game directly."
    exit 0
}

$target = Join-Path (Join-Path $GameDir 'mods') $ModName

if (-not (Test-Path -LiteralPath $target -PathType Container)) {
    throw ("Deploy target does not exist: $target`n Install the mod through Vortex at least once first. Deploying into a folder Vortex doesn't know about would leave an install it can't manage or remove.")
}

# Copy file-by-file, not the whole directory, so audio\ and Vortex's own markers are left alone.
$copied = 0
try {
    foreach ($file in Get-ChildItem -LiteralPath $StageMod -Recurse -File) {
        $relative = $file.FullName.Substring($StageMod.Length).TrimStart('\')
        $destination = Join-Path $target $relative
        $destinationDir = Split-Path -Parent $destination

        if (-not (Test-Path -LiteralPath $destinationDir)) {
            New-Item -ItemType Directory -Path $destinationDir -Force | Out-Null
        }

        Copy-Item -LiteralPath $file.FullName -Destination $destination -Force
        Write-Host "  -> $relative"
        $copied++
    }
}
catch [System.UnauthorizedAccessException] {
    throw "Access denied writing to $target`nRe-run from an elevated PowerShell, or close anything holding those files."
}

Write-Host ""
Write-Host "Deployed $copied file(s) to $target"

# Same as the ZIP: create any that are missing, never touch existing ones.
foreach ($context in $AudioContexts) {
    $contextDir = Join-Path $target "audio\$context"
    if (-not (Test-Path -LiteralPath $contextDir)) {
        New-Item -ItemType Directory -Path $contextDir -Force | Out-Null
    }
}

Write-Host ""
Write-Host "audio\ (files never touched by this script):"
foreach ($context in Get-ChildItem -LiteralPath (Join-Path $target 'audio') -Directory) {
    $count = @(Get-ChildItem -LiteralPath $context.FullName -File).Count # @() -- a single file isn't an array.
    Write-Host ("  {0,-18} {1} file(s)" -f $context.Name, $count)
}

exit 0
