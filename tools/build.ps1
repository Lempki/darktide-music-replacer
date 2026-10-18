#Requires -Version 5.1
<#
.SYNOPSIS
    Builds dist\MusicReplacer.zip for Vortex, and optionally deploys straight into the game.
.PARAMETER Deploy
    Copy the built files into the installed mod folder under -GameDir instead of reinstalling through Vortex. Never touches files in audio\.
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
$AudioContexts = @('hub', 'loading', 'mission_preparation', 'mission_loading', 'mission_explore', 'mission_combat', 'mission_horde', 'mission_boss', 'mission_event', 'mission_last_stand', 'mission_victory', 'mission_defeat', 'mortis_trials_wave', 'mortis_trials_break') # Keep in sync with CONTEXTS in library.lua.

$RepoRoot = Split-Path -Parent $PSScriptRoot
if (-not $OutDir) {
    $OutDir = Join-Path $RepoRoot 'dist'
}
# The archive's entry names are cut from full staging paths, so a relative -OutDir must become a full path first.
$OutDir = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($OutDir)

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

Copy-Item -LiteralPath (Join-Path $RepoRoot "$ModName.mod") -Destination $StageMod -Force
Copy-Item -LiteralPath (Join-Path $RepoRoot 'info.json') -Destination $StageMod -Force

# The Lua files git tracks, or would track, so a backup or scratch file left in scripts\ never ships.
# Untracked ones still ship, so a new module can be tested before it is committed, and each is named here.
$hasGit = [bool](Get-Command git -ErrorAction SilentlyContinue)
if ($hasGit) {
    $scriptFiles = @(& git -C $RepoRoot ls-files --cached --others --exclude-standard -- 'scripts/*.lua' | Where-Object { $_ })
    $untracked = @(& git -C $RepoRoot ls-files --others --exclude-standard -- 'scripts/*.lua' | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0 -or $scriptFiles.Count -eq 0) {
        throw 'git could not list the files under scripts\. Run this script from a full checkout.'
    }
    foreach ($file in $untracked) {
        Write-Warning "Packaging $file, which git does not track yet."
    }
}
else {
    Write-Warning 'git was not found, so every .lua file under scripts\ is packaged, tracked or not.'
    $scriptFiles = @(Get-ChildItem -LiteralPath (Join-Path $RepoRoot 'scripts') -Recurse -File -Filter '*.lua' |
        ForEach-Object { $_.FullName.Substring($RepoRoot.Length).TrimStart('\') })
}
foreach ($file in $scriptFiles) {
    $destination = Join-Path $StageMod $file
    New-Item -ItemType Directory -Path (Split-Path -Parent $destination) -Force | Out-Null
    Copy-Item -LiteralPath (Join-Path $RepoRoot $file) -Destination $destination -Force
}

# The commit and build time, with -dirty when the packaged files differ from that commit.
function Get-BuildStamp {
    # Git can write warnings to stderr, such as about line endings, which must not turn into a stop under the script's preference.
    $ErrorActionPreference = 'Continue'
    $commit = 'unknown commit'
    if ($hasGit) {
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
if ((ConvertFrom-Json $infoText).PSObject.Properties.Name -contains 'build') {
    throw 'info.json already has a "build" key, which the build writes itself. Remove it from the source file.'
}
$infoText = ([regex]'\{').Replace($infoText, "{`n  `"build`": `"$BuildStamp`",", 1)
if ((ConvertFrom-Json $infoText).build -ne $BuildStamp) {
    throw 'The stamped info.json does not read back as JSON with its build stamp.'
}
[System.IO.File]::WriteAllText($StagedInfo, $infoText, (New-Object System.Text.UTF8Encoding $false)) # UTF-8 without a BOM, like the source file.

# Empty folders so a fresh install is ready to receive files immediately, without waiting for the mod to create them on its first launch.
# Synthesized here, since git cannot track an empty directory.
foreach ($context in $AudioContexts) {
    New-Item -ItemType Directory -Path (Join-Path $StageMod "audio\$context") -Force | Out-Null
}

# Wrapper dir matters: MusicReplacer.mod's declared paths and io_dofile calls are resolved as mods\<path>, so the archive needs MusicReplacer\ as the first segment, not the files loose at the root.
# Compress-Archive in Windows PowerShell 5.1 writes "\" into entry names, which Linux and Steam Deck tools extract as literal file names.
# So the archive is written entry by entry, with the "/" separators the zip format requires, and the empty audio folders as folder entries.
Add-Type -AssemblyName System.IO.Compression
Add-Type -AssemblyName System.IO.Compression.FileSystem

if (Test-Path -LiteralPath $ZipPath) {
    Remove-Item -LiteralPath $ZipPath -Force
}

$zip = [System.IO.Compression.ZipFile]::Open($ZipPath, [System.IO.Compression.ZipArchiveMode]::Create)
try {
    [void]$zip.CreateEntry("$ModName/")
    foreach ($item in Get-ChildItem -LiteralPath $StageMod -Recurse | Sort-Object FullName) {
        $entryName = "$ModName/" + $item.FullName.Substring($StageMod.Length).TrimStart('\').Replace('\', '/')
        if ($item.PSIsContainer) {
            [void]$zip.CreateEntry("$entryName/")
        }
        else {
            [void][System.IO.Compression.ZipFileExtensions]::CreateEntryFromFile($zip, $item.FullName, $entryName, [System.IO.Compression.CompressionLevel]::Optimal)
        }
    }
}
finally {
    $zip.Dispose()
}

$zipInfo = Get-Item -LiteralPath $ZipPath
Write-Host ""
Write-Host ("Built {0} ({1:N1} KB)" -f $zipInfo.FullName, ($zipInfo.Length / 1KB))
Write-Host ("Build stamp: {0}" -f $BuildStamp)
Write-Host ""

# Reads the archive back, so a layout that would install wrongly fails the build instead of reaching players.
# Every entry sits in MusicReplacer/, as the mod file, info.json, a script, or an audio folder, and the files the mod cannot load without are there.
$allowedEntry = "^$ModName/($ModName\.mod|info\.json|scripts/.*|audio/.*)?$"
$requiredEntries = @("$ModName/$ModName.mod", "$ModName/info.json", "$ModName/scripts/mods/$ModName/$ModName.lua")
$badEntries = @()
$entryNames = @()
$archive = [System.IO.Compression.ZipFile]::OpenRead($ZipPath)
try {
    foreach ($entry in $archive.Entries) {
        Write-Host ("  {0,8}  {1}" -f $entry.Length, $entry.FullName)
        $entryNames += $entry.FullName
        if ($entry.FullName.Contains('\') -or $entry.FullName -notmatch $allowedEntry) {
            $badEntries += $entry.FullName
        }
    }
}
finally {
    $archive.Dispose()
}
Write-Host ""

if ($badEntries.Count -gt 0) {
    throw ("The archive has entries outside the mod's layout or with backslashes in their names: $($badEntries -join ', ')")
}
$missingEntries = @($requiredEntries | Where-Object { $entryNames -notcontains $_ })
if ($missingEntries.Count -gt 0) {
    throw ("The archive is missing: $($missingEntries -join ', ')")
}

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
    $count = @(Get-ChildItem -LiteralPath $context.FullName -File).Count # @() so that a single file still counts as an array.
    Write-Host ("  {0,-20} {1} file(s)" -f $context.Name, $count)
}

exit 0
