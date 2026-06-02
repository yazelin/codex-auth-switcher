# Codex Auth Switcher — Windows one-line installer
# Usage (paste into any PowerShell terminal):
#
#   irm https://raw.githubusercontent.com/yazelin/codex-auth-switcher/main/install-oneliner.ps1 | iex

$ErrorActionPreference = "Stop"

$RepoUrl    = "https://github.com/yazelin/codex-auth-switcher.git"
$InstallDir = Join-Path $HOME "codex-auth-switcher"

Write-Host ""
Write-Host "  Codex Auth Switcher" -ForegroundColor Cyan -NoNewline
Write-Host "  --  Windows Installer" -ForegroundColor DarkGray
Write-Host "  ----------------------------------------------" -ForegroundColor DarkGray
Write-Host ""

# ── 1. Clone or update ──────────────────────────────────────────────────────
if (Test-Path (Join-Path $InstallDir ".git")) {
    Write-Host "  Updating existing install at $InstallDir ..." -ForegroundColor Yellow
    & git -C $InstallDir pull --ff-only origin main
} else {
    Write-Host "  Cloning to $InstallDir ..." -ForegroundColor Yellow
    & git clone --depth 1 $RepoUrl $InstallDir
}
Write-Host ""

# ── 2. Add source line to PowerShell profile ────────────────────────────────
$shellScript = Join-Path $InstallDir "shell\powershell.ps1"
$sourceLine  = ". `"$shellScript`""
$profileDir  = Split-Path -Parent $PROFILE
New-Item -ItemType Directory -Force -Path $profileDir | Out-Null

$alreadySet = (Test-Path $PROFILE) -and ((Get-Content $PROFILE -Raw) -like "*$shellScript*")
if ($alreadySet) {
    Write-Host "  Profile already configured -- skipping." -ForegroundColor Green
} else {
    Add-Content -Path $PROFILE -Value ""
    Add-Content -Path $PROFILE -Value "# Codex Auth Switcher"
    Add-Content -Path $PROFILE -Value $sourceLine
    Write-Host "  Added to profile: $PROFILE" -ForegroundColor Green
}

# ── 3. Load cx and codex into this session immediately ──────────────────────
. $shellScript
Write-Host "  cx and codex are ready in this session." -ForegroundColor Green

# ── 4. Post-install guide ───────────────────────────────────────────────────
$div = "  ----------------------------------------------"
Write-Host ""
Write-Host $div -ForegroundColor DarkGray
Write-Host "  Install complete!  Next steps:" -ForegroundColor Cyan
Write-Host $div -ForegroundColor DarkGray
Write-Host ""
Write-Host "  1. Import your current Codex login as a named profile:" -ForegroundColor White
Write-Host "       cx import main" -ForegroundColor Yellow
Write-Host ""
Write-Host "  2. View all profiles and their status:" -ForegroundColor White
Write-Host "       cx list" -ForegroundColor Yellow
Write-Host ""
Write-Host "  3. Log in with another account under a new profile name:" -ForegroundColor White
Write-Host "       cx login work" -ForegroundColor Yellow
Write-Host ""
Write-Host "  4. Interactive profile switcher (kills Codex first automatically):" -ForegroundColor White
Write-Host "       cx switch" -ForegroundColor Yellow
Write-Host ""
Write-Host "  5. Launch Codex under the active profile:" -ForegroundColor White
Write-Host "       codex" -ForegroundColor Yellow
Write-Host ""
Write-Host "  Show all commands:    cx help" -ForegroundColor DarkGray
Write-Host "  Full guide:           https://yazelin.github.io/codex-auth-switcher/" -ForegroundColor DarkGray
Write-Host $div -ForegroundColor DarkGray
Write-Host ""
