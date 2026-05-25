# Dot-source this file from your PowerShell profile after cloning the repo.
#
# Example:
#   . "$HOME\codex-auth-switcher\shell\powershell.ps1"

$script:CodexAuthSwitcherRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)

function cx {
    & (Join-Path $script:CodexAuthSwitcherRoot "bin/cx.ps1") @args
}

function codex {
    & (Join-Path $script:CodexAuthSwitcherRoot "bin/cx.ps1") run -- @args
}
