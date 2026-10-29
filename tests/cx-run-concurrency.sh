#!/usr/bin/env bash
# 同時開很多個 cx run，登入檔不能被蓋成空的。用法：tests/cx-run-concurrency.sh [cx 路徑] [次數]
CX="${1:-$(dirname "$0")/../bin/cx}"; N="${2:-30}"
T="$(mktemp -d)"; trap 'rm -rf "$T"' EXIT
mkdir -p "$T/profiles/acct" "$T/home"
echo '{"tokens":{"account_id":"a","id_token":"x"}}' > "$T/profiles/acct/auth.json"
echo acct > "$T/profiles/current"
cp "$T/profiles/acct/auth.json" "$T/home/auth.json"
printf '#!/bin/sh\nsleep 0.0$((RANDOM %% 5))\n' > "$T/fakecodex"; chmod +x "$T/fakecodex"
export CX_PROFILES_DIR="$T/profiles" CX_CODEX_HOME="$T/home" CX_CODEX_BIN="$T/fakecodex"
for i in $(seq "$N"); do "$CX" run -- exec x </dev/null >/dev/null 2>&1 & done; wait
bad=0
for f in "$T/profiles/acct/auth.json" "$T/home/auth.json"; do [ -s "$f" ] || { echo "FAIL: 空檔 $f"; bad=1; }; done
[ "$bad" = 0 ] && echo "OK: $N 個並行 cx run，登入檔都完整"; exit "$bad"
