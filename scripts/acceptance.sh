#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

# Only rebuild if the app bundle doesn't already exist (CI pre-builds it)
if [ ! -f "dist/Kopie.app/Contents/MacOS/Kopie" ]; then
  bash scripts/build.sh debug >/dev/null 2>&1
fi
export KOPIE_STORAGE_DIR="$(mktemp -d)"
# Headless harness must not block on Keychain access (a terminal-invoked signed
# binary can wait forever on an authorization prompt) — run in plaintext mode.
export KOPIE_DISABLE_ENCRYPTION=1
K="./dist/Kopie.app/Contents/MacOS/Kopie"
trap 'rm -rf "$KOPIE_STORAGE_DIR"' EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# Run a command with a timeout (seconds).
with_timeout() {
  local secs=$1; shift
  perl -e 'alarm shift; exec @ARGV' "$secs" "$@"
}

# 1. text save
with_timeout 30 $K --smoke-capture "acceptance-text-123" >/dev/null
with_timeout 30 $K --smoke-list | grep -q "acceptance-text-123" && pass "text saved" || fail "text saved"

# 2. re-copy detection: same content increments copy count (no duplicate row)
with_timeout 30 $K --smoke-capture "acceptance-text-123" | grep -q "recopied(" && pass "dedup works" || fail "dedup works"

# 3. text restore -> pasteboard
id=$(with_timeout 30 $K --smoke-list | head -n1 | awk '{print $1}')
with_timeout 30 $K --smoke-restore "$id" >/dev/null
with_timeout 30 $K --smoke-readboard | grep -q "acceptance-text-123" && pass "text restored to clipboard" || fail "text restored to clipboard"

# 4. image save + restore
python3 - <<'PY'
import struct, zlib
def chunk(t, d):
    c = t + d
    return struct.pack(">I", len(d)) + c + struct.pack(">I", zlib.crc32(c) & 0xffffffff)
w = h = 48
raw = b''.join(b'\x00' + bytes([200, 30, 30]) * w for _ in range(h))
png = (b'\x89PNG\r\n\x1a\n'
       + chunk(b'IHDR', struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
       + chunk(b'IDAT', zlib.compress(raw))
       + chunk(b'IEND', b''))
open('/tmp/kopie_test.png', 'wb').write(png)
PY
with_timeout 30 $K --smoke-capture-image /tmp/kopie_test.png >/dev/null
iid=$(with_timeout 30 $K --smoke-list | grep "image" | head -n1 | awk '{print $1}')
with_timeout 30 $K --smoke-restore "$iid" >/dev/null
if with_timeout 30 $K --smoke-readboard | grep -Eq "public.png|com.apple.pict|public.tiff"; then
    pass "image restored to clipboard"
else
    fail "image restored to clipboard"
fi

# 5. persistence across processes: separate invocations share the same storage dir (covered above)

# 6. retention purge
with_timeout 30 $K --smoke-purge 0 >/dev/null
n=$(with_timeout 30 $K --smoke-count | awk '{print $2}')
pass "purge ran (remaining=$n)"

# 7. launch hygiene: only the status item (and nothing else) may be visible at
#    startup. Guards against the blank "Kopie Settings" window a vestigial
#    SwiftUI Settings scene once presented on every launch.
out=$(with_timeout 30 $K --smoke-windows)
case "$out" in
  "WINDOWS Item-0"*|"WINDOWS NONE") pass "no stray windows at launch" ;;
  *) fail "no stray windows at launch ($out)" ;;
esac

echo "ALL CHECKS PASSED"
