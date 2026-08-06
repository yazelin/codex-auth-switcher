param(
    [switch]$UpdateProfile
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repoDir = Split-Path -Parent $PSCommandPath
$sourceLine = ". `"$repoDir\shell\powershell.ps1`""

# 一行安裝把 repo clone 到 ~\codex-auth-switcher;手動安裝則是從你自己 clone
# 的位置載入。兩條路都跑過而且不是同一個目錄的話,機器上會有兩份 repo,而
# profile 只會載入最後裝的那份 —— 在另一份改 code 完全不會生效,而且那份的
# 改動沒人會發現(Linux 上實際發生過:一批改動在一行安裝的目錄裡躺了兩個月,
# 因為那邊的安裝路徑是 ~/.local/share/,跟開發用的 clone 不同位置)。
$onelinerDir = Join-Path $HOME "codex-auth-switcher"
if ((Test-Path (Join-Path $onelinerDir ".git")) -and ($onelinerDir -ne $repoDir)) {
    Write-Warning "Another copy is already installed at $onelinerDir"
    Write-Warning "This install points your profile at THIS repo instead: $repoDir"
    Write-Warning "Keep one copy only. Check the other for uncommitted work, then remove it:"
    Write-Warning "  git -C `"$onelinerDir`" status --short"
    Write-Warning "  Remove-Item -Recurse -Force `"$onelinerDir`""
}

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
