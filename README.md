# Codex Auth Switcher

**繁體中文** · [English](README.en.md) · [日本語](README.ja.md)

在同一台機器上管理多個 Codex ChatGPT auth profile。  
無需重新登入即可瞬間切換帳號，支援 **Windows**、**Linux** 及 **macOS**。

**[完整使用指南 → yazelin.github.io/codex-auth-switcher](https://yazelin.github.io/codex-auth-switcher/)**

## 快速安裝

**Windows PowerShell** — 開啟任意 PowerShell 視窗並貼上：

```powershell
irm https://raw.githubusercontent.com/yazelin/codex-auth-switcher/main/install-oneliner.ps1 | iex
```

**Linux / macOS** — 開啟任意 bash 或 zsh 終端機並貼上：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/codex-auth-switcher/main/install-oneliner.sh)
```

安裝程式會 clone 此 repo、設定好 shell profile，並印出初次設定說明。

---

這是一組小型 shell 工具，用於在同一台電腦上管理多個 Codex ChatGPT auth 身份，同時保留共用的 Codex 設定。

設計上刻意共用 Codex 設定與可重複使用的本機資源：

- `~/.codex/config.toml`
- `~/.codex/hooks.json`
- plugins、skills、memories 及其他狀態

只有 `~/.codex/auth.json` 會在各具名 auth profile 之間切換。  
透過包裝執行的 `codex` 使用正常的 Codex home，因此同一個使用中帳號的多個 session 共享 `/resume`、session history、sqlite 狀態、skills 及 plugins。切換帳號時若 Codex 正在執行，系統會阻擋操作，避免在執行中的 session 底下替換 `auth.json`。

## 平台支援

此 repo 支援：

- Linux 與 macOS（透過 bash）
- Windows（透過 PowerShell）

兩個平台的行為與儲存格式完全相同，Windows 使用 PowerShell 腳本取代 bash wrapper。

## 目錄結構

共用的 Codex 狀態維持在 Codex 原本預期的位置：

```text
~/.codex/
  auth.json        # currently active auth only
  config.toml      # shared
  hooks.json       # shared
  sessions/        # direct Codex sessions
  history.jsonl    # direct Codex history
  logs_*.sqlite    # direct Codex logs
```

已儲存的 auth profile 則放在獨立的位置。

Linux/macOS：

```text
~/.codex_auth_profiles/
  current
  main/
    auth.json
    .usage
    .limit
  team-a/
    auth.json
    .usage
    .limit
  coworker-1/
    auth.json
    .usage
    .limit
```

Windows：

```text
%USERPROFILE%\.codex_auth_profiles\
  current
  main\
    auth.json
    .usage
    .limit
  team-a\
    auth.json
    .usage
    .limit
  coworker-1\
    auth.json
    .usage
    .limit
```

Profile 名稱可自由命名，`work`、`personal`、`team-a`、`backup` 或同事名稱都只是標籤。

## 安裝

請參閱上方的**[快速安裝](#快速安裝)**取得一行指令。

### 手動安裝 — Linux / macOS

Clone 此 repo，然後在 repo 根目錄執行：

```bash
./install.sh
```

將印出的 source 指令加入 `~/.bashrc`，通常如下：

```bash
source "$HOME/.config/codex-auth-switcher/bash.sh"
```

重新載入 shell：

```bash
source ~/.bashrc
```

### 手動安裝 — Windows PowerShell

Clone 此 repo，然後執行安裝程式，將 source 指令附加至 profile：

```powershell
.\install.ps1 -UpdateProfile
```

重新載入 profile：

```powershell
. $PROFILE
```

兩種 shell 整合都會提供：

- `cx`：profile 管理工具
- `codex`：透過 `cx` 執行 Codex 的 shell function wrapper

此 wrapper 會以目前選定 profile 的 auth 啟動 Codex（使用共用的 `~/.codex` home，所以 session history、`/resume`、sqlite 狀態都共享），並在 Codex 結束後將任何已刷新的 token 存回該 profile。（帳號的「隔離暫存 `CODEX_HOME`」只用在 `cx login` 登入當下，見上面的 auth profile 說明。）

## 解除安裝

移除 shell 接線（`cx` / `codex` 指令）。已存的帳號預設保留。

**Linux / macOS**

```bash
# 一行安裝預設 clone 在 ~/.local/share/codex-auth-switcher
bash ~/.local/share/codex-auth-switcher/uninstall.sh
# 連同已存帳號一起刪除：
bash ~/.local/share/codex-auth-switcher/uninstall.sh --purge
```

（手動安裝者，從你 clone 的 repo 目錄執行 `bash uninstall.sh` 即可。）

**Windows PowerShell**

```powershell
& "$HOME\codex-auth-switcher\uninstall.ps1"
# 連同已存帳號一起刪除：
& "$HOME\codex-auth-switcher\uninstall.ps1" -Purge
```

uninstall 會移除 `cx` symlink（`~/.local/bin/cx`）、
`~/.config/codex-auth-switcher/bash.sh`，以及 shell profile 裡的
`# Codex Auth Switcher` 區塊（改動前留 `.cx-bak` 備份），但**保留** repo 本身與
`~/.codex_auth_profiles` 裡已存的帳號。執行完會印出手動刪除 repo 的指令；
加 `--purge` / `-Purge` 則一併刪除已存帳號。

## 初次設定

若目前機器上已有登入的 Codex 帳號：

Linux/macOS：

```bash
cx import main
cx list
```

Windows：

```powershell
cx import main
cx list
```

新增另一個 auth profile：

```bash
cx login team-a
cx login coworker-1
```

`cx login` 採「隔離登入」：它在一個全新的暫存 `CODEX_HOME` 中執行 `codex login`，
登入成功後只把該帳號的 `auth.json` 收進對應 profile，再以純檔案 swap 啟用。
這很重要——`codex login` 成功時會撤銷「同一個 `CODEX_HOME` 裡的舊 token」;
若直接在共用的 `~/.codex` 登入，新增/重登一個帳號就會連帶撤掉**目前正在用的那個帳號**,
甚至因 refresh token 的 reuse 偵測連坐撤銷整批。隔離登入讓登入動作碰不到其他 profile,
因此你可以安全地保留多個帳號(含同一個 email 底下的多個 workspace)並用 `cx switch` 自由切換。

> 經驗法則:① 每個帳號各自 `cx login` 一次建好 profile;② 之後只用 `cx switch` / `cx use` 切換(純換檔、不重登);③ 同一個 workspace 不要開兩個 profile(會被警告)。

選擇 Codex 要使用的 auth：

```bash
cx use team-a
codex
```

## 日常指令

Linux/macOS 與 Windows 使用相同的指令：

```bash
cx switch               # interactive profile switcher — kills Codex first
cx switch --live        # refresh usage for all profiles before switching
cx kill                 # kill all active Codex processes
cx list
cx list --live          # refresh usage for all profiles before listing
cx usage                # refresh usage for all profiles
cx usage <name>         # refresh usage for one profile
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

`cx list` 顯示內容如下：

```text
CURRENT  PROFILE                  LOGIN      EMAIL                        PLAN       USAGE                            LIMIT
*        main                     ok         ma***@example.com            plus       5h 97% left @06:15 | W 48% left @Sun 05:45 (4m) -
         team-a                   ok         te***@example.com            team       5h 22% left @03:59 | W 59% left @Sun 10:06 (2h) hit until 2026-05-25 17:06
         coworker-1               not-login  -                            -          -                                -
```

`LOGIN` 欄位依據該 profile 是否有已儲存的 `auth.json` 來判斷。`EMAIL` 與 `PLAN` 是在有效時從 ChatGPT `id_token` 解析而來。`USAGE` 顯示快取的 5 小時及每週配額剩餘量；`@` 後為本地重置時間，最後的時間戳為快取更新時間。Email 與帳號 ID 在終端機顯示時會遮罩處理。

需要即時用量時請使用 `cx usage` 或 `cx list --live`。即時刷新會將各選定 profile 的 ChatGPT access token 送至 `https://chatgpt.com/backend-api/wham/usage`，並將結果儲存至：

```text
~/.codex_auth_profiles/<name>/.usage
```

直接執行 `cx list` 與 `cx switch` 不會呼叫網路，只會顯示最新快取的 `.usage` 值（若存在）。

`cx info <name>` 以 key-value 形式顯示單一 profile：

```text
profile=main
current=yes
login=ok
auth_mode=chatgpt
email=ma***@example.com
plan=plus
account_id=acc_1234...cdef
subscription_expires_at=2026-04-23T05:03:38+00:00
usage=5h 97% left @06:15 | W 48% left @Sun 05:45 (4m)
five_hour_resets_at=2026-05-27 06:15
weekly_resets_at=2026-05-31 05:45
limit=-
profile_dir=/home/me/.codex_auth_profiles/main
```

`cx remove <name>` 刪除已儲存的 auth profile 目錄：

```bash
cx remove old-profile
```

為安全起見，無法移除當前使用中的 profile，請先切換至其他 profile：

```bash
cx use main
cx remove old-profile
```

## 用量限制追蹤

Codex session 的 JSONL 檔可包含 `rate_limits` 資料：

```json
{
  "rate_limits": {
    "primary": { "used_percent": 100.0, "resets_at": 1779700000 },
    "secondary": { "used_percent": 80.0, "resets_at": 1779800000 },
    "rate_limit_reached_type": "primary"
  }
}
```

每次透過 wrapper 執行 `codex` 結束後，`cx` 會掃描該次執行的 session 檔。若有用量資料，會更新快取的 `.usage` 快照。若觸達 rate limit，則寫入：

```text
~/.codex_auth_profiles/<name>/.limit
```

此標記檔儲存：

```text
hit_at=1779694300
reset_at=1779700000
type=primary
source=session-scan
label=hit until 2026-05-25 17:06
```

`cx list` 在 `now >= reset_at` 時會自動清除 `.limit`，讓 profile 在下次列出時恢復可用。

若無法偵測到重置時間，狀態會維持 `hit unknown`，直到手動清除：

```bash
cx ok <name>
```

也支援手動標記：

```bash
cx limit <name>
cx limit <name> <reset_epoch>
```

## 選用的 Stop Hook

`codex` wrapper 在 Codex 結束後已會掃描限制狀態。選用的 hook 可更早捕捉 Codex 的正常 `Stop` 事件。

### Linux / macOS Hook

印出 hook 指令：

```bash
cx hook-command
```

將其加入 `~/.codex/hooks.json` 的 `Stop` 區塊：

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

若已有其他 `Stop` hook，將此項新增為另一個 command entry，除非刻意要移除否則請保留現有 hook。

### Windows Hook

印出 hook 指令：

```powershell
cx hook-command
```

輸出格式如下：

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\codex-auth-switcher\hooks\codex-limit-hook.ps1"
```

將該指令加入 `%USERPROFILE%\.codex\hooks.json` 的 `Stop` 區塊：

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

## 並行執行

透過 wrapper 執行的 `codex` 使用共用的 Codex home。同一個使用中 profile 的多個 session 可同時執行，並看到相同的 `/resume` history。

也就是說，當使用同一個使用中 profile 時，可以同時開啟兩個或三個 Codex session。

`cx use` 與 `cx login` 在變更 `~/.codex/auth.json` 前會檢查是否有其他 Codex 程序正在執行。`cx switch` 則刻意在切換共用的使用中 profile 前先終止所有 Codex 程序。

```bash
cx ps
cx doctor
```

`cx ps` 列出偵測到的 Codex 程序，標記為 `active` 或 `background`。`active` 程序預設會阻擋登入，並在 `cx switch` 時被終止。`background` 程序（如 app-server 或 IDE 輔助程序）會顯示但不阻擋操作。

若要略過程序保護：

```bash
CX_ALLOW_ACTIVE_CODEX=1 cx login <name>
```

PowerShell — 用 `;` 在同一行設定變數並執行指令：

```powershell
$env:CX_ALLOW_ACTIVE_CODEX = "1"; cx login <name>
```

或分兩行：

```powershell
$env:CX_ALLOW_ACTIVE_CODEX = "1"
cx login <name>
```

> **PowerShell 5.1 注意事項** — 以下 bash 風格的寫法在 PowerShell 中無效，會產生錯誤：
> - `CX_ALLOW_ACTIVE_CODEX=1 cx login <name>` — inline 環境變數前綴不是合法的 PowerShell 語法
> - `set CX_ALLOW_ACTIVE_CODEX=1 && cx login <name>` — PowerShell 5.1 不支援 `&&`
> - `set CX_ALLOW_ACTIVE_CODEX=1 | cx login <name>` — `set`（`Set-Variable`）pipe 至指令沒有實際效果
>
> 在 PowerShell 中請一律使用 `$env:VAR = "value"; command`。

## 匯出與還原

Profile 可打包為 tar.gz 壓縮檔複製至另一台機器：

```bash
cx export profiles.tgz
cx restore profiles.tgz
```

PowerShell 使用相同指令：

```powershell
cx export profiles.tgz
cx restore profiles.tgz
```

壓縮檔包含 auth token，請妥善保管並在完成 profile 搬移後刪除。

## 環境變數

預設值：

Linux/macOS：

```bash
CX_PROFILES_DIR="$HOME/.codex_auth_profiles"
CX_CODEX_HOME="${CODEX_HOME:-$HOME/.codex}"
CX_LIMIT_THRESHOLD=100
```

Windows PowerShell：

```powershell
$env:CX_PROFILES_DIR = "$HOME\.codex_auth_profiles"
$env:CX_CODEX_HOME = "$HOME\.codex"
$env:CX_LIMIT_THRESHOLD = "100"
```

若需要指定特定的 Codex 執行檔：

```bash
export CX_CODEX_BIN="/path/to/codex"
```

Windows：

```powershell
$env:CX_CODEX_BIN = "C:\path\to\codex.cmd"
```

使用非預設的共用 Codex home：

```bash
export CX_CODEX_HOME="$HOME/.codex"
```

Windows：

```powershell
$env:CX_CODEX_HOME = "$HOME\.codex"
```

允許在偵測到 Codex 程序時仍可登入：

```bash
export CX_ALLOW_ACTIVE_CODEX=1
```

Windows：

```powershell
$env:CX_ALLOW_ACTIVE_CODEX = "1"
```

## 安全注意事項

此工具不會在達到限制後自動切換至其他帳號。它只記錄哪個 profile 看起來受到限制以及預計重置時間，讓你用 `cx use <name>` 自行選擇下一個 profile。

Auth profile 包含 token，請勿 commit `~/.codex_auth_profiles` 或任何 `auth.json` 檔案。

即時用量刷新為選用功能。`cx usage`、`cx list --live` 及 `cx switch --live` 會以選定 profile 的 token 呼叫 ChatGPT 後端 endpoint；直接執行 `cx list` 與 `cx switch` 只讀取本地快取。

## 相關先行作品

比較此 wrapper 與 `Lampese/codex-switcher` 的說明請參閱 [docs/prior-art.md](docs/prior-art.md)。
