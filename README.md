# Codex Auth Switcher

Small shell tooling for managing multiple Codex ChatGPT auth identities on one computer while keeping one shared Codex home.

The design intentionally shares all Codex context:

- `~/.codex/config.toml`
- `~/.codex/hooks.json`
- `~/.codex/sessions/`
- `~/.codex/history.jsonl`
- `~/.codex/logs_*.sqlite`
- plugins, skills, memories, and other state

Only `~/.codex/auth.json` is switched between named auth profiles.

## Platform Support

This repo supports:

- Linux and macOS through bash
- Windows through PowerShell

The behavior and storage format are the same on both platforms. Windows uses PowerShell scripts instead of bash wrappers.

## Layout

Shared Codex state stays where Codex already expects it:

```text
~/.codex/
  auth.json        # currently active auth only
  config.toml      # shared
  hooks.json       # shared
  sessions/        # shared
  history.jsonl    # shared
  logs_*.sqlite    # shared
```

Stored auth profiles live separately.

Linux/macOS:

```text
~/.codex_auth_profiles/
  current
  main/
    auth.json
    .limit
  team-a/
    auth.json
    .limit
  coworker-1/
    auth.json
    .limit
```

Windows:

```text
%USERPROFILE%\.codex_auth_profiles\
  current
  main\
    auth.json
    .limit
  team-a\
    auth.json
    .limit
  coworker-1\
    auth.json
    .limit
```

Profile names are arbitrary. `work`, `personal`, `team-a`, `backup`, or a teammate name are all just labels.

## Install

### Linux / macOS

Clone this repo, then run from the repo root:

```bash
./install.sh
```

Add the printed source line to `~/.bashrc`, usually:

```bash
source "$HOME/.config/codex-auth-switcher/bash.sh"
```

Reload your shell:

```bash
source ~/.bashrc
```

### Windows PowerShell

Clone this repo, then add this to your PowerShell profile:

```powershell
. "$HOME\codex-auth-switcher\shell\powershell.ps1"
```

You can print your profile path with:

```powershell
$PROFILE
```

Or let the installer append the source line:

```powershell
.\install.ps1 -UpdateProfile
```

Then reload PowerShell or dot-source the profile:

```powershell
. $PROFILE
```

Both shell integrations give you:

- `cx`: profile manager
- `codex`: shell function wrapper that runs Codex through `cx`

The wrapper is required because it copies the selected profile auth into `~/.codex/auth.json` before Codex starts, then saves any refreshed token back after Codex exits.

## First-Time Setup

If the current machine already has a logged-in Codex account:

Linux/macOS:

```bash
cx import main
cx list
```

Windows:

```powershell
cx import main
cx list
```

To add another auth profile:

```bash
cx login team-a
cx login coworker-1
```

To choose which auth Codex should use:

```bash
cx use team-a
codex
```

## Daily Commands

Linux/macOS and Windows use the same commands:

```bash
cx list
cx info <name>
cx use <name>
cx remove <name>
cx login <name>
cx ps
cx doctor
cx export profiles.tgz
cx restore profiles.tgz
cx ok <name>
codex
```

`cx list` shows:

```text
CURRENT  PROFILE                  LOGIN      EMAIL                        PLAN       LIMIT
*        main                     ok         ma***@example.com            plus       -
         team-a                   ok         te***@example.com            team       hit until 2026-05-25 17:06
         coworker-1               not-login  -                            -          -
```

`LOGIN` is based on whether that profile has a saved `auth.json`. `EMAIL` and `PLAN` are parsed from the ChatGPT `id_token` when available. Email and account IDs are masked for terminal display.

`cx info <name>` shows one profile in key-value form:

```text
profile=main
current=yes
login=ok
auth_mode=chatgpt
email=ma***@example.com
plan=plus
account_id=acc_1234...cdef
subscription_expires_at=2026-04-23T05:03:38+00:00
limit=-
profile_dir=/home/me/.codex_auth_profiles/main
```

`cx remove <name>` deletes a saved auth profile directory:

```bash
cx remove old-profile
```

For safety, it refuses to remove the currently active profile. Switch to another profile first:

```bash
cx use main
cx remove old-profile
```

## Limit Tracking

Codex session JSONL files can include `rate_limits` data:

```json
{
  "rate_limits": {
    "primary": { "used_percent": 100.0, "resets_at": 1779700000 },
    "secondary": { "used_percent": 80.0, "resets_at": 1779800000 },
    "rate_limit_reached_type": "primary"
  }
}
```

After each wrapped `codex` run, `cx` scans the latest shared session file. If a rate limit was reached, it writes:

```text
~/.codex_auth_profiles/<name>/.limit
```

The marker stores:

```text
hit_at=1779694300
reset_at=1779700000
type=primary
source=session-scan
label=hit until 2026-05-25 17:06
```

`cx list` automatically clears `.limit` when `now >= reset_at`, so a profile becomes available again the next time you list profiles.

If reset time cannot be detected, the status stays `hit unknown` until you clear it manually:

```bash
cx ok <name>
```

Manual marking is also supported:

```bash
cx limit <name>
cx limit <name> <reset_epoch>
```

## Optional Stop Hook

The `codex` wrapper already scans limits after Codex exits. The optional hook catches normal Codex `Stop` events earlier.

### Linux / macOS Hook

Print the hook command:

```bash
cx hook-command
```

Add it to the `Stop` section of `~/.codex/hooks.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"/path/to/codex-auth-switcher/hooks/codex-limit-hook\""
          }
        ]
      }
    ]
  }
}
```

If you already have other `Stop` hooks, add this as another command entry. Do not remove existing hooks unless you intentionally want to.

### Windows Hook

Print the hook command:

```powershell
cx hook-command
```

It will look like:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\codex-auth-switcher\hooks\codex-limit-hook.ps1"
```

Add that command to the `Stop` section of `%USERPROFILE%\.codex\hooks.json`:

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "powershell.exe -NoProfile -ExecutionPolicy Bypass -File \"C:\\path\\to\\codex-auth-switcher\\hooks\\codex-limit-hook.ps1\""
          }
        ]
      }
    ]
  }
}
```

## Concurrency

This tool uses one shared `~/.codex/auth.json`, so it takes a lock while running Codex through `cx`.

That means you should not run two different auth profiles at the same time in the same shared Codex home. The lock prevents accidental overlapping `cx` runs because overlapping would make `auth.json` ambiguous.

`cx use`, `cx login`, and wrapped `codex` runs also check for other active Codex processes before changing `auth.json`.

```bash
cx ps
cx doctor
```

`cx ps` lists detected Codex processes as `active` or `background`. `active` processes block switching by default. `background` processes such as app-server or IDE helper processes are shown but do not block.

To override the process guard:

```bash
CX_ALLOW_ACTIVE_CODEX=1 cx use <name>
```

PowerShell:

```powershell
$env:CX_ALLOW_ACTIVE_CODEX = "1"
cx use <name>
```

## Export And Restore

Profiles can be copied to another machine as a tar.gz archive:

```bash
cx export profiles.tgz
cx restore profiles.tgz
```

PowerShell uses the same commands:

```powershell
cx export profiles.tgz
cx restore profiles.tgz
```

The archive contains auth tokens. Keep it private and delete it when you are done moving profiles.

## Environment

Defaults:

Linux/macOS:

```bash
CX_PROFILES_DIR="$HOME/.codex_auth_profiles"
CX_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CX_LIMIT_THRESHOLD=100
```

Windows PowerShell:

```powershell
$env:CX_PROFILES_DIR = "$HOME\.codex_auth_profiles"
$env:CX_CODEX_HOME = "$HOME\.codex"
$env:CX_LIMIT_THRESHOLD = "100"
```

Override the real Codex binary if needed:

```bash
export CX_CODEX_BIN="/path/to/codex"
```

Windows:

```powershell
$env:CX_CODEX_BIN = "C:\path\to\codex.cmd"
```

Use a non-default shared Codex home:

```bash
export CX_CODEX_HOME="$HOME/.codex"
```

Windows:

```powershell
$env:CX_CODEX_HOME = "$HOME\.codex"
```

Allow switching while active Codex processes are detected:

```bash
export CX_ALLOW_ACTIVE_CODEX=1
```

Windows:

```powershell
$env:CX_ALLOW_ACTIVE_CODEX = "1"
```

## Safety Notes

This tool does not automatically switch to another account after a limit is reached. It records which profile appears limited and when it should reset, then lets you choose the next profile with `cx use <name>`.

Auth profiles contain tokens. Do not commit `~/.codex_auth_profiles` or any `auth.json` file.

## Prior Art

See [docs/prior-art.md](docs/prior-art.md) for notes comparing this small wrapper with `Lampese/codex-switcher`.
