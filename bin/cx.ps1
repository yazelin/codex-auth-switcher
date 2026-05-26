Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$ProfilesDir = if ($env:CX_PROFILES_DIR) { $env:CX_PROFILES_DIR } else { Join-Path $HOME ".codex_auth_profiles" }
$DefaultCodexHome = Join-Path $HOME ".codex"
if ($env:CX_CODEX_HOME) {
    $CodexHome = $env:CX_CODEX_HOME
} elseif ($env:CODEX_HOME) {
    $runtimeRootText = (Join-Path $ProfilesDir ".runtime").TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).Replace("\", "/")
    $codexHomeText = ([string]$env:CODEX_HOME).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).Replace("\", "/")
    if ($codexHomeText.StartsWith("$runtimeRootText/run-", [StringComparison]::OrdinalIgnoreCase)) {
        $CodexHome = $DefaultCodexHome
    } else {
        $CodexHome = $env:CODEX_HOME
    }
} else {
    $CodexHome = $DefaultCodexHome
}
$LimitThreshold = if ($env:CX_LIMIT_THRESHOLD) { [double]$env:CX_LIMIT_THRESHOLD } else { 100.0 }

$CurrentFile = Join-Path $ProfilesDir "current"
$LockDir = Join-Path $ProfilesDir ".lock"

function Write-Usage {
    @"
usage:
  cx import <name>          Save current ~/.codex/auth.json as a profile
  cx login <name> [args]    Login or refresh a profile
  cx use <name>             Switch active auth profile
  cx switch [--live]        Interactive profile switcher (kills Codex first)
  cx kill                   Kill all active Codex processes
  cx remove <name>          Remove a saved auth profile
  cx list [--live]          List profiles, login, metadata, usage, and limit state
  cx usage [name|--all]     Refresh live usage from ChatGPT and cache it
  cx info [name]            Show metadata for one profile
  cx current                Print active profile
  cx run -- [codex args]    Run codex with the active auth profile
  cx ps                     Show Codex processes that can affect switching
  cx doctor                 Show paths, process state, and profile summary
  cx export <archive.tgz>   Export auth profiles to a tar.gz archive
  cx restore <archive.tgz>  Restore auth profiles from a tar.gz archive
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
  CX_ALLOW_ACTIVE_CODEX     Set to 1 to login even if Codex is running
"@
}

function Die([string]$Message) {
    throw "cx: $Message"
}

function First-Arg([string[]]$List) {
    foreach ($item in $List) { return $item }
    ""
}

function Get-Prop($Object, [string]$Name) {
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($prop) { return $prop.Value }
    $null
}

function Format-PlainValue($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { "-" } else { [string]$Value }
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

function Format-ResetShort([string]$Epoch) {
    if ([string]::IsNullOrWhiteSpace($Epoch)) { return "-" }
    try {
        $dto = [DateTimeOffset]::FromUnixTimeSeconds([int64]$Epoch).ToLocalTime()
        if ($dto.Date -eq [DateTimeOffset]::Now.Date) { return $dto.ToString("HH:mm") }
        return $dto.ToString("ddd HH:mm")
    } catch {
        return $Epoch
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

    $all = @(Get-Command codex -All -ErrorAction SilentlyContinue |
        Where-Object { $_.CommandType -in @("Application", "ExternalScript") })

    # Prefer Application (.cmd, .exe) over ExternalScript (.ps1) — PowerShell .ps1
    # wrappers generated by npm can break Node.js TTY detection (process.stdout.isTTY)
    # because they introduce an extra PowerShell pipeline layer. The .cmd wrapper goes
    # through cmd.exe and preserves the Windows console handle correctly.
    $cmd = $all | Where-Object { $_.CommandType -eq "Application" } | Select-Object -First 1
    if (-not $cmd) {
        $cmd = $all | Where-Object { $_.CommandType -eq "ExternalScript" } | Select-Object -First 1
    }

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

function Store-ProfileAuthFromPath([string]$Name, [string]$AuthPath) {
    if (-not (Test-Path -LiteralPath $AuthPath)) { return }
    New-Item -ItemType Directory -Force -Path (Get-ProfileDir $Name) | Out-Null
    Copy-Item -LiteralPath $AuthPath -Destination (Get-ProfileAuth $Name) -Force
}

function Get-RuntimeRoot {
    Join-Path $ProfilesDir ".runtime"
}

function Test-CodexRuntimeDatabaseEntry([string]$Name) {
    $Name -match '\.sqlite3?($|[.-])' -or $Name -match '\.db($|[.-])'
}

function Copy-CodexHomeEntryToRuntime([System.IO.FileSystemInfo]$Entry, [string]$RuntimeHome) {
    $name = $Entry.Name
    if ($name -eq "auth.json" -or $name -eq "sessions" -or $name -eq "history.jsonl" -or (Test-CodexRuntimeDatabaseEntry $name)) {
        return
    }

    $destination = Join-Path $RuntimeHome $name
    if ($name -eq "hooks.json" -and -not $Entry.PSIsContainer) {
        $text = [System.IO.File]::ReadAllText($Entry.FullName)
        $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
        [System.IO.File]::WriteAllText($destination, $text, $utf8NoBom)
        return
    }

    try {
        New-Item -ItemType SymbolicLink -Path $destination -Target $Entry.FullName -ErrorAction Stop | Out-Null
        return
    } catch {
        Copy-Item -LiteralPath $Entry.FullName -Destination $destination -Recurse:$Entry.PSIsContainer -Force -ErrorAction SilentlyContinue
    }
}

function New-RuntimeCodexHome([string]$Name) {
    $root = Get-RuntimeRoot
    New-Item -ItemType Directory -Force -Path $root | Out-Null
    $runtime = Join-Path $root ("run-{0}-{1}" -f $PID, ([Guid]::NewGuid().ToString("N")))
    New-Item -ItemType Directory -Force -Path $runtime | Out-Null
    Copy-Item -LiteralPath (Get-ProfileAuth $Name) -Destination (Join-Path $runtime "auth.json") -Force

    if (Test-Path -LiteralPath $CodexHome -PathType Container) {
        Get-ChildItem -LiteralPath $CodexHome -Force -ErrorAction SilentlyContinue |
            ForEach-Object { Copy-CodexHomeEntryToRuntime $_ $runtime }
    }

    $runtime
}

function Remove-RuntimeCodexHome([string]$RuntimeHome) {
    if ([string]::IsNullOrWhiteSpace($RuntimeHome)) { return }
    $root = Get-RuntimeRoot
    try {
        $resolvedRuntime = (Resolve-Path -LiteralPath $RuntimeHome -ErrorAction Stop).Path
        $resolvedRoot = (Resolve-Path -LiteralPath $root -ErrorAction Stop).Path
        $rootPrefix = $resolvedRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
        if ($resolvedRuntime.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase) -and
            (Split-Path -Leaf $resolvedRuntime).StartsWith("run-")) {
            Remove-Item -LiteralPath $resolvedRuntime -Recurse -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

function Set-CurrentProfile([string]$Name) {
    New-Item -ItemType Directory -Force -Path (Get-ProfileDir $Name) | Out-Null
    Set-Content -LiteralPath $CurrentFile -Value $Name
}

function Get-AuthState([string]$Name) {
    if (Test-Path -LiteralPath (Get-ProfileAuth $Name)) { "ok" } else { "not-login" }
}

function Decode-Base64Url([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    $normalized = $Value.Replace("-", "+").Replace("_", "/")
    switch ($normalized.Length % 4) {
        0 { }
        2 { $normalized += "==" }
        3 { $normalized += "=" }
        default { return $null }
    }
    try {
        [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($normalized))
    } catch {
        $null
    }
}

function Decode-JwtPayload([string]$Token) {
    if ([string]::IsNullOrWhiteSpace($Token)) { return $null }
    $parts = $Token.Split(".")
    if ($parts.Count -ne 3) { return $null }
    Decode-Base64Url $parts[1]
}

function Mask-Email([string]$Email) {
    if ([string]::IsNullOrWhiteSpace($Email) -or $Email -eq "-") { return "-" }
    if ($Email -notmatch "@") { return $Email }
    $parts = $Email.Split("@", 2)
    $local = $parts[0]
    $domain = $parts[1]
    $prefix = if ($local.Length -ge 2) { $local.Substring(0, 2) } elseif ($local.Length -eq 1) { $local } else { "" }
    "$prefix***@$domain"
}

function Mask-Id([string]$Value) {
    if ([string]::IsNullOrWhiteSpace($Value) -or $Value -eq "-") { return "-" }
    if ($Value.Length -le 12) { return $Value }
    "$($Value.Substring(0, 8))...$($Value.Substring($Value.Length - 4))"
}

function Get-ProfileMetadata([string]$Name) {
    $authPath = Get-ProfileAuth $Name
    if (-not (Test-Path -LiteralPath $authPath)) {
        return [PSCustomObject]@{
            Mode = "not-login"
            Email = "-"
            Plan = "-"
            AccountId = "-"
            SubscriptionExpiresAt = "-"
        }
    }

    try {
        $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json -ErrorAction Stop
    } catch {
        return [PSCustomObject]@{
            Mode = "invalid"
            Email = "-"
            Plan = "-"
            AccountId = "-"
            SubscriptionExpiresAt = "-"
        }
    }

    $tokens = Get-Prop $auth "tokens"
    $idToken = Get-Prop $tokens "id_token"
    if ($idToken) {
        $payloadText = Decode-JwtPayload ([string]$idToken)
        $claims = $null
        if ($payloadText) {
            try { $claims = $payloadText | ConvertFrom-Json -ErrorAction Stop } catch { $claims = $null }
        }
        $authClaims = Get-Prop $claims "https://api.openai.com/auth"
        $email = Format-PlainValue (Get-Prop $claims "email")
        $plan = Format-PlainValue (Get-Prop $authClaims "chatgpt_plan_type")
        $accountId = Format-PlainValue (Get-Prop $authClaims "chatgpt_account_id")
        $expiresAt = Format-PlainValue (Get-Prop $authClaims "chatgpt_subscription_active_until")
        return [PSCustomObject]@{
            Mode = "chatgpt"
            Email = $email
            Plan = $plan
            AccountId = $accountId
            SubscriptionExpiresAt = $expiresAt
        }
    }

    $apiKey = Get-Prop $auth "OPENAI_API_KEY"
    if ($apiKey) {
        return [PSCustomObject]@{
            Mode = "api_key"
            Email = "-"
            Plan = "api_key"
            AccountId = "-"
            SubscriptionExpiresAt = "-"
        }
    }

    [PSCustomObject]@{
        Mode = "unknown"
        Email = "-"
        Plan = "-"
        AccountId = "-"
        SubscriptionExpiresAt = "-"
    }
}

function Get-CodexProcesses {
    $processes = @()
    try {
        $processes = Get-CimInstance Win32_Process -ErrorAction Stop |
            Where-Object { $_.Name -ieq "codex.exe" -or $_.Name -ieq "Codex.exe" }
    } catch {
        $processes = Get-Process -Name codex,Codex -ErrorAction SilentlyContinue |
            ForEach-Object {
                [PSCustomObject]@{
                    ProcessId = $_.Id
                    Name = $_.Name
                    CommandLine = $_.Path
                }
            }
    }

    foreach ($process in $processes) {
        $pidValue = [int](Get-Prop $process "ProcessId")
        if ($pidValue -eq $PID) { continue }
        $command = [string](Get-Prop $process "CommandLine")
        if (-not $command) { $command = [string](Get-Prop $process "Name") }
        $lower = $command.ToLowerInvariant()
        if ($lower.Contains("codex-auth-switcher")) { continue }

        $kind = "active"
        if ($lower.Contains(" app-server") -or
            $lower.Contains(" mcp-server") -or
            $lower.Contains(" exec-server") -or
            $lower.Contains("\resources\codex.exe") -or
            $lower.Contains(".vscode\extensions\openai.chatgpt") -or
            $lower.Contains(".antigravity") -or
            $lower.Contains("openai.chatgpt") -or
            $lower.Contains("--type=")) {
            $kind = "background"
        }

        [PSCustomObject]@{
            Kind = $kind
            PID = $pidValue
            TTY = "-"
            Command = $command
        }
    }
}

function Assert-NoActiveCodex([string]$Action = "login") {
    if ($env:CX_ALLOW_ACTIVE_CODEX -eq "1") { return }
    $active = @(Get-CodexProcesses | Where-Object { $_.Kind -eq "active" })
    if ($active.Count -eq 0) { return }

    [Console]::Error.WriteLine("cx: refusing to $Action while another Codex session is active")
    $active | ForEach-Object {
        [Console]::Error.WriteLine(("  pid={0} command={1}" -f $_.PID, $_.Command))
    }
    throw "run cx ps for details, or set CX_ALLOW_ACTIVE_CODEX=1 to override"
}

function Get-LimitFile([string]$Name) {
    Join-Path (Get-ProfileDir $Name) ".limit"
}

function Get-UsageFile([string]$Name) {
    Join-Path (Get-ProfileDir $Name) ".usage"
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

function Read-KeyValueMap([string]$File) {
    $map = @{}
    if (-not (Test-Path -LiteralPath $File)) { return $map }
    foreach ($line in Get-Content -LiteralPath $File) {
        if ($line -match '^([^=]+)=(.*)$') {
            $map[$matches[1]] = $matches[2]
        }
    }
    $map
}

function Format-UsageNumber($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value)) { return "-" }
    try {
        $n = [double]$Value
        if ([Math]::Abs($n - [Math]::Round($n)) -lt 0.05) { return ([Math]::Round($n)).ToString("0") }
        return $n.ToString("0.#")
    } catch {
        return [string]$Value
    }
}

function Format-RemainingNumber($Value) {
    if ($null -eq $Value -or [string]::IsNullOrWhiteSpace([string]$Value) -or [string]$Value -eq "-") { return "-" }
    try {
        return Format-UsageNumber ([Math]::Max(0, 100.0 - [double]$Value))
    } catch {
        return "-"
    }
}

function Format-Age([string]$Epoch) {
    if ([string]::IsNullOrWhiteSpace($Epoch)) { return "" }
    try {
        $age = [Math]::Max(0, (Get-NowEpoch) - [int64]$Epoch)
        if ($age -lt 60) { return "${age}s" }
        if ($age -lt 3600) { return "$([Math]::Floor($age / 60))m" }
        if ($age -lt 86400) { return "$([Math]::Floor($age / 3600))h" }
        return "$([Math]::Floor($age / 86400))d"
    } catch {
        return ""
    }
}

function Write-UsageCache(
    [string]$Name,
    [string]$Plan,
    $PrimaryUsed,
    $PrimaryResetAt,
    $PrimaryWindowSeconds,
    $SecondaryUsed,
    $SecondaryResetAt,
    $SecondaryWindowSeconds,
    [string]$ReachedType = "",
    [string]$Source = "api"
) {
    New-Item -ItemType Directory -Force -Path (Get-ProfileDir $Name) | Out-Null
    $file = Get-UsageFile $Name
    $lines = @(
        "checked_at=$(Get-NowEpoch)",
        "source=$Source",
        $(if ($Plan) { "plan=$Plan" }),
        "primary_used_percent=$(Format-UsageNumber $PrimaryUsed)",
        $(if ($PrimaryResetAt) { "primary_reset_at=$PrimaryResetAt" }),
        $(if ($PrimaryWindowSeconds) { "primary_window_seconds=$PrimaryWindowSeconds" }),
        "secondary_used_percent=$(Format-UsageNumber $SecondaryUsed)",
        $(if ($SecondaryResetAt) { "secondary_reset_at=$SecondaryResetAt" }),
        $(if ($SecondaryWindowSeconds) { "secondary_window_seconds=$SecondaryWindowSeconds" }),
        $(if ($ReachedType) { "rate_limit_reached_type=$ReachedType" })
    ) | Where-Object { $_ }
    Set-Content -LiteralPath $file -Value $lines
}

function Get-UsageStatus([string]$Name) {
    $map = Read-KeyValueMap (Get-UsageFile $Name)
    if ($map.Count -eq 0) { return "-" }
    $primary = Format-RemainingNumber $map["primary_used_percent"]
    $secondary = Format-RemainingNumber $map["secondary_used_percent"]
    $primaryReset = Format-ResetShort $map["primary_reset_at"]
    $secondaryReset = Format-ResetShort $map["secondary_reset_at"]
    $label = "5h ${primary}% left @$primaryReset | W ${secondary}% left @$secondaryReset"
    $age = Format-Age $map["checked_at"]
    if ($age) { return "$label ($age)" }
    $label
}

function Get-UsageResetMap([string]$Name) {
    $map = Read-KeyValueMap (Get-UsageFile $Name)
    [PSCustomObject]@{
        Primary = Format-Epoch $map["primary_reset_at"]
        Secondary = Format-Epoch $map["secondary_reset_at"]
    }
}

function Refresh-UsageForProfile([string]$Name, [bool]$Quiet = $false) {
    $authPath = Get-ProfileAuth $Name
    if (-not (Test-Path -LiteralPath $authPath)) {
        if (-not $Quiet) { Write-Warning "cx: profile has no auth.json: $Name" }
        return $false
    }

    try {
        $auth = Get-Content -LiteralPath $authPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $tokens = Get-Prop $auth "tokens"
        $token = Get-Prop $tokens "access_token"
        if (-not $token) {
            if (-not $Quiet) { Write-Warning "cx: no ChatGPT access_token for profile: $Name" }
            return $false
        }

        $resp = Invoke-RestMethod -Method Get -Uri "https://chatgpt.com/backend-api/wham/usage" -Headers @{
            Authorization = "Bearer $token"
            Accept = "application/json"
        } -ErrorAction Stop

        $rate = Get-Prop $resp "rate_limit"
        $primary = Get-Prop $rate "primary_window"
        $secondary = Get-Prop $rate "secondary_window"
        $reached = [string](Get-Prop $resp "rate_limit_reached_type")
        if (-not $reached) { $reached = [string](Get-Prop $rate "rate_limit_reached_type") }

        Write-UsageCache $Name `
            ([string](Get-Prop $resp "plan_type")) `
            (Get-Prop $primary "used_percent") `
            (Get-Prop $primary "reset_at") `
            (Get-Prop $primary "limit_window_seconds") `
            (Get-Prop $secondary "used_percent") `
            (Get-Prop $secondary "reset_at") `
            (Get-Prop $secondary "limit_window_seconds") `
            $reached `
            "api"

        if ($reached) {
            $resetAt = if ($reached -eq "primary") { Get-Prop $primary "reset_at" } elseif ($reached -eq "secondary") { Get-Prop $secondary "reset_at" } else { Max-Epoch (Get-Prop $primary "reset_at") (Get-Prop $secondary "reset_at") }
            Write-Limit $Name $reached ([string]$resetAt) "api"
        } elseif ($rate -and -not [bool](Get-Prop $rate "limit_reached")) {
            Clear-Limit $Name
        }
        return $true
    } catch {
        if (-not $Quiet) { Write-Warning "cx: usage refresh failed for ${Name}: $_" }
        return $false
    }
}

function Refresh-UsageForProfiles([string[]]$Names) {
    foreach ($name in $Names) {
        [void](Refresh-UsageForProfile $name $true)
    }
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
    param([datetime]$After = [datetime]::MinValue, [string]$HomePath = $CodexHome)
    $sessionDir = Join-Path $HomePath "sessions"
    if (-not (Test-Path -LiteralPath $sessionDir)) { return $null }
    Get-ChildItem -LiteralPath $sessionDir -Recurse -Filter "*.jsonl" -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTimeUtc -gt $After.ToUniversalTime() } |
        Sort-Object LastWriteTimeUtc -Descending |
        Select-Object -First 1 -ExpandProperty FullName
}

function Get-LastRateLimitRecord([string]$SessionFile) {
    if (-not $SessionFile) { return $null }
    # Read from the tail — rate_limits always appears in the last token_count event
    $lines = Get-Content -LiteralPath $SessionFile -ErrorAction SilentlyContinue
    if (-not $lines) { return $null }
    $total = $lines.Count
    $limit = [Math]::Max(0, $total - 80)
    for ($i = $total - 1; $i -ge $limit; $i--) {
        if ($lines[$i] -notlike '*"rate_limits"*') { continue }
        try {
            $obj = $lines[$i] | ConvertFrom-Json -ErrorAction Stop
            $rate = Get-Prop $obj "rate_limits"
            if (-not $rate) {
                $payload = Get-Prop $obj "payload"
                $rate = Get-Prop $payload "rate_limits"
            }
            if ($rate) { return $rate }
        } catch { }
    }
    return $null
}

function Max-Epoch([string]$A, [string]$B) {
    if (-not $A) { return $B }
    if (-not $B) { return $A }
    if ([int64]$A -ge [int64]$B) { $A } else { $B }
}

function Scan-LimitForProfile([string]$Name, [datetime]$After = [datetime]::MinValue, [string]$HomePath = $CodexHome) {
    $session = Get-LatestSessionFile -After $After -HomePath $HomePath
    $rate = Get-LastRateLimitRecord $session
    if (-not $rate) { return }

    $primary = Get-Prop $rate "primary"
    $secondary = Get-Prop $rate "secondary"
    $reached = [string](Get-Prop $rate "rate_limit_reached_type")
    $primaryUsedValue = Get-Prop $primary "used_percent"
    $primaryResetValue = Get-Prop $primary "resets_at"
    $secondaryUsedValue = Get-Prop $secondary "used_percent"
    $secondaryResetValue = Get-Prop $secondary "resets_at"
    if ($null -eq $secondaryResetValue) { $secondaryResetValue = Get-Prop $secondary "reset_at" }
    if ($null -eq $primaryResetValue) { $primaryResetValue = Get-Prop $primary "reset_at" }
    $primaryUsed = if ($null -ne $primaryUsedValue) { [double]$primaryUsedValue } else { 0.0 }
    $primaryReset = if ($null -ne $primaryResetValue) { [string]$primaryResetValue } else { "" }
    $secondaryUsed = if ($null -ne $secondaryUsedValue) { [double]$secondaryUsedValue } else { 0.0 }
    $secondaryReset = if ($null -ne $secondaryResetValue) { [string]$secondaryResetValue } else { "" }
    Write-UsageCache $Name ([string](Get-Prop $rate "plan_type")) $primaryUsed $primaryReset (Get-Prop $primary "window_duration_mins") $secondaryUsed $secondaryReset (Get-Prop $secondary "window_duration_mins") $reached "session-scan"

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

function Invoke-CodexWithEnv([string]$Profile, [string[]]$CodexArgs = @(), [string]$RunCodexHome = $CodexHome) {
    $codexBin = Find-CodexBin
    $oldCodexHome = $env:CODEX_HOME
    $oldAuthProfile = $env:CODEX_AUTH_PROFILE
    try {
        $env:CODEX_HOME = $RunCodexHome
        $env:CODEX_AUTH_PROFILE = $Profile
        # Start-Process -NoNewWindow shares the current console window with the child
        # process, ensuring Node.js isTTY = true. The & operator inside a running
        # script can route stdout through PowerShell's output pipeline, breaking the
        # TTY check even in an interactive terminal.
        $startArgs = @{ FilePath = $codexBin; NoNewWindow = $true; PassThru = $true; Wait = $true }
        if ($CodexArgs.Count -gt 0) { $startArgs.ArgumentList = $CodexArgs }
        $proc = Start-Process @startArgs
        $exitCode = 0
        if ($null -ne $proc.ExitCode) { $exitCode = [int]$proc.ExitCode }
        return $exitCode
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
        Assert-NoActiveCodex
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
    $current = Get-CurrentProfile
    if ($name -eq $current) { "current: $name"; return }
    Assert-NoActiveCodex "switch profiles"
    Save-ActiveAuthIfKnown
    Stage-ProfileAuth $name
    Set-CurrentProfile $name
    "current: $name"
}

function Cmd-Remove([string[]]$Rest) {
    $name = First-Arg $Rest
    if (-not $name) { Die "usage: cx remove <name>" }
    Ensure-Dirs

    $current = Get-CurrentProfile
    if ($name -eq $current) { Die "cannot remove active profile: $name; run: cx use <other> first" }

    $dir = Get-ProfileDir $name
    if (-not (Test-Path -LiteralPath $dir -PathType Container)) { Die "profile not found: $name" }
    Remove-Item -LiteralPath $dir -Recurse -Force
    "removed profile: $name"
}

function Cmd-List([string[]]$Rest) {
    Ensure-Dirs
    $current = Get-CurrentProfile
    foreach ($arg in $Rest) {
        if ($arg -eq "-h" -or $arg -eq "--help") { "usage: cx list [--live]"; return }
        if ($arg -ne "--live") { Die "unknown option for list: $arg; usage: cx list [--live]" }
    }
    $live = $Rest -contains "--live"
    $names = @(
        Get-ChildItem -LiteralPath $ProfilesDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne ".lock" -and $_.Name -ne ".runtime" } |
        Sort-Object Name |
        ForEach-Object { $_.Name }
    )
    if ($live) { Refresh-UsageForProfiles $names }

    "{0,-8} {1,-24} {2,-10} {3,-28} {4,-10} {5,-54} {6}" -f "CURRENT", "PROFILE", "LOGIN", "EMAIL", "PLAN", "USAGE", "LIMIT"
    foreach ($name in $names) {
        $mark = if ($name -eq $current) { "*" } else { "" }
        $meta = Get-ProfileMetadata $name
        "{0,-8} {1,-24} {2,-10} {3,-28} {4,-10} {5,-54} {6}" -f $mark, $name, (Get-AuthState $name), (Mask-Email $meta.Email), $meta.Plan, (Get-UsageStatus $name), (Get-LimitStatus $name)
    }
}

function Cmd-Info([string[]]$Rest) {
    $name = First-Arg $Rest
    if (-not $name) { $name = Require-CurrentProfile }
    Ensure-Dirs

    $current = Get-CurrentProfile
    $meta = Get-ProfileMetadata $name
    $resets = Get-UsageResetMap $name
    "profile=$name"
    "current=$(if ($name -eq $current) { "yes" } else { "no" })"
    "login=$(Get-AuthState $name)"
    "auth_mode=$($meta.Mode)"
    "email=$(Mask-Email $meta.Email)"
    "plan=$($meta.Plan)"
    "account_id=$(Mask-Id $meta.AccountId)"
    "subscription_expires_at=$($meta.SubscriptionExpiresAt)"
    "usage=$(Get-UsageStatus $name)"
    "five_hour_resets_at=$($resets.Primary)"
    "weekly_resets_at=$($resets.Secondary)"
    "limit=$(Get-LimitStatus $name)"
    "profile_dir=$(Get-ProfileDir $name)"
}

function Cmd-Run([string[]]$Rest) {
    # PS5.1 strict-mode quirk: if/else expressions with null [string[]] propagate null.
    # Use ArrayList + two-step assignment to reliably strip the "--" separator.
    $cxArgList = [System.Collections.ArrayList]::new()
    if ($null -ne $Rest) {
        [bool]$sawSep = $false
        foreach ($item in $Rest) {
            if (-not $sawSep -and [string]$item -eq "--") { $sawSep = $true; continue }
            [void]$cxArgList.Add([string]$item)
        }
    }
    [string[]]$codexArgs = [string[]]::new(0)
    if ($cxArgList.Count -gt 0) { [string[]]$codexArgs = $cxArgList.ToArray() }

    Ensure-Dirs
    $name = Require-CurrentProfile
    if (-not (Test-Path -LiteralPath (Get-ProfileAuth $name))) { Die "profile has no auth.json: $name; run: cx login $name" }

    Save-ActiveAuthIfKnown
    Stage-ProfileAuth $name
    $runStart = [datetime]::UtcNow
    $status = Invoke-CodexWithEnv $name $codexArgs $CodexHome
    Store-ProfileAuth $name
    Scan-LimitForProfile $name $runStart $CodexHome
    $global:LASTEXITCODE = $status
}

function Cmd-HookCommand {
    $scriptDir = Split-Path -Parent $PSCommandPath
    $repoDir = Split-Path -Parent $scriptDir
    $hook = Join-Path (Join-Path $repoDir "hooks") "codex-limit-hook.ps1"
    "powershell.exe -NoProfile -ExecutionPolicy Bypass -File `"$hook`""
}

function Cmd-Ps {
    $rows = @(Get-CodexProcesses)
    if ($rows.Count -eq 0) {
        "No Codex processes detected."
        return
    }
    "{0,-12} {1,-8} {2,-10} {3}" -f "KIND", "PID", "TTY", "COMMAND"
    $rows | Sort-Object Kind, PID | ForEach-Object {
        "{0,-12} {1,-8} {2,-10} {3}" -f $_.Kind, $_.PID, $_.TTY, $_.Command
    }
}

function Kill-AllCodex {
    $activePids = @(
        Get-CodexProcesses |
        Where-Object { $_.Kind -eq "active" } |
        ForEach-Object { [string]$_.PID }
    )
    if ($activePids.Count -eq 0) { return 0 }
    foreach ($pidStr in $activePids) {
        try { Stop-Process -Id ([int]$pidStr) -Force -ErrorAction Stop }
        catch { Write-Warning "cx: could not kill pid ${pidStr}: $_" }
    }
    Start-Sleep -Milliseconds 500
    return $activePids.Count
}

function Cmd-Kill {
    [int]$killed = Kill-AllCodex
    if ($killed -eq 0) { "No active Codex processes found." }
    else { "Killed $killed active Codex process(es)." }
}

function Cmd-Usage([string[]]$Rest) {
    Ensure-Dirs
    $restCount = 0
    foreach ($item in $Rest) { $restCount++ }
    if ($restCount -gt 1) { Die "usage: cx usage [name|--all]" }
    $target = First-Arg $Rest
    if (-not $target) { $target = "--all" }
    if ($target -eq "-h" -or $target -eq "--help") { "usage: cx usage [name|--all]"; return }
    if ($target.StartsWith("--") -and $target -ne "--all") { Die "unknown option for usage: $target; usage: cx usage [name|--all]" }

    $names = @()
    if ($target -eq "--all") {
        $names = @(
            Get-ChildItem -LiteralPath $ProfilesDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -ne ".lock" -and $_.Name -ne ".runtime" } |
            Sort-Object Name |
            ForEach-Object { $_.Name }
        )
    } else {
        $names = @($target)
    }
    if ($names.Count -eq 0) { Die "no profiles found; run: cx import <name>" }

    "{0,-24} {1,-10} {2}" -f "PROFILE", "UPDATED", "USAGE"
    foreach ($name in $names) {
        $ok = Refresh-UsageForProfile $name $false
        "{0,-24} {1,-10} {2}" -f $name, $(if ($ok) { "yes" } else { "no" }), (Get-UsageStatus $name)
    }
}

function Cmd-Switch([string[]]$Rest) {
    Ensure-Dirs
    $current = Get-CurrentProfile
    foreach ($arg in $Rest) {
        if ($arg -eq "-h" -or $arg -eq "--help") { "usage: cx switch [--live]"; return }
        if ($arg -ne "--live") { Die "unknown option for switch: $arg; usage: cx switch [--live]" }
    }
    $live = $Rest -contains "--live"

    $profileNames = @(
        Get-ChildItem -LiteralPath $ProfilesDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne ".lock" -and $_.Name -ne ".runtime" } |
        Sort-Object Name |
        ForEach-Object { $_.Name }
    )

    if ($profileNames.Count -eq 0) { Die "no profiles found; run: cx import <name>" }
    if ($live) { Refresh-UsageForProfiles $profileNames }

    $selectedIdx = 0
    for ($i = 0; $i -lt $profileNames.Count; $i++) {
        if ($profileNames[$i] -eq $current) { $selectedIdx = $i; break }
    }

    $rows = @(foreach ($pname in $profileNames) {
        [PSCustomObject]@{
            Name  = $pname
            Mark  = if ($pname -eq $current) { "*" } else { " " }
            Auth  = Get-AuthState $pname
            Usage = Get-UsageStatus $pname
            Limit = Get-LimitStatus $pname
        }
    })

    $drawMenu = {
        param([int]$Sel)
        [Console]::SetCursorPosition(0, $menuTop)
        $title = "  Codex Profile Switcher  (Up/Down: navigate | Enter: switch | Esc: cancel)"
        Write-Host $title -ForegroundColor Cyan
        Write-Host ("  " + [string]("-" * ($title.Length - 2))) -ForegroundColor DarkGray
        for ($i = 0; $i -lt $rows.Count; $i++) {
            $r = $rows[$i]
            $limitStr = if ($r.Limit -eq "-") { "" } else { "  !$($r.Limit)" }
            $usageStr = if ($r.Usage -eq "-") { "" } else { "  $($r.Usage)" }
            $line = ("  {0} {1,-20} {2,-8}{3}{4}" -f $r.Mark, $r.Name, $r.Auth, $usageStr, $limitStr).PadRight(108)
            if ($i -eq $Sel) {
                Write-Host $line -BackgroundColor DarkCyan -ForegroundColor White
            } else {
                Write-Host $line
            }
        }
        Write-Host ""
    }

    [Console]::CursorVisible = $false
    [int]$totalLines = $rows.Count + 3
    for ($i = 0; $i -lt $totalLines; $i++) { Write-Host "" }
    [int]$menuTop = [Console]::CursorTop - $totalLines

    $chosen    = $null
    $cancelled = $false

    try {
        & $drawMenu $selectedIdx
        while ($true) {
            $key = [Console]::ReadKey($true)
            if ($key.Key -eq [ConsoleKey]::UpArrow -and $selectedIdx -gt 0) {
                $selectedIdx--; & $drawMenu $selectedIdx
            } elseif ($key.Key -eq [ConsoleKey]::DownArrow -and $selectedIdx -lt ($rows.Count - 1)) {
                $selectedIdx++; & $drawMenu $selectedIdx
            } elseif ($key.Key -eq [ConsoleKey]::Enter) {
                $chosen = $profileNames[$selectedIdx]; break
            } elseif ($key.Key -eq [ConsoleKey]::Escape) {
                $cancelled = $true; break
            }
        }
    } finally {
        [Console]::CursorVisible = $true
        [Console]::SetCursorPosition(0, $menuTop + $totalLines)
    }

    if ($cancelled) { "cancelled."; return }
    if ($chosen -eq $current) { "already on: $chosen"; return }

    $activePids = @(
        Get-CodexProcesses |
        Where-Object { $_.Kind -eq "active" } |
        ForEach-Object { [string]$_.PID }
    )
    if ($activePids.Count -gt 0) {
        "Killing $($activePids.Count) active Codex process(es)..."
        foreach ($pidStr in $activePids) {
            try { Stop-Process -Id ([int]$pidStr) -Force -ErrorAction Stop }
            catch { Write-Warning "cx: could not kill pid ${pidStr}" }
        }
        Start-Sleep -Milliseconds 500
    }

    if (-not (Test-Path -LiteralPath (Get-ProfileAuth $chosen))) {
        Die "profile has no auth.json: $chosen; run: cx login $chosen"
    }
    Save-ActiveAuthIfKnown
    Stage-ProfileAuth $chosen
    Set-CurrentProfile $chosen
    "switched to: $chosen"
}

function Cmd-Doctor {
    Ensure-Dirs
    $current = Get-CurrentProfile
    $profiles = @(Get-ChildItem -LiteralPath $ProfilesDir -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne ".lock" -and $_.Name -ne ".runtime" })
    $processes = @(Get-CodexProcesses)
    $active = @($processes | Where-Object { $_.Kind -eq "active" })
    $background = @($processes | Where-Object { $_.Kind -eq "background" })
    $codexBin = try { Find-CodexBin } catch { "-" }

    "codex_home=$CodexHome"
    "profiles_dir=$ProfilesDir"
    "current_profile=$(if ($current) { $current } else { "-" })"
    "profile_count=$($profiles.Count)"
    "codex_bin=$codexBin"
    "lock=$(if (Test-Path -LiteralPath $LockDir) { "present" } else { "absent" })"
    "active_codex_processes=$($active.Count)"
    "background_codex_processes=$($background.Count)"
    ""
    Cmd-List
}

function Cmd-Export([string[]]$Rest) {
    $dest = First-Arg $Rest
    if (-not $dest) { Die "usage: cx export <archive.tgz>" }
    Ensure-Dirs
    $parent = Split-Path -Parent $dest
    if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $tar = Get-Command tar -ErrorAction SilentlyContinue
    if (-not $tar) { Die "tar is required for cx export" }
    & $tar.Source --exclude "./.lock" --exclude "./.runtime" -czf $dest -C $ProfilesDir .
    if ($LASTEXITCODE -ne 0) { Die "tar export failed" }
    "exported profiles to: $dest"
}

function Cmd-Restore([string[]]$Rest) {
    $src = First-Arg $Rest
    if (-not $src) { Die "usage: cx restore <archive.tgz>" }
    if (-not (Test-Path -LiteralPath $src)) { Die "archive not found: $src" }
    Ensure-Dirs
    $tar = Get-Command tar -ErrorAction SilentlyContinue
    if (-not $tar) { Die "tar is required for cx restore" }
    & $tar.Source -xzf $src -C $ProfilesDir
    if ($LASTEXITCODE -ne 0) { Die "tar restore failed" }
    "restored profiles from: $src"
}

$cmd = if ($args.Count -gt 0) { $args[0] } else { "help" }
$rest = if ($args.Count -gt 1) { @($args | Select-Object -Skip 1) } else { @() }

try {
    switch ($cmd) {
        "import" { Cmd-Import $rest }
        "init" { Cmd-Import $rest }
        "login" { Cmd-Login $rest }
        "use" { Cmd-Use $rest }
        "switch" { Cmd-Switch $rest }
        "kill" { Cmd-Kill }
        "remove" { Cmd-Remove $rest }
        "rm" { Cmd-Remove $rest }
        "delete" { Cmd-Remove $rest }
        "list" { Cmd-List $rest }
        "ls" { Cmd-List $rest }
        "usage" { Cmd-Usage $rest }
        "info" { Cmd-Info $rest }
        "current" { $name = Get-CurrentProfile; if (-not $name) { Die "no active profile" }; $name }
        "run" { Cmd-Run $rest }
        "ps" { Cmd-Ps }
        "doctor" { Cmd-Doctor }
        "export" { Cmd-Export $rest }
        "restore" { Cmd-Restore $rest }
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
            Die "unknown command: $cmd"
        }
    }
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
