#!/bin/bash
# Settings-app end-to-end gate (charter "Verification gate", step 3), idb-style syntax
# (docs/IDB-COMPAT.md). taptaptap invocations omit --udid throughout, relying on the
# single-booted-simulator default (IDB-COMPAT.md §3) -- $UDID is still used for the
# xcrun simctl setup/verification calls around each step, which are unrelated to taptaptap.
# Usage: scripts/e2e-settings.sh <binary> <evidence-dir> [udid]
# Exit 0 only if every check passes. Writes logs, screenshots, video and lsof output to <evidence-dir>.
set -uo pipefail

BIN="$1"; EV="$2"; UDID="${3:-77FC7DAB-191A-4A19-BC74-D4F882851A14}"
BIN_NAME="$(basename "$BIN")"
rm -rf "$EV"; mkdir -p "$EV"  # no stale evidence from earlier runs
FAIL=0
pass() { echo "PASS $*" | tee -a "$EV/e2e-summary.txt"; }
fail() { echo "FAIL $*" | tee -a "$EV/e2e-summary.txt"; FAIL=1; }
: > "$EV/e2e-summary.txt"
echo "binary=$BIN sha256=$(shasum -a 256 "$BIN" | cut -d' ' -f1) version=$("$BIN" --version)" | tee -a "$EV/e2e-summary.txt"

relaunch() {
  xcrun simctl terminate "$UDID" com.apple.Preferences >/dev/null 2>&1
  xcrun simctl launch "$UDID" com.apple.Preferences >/dev/null
  sleep 2
}

describe() { # describe <out.json>; retries while the AX translation is not ready
  local i
  for i in 1 2 3 4 5 6 7 8; do
    if "$BIN" ui describe-all > "$1" 2> "$1.err"; then return 0; fi
    sleep 2
  done
  return 1
}

centre_of() { # centre_of <json> <AXLabel> [lowest]: centre of the first (or lowest on screen) element with that label
  python3 - "$1" "$2" "${3:-first}" <<'EOF'
import json, sys
tree = json.load(open(sys.argv[1])); label = sys.argv[2]; mode = sys.argv[3]
hits = []
def walk(n):
    if isinstance(n, list):
        for c in n: walk(c)
        return
    if n.get("AXLabel") == label and n.get("frame"):
        hits.append(n["frame"])
    walk(n.get("children") or [])
walk(tree)
if hits:
    f = max(hits, key=lambda f: f["y"]) if mode == "lowest" else hits[0]
    print(f"{f['x'] + f['width']/2:.0f} {f['y'] + f['height']/2:.0f}")
EOF
}

# 1. list-targets
if "$BIN" list-targets > "$EV/list-targets.txt" 2>&1 && grep -q "$UDID" "$EV/list-targets.txt"; then
  pass "list-targets lists $UDID"; else fail "list-targets"; fi

# 2. ui describe-all + ui tap General -> About
relaunch
if describe "$EV/describe-root.json"; then pass "ui describe-all $(wc -c < "$EV/describe-root.json") bytes"; else fail "ui describe-all"; fi
read -r GX GY <<< "$(centre_of "$EV/describe-root.json" General)"
if [[ -n "${GX:-}" ]] && "$BIN" ui tap "$GX" "$GY" > "$EV/tap.log" 2>&1; then
  sleep 1.5
  describe "$EV/describe-general.json"
  xcrun simctl io "$UDID" screenshot "$EV/after-tap-general.png" >/dev/null 2>&1
  if grep -q '"About"' "$EV/describe-general.json"; then pass "ui tap General ($GX,$GY) -> About visible"; else fail "ui tap General: About not found"; fi
else fail "ui tap General (centre '${GX:-}')"; fi

# 3. ui swipe
relaunch
if "$BIN" ui swipe 200 700 200 250 > "$EV/swipe.log" 2>&1; then
  sleep 1; xcrun simctl io "$UDID" screenshot "$EV/after-swipe.png" >/dev/null 2>&1
  describe "$EV/describe-swipe.json"
  read -r _ GY2 <<< "$(centre_of "$EV/describe-swipe.json" General)"
  if [[ "${GY2:-none}" != "${GY:-}" ]]; then pass "ui swipe moved General centre y ${GY:-?} -> ${GY2:-offscreen}"; else fail "ui swipe: General did not move"; fi
else fail "ui swipe"; fi

# 4. Search + ui text
relaunch
describe "$EV/describe-search.json"
read -r SX SY <<< "$(centre_of "$EV/describe-search.json" Search lowest)"
[[ -z "${SX:-}" ]] && { SX=204; SY=820; }
TEXT="hello taptaptap $$"
if "$BIN" ui tap "$SX" "$SY" > "$EV/tap-search.log" 2>&1 && sleep 1.5 &&
   "$BIN" ui text "$TEXT" > "$EV/text.log" 2>&1; then
  sleep 1.5; describe "$EV/describe-typed.json"
  xcrun simctl io "$UDID" screenshot "$EV/after-text.png" >/dev/null 2>&1
  if grep -qi "ello taptaptap $$" "$EV/describe-typed.json"; then pass "Search ($SX,$SY) + ui text '$TEXT' visible in AXValue"; else fail "ui text: text not found"; fi
else fail "ui tap Search / ui text"; fi

# 4b. ui key, ui key-sequence, ui key-combo in the focused search field (HID keyboard path)
BASE="$(printf '%s' "$TEXT" | sed 's/.$//')"   # key 42 (backspace) removes the last character
if "$BIN" ui key 42 > "$EV/key.log" 2>&1 && sleep 0.5 &&
   "$BIN" ui key-sequence 4 5 > "$EV/key-sequence.log" 2>&1 && sleep 0.5 &&
   "$BIN" ui key-combo --modifiers 225 --key 6 > "$EV/key-combo.log" 2>&1; then
  sleep 1.5; describe "$EV/describe-keys.json"
  if grep -qi "${BASE#h}abC\"" "$EV/describe-keys.json"; then pass "ui key 42 + key-sequence 4 5 + key-combo shift+6 -> '...${BASE: -3}abC'"; else fail "keys: expected text '${BASE}abC' not found"; fi
else fail "ui key / key-sequence / key-combo"; fi

# 4c. ui drag and ui gesture on the root list
relaunch
describe "$EV/describe-drag-before.json"
read -r _ DY0 <<< "$(centre_of "$EV/describe-drag-before.json" General)"
if "$BIN" ui drag 200 650 200 350 > "$EV/drag.log" 2>&1; then
  sleep 1; describe "$EV/describe-drag-after.json"
  read -r _ DY1 <<< "$(centre_of "$EV/describe-drag-after.json" General)"
  [[ "${DY1:-none}" != "${DY0:-}" ]] && pass "ui drag moved General centre y ${DY0:-?} -> ${DY1:-offscreen}" || fail "ui drag: General did not move"
else fail "ui drag"; fi
relaunch
describe "$EV/describe-gesture-before.json"  # wait until the list is live
if "$BIN" ui gesture scroll-up --screen-width 402 --screen-height 874 > "$EV/gesture.log" 2>&1; then
  sleep 1; describe "$EV/describe-gesture.json"
  read -r _ DY2 <<< "$(centre_of "$EV/describe-gesture.json" General)"
  [[ "${DY2:-none}" != "${DY0:-}" ]] && pass "ui gesture scroll-up moved General centre y ${DY0:-319} -> ${DY2:-offscreen}" || fail "ui gesture: General did not move"
else fail "ui gesture"; fi

# 4d. ui button HOME sends Settings to the background
relaunch
if "$BIN" ui button HOME > "$EV/button.log" 2>&1; then
  sleep 2; describe "$EV/describe-home.json"
  if ! grep -q '"AXLabel" : "General"' "$EV/describe-home.json" && grep -q '"AXLabel" : "Calendar"' "$EV/describe-home.json"; then
    pass "ui button HOME: home screen frontmost (Calendar icon visible, General gone)"; else fail "ui button HOME: home screen not detected"; fi
else fail "ui button HOME"; fi

# 4e. ui slider: Accessibility > Display & Text Size > Larger Text. On iOS 26.5 Settings exposes
# the DYNAMIC_TYPE_SLIDER element twice, so selector resolution must fail identically to the
# Phase 1 reference binary's exit code (parity check of the AX selector path, not a value change).
# The message text itself is intentionally NOT byte-parity-checked as of Phase 5 F2 (TESTING.md):
# taptaptap's ambiguity message was corrected there (no longer points at the removed `describe-ui`
# command, and no longer tells an --id caller to "use --id") while the frozen Phase 1 reference
# binary keeps the old wording forever, so exact-text parity would now fail on a fix, not a
# regression. The reference binary's slider flags are unchanged by Phase 4 (extra, not idb
# syntax), so --udid is kept explicit for this one comparison to pin both sides to the same target
# unambiguously.
REF="${TTT_REFERENCE_BIN:-$(cd "$(dirname "$0")/../.." && pwd)/bin/axe}"
relaunch
for L in "Accessibility" "Display & Text Size" "Larger Text, Off"; do
  describe "$EV/describe-nav.json"
  read -r NX NY <<< "$(centre_of "$EV/describe-nav.json" "$L")"
  [[ -n "${NX:-}" ]] && "$BIN" ui tap "$NX" "$NY" >/dev/null 2>&1 && sleep 1.5
done
"$BIN" ui slider --id DYNAMIC_TYPE_SLIDER --value 83 --udid "$UDID" > "$EV/slider.log" 2>&1; SRC=$?
"$REF" slider --id DYNAMIC_TYPE_SLIDER --value 83 --udid "$UDID" > "$EV/slider-reference.log" 2>&1; RRC2=$?
if [[ $SRC -eq $RRC2 ]] &&
   grep -q "Multiple (2) accessibility elements matched --id 'DYNAMIC_TYPE_SLIDER'" "$EV/slider.log" &&
   grep -q 'taptaptap ui describe-all' "$EV/slider.log" &&
   ! grep -q 'describe-ui --udid' "$EV/slider.log" &&
   ! grep -q 'Use --id when labels are not unique' "$EV/slider.log"; then
  pass "ui slider ambiguity rc parity ($SRC) + corrected F2 message: $(head -1 "$EV/slider.log" | cut -c1-90)"; else
  fail "ui slider rc $SRC vs $RRC2, or message missing the F2 fix: $(head -1 "$EV/slider.log" | cut -c1-120)"; fi

# 5. screenshot (idb-style positional destination)
rm -f "$EV/screenshot.png"
if "$BIN" screenshot "$EV/screenshot.png" > "$EV/screenshot.log" 2>&1 &&
   sips -g pixelWidth -g pixelHeight "$EV/screenshot.png" > "$EV/screenshot-dims.txt" 2>&1; then
  pass "screenshot $(tr -s ' \n' ' ' < "$EV/screenshot-dims.txt" | sed 's|.*pixelWidth|pixelWidth|')"; else fail "screenshot"; fi

# 5b. screenshot - (stdout, idb's dash convention)
rm -f "$EV/screenshot-stdout.png"
if "$BIN" screenshot - > "$EV/screenshot-stdout.png" 2>"$EV/screenshot-stdout.log" &&
   [[ -s "$EV/screenshot-stdout.png" ]] && file "$EV/screenshot-stdout.png" | grep -q PNG; then
  pass "screenshot - (stdout) $(wc -c < "$EV/screenshot-stdout.png") bytes"; else fail "screenshot - (stdout)"; fi

# 6. record-video 5 s (idb-style positional output) + lsof on the client
rm -f "$EV/record.mp4"
"$BIN" record-video "$EV/record.mp4" > "$EV/record.log" 2>&1 &
RPID=$!
sleep 2.5
lsof -nP -p "$RPID" > "$EV/lsof-record-video-full.txt" 2>&1
sleep 2.5
kill -INT "$RPID"; wait "$RPID"; RRC=$?
DUR=$(avmediainfo "$EV/record.mp4" 2>/dev/null | awk '/Duration/{print $2; exit}')
if [[ $RRC -eq 0 && -s "$EV/record.mp4" && -n "$DUR" ]]; then
  pass "record-video rc=0 $(wc -c < "$EV/record.mp4") bytes duration=${DUR}"; else fail "record-video rc=$RRC dur='${DUR:-}'"; fi

# 6a. record-video --duration self-terminates with no signal (F1, TESTING.md)
rm -f "$EV/record-duration.mp4"
DSTART=$(date +%s)
"$BIN" record-video "$EV/record-duration.mp4" --duration 3 > "$EV/record-duration.log" 2>&1
DRC=$?
DELAPSED=$(( $(date +%s) - DSTART ))
DDUR=$(avmediainfo "$EV/record-duration.mp4" 2>/dev/null | awk '/Duration/{print $2; exit}')
if [[ $DRC -eq 0 && -s "$EV/record-duration.mp4" && -n "$DDUR" && $DELAPSED -ge 2 && $DELAPSED -le 15 ]]; then
  pass "record-video --duration 3 self-terminated rc=0 elapsed=${DELAPSED}s duration=${DDUR}"; else
  fail "record-video --duration 3 rc=$DRC elapsed=${DELAPSED}s dur='${DDUR:-}'"; fi

# 6b. record-video finalizes on SIGTERM mid-recording (F1, TESTING.md)
rm -f "$EV/record-sigterm.mp4"
"$BIN" record-video "$EV/record-sigterm.mp4" > "$EV/record-sigterm.log" 2>&1 &
RPID=$!
sleep 3
kill -TERM "$RPID"; wait "$RPID"; TRRC=$?
TDUR=$(avmediainfo "$EV/record-sigterm.mp4" 2>/dev/null | awk '/Duration/{print $2; exit}')
if [[ $TRRC -eq 0 && -s "$EV/record-sigterm.mp4" && -n "$TDUR" ]]; then
  pass "record-video SIGTERM finalized rc=0 duration=${TDUR}"; else fail "record-video SIGTERM rc=$TRRC dur='${TDUR:-}'"; fi

# 6c. record-video finalizes on SIGHUP mid-recording, e.g. a background job orphaned when its
# shell exits (F1, TESTING.md)
rm -f "$EV/record-sighup.mp4"
"$BIN" record-video "$EV/record-sighup.mp4" > "$EV/record-sighup.log" 2>&1 &
RPID=$!
sleep 3
kill -HUP "$RPID"; wait "$RPID"; HRRC=$?
HDUR=$(avmediainfo "$EV/record-sighup.mp4" 2>/dev/null | awk '/Duration/{print $2; exit}')
if [[ $HRRC -eq 0 && -s "$EV/record-sighup.mp4" && -n "$HDUR" ]]; then
  pass "record-video SIGHUP finalized rc=0 duration=${HDUR}"; else fail "record-video SIGHUP rc=$HRRC dur='${HDUR:-}'"; fi

# 7. batch (idb-style step syntax)
relaunch
if "$BIN" batch --step "swipe 200 700 200 300" --step "sleep 0.5" \
     --step "touch 200 300 --down --up" > "$EV/batch.log" 2>&1 && grep -q 'Batch completed successfully' "$EV/batch.log"; then
  pass "batch: $(grep 'Batch completed' "$EV/batch.log")"; else fail "batch"; fi
xcrun simctl io "$UDID" screenshot "$EV/after-batch.png" >/dev/null 2>&1

# 8. standalone ui touch -> hid-broker; lsof client + broker
relaunch
pkill -f "hid-broker --udid $UDID" 2>/dev/null; sleep 1  # force a fresh broker from this binary
"$BIN" ui touch 200 600 --down --up --delay 9 --udid "$UDID" > "$EV/touch.log" 2>&1 &
TPID=$!
BPID=""
for _ in $(seq 1 32); do  # poll up to 8 s for the broker the touch client spawns or reuses
  sleep 0.25
  BPID=$(pgrep -f "$BIN_NAME hid-broker --udid $UDID" | head -1)
  [[ -n "$BPID" ]] && break
done
sleep 0.5
lsof -nP -p "$TPID" > "$EV/lsof-touch-client-full.txt" 2>&1
if [[ -n "$BPID" ]]; then
  lsof -nP -p "$BPID" > "$EV/lsof-broker-full.txt" 2>&1
  ps -o pid,command -p "$BPID" > "$EV/broker-ps.txt"
  SOCK=$(awk '$5=="unix" && $NF ~ /\.sock$/ {print $NF; exit}' "$EV/lsof-broker-full.txt")
  { ls -ld "$(dirname "${SOCK:-/nonexistent}")" "${SOCK:-/nonexistent}"; } > "$EV/broker-socket-perms.txt" 2>&1
fi
wait "$TPID"; TRC=$?
[[ $TRC -eq 0 ]] && pass "ui touch --down --up --delay 9" || fail "ui touch rc=$TRC"
[[ -n "$BPID" ]] && pass "hid-broker running pid $BPID" || fail "hid-broker not found"
for f in "$EV"/lsof-*-full.txt; do
  inet=$(awk '$5 ~ /IPv4|IPv6/' "$f" | wc -l | tr -d ' ')
  unix=$(awk '$5=="unix"' "$f" | wc -l | tr -d ' ')
  awk '$5 ~ /IPv4|IPv6|unix/' "$f" > "${f%-full.txt}.txt"
  # Positive control: lsof must have seen a live process (its executable 'txt' mapping).
  grep -q ' txt ' "$f" || { fail "lsof $(basename "$f"): process not captured"; continue; }
  [[ "$inet" == 0 ]] && pass "lsof $(basename "$f"): IPv4/IPv6=0 unix=$unix" || fail "lsof $(basename "$f"): IPv4/IPv6=$inet"
done
if [[ -s "$EV/broker-socket-perms.txt" ]] && grep -q '^srw-------' "$EV/broker-socket-perms.txt" && grep -q '^drwx------' "$EV/broker-socket-perms.txt"; then
  pass "broker socket 0600 in 0700 dir: $(grep -o '[^ ]*\.sock$' "$EV/broker-socket-perms.txt")"; else fail "broker socket perms"; fi

# 9. unsupported-command pointer (docs/IDB-COMPAT.md §6)
if ! "$BIN" install /nonexistent.app > "$EV/unsupported-install.log" 2>&1 && grep -q 'xcrun simctl install' "$EV/unsupported-install.log"; then
  pass "install: pointer to xcrun simctl install"; else fail "install: expected an xcrun simctl pointer"; fi

echo "RESULT=$([[ $FAIL -eq 0 ]] && echo PASS || echo FAIL)" | tee -a "$EV/e2e-summary.txt"
exit $FAIL
