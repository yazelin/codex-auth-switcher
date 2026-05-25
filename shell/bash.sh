# Source this file from ~/.bashrc after cloning the repo.
#
# Example:
#   source "$HOME/codex-auth-switcher/shell/bash.sh"

_cx_auth_switcher_file="${BASH_SOURCE[0]}"
_cx_auth_switcher_dir="$(cd "$(dirname "$_cx_auth_switcher_file")/.." && pwd)"

cx() {
    "$_cx_auth_switcher_dir/bin/cx" "$@"
}

codex() {
    "$_cx_auth_switcher_dir/bin/cx" run -- "$@"
}
