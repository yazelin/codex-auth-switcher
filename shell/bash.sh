# Source this file from ~/.bashrc after cloning the repo.
#
# Example:
#   source "$HOME/codex-auth-switcher/shell/bash.sh"

_cx_auth_switcher_file="${BASH_SOURCE[0]}"
while [ -L "$_cx_auth_switcher_file" ]; do
    _cx_auth_switcher_link_dir="$(cd -P "$(dirname "$_cx_auth_switcher_file")" && pwd)"
    _cx_auth_switcher_file="$(readlink "$_cx_auth_switcher_file")"
    case "$_cx_auth_switcher_file" in
        /*) ;;
        *) _cx_auth_switcher_file="$_cx_auth_switcher_link_dir/$_cx_auth_switcher_file" ;;
    esac
done
_cx_auth_switcher_dir="$(cd -P "$(dirname "$_cx_auth_switcher_file")/.." && pwd)"

cx() {
    "$_cx_auth_switcher_dir/bin/cx" "$@"
}

codex() {
    "$_cx_auth_switcher_dir/bin/cx" run -- "$@"
}
