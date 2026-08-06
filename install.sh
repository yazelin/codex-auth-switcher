#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${HOME}/.local/bin"
shell_dir="${HOME}/.config/codex-auth-switcher"

# 一行安裝把 repo clone 到 ~/.local/share/codex-auth-switcher;手動安裝則是
# 從你自己 clone 的位置 symlink 過去。兩條路都跑過的話,機器上會有兩份 repo,
# 而 ~/.local/bin/cx 只指向最後裝的那份 —— 在另一份改 code 就完全不會生效,
# 而且那份的改動沒人會發現(實際發生過:一批改動在一行安裝的目錄裡躺了兩個月)。
oneliner_dir="${HOME}/.local/share/codex-auth-switcher"
if [ -d "$oneliner_dir/.git" ] && [ "$oneliner_dir" != "$repo_dir" ]; then
    printf 'Warning: another copy is already installed at\n  %s\n' "$oneliner_dir" >&2
    printf 'This install will point ~/.local/bin/cx at THIS repo instead:\n  %s\n' "$repo_dir" >&2
    printf 'Keep one copy only. Check the other for uncommitted work, then remove it:\n' >&2
    printf '  git -C %s status --short && git -C %s stash list\n' "$oneliner_dir" "$oneliner_dir" >&2
    printf '  rm -rf %s\n\n' "$oneliner_dir" >&2
fi

mkdir -p "$target_dir" "$shell_dir"
ln -sfn "$repo_dir/bin/cx" "$target_dir/cx"
ln -sfn "$repo_dir/shell/bash.sh" "$shell_dir/bash.sh"

cat <<EOF
Installed:
  $target_dir/cx -> $repo_dir/bin/cx
  $shell_dir/bash.sh -> $repo_dir/shell/bash.sh

Add this to ~/.bashrc:

  source "$shell_dir/bash.sh"

Then reload your shell:

  source ~/.bashrc

First-time setup:

  cx import main
  cx list
EOF
