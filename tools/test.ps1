#Requires -Version 5.1
<#
.SYNOPSIS
    Runs the Lua specs under tests\spec with LuaJIT, and exits non-zero when any fails.
.PARAMETER Spec
    Spec files to run instead of all of them, relative to the repo root.
#>
[CmdletBinding()]
param(
    [string[]] $Spec = @()
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not (Get-Command luajit -ErrorAction SilentlyContinue)) {
    throw 'luajit was not found on PATH. Install LuaJIT 2.1 and open a new terminal.'
}

$RepoRoot = Split-Path -Parent $PSScriptRoot

Push-Location -LiteralPath $RepoRoot
try {
    & luajit tests/run.lua @Spec
    $exitCode = $LASTEXITCODE
}
finally {
    Pop-Location
}

exit $exitCode
