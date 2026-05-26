#!/usr/bin/env bash
# Codex Auth Switcher — Linux / macOS one-line installer
# Usage (paste into any bash or zsh terminal):
#
#   bash <(curl -fsSL https://raw.githubusercontent.com/yazelin/codex-auth-switcher/main/install-oneliner.sh)

set -euo pipefail

REPO_URL="https://github.com/yazelin/codex-auth-switcher.git"
INSTALL_DIR="${HOME}/.local/share/codex-auth-switcher"
TARGET_BIN="${HOME}/.local/bin"
SHELL_CONFIG="${HOME}/.config/codex-auth-switcher"

# Detect shell rc file
if [ "$(basename "${SHELL:-}")" = "zsh" ] || [ -n "${ZSH_VERSION:-}" ]; then
    SHELL_RC="${HOME}/.zshrc"
else
    SHELL_RC="${HOME}/.bashrc"
fi

CYAN='\033[36m'; GREEN='\033[32m'; YELLOW='\033[33m'; GRAY='\033[90m'; RESET='\033[0m'
DIV="  ──────────────────────────────────────────────"

echo ""
printf "  ${CYAN}Codex Auth Switcher${RESET}  —  Linux / macOS Installer\n"
printf "%s\n" "$DIV"
echo ""

# ── 1. Clone or update ──────────────────────────────────────────────────────
if [ -d "${INSTALL_DIR}/.git" ]; then
    printf "  ${YELLOW}Updating existing install at %s ...${RESET}\n" "$INSTALL_DIR"
    git -C "$INSTALL_DIR" pull --ff-only origin main
else
    printf "  ${YELLOW}Cloning to %s ...${RESET}\n" "$INSTALL_DIR"
    git clone --depth 1 "$REPO_URL" "$INSTALL_DIR"
fi
echo ""

# ── 2. Install symlinks ─────────────────────────────────────────────────────
mkdir -p "$TARGET_BIN" "$SHELL_CONFIG"
ln -sfn "${INSTALL_DIR}/bin/cx"        "${TARGET_BIN}/cx"
ln -sfn "${INSTALL_DIR}/shell/bash.sh" "${SHELL_CONFIG}/bash.sh"
chmod +x "${INSTALL_DIR}/bin/cx"
printf "  ${GREEN}Installed:${RESET}  %s/cx\n" "$TARGET_BIN"

# ── 3. Add source line to shell rc ──────────────────────────────────────────
SOURCE_LINE="source \"${SHELL_CONFIG}/bash.sh\""
if grep -qF "$SOURCE_LINE" "$SHELL_RC" 2>/dev/null; then
    printf "  ${GREEN}Shell already configured — skipping.${RESET}\n"
else
    { echo ""; echo "# Codex Auth Switcher"; echo "$SOURCE_LINE"; } >> "$SHELL_RC"
    printf "  ${GREEN}Added to %s${RESET}\n" "$SHELL_RC"
fi

# ── 4. Load into current session ────────────────────────────────────────────
# shellcheck disable=SC1090
source "${SHELL_CONFIG}/bash.sh"
printf "  ${GREEN}cx and codex are ready in this session.${RESET}\n"

# ── 5. Post-install guide ───────────────────────────────────────────────────
echo ""
printf "%s\n" "$DIV"
printf "  ${CYAN}Install complete!  Next steps:${RESET}\n"
printf "%s\n" "$DIV"
echo ""
printf "  1. Import your current Codex login as a named profile:\n"
printf "       ${YELLOW}cx import main${RESET}\n\n"
printf "  2. View all profiles and their status:\n"
printf "       ${YELLOW}cx list${RESET}\n\n"
printf "  3. Log in with another account under a new profile name:\n"
printf "       ${YELLOW}cx login work${RESET}\n\n"
printf "  4. Switch profiles:\n"
printf "       ${YELLOW}cx use work${RESET}\n\n"
printf "  5. Launch Codex under the active profile:\n"
printf "       ${YELLOW}codex${RESET}\n\n"
printf "  Show all commands:    ${GRAY}cx help${RESET}\n"
printf "  Full guide:           ${GRAY}https://yazelin.github.io/codex-auth-switcher/${RESET}\n"
printf "%s\n" "$DIV"
echo ""
