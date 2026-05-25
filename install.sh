#!/usr/bin/env bash
set -euo pipefail

repo_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${HOME}/.local/bin"
shell_dir="${HOME}/.config/codex-auth-switcher"

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
