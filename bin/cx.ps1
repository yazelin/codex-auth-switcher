Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProfilesDir = if ($env:CX_PROFILES_DIR) { $env:CX_PROFILES_DIR } else { Join-Path $HOME ".codex_auth_profiles" }
$CodexHome = if ($env:CX_CODEX_HOME) { $env:CX_CODEX_HOME } elseif ($env:CODEX_HOME) { $env:CODEX_HOME } else { Join-Path $HOME ".codex" }
$LimitThreshold = if ($env:CX_LIMIT_THRESHOLD) { [double]$env:CX_LIMIT_THRESHOLD } else { 100.0 }

$CurrentFile = Join-Path $ProfilesDir "current"
$LockDir = Join-Path $ProfilesDir ".lock"

function Write-Usage {
    @"
usage:
  cx import <name>          Save current ~/.codex/auth.json as a profile
  cx login <name> [args]    Login or refresh a profile
  cx use <name>             Switch active auth profile
  cx list                   List profiles, login state, and limit state
  cx current                Print active profile
  cx run -- [codex args]    Run codex with the active auth profile
  cx scan-limit [name]      Scan latest Codex session and update .limit
  cx limit <name> [epoch]   Manually mark a profile as limited
  cx ok <name>              Clear a profile's limit marker
  cx hook-command           Print the Stop hook command
  cx help                   Show this help

environment:
  CX_PROFILES_DIR           Default: ~/.codex_auth_profiles
  CX_CODEX_HOME             Default: `$CODEX_HOME or ~/.codex
  CX_CODEX_BIN              Optional path to the real codex executable
  CX_LIMIT_THRESHOLD        Default: 100
"@
}

function Die([string]$Message) {
    throw "cx: $Message"
}

function First-Arg([string[]]$List) {
    if ($List.Count -gt 0) { return $List[0] }
    ""
}

function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    $null
}

function Ensure-Dirs {
    New-Item -ItemType Directory -Force -Path $ProfilesDir, $CodexHome | Out-Null
}

function Get-ProfileDir([string]$Name) {
    if ([string]::IsNullOrWhiteSpace($Name)) { Die "profile name is required" }
    if ($Name -match '[\\/:\r\n]' -or $Name.StartsWith(".")) { Die "invalid profile name: $Name" }
    Join-Path $ProfilesDir $Name
}

function Get-SharedAuth {
    Join-Path $CodexHome "auth.json"
}

function Get-ProfileAuth([string]$Name) {
    Join-Path (Get-ProfileDir $Name) "auth.json"
}

function Get-CurrentProfile {
    if (Test-Path -LiteralPath $CurrentFile) {
        (Get-Content -LiteralPath $CurrentFile -TotalCount 1).Trim()
    }
}

function Require-CurrentProfile {
    $name = Get-CurrentProfile
    if ([string]::IsNullOrWhiteSpace($name)) {
        Die "no active profile; run: cx use <name> or cx import <name>"
    }
    $name
}

function Format-Epoch([string]$Epoch) {
    if ([string]::IsNullOrWhiteSpace($Epoch)) { return "" }
    try {
        $dto = [DateTimeOffset]::FromUnixTimeSeconds([int64]$Epoch).ToLocalTime()
        $dto.ToString("yyyy-MM-dd HH:mm")
    } catch {
        $Epoch
    }
}

function Get-NowEpoch {
    [DateTimeOffset]::Now.ToUnixTimeSeconds()
}

function Acquire-Lock {
    Ensure-Dirs
    try {
        New-Item -ItemType Directory -Path $LockDir -ErrorAction Stop | Out-Null
        Set-Content -LiteralPath (Join-Path $LockDir "pid") -Value $PID -NoNewline
    } catch {
        $pidText = ""
        $pidFile = Join-Path $LockDir "pid"
        if (Test-Path -LiteralPath $pidFile) {
            $pidText = Get-Content -LiteralPath $pidFile -Raw
        }
        Die "another cx-managed codex process is running$(if ($pidText) { " (pid $pidText)" })"
    }
}

function Release-Lock {
    $pidFile = Join-Path $LockDir "pid"
    if ((Test-Path -LiteralPath $pidFile) -and ((Get-Content -LiteralPath $pidFile -Raw) -eq [string]$PID)) {
        Remove-Item -LiteralPath $LockDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

function Find-CodexBin {
    if ($env:CX_CODEX_BIN) {
        if (-not (Test-Path -LiteralPath $env:CX_CODEX_BIN)) { Die "CX_CODEX_BIN does not exist: $env:CX_CODEX_BIN" }
        return $env:CX_CODEX_BIN
    }

    $cmd = Get-Command codex -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -in @("Application", "ExternalScript") } |
        Select-Object -First 1

    if (-not $cmd) { Die "codex executable not found; set CX_CODEX_BIN=/path/to/codex" }
    $cmd.Source
}

function Save-ActiveAuthIfKnown {
    $name = Get-CurrentProfile
    if ([string]::IsNullOrWhiteSpace($name)) { return }
    $shared = Get-SharedAuth
    if (-not (Test-Path -LiteralPath $shared)) { return }
    New-Item -ItemType Directory -Force -Path (Get-ProfileDir $name) | Out-Null
    Copy-Item -LiteralPath $shared -Destination (Get-ProfileAuth $name) -Force
}

function Stage-ProfileAuth([string]$Name) {
    $auth = Get-ProfileAuth $Name
    if (-not (Test-Path -LiteralPath $auth)) { Die "profile has no auth.json: $Name; run: cx login $Name" }
    Copy-Item -LiteralPath $auth -Destination (Get-SharedAuth) -Force
}

function Store-ProfileAuth([string]$Name) {
    $shared = Get-SharedAuth
    if (-not (Test-Path -LiteralPath $shared)) { return }
    New-Item -ItemType Directory -Force -Path (Get-ProfileDir $Name) | Out-Null
    Copy-Item -LiteralPath $shared -Destination (Get-ProfileAuth $Name) -Force
}

function Set-CurrentProfile([string]$Name) {
    New-Item -ItemType Directory -Force -Path (Get-ProfileDir $Name) | Out-Null
    Set-Content -LiteralPath $CurrentFile -Value $Name
}

function Get-AuthState([string]$Name) {
    if (Test-Path -LiteralPath (Get-ProfileAuth $Name)) { "ok" } else { "not-login" }
}

function Get-LimitFile([string]$Name) {
    Join-Path (Get-ProfileDir $Name) ".limit"
}

function Read-LimitMap([string]$File) {
    $map = @{}
    if (-not (Test-Path -LiteralPath $File)) { return $map }
    foreach ($line in Get-Content -LiteralPath $File) {
        if ($line -match '^([^=]+)=(.*)$') {
            $map[$matches[1]] = $matches[2]
        }
    }
    $map
}

function Get-LimitStatus([string]$Name) {
    $file = Get-LimitFile $Name
    if (-not (Test-Path -LiteralPath $file)) { return "-" }

    $map = Read-LimitMap $file
    $resetAt = $map["reset_at"]
    if ($resetAt) {
        try {
            if ((Get-NowEpoch) -ge [int64]$resetAt) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
                return "-"
            }
        } catch {}
    }

    if ($map["label"]) { return $map["label"] }
    if ($resetAt) { return "hit until $(Format-Epoch $resetAt)" }
    "hit unknown"
}

function Write-Limit([string]$Name, [string]$Type = "unknown", [string]$ResetAt = "", [string]$Source = "manual") {
    New-Item -ItemType Directory -Force -Path (Get-ProfileDir $Name) | Out-Null
    $file = Get-LimitFile $Name
    $hitAt = Get-NowEpoch
    $label = if ($ResetAt) { "hit until $(Format-Epoch $ResetAt)" } else { "hit unknown" }

    $lines = @(
        "hit_at=$hitAt",
        $(if ($ResetAt) { "reset_at=$ResetAt" }),
        "type=$Type",
        "source=$Source",
        "label=$label"
    ) | Where-Object { $_ }

    Set-Content -LiteralPath $file -Value $lines
}

function Clear-Limit([string]$Name) {
    Remove-Item -LiteralPath (Get-LimitFile $Name) -Force -ErrorAction SilentlyContinue
}

function Get-LatestSessionFile {
    $sessionDir = Join-Path $CodexHome "sessions"
    if (-not (Test-Path -LiteralPath $sessionDir)) { return $null }
    Get-ChildItem -LiteralPath $sessionDir -Recurse -Filter "*.jsonl" -File -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Get-LastRateLimitRecord([string]$SessionFile) {
    if (-not $SessionFile) { return $null }
    $lastLine = $null
    foreach ($line in Get-Content -LiteralPath $SessionFile -ErrorAction SilentlyContinue) {
        if ($line -like '*"rate_limits"*') {
            $lastLine = $line
        }
    }
    if (-not $lastLine) { return $null }

    try {
        $obj = $lastLine | ConvertFrom-Json -ErrorAction Stop
        $rate = Get-Prop $obj "rate_limits"
        if ($rate) { return $rate }
        $payload = Get-Prop $obj "payload"
        $rate = Get-Prop $payload "rate_limits"
        if ($rate) { return $rate }
    } catch {
        return $null
    }
}

function Max-Epoch([string]$A, [string]$B) {
    if (-not $A) { return $B }
    if (-not $B) { return $A }
    if ([int64]$A -ge [int64]$B) { $A } else { $B }
}

function Scan-LimitForProfile([string]$Name) {
    $session = Get-LatestSessionFile
    $rate = Get-LastRateLimitRecord $session
    if (-not $rate) { return }

    $primary = Get-Prop $rate "primary"
    $secondary = Get-Prop $rate "secondary"
    $reached = [string](Get-Prop $rate "rate_limit_reached_type")
    $primaryUsedValue = Get-Prop $primary "used_percent"
    $primaryResetValue = Get-Prop $primary "resets_at"
    $secondaryUsedValue = Get-Prop $secondary "used_percent"
    $secondaryResetValue = Get-Prop $secondary "resets_at"
    $primaryUsed = if ($null -ne $primaryUsedValue) { [double]$primaryUsedValue } else { 0.0 }
    $primaryReset = if ($null -ne $primaryResetValue) { [string]$primaryResetValue } else { "" }
    $secondaryUsed = if ($null -ne $secondaryUsedValue) { [double]$secondaryUsedValue } else { 0.0 }
    $secondaryReset = if ($null -ne $secondaryResetValue) { [string]$secondaryResetValue } else { "" }

    $hitType = ""
    $resetAt = ""

    if ($reached -eq "primary") {
        $hitType = "primary"
        $resetAt = $primaryReset
    } elseif ($reached -eq "secondary") {
        $hitType = "secondary"
        $resetAt = $secondaryReset
    } elseif ($reached) {
        $hitType = $reached
        $resetAt = Max-Epoch $primaryReset $secondaryReset
    } else {
        if ($secondaryUsed -ge $LimitThreshold) {
            $hitType = "secondary"
            $resetAt = $secondaryReset
        }
        if ($primaryUsed -ge $LimitThreshold) {
            if ($hitType) {
                $hitType = "primary+secondary"
                $resetAt = Max-Epoch $resetAt $primaryReset
            } else {
                $hitType = "primary"
                $resetAt = $primaryReset
            }
        }
    }

    if ($hitType) {
        Write-Limit $Name $hitType $resetAt "session-scan"
    } else {
        Clear-Limit $Name
    }
}

function Invoke-CodexWithEnv([string]$Profile, [string[]]$CodexArgs = @()) {
    $codexBin = Find-CodexBin
    $oldCodexHome = $env:CODEX_HOME
    $oldAuthProfile = $env:CODEX_AUTH_PROFILE
    try {
        $env:CODEX_HOME = $CodexHome
        $env:CODEX_AUTH_PROFILE = $Profile
        & $codexBin @CodexArgs
        return $LASTEXITCODE
    } finally {
        if ($null -eq $oldCodexHome) { Remove-Item Env:\CODEX_HOME -ErrorAction SilentlyContinue } else { $env:CODEX_HOME = $oldCodexHome }
        if ($null -eq $oldAuthProfile) { Remove-Item Env:\CODEX_AUTH_PROFILE -ErrorAction SilentlyContinue } else { $env:CODEX_AUTH_PROFILE = $oldAuthProfile }
    }
}

function Cmd-Import([string[]]$Rest) {
    $name = First-Arg $Rest
    if (-not $name) { Die "usage: cx import <name>" }
    Ensure-Dirs
    if (-not (Test-Path -LiteralPath (Get-SharedAuth))) { Die "no shared auth found at $(Get-SharedAuth)" }
    New-Item -ItemType Directory -Force -Path (Get-ProfileDir $name) | Out-Null
    Copy-Item -LiteralPath (Get-SharedAuth) -Destination (Get-ProfileAuth $name) -Force
    Set-CurrentProfile $name
    "imported current auth as profile: $name"
}

function Cmd-Login([string[]]$Rest) {
    $name = First-Arg $Rest
    if (-not $name) { Die "usage: cx login <name> [codex login args]" }
    $loginArgs = @($Rest | Select-Object -Skip 1)

    Ensure-Dirs
    Acquire-Lock
    try {
        Save-ActiveAuthIfKnown
        $backup = $null
        $shared = Get-SharedAuth
        if (Test-Path -LiteralPath $shared) {
            $backup = "$shared.cx-login-backup.$PID"
            Copy-Item -LiteralPath $shared -Destination $backup -Force
        }

        if (Test-Path -LiteralPath (Get-ProfileAuth $name)) {
            Stage-ProfileAuth $name
        } elseif (Test-Path -LiteralPath $shared) {
            Remove-Item -LiteralPath $shared -Force
        }

        $loginCommandArgs = @("login") + $loginArgs
        $status = Invoke-CodexWithEnv $name $loginCommandArgs
        if ($status -eq 0 -and (Test-Path -LiteralPath $shared)) {
            Store-ProfileAuth $name
            Set-CurrentProfile $name
            if ($backup) { Remove-Item -LiteralPath $backup -Force -ErrorAction SilentlyContinue }
            "current: $name"
            return
        }

        if ($backup -and (Test-Path -LiteralPath $backup)) {
            Copy-Item -LiteralPath $backup -Destination $shared -Force
            Remove-Item -LiteralPath $backup -Force
        }
        $global:LASTEXITCODE = $status
    } finally {
        Release-Lock
    }
}

function Cmd-Use([string[]]$Rest) {
    $name = First-Arg $Rest
    if (-not $name) { Die "usage: cx use <name>" }
    Ensure-Dirs
    if (-not (Test-Path -LiteralPath (Get-ProfileAuth $name))) { Die "profile has no auth.json: $name; run: cx login $name" }
    Save-ActiveAuthIfKnown
    Stage-ProfileAuth $name
    Set-CurrentProfile $name
    "current: $name"
}

function Cmd-List {
    Ensure-Dirs
    $current = Get-CurrentProfile
    "{0,-8} {1,-24} {2,-10} {3}" -f "CURRENT", "PROFILE", "LOGIN", "LIMIT"
    Get-ChildItem -LiteralPath $ProfilesDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne ".lock" } |
        Sort-Object Name |
        ForEach-Object {
            $name = $_.Name
            $mark = if ($name -eq $current) { "*" } else { "" }
            "{0,-8} {1,-24} {2,-10} {3}" -f $mark, $name, (Get-AuthState $name), (Get-LimitStatus $name)
        }
}

function Cmd-Run([string[]]$Rest) {
    $codexArgs = @($Rest)
    if ($codexArgs.Count -gt 0 -and $codexArgs[0] -eq "--") {
        $codexArgs = @($codexArgs | Select-Object -Skip 1)
    }

    Ensure-Dirs
    $name = Require-CurrentProfile
    if (-not (Test-Path -LiteralPath (Get-ProfileAuth $name))) { Die "profile has no auth.json: $name; run: cx login $name" }

    Acquire-Lock
    try {
        Stage-ProfileAuth $name
        $status = Invoke-CodexWithEnv $name $codexArgs
        Store-ProfileAuth $name
        Scan-LimitForProfile $name
        $global:LASTEXITCODE = $status
    } finally {
        Release-Lock
    }
}

function Cmd-HookCommand {
    $scriptDir = Split-Path -Parent $PSCommandPath
    $repoDir = Split-Path -Parent $scriptDir
    $hook = Join-Path (Join-Path $repoDir "hooks") "codex-limit-hook.ps1"
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$hook`""
}

$cmd = if ($args.Count -gt 0) { $args[0] } else { "help" }
$rest = if ($args.Count -gt 1) { @($args | Select-Object -Skip 1) } else { @() }

switch ($cmd) {
    "import" { Cmd-Import $rest }
    "init" { Cmd-Import $rest }
    "login" { Cmd-Login $rest }
    "use" { Cmd-Use $rest }
    "list" { Cmd-List }
    "ls" { Cmd-List }
    "current" { $name = Get-CurrentProfile; if (-not $name) { Die "no active profile" }; $name }
    "run" { Cmd-Run $rest }
    "scan-limit" {
        Ensure-Dirs
        $name = if ($rest.Count -gt 0 -and $rest[0]) { $rest[0] } else { Require-CurrentProfile }
        Scan-LimitForProfile $name
    }
    "limit" {
        $name = First-Arg $rest
        if (-not $name) { Die "usage: cx limit <name> [reset_epoch]" }
        $resetAt = if ($rest.Count -gt 1) { $rest[1] } else { "" }
        Write-Limit $name "manual" $resetAt "manual"
    }
    "ok" {
        $name = First-Arg $rest
        if (-not $name) { Die "usage: cx ok <name>" }
        Clear-Limit $name
    }
    "hook-command" { Cmd-HookCommand }
    "help" { Write-Usage }
    "-h" { Write-Usage }
    "--help" { Write-Usage }
    default {
        Write-Usage
        throw "unknown command: $cmd"
    }
}
