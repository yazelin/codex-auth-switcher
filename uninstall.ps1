# Undo what install.ps1 / install-oneliner.ps1 did:
#   - remove the "# Codex Auth Switcher" + dot-source line from your PowerShell profile(s)
# By default your saved accounts in %USERPROFILE%\.codex_auth_profiles are KEPT.
# Pass -Purge to also delete them.
param([switch]$Purge)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSCommandPath
$line = ". `"$root\shell\powershell.ps1`""
$profilesDir = if ($env:CX_PROFILES_DIR) { $env:CX_PROFILES_DIR } else { Join-Path $HOME '.codex_auth_profiles' }

$targets = @(
  $PROFILE
  Join-Path (Split-Path -Parent $PROFILE) 'Microsoft.PowerShell_profile.ps1'
) | Select-Object -Unique

foreach ($p in $targets) {
  if (-not (Test-Path $p)) { continue }
  $content = Get-Content -LiteralPath $p
  $kept = $content | Where-Object {
    ($_.Trim() -ne '# Codex Auth Switcher') -and
    ($_.Trim() -ne $line) -and
    ($_ -notmatch 'codex-auth-switcher[\\/]shell[\\/]powershell\.ps1')
  }
  if ($kept.Count -ne $content.Count) {
    Copy-Item -LiteralPath $p -Destination "$p.cx-bak" -Force
    Set-Content -LiteralPath $p -Value $kept
    "cleaned $p (backup: $p.cx-bak)"
  }
}

if ($Purge) {
  if (Test-Path -LiteralPath $profilesDir) {
    Remove-Item -LiteralPath $profilesDir -Recurse -Force
    "purged saved accounts: $profilesDir"
  }
} else {
  if (Test-Path -LiteralPath $profilesDir) {
    "kept saved accounts: $profilesDir (re-run with -Purge to remove)"
  }
}

""
"Shell wiring removed. The 'cx' command is gone from new PowerShell sessions."
"This repo was left in place. To delete it too, run:"
"  Remove-Item -Recurse -Force `"$root`""
