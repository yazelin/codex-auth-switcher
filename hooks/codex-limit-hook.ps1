Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoDir = Split-Path -Parent $scriptDir
$cx = Join-Path $repoDir "bin/cx.ps1"

$profile = $env:CODEX_AUTH_PROFILE
if ($profile) {
    & $cx scan-limit $profile
} else {
    & $cx scan-limit
}
