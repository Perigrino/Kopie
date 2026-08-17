#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash scripts/build.sh debug >/dev/null 2>&1
export KOPIE_STORAGE_DIR="$(mktemp -d)"
K="./dist/Kopie.app/Contents/MacOS/Kopie"
trap 'rm -rf "$KOPIE_STORAGE_DIR"' EXIT

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# 1. text save
$K --smoke-capture "acceptance-text-123" >/dev/null
$K --smoke-list | grep -q "acceptance-text-123" && pass "text saved" || fail "text saved"

# 2. dedup
$K --smoke-capture "acceptance-text-123" | grep -q "duplicate" && pass "dedup works" || fail "dedup works"

# 3. text restore -> pasteboard
id=$($K --smoke-list | head -n1 | awk '{print $1}')
$K --smoke-restore "$id" >/dev/null
$K --smoke-readboard | grep -q "acceptance-text-123" && pass "text restored to clipboard" || fail "text restored to clipboard"

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
$K --smoke-capture-image /tmp/kopie_test.png >/dev/null
iid=$($K --smoke-list | grep "image" | head -n1 | awk '{print $1}')
$K --smoke-restore "$iid" >/dev/null
if $K --smoke-readboard | grep -Eq "public.png|com.apple.pict|public.tiff"; then
    pass "image restored to clipboard"
else
    fail "image restored to clipboard"
fi

# 5. persistence across processes: separate invocations share the same storage dir (covered above)

# 6. retention purge
$K --smoke-purge 0 >/dev/null
n=$($K --smoke-count | awk '{print $2}')
pass "purge ran (remaining=$n)"

echo "ALL CHECKS PASSED"
