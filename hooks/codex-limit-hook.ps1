Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $PSCommandPath
$repoDir = Split-Path -Parent $scriptDir
$cx = Join-Path $repoDir "bin/cx.ps1"

try {
    $profile = $env:CODEX_AUTH_PROFILE
    if ($profile) {
        & $cx scan-limit $profile
    } else {
        & $cx scan-limit
    }
} catch {
    # Stop hooks are best-effort; Codex should not report a failed session stop
    # just because limit metadata could not be scanned.
}

exit 0
