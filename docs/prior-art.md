# Prior Art: Lampese/codex-switcher

Reference: <https://github.com/Lampese/codex-switcher>

`Lampese/codex-switcher` solves a similar account-switching problem, but its product shape is much larger than this repo. It is a Tauri desktop application with a React frontend, Rust backend, OAuth login flow, live usage API calls, import/export, and process detection.

This repo intentionally stays smaller: a portable shell/PowerShell wrapper that shares one Codex home and switches only `auth.json`.

## What It Does

The upstream project describes itself as a desktop app for managing multiple OpenAI Codex CLI accounts. Its README highlights:

- multi-account management
- one-click switching
- real-time 5-hour and weekly usage monitoring
- OAuth login or importing existing `auth.json`
- browser dashboard mode over HTTP

Its implementation stores account records in `~/.codex-switcher/accounts.json`, then switches accounts by writing credentials into Codex's active `auth.json`.

## Ideas Adopted Here

The account-switching model confirms our chosen approach:

```text
stored profiles -> write active credentials to ~/.codex/auth.json
```

Borrowed ideas implemented in this repo:

- Parse ChatGPT `id_token` claims to derive masked email, plan type, subscription expiry, and account id when available.
- Keep the displayed profile name user-controlled even when metadata exists.
- Detect active Codex processes before switching, because shared `auth.json` is unsafe during concurrent runs.
- Treat usage/limit state as account-specific metadata, not shared Codex-home metadata.
- Preserve `CODEX_HOME` override support.
- Set restrictive file permissions for stored auth on Unix.
- Provide simple profile export/restore without building a desktop app.

## What We Should Not Copy

The upstream project is too large for this use case:

- Tauri, React, Rust, pnpm, and build pipelines are unnecessary for a CLI-first workflow.
- Direct OAuth login, browser dashboard, release tooling, encrypted import/export, and warmup requests are more surface area than needed.
- Live usage polling requires network calls to ChatGPT backend endpoints, which is heavier and more brittle than reading Codex's existing session `rate_limits`.
- It stores all accounts in a single app-specific JSON file, while this repo keeps each profile as a plain directory with its own `auth.json` and `.limit`.

## Design Decision

Stay with the minimal design:

```text
~/.codex/
  auth.json        # active auth only
  config.toml      # shared
  sessions/        # shared
  history.jsonl    # shared

~/.codex_auth_profiles/
  current
  <name>/
    auth.json
    .limit
```

`cx run` copies the selected profile auth into `~/.codex/auth.json`, runs Codex, saves refreshed auth back to that profile, then scans the latest session for `rate_limits`.

## Possible Future Enhancements

These would keep the project small while taking the best ideas:

- Add Windows process-lock cleanup for stale lock directories.
- Add encrypted export archives if plain tar.gz is not acceptable for a workflow.

## Policy Boundary

This repo should remain a manual switcher and status viewer. It should not automatically rotate accounts after a limit is reached or otherwise automate limit avoidance.
