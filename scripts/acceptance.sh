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

# 8. PastePlan decision smoke (S-001/S-002/S-003): app-target check of the exact
#    decision machine the paste matrix below exercises.
if with_timeout 30 $K --smoke-paste-plan | grep -q "^PASS"; then
    pass "PastePlan decisions (S-001/S-002/S-003)"
else
    fail "PastePlan decisions (S-001/S-002/S-003)"
fi

# 9. [self] Rapid capture harness (S-010): 50 copies ≤500 ms apart must all land.
#    Pumps the run loop between writes so the monitor's 150ms timer ticks 2-3×
#    per write; don't speed it up (intentionally ~25s, not faster).
if with_timeout 60 $K --smoke-rapid-capture | grep -q "^PASS"; then
    pass "Rapid capture (S-010)"
else
    fail "Rapid capture (S-010)"
fi

# 10. [self] Own-write filter (S-011): full capture⇨paste-back⇄capture leaves
#     history unchanged for the same content.
if with_timeout 30 $K --smoke-own-write | grep -q "^PASS"; then
    pass "Own-write filter (S-011)"
else
    fail "Own-write filter (S-011)"
fi

# 11. [self] OCR pipeline (S-020): capture image with known text, async Vision
#     on serial queue, item becomes searchable. Capture call must return in <50ms.
if with_timeout 60 $K --smoke-ocr-pipeline | grep -q "^PASS"; then
    pass "OCR pipeline (S-020)"
else
    fail "OCR pipeline (S-020)"
fi

# 12. [self] OCR backfill (S-021): seed 5 images without OCR, run backfill,
#     assert all searchable + done == total.
if with_timeout 60 $K --smoke-ocr-backfill | grep -q "^PASS"; then
    pass "OCR backfill (S-021)"
else
    fail "OCR backfill (S-021)"
fi

# 13. [manual] paste matrix (S-002/S-003) — a human runs these on real targets
#     before a release; this script stays headless. Every row must end *pasted*
#     or with the floating fallback toast within the time budget (never silent):
#       - TextEdit                 — plain ⌥↩ paste should succeed on the first post
#       - Electron app (VS Code)   — may swallow the session tap; retry posts to the
#                                    target pid, then pastes or toasts
#       - terminal emulator        — may refuse synthetic keys; one retry, then the
#                                    "Unable to paste into {App}…" toast
#       - Parallels/VM (Java app)  — may refuse outright; toast fallback, no crash
#       - Secure Input             — enable Terminal ▸ Secure Keyboard Entry, then
#                                    paste: the password-field toast must appear and
#                                    no keystroke may leak into the secure field
#       - fallback toast actions   — "Open Settings…" jumps to Privacy & Security →
#                                    Accessibility; "Dismiss" and Escape close the toast
#       - quick-select ⌥1-9        — pastes the Nth history row directly
#       - plain paste              — hold ⌃ (Paste as plain modifier) to insert plain text
# Plus M2 [manual] rows (automated bits covered above; these stay open for human pass):
#       - Missed-copies badge (S-012): not feasible to force headless — unit test
#         contract covers it. Visually exercise via a release build.
#       - Pasteboard-prompt awareness (S-013): run ~1h of normal use on macOS 15+/26
#         with a prompt counter → expect 0 unexpected prompts; with captureOnlyWhileInteracting=true,
#         idle copies beyond the 90s window are NOT captured (deliberate, not a miss).
#       - Burst grouping (S-014): copy 3 items within 2s in TextEdit → one row
#         with a "3" badge; click through to main window → "Copies in this burst"
#         with 2 children; toggle off in settings → rows separate again, no loss.
echo "ALL CHECKS PASSED"