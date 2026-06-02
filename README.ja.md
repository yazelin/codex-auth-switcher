# Codex Auth Switcher

[繁體中文](README.md) · [English](README.en.md) · **日本語**

1台のマシンで複数の Codex ChatGPT 認証プロファイルを管理できます。  
再ログインなしに瞬時にアカウントを切り替えられます。**Windows**、**Linux**、**macOS** に対応しています。

**[詳細ガイド → yazelin.github.io/codex-auth-switcher/ja/](https://yazelin.github.io/codex-auth-switcher/ja/)**

## クイックインストール

**Windows PowerShell** — 任意の PowerShell ウィンドウを開いて貼り付けてください:

```powershell
irm https://raw.githubusercontent.com/yazelin/codex-auth-switcher/main/install-oneliner.ps1 | iex
```

**Linux / macOS** — 任意の bash または zsh ターミナルを開いて貼り付けてください:

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/codex-auth-switcher/main/install-oneliner.sh)
```

インストーラーはリポジトリをクローンし、シェルプロファイルを設定した上で、初回セットアップガイドを表示します。

---

1台のコンピューター上で複数の Codex ChatGPT 認証 ID を管理しながら、通常の Codex 設定を共有し続けるための小さなシェルツールセットです。

設計上、Codex の設定および再利用可能なローカルリソースは共有されます:

- `~/.codex/config.toml`
- `~/.codex/hooks.json`
- プラグイン、スキル、メモリ、その他の状態

切り替えられるのは `~/.codex/auth.json` のみで、名前付き認証プロファイルの間で切り替わります。  
ラップされた `codex` の実行は通常の Codex ホームを使用するため、同じアクティブアカウントで複数のセッションが `/resume` やセッション履歴、sqlite の状態、スキル、プラグインを共有できます。Codex が実行中に `auth.json` を変更しないよう、Codex 動作中のアカウント切り替えはガードされています。

## プラットフォームサポート

このリポジトリは以下をサポートしています:

- bash による Linux および macOS
- PowerShell による Windows

動作とストレージ形式は両プラットフォームで同じです。Windows では bash ラッパーの代わりに PowerShell スクリプトを使用します。

## レイアウト

共有 Codex の状態は、Codex が既に想定している場所に保持されます:

```text
~/.codex/
  auth.json        # currently active auth only
  config.toml      # shared
  hooks.json       # shared
  sessions/        # direct Codex sessions
  history.jsonl    # direct Codex history
  logs_*.sqlite    # direct Codex logs
```

保存された認証プロファイルは別の場所に格納されます。

Linux/macOS:

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

Windows:

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

プロファイル名は任意です。`work`、`personal`、`team-a`、`backup`、またはチームメンバーの名前など、すべてただのラベルです。

## インストール

ワンライナーコマンドは上記の **[クイックインストール](#クイックインストール)** を参照してください。

### 手動インストール — Linux / macOS

このリポジトリをクローンし、リポジトリのルートから実行します:

```bash
./install.sh
```

表示された source 行を `~/.bashrc` に追加します。通常は以下のようになります:

```bash
source "$HOME/.config/codex-auth-switcher/bash.sh"
```

シェルをリロードします:

```bash
source ~/.bashrc
```

### 手動インストール — Windows PowerShell

このリポジトリをクローンし、インストーラーを実行してプロファイルに source 行を追加します:

```powershell
.\install.ps1 -UpdateProfile
```

次にプロファイルをリロードします:

```powershell
. $PROFILE
```

どちらのシェル統合でも以下が使えるようになります:

- `cx`: プロファイルマネージャー
- `codex`: `cx` を通じて Codex を実行するシェル関数ラッパー

このラッパーは、選択したプロファイルの認証を使って分離された一時 `CODEX_HOME` で Codex を起動し、Codex 終了後にリフレッシュされたトークンを保存するために必要です。

## アンインストール

シェル連携（`cx` / `codex` コマンド）を削除します。保存済みアカウントはデフォルトで残します。

**Linux / macOS**

```bash
# ワンライナーはデフォルトで ~/.local/share/codex-auth-switcher にインストールされます
bash ~/.local/share/codex-auth-switcher/uninstall.sh
# 保存済みアカウントも削除する場合:
bash ~/.local/share/codex-auth-switcher/uninstall.sh --purge
```

（手動インストールした場合は、クローンした repo ディレクトリで `bash uninstall.sh` を実行してください。）

**Windows PowerShell**

```powershell
& "$HOME\codex-auth-switcher\uninstall.ps1"
# 保存済みアカウントも削除する場合:
& "$HOME\codex-auth-switcher\uninstall.ps1" -Purge
```

アンインストーラは `cx` シンボリックリンク（`~/.local/bin/cx`）、
`~/.config/codex-auth-switcher/bash.sh`、そしてシェルプロファイル内の
`# Codex Auth Switcher` ブロックを削除し（変更前に `.cx-bak` バックアップを作成）、
repo 本体と `~/.codex_auth_profiles` 内の保存済みアカウントは**残します**。完了時に
repo を手動削除するコマンドを表示します。`--purge` / `-Purge` を付けると保存済み
アカウントも削除します。

## 初回セットアップ

現在のマシンにすでにログイン済みの Codex アカウントがある場合:

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

別の認証プロファイルを追加する場合:

```bash
cx login team-a
cx login coworker-1
```

Codex が使用する認証を選択する場合:

```bash
cx use team-a
codex
```

## 日常コマンド

Linux/macOS と Windows で同じコマンドを使用します:

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

`cx list` の表示例:

```text
CURRENT  PROFILE                  LOGIN      EMAIL                        PLAN       USAGE                            LIMIT
*        main                     ok         ma***@example.com            plus       5h 97% left @06:15 | W 48% left @Sun 05:45 (4m) -
         team-a                   ok         te***@example.com            team       5h 22% left @03:59 | W 59% left @Sun 10:06 (2h) hit until 2026-05-25 17:06
         coworker-1               not-login  -                            -          -                                -
```

`LOGIN` は、そのプロファイルに保存済みの `auth.json` があるかどうかに基づいています。`EMAIL` と `PLAN` は利用可能な場合に ChatGPT の `id_token` から解析されます。`USAGE` にはキャッシュされた 5 時間分および週次クォータの残量が表示され、`@` がローカルのリセット時刻、末尾のエイジはキャッシュが更新された時刻を示します。メールアドレスとアカウント ID はターミナル表示のためにマスクされます。

最新の使用状況を取得したい場合は `cx usage` または `cx list --live` を使用してください。ライブリフレッシュは選択したプロファイルの ChatGPT アクセストークンを `https://chatgpt.com/backend-api/wham/usage` に送信し、結果を以下に保存します:

```text
~/.codex_auth_profiles/<name>/.usage
```

通常の `cx list` および `cx switch` はネットワークを呼び出しません。存在する場合は最新のキャッシュ済み `.usage` の値を表示します。

`cx info <name>` は 1 つのプロファイルをキーと値の形式で表示します:

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

`cx remove <name>` は保存された認証プロファイルのディレクトリを削除します:

```bash
cx remove old-profile
```

安全のため、現在アクティブなプロファイルの削除は拒否されます。先に別のプロファイルに切り替えてください:

```bash
cx use main
cx remove old-profile
```

## 使用制限のトラッキング

Codex セッションの JSONL ファイルには `rate_limits` データが含まれることがあります:

```json
{
  "rate_limits": {
    "primary": { "used_percent": 100.0, "resets_at": 1779700000 },
    "secondary": { "used_percent": 80.0, "resets_at": 1779800000 },
    "rate_limit_reached_type": "primary"
  }
}
```

ラップされた `codex` の実行が終わるたびに、`cx` はその実行のセッションファイルをスキャンします。使用状況データがある場合はキャッシュ済みの `.usage` スナップショットを更新します。レート制限に達した場合は以下に書き込みます:

```text
~/.codex_auth_profiles/<name>/.limit
```

このマーカーには以下が格納されます:

```text
hit_at=1779694300
reset_at=1779700000
type=primary
source=session-scan
label=hit until 2026-05-25 17:06
```

`now >= reset_at` になると `cx list` は自動的に `.limit` をクリアするため、次にプロファイル一覧を表示したときにそのプロファイルが再び利用可能になります。

リセット時刻を検出できなかった場合、ステータスは手動でクリアするまで `hit unknown` のままになります:

```bash
cx ok <name>
```

手動でのマーキングも可能です:

```bash
cx limit <name>
cx limit <name> <reset_epoch>
```

## オプションの Stop フック

`codex` ラッパーは Codex 終了後に制限をスキャンします。オプションのフックを使うと、通常の Codex の `Stop` イベントをより早くキャッチできます。

### Linux / macOS フック

フックコマンドを表示します:

```bash
cx hook-command
```

`~/.codex/hooks.json` の `Stop` セクションに追加します:

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

既に他の `Stop` フックがある場合は、このエントリを別のコマンドエントリとして追加してください。意図的に削除したい場合以外は、既存のフックを削除しないでください。

### Windows フック

フックコマンドを表示します:

```powershell
cx hook-command
```

表示内容は以下のようになります:

```text
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "C:\path\to\codex-auth-switcher\hooks\codex-limit-hook.ps1"
```

そのコマンドを `%USERPROFILE%\.codex\hooks.json` の `Stop` セクションに追加します:

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

## 並行実行

ラップされた `codex` の実行は共有 Codex ホームを使用します。同じアクティブプロファイルで複数のセッションを同時に実行でき、同じ `/resume` 履歴を参照できます。

つまり、同じアクティブプロファイルを使用していれば、2 つまたは 3 つの Codex セッションを同時に開くことができます。

`cx use` および `cx login` は `~/.codex/auth.json` を変更する前に他のアクティブな Codex プロセスを確認します。`cx switch` はアクティブな Codex プロセスを意図的に終了してから共有アクティブプロファイルを切り替えます。

```bash
cx ps
cx doctor
```

`cx ps` は検出された Codex プロセスを `active` または `background` として一覧表示します。`active` プロセスはデフォルトでログインをブロックし、`cx switch` によって終了されます。アプリサーバーや IDE ヘルパープロセスなどの `background` プロセスは表示されますがブロックしません。

プロセスガードを無効化するには:

```bash
CX_ALLOW_ACTIVE_CODEX=1 cx login <name>
```

PowerShell — 変数を設定してから同じ行で `;` を使ってコマンドを実行します:

```powershell
$env:CX_ALLOW_ACTIVE_CODEX = "1"; cx login <name>
```

または 2 行に分けて書く場合:

```powershell
$env:CX_ALLOW_ACTIVE_CODEX = "1"
cx login <name>
```

> **PowerShell 5.1 の注意点** — 以下の bash スタイルのパターンは動作せず、エラーになります:
> - `CX_ALLOW_ACTIVE_CODEX=1 cx login <name>` — インライン環境変数プレフィックスは PowerShell の有効な構文ではありません
> - `set CX_ALLOW_ACTIVE_CODEX=1 && cx login <name>` — `&&` は PowerShell 5.1 ではサポートされていません
> - `set CX_ALLOW_ACTIVE_CODEX=1 | cx login <name>` — `set`（`Set-Variable`）をコマンドにパイプしても何も起きません
>
> PowerShell では常に `$env:VAR = "value"; command` の形式を使用してください。

## エクスポートとリストア

プロファイルは tar.gz アーカイブとして別のマシンにコピーできます:

```bash
cx export profiles.tgz
cx restore profiles.tgz
```

PowerShell でも同じコマンドを使用します:

```powershell
cx export profiles.tgz
cx restore profiles.tgz
```

アーカイブには認証トークンが含まれています。プライベートに保管し、プロファイルの移動が完了したら削除してください。

## 環境変数

デフォルト値:

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

必要に応じて Codex バイナリのパスを上書きできます:

```bash
export CX_CODEX_BIN="/path/to/codex"
```

Windows:

```powershell
$env:CX_CODEX_BIN = "C:\path\to\codex.cmd"
```

デフォルト以外の共有 Codex ホームを使用する場合:

```bash
export CX_CODEX_HOME="$HOME/.codex"
```

Windows:

```powershell
$env:CX_CODEX_HOME = "$HOME\.codex"
```

アクティブな Codex プロセスが検出されている状態でのログインを許可する場合:

```bash
export CX_ALLOW_ACTIVE_CODEX=1
```

Windows:

```powershell
$env:CX_ALLOW_ACTIVE_CODEX = "1"
```

## 安全に関する注意

このツールは制限に達しても自動的に別のアカウントに切り替えません。制限がかかっているプロファイルとリセット予定時刻を記録し、`cx use <name>` で次のプロファイルを選択できるようにします。

認証プロファイルにはトークンが含まれています。`~/.codex_auth_profiles` や `auth.json` ファイルをコミットしないでください。

ライブ使用状況リフレッシュはオプトイン制です。`cx usage`、`cx list --live`、`cx switch --live` は選択したプロファイルのトークンを使って ChatGPT バックエンドエンドポイントを呼び出します。通常の `cx list` と `cx switch` はローカルキャッシュのみを読み取ります。

## 関連プロジェクト

`Lampese/codex-switcher` との比較などの情報は [docs/prior-art.md](docs/prior-art.md) を参照してください。
