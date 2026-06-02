#!/usr/bin/env bash
# Undo what install.sh / install-oneliner.sh did:
#   - remove the cx symlink (~/.local/bin/cx)
#   - remove the shell-config symlink (~/.config/codex-auth-switcher/bash.sh)
#   - remove the "# Codex Auth Switcher" + source line from your shell rc file(s)
# By default your saved accounts in ~/.codex_auth_profiles are KEPT.
# Pass --purge to also delete them.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
bin_link="${HOME}/.local/bin/cx"
shell_dir="${HOME}/.config/codex-auth-switcher"
profiles_dir="${CX_PROFILES_DIR:-$HOME/.codex_auth_profiles}"

purge=0
for arg in "$@"; do
  case "$arg" in
    --purge) purge=1 ;;
    -h|--help)
      echo "usage: bash uninstall.sh [--purge]"
      echo "  --purge   also delete saved accounts in $profiles_dir"
      exit 0 ;;
    *) echo "unknown option: $arg" >&2; exit 2 ;;
  esac
done

# Remove a symlink only if it actually points into a codex-auth-switcher install.
remove_link() {
  local link="$1"
  if [ -L "$link" ]; then
    local target; target="$(readlink -f "$link" 2>/dev/null || true)"
    case "$target" in
      *codex-auth-switcher*) rm -f "$link"; echo "removed symlink: $link" ;;
      *) echo "left $link (points outside codex-auth-switcher: $target)" ;;
    esac
  fi
}

remove_link "$bin_link"
remove_link "$shell_dir/bash.sh"
# drop the config dir if it is now empty
[ -d "$shell_dir" ] && rmdir "$shell_dir" 2>/dev/null && echo "removed empty dir: $shell_dir" || true

# Remove our block (comment + source line) from each rc file.
clean_rc() {
  local rc="$1"
  [ -f "$rc" ] || return 0
  if ! grep -Fq "codex-auth-switcher" "$rc" 2>/dev/null; then
    return 0
  fi
  local tmp; tmp="$(mktemp)"
  awk '
    $0 == "# Codex Auth Switcher" { next }
    /codex-auth-switcher\/(shell\/)?bash\.sh/ { next }
    { print }
  ' "$rc" > "$tmp"
  if ! cmp -s "$rc" "$tmp"; then
    cp "$rc" "$rc.cx-bak"
    cat "$tmp" > "$rc"
    echo "cleaned $rc (backup: $rc.cx-bak)"
  fi
  rm -f "$tmp"
}

for rc in "$HOME/.bashrc" "$HOME/.zshrc" "$HOME/.bash_profile" "$HOME/.profile"; do
  clean_rc "$rc"
done

if [ "$purge" -eq 1 ]; then
  if [ -d "$profiles_dir" ]; then
    rm -rf "$profiles_dir"
    echo "purged saved accounts: $profiles_dir"
  fi
else
  if [ -d "$profiles_dir" ]; then
    echo "kept saved accounts: $profiles_dir (re-run with --purge to remove)"
  fi
fi

echo
echo "shell wiring removed. The 'cx' command is gone from new shells."
echo "This repo was left in place. To delete it too, run:"
echo "  rm -rf \"$root\""
