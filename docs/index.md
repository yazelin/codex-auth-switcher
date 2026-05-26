---
layout: default
title: Codex Auth Switcher
---

# Codex Auth Switcher

Manage multiple Codex ChatGPT auth profiles on one machine.  
Switch accounts instantly without re-logging in. Works on **Windows**, **Linux**, and **macOS**.

---

## Install

### Windows PowerShell — one line

Open any PowerShell window and paste:

```powershell
irm https://raw.githubusercontent.com/yazelin/codex-auth-switcher/main/install-oneliner.ps1 | iex
```

The installer will:
1. Clone the repo to `~/codex-auth-switcher`
2. Add the shell integration to your PowerShell profile
3. Load `cx` and `codex` into the current session immediately
4. Print the next-steps guide

---

### Linux / macOS — one line

Open any bash or zsh terminal and paste:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/codex-auth-switcher/main/install-oneliner.sh)
```

The installer will:
1. Clone the repo to `~/.local/share/codex-auth-switcher`
2. Symlink `cx` into `~/.local/bin`
3. Add the shell integration to `~/.bashrc` or `~/.zshrc`
4. Load `cx` and `codex` into the current session immediately
5. Print the next-steps guide

---

## First-Time Setup

After installing, run these commands once:

```bash
# Save your current Codex login as a profile named "main"
cx import main

# Check what was saved
cx list
```

**Output example:**

```
CURRENT  PROFILE   LOGIN   EMAIL                  PLAN   LIMIT
*        main      ok      ma***@example.com      plus   -
```

To add more accounts:

```bash
cx login work        # opens Codex login for a new profile called "work"
cx login personal    # another account
```

---

## Daily Commands

### Interactive switcher — recommended

```bash
cx switch
```

Opens an arrow-key menu showing all profiles and their status.  
Selecting a profile automatically kills any running Codex session, then switches.  
Press **↑ / ↓** to navigate, **Enter** to confirm, **Esc** to cancel.

---

### All commands

| Command | What it does |
|---|---|
| `cx import <name>` | Save the current `~/.codex/auth.json` as a profile |
| `cx login <name>` | Open Codex login flow for a new profile |
| `cx use <name>` | Switch the shared active profile |
| `cx switch --live` | Refresh usage for all profiles before opening the switcher |
| `cx switch` | Interactive TUI switcher — kills Codex first |
| `cx kill` | Kill all active Codex processes |
| `cx list [--live]` | List all profiles with login status, email, plan, usage, and limit |
| `cx usage [name\|--all]` | Refresh live usage; no argument refreshes all profiles |
| `cx info [name]` | Detailed info for one profile |
| `cx current` | Print the currently active profile name |
| `cx remove <name>` | Delete a saved profile |
| `cx ps` | Show detected Codex processes |
| `cx doctor` | Diagnostics — paths, process state, profile summary |
| `cx export profiles.tgz` | Back up all profiles to a tar archive |
| `cx restore profiles.tgz` | Restore profiles from a tar archive |
| `cx ok <name>` | Clear a rate-limit marker manually |
| `cx help` | Show built-in command reference |
| `codex` | Launch Codex under the active profile |

---

## Profile Switching in Detail

`cx switch` is the recommended way to change accounts:

```
  Codex Profile Switcher  (Up/Down: navigate | Enter: switch | Esc: cancel)
  ───────────────────────────────────────────────────────────────────────
  * main                   ok        5h 97% left @06:15 | W 48% left @Sun 05:45 (4m)
    work                   ok        5h 22% left @03:59 | W 59% left @Sun 10:06 (2h)  !hit until 2026-05-26 09:00
    personal               ok
```

- `*` marks the currently active profile
- `ok` means the profile has a saved login
- usage values show remaining quota; `@` is the local reset time and the final age is when the cache was refreshed
- `!hit until …` means that account hit a rate limit and when it resets

If there are active Codex processes when you press Enter, they are killed before the profile file is swapped. You do not need to close Codex manually.

---

## What Gets Shared vs. Switched

Only `~/.codex/auth.json` is switched between profiles.

Wrapped `codex` runs use the normal Codex home, so same-account multi-session work keeps shared `/resume`, session history, sqlite state, skills, and plugins. Profile switching is guarded while Codex is active so `auth.json` is not changed under a running session.

Configuration and reusable resources are shared across all profiles on the same machine:

| Item | Shared |
|---|---|
| `~/.codex/config.toml` | ✓ yes |
| `~/.codex/hooks.json` | ✓ yes |
| `~/.codex/sessions/` | shared |
| `~/.codex/history.jsonl` | shared |
| `~/.codex/auth.json` | — switched per profile |

This means skills, memories, config, and resume history are shared for the active account. Switch profiles only after active Codex sessions are closed, or use `cx switch` to kill them before switching.

---

## Rate Limit Tracking

After each `codex` run, the tool scans the latest session file for rate-limit data.
If usage data is present, it updates the local `.usage` cache. Use `cx usage`, `cx list --live`, or `cx switch --live` to refresh directly from ChatGPT; plain `cx list` and `cx switch` only show cached usage and do not call the network.

If a limit was hit, it records when it resets:

```
CURRENT  PROFILE   LOGIN   EMAIL                  PLAN   USAGE                                      LIMIT
*        main      ok      ma***@example.com      plus   5h 97% left @06:15 | W 48% left @Sun 05:45 (4m) -
         work      ok      wo***@example.com      team   5h 22% left @03:59 | W 59% left @Sun 10:06 (2h) hit until 2026-05-26 09:00
```

The marker clears automatically when the reset time passes. To clear it manually:

```bash
cx ok work
```

---

## Optional Stop Hook

Add this to `~/.codex/hooks.json` so rate-limit data is captured as soon as a session ends:

**Linux / macOS:**

```bash
cx hook-command
```

**Windows:**

```powershell
cx hook-command
```

Copy the printed command and add it to the `Stop` section of your `hooks.json`.

---

## Security Notes

Auth profiles contain login tokens. Do **not** commit `~/.codex_auth_profiles` or any `auth.json` file.

The `cx export` archive also contains tokens — keep it private and delete it after transferring to another machine.

---

## Source

[github.com/yazelin/codex-auth-switcher](https://github.com/yazelin/codex-auth-switcher)
