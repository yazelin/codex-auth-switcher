param(
    [switch]$UpdateProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoDir = Split-Path -Parent $PSCommandPath
$sourceLine = ". `"$repoDir\shell\powershell.ps1`""

if ($UpdateProfile) {
    $profileDir = Split-Path -Parent $PROFILE
    New-Item -ItemType Directory -Force -Path $profileDir | Out-Null
    if ((Test-Path -LiteralPath $PROFILE) -and ((Get-Content -LiteralPath $PROFILE -Raw) -like "*$sourceLine*")) {
        Write-Host "PowerShell profile already contains source line:"
        Write-Host "  $sourceLine"
    } else {
        Add-Content -LiteralPath $PROFILE -Value ""
        Add-Content -LiteralPath $PROFILE -Value "# Codex Auth Switcher"
        Add-Content -LiteralPath $PROFILE -Value $sourceLine
        Write-Host "Updated PowerShell profile:"
        Write-Host "  $PROFILE"
    }
}

Write-Host "Add this to your PowerShell profile:"
Write-Host ""
Write-Host "  $sourceLine"
Write-Host ""
Write-Host "Or run this installer with:"
Write-Host ""
Write-Host "  .\install.ps1 -UpdateProfile"
Write-Host ""
Write-Host "First-time setup:"
Write-Host ""
Write-Host "  cx import main"
Write-Host "  cx list"
