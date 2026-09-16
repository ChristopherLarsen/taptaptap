#!/bin/bash
# 3e per-commit gate: debug build + unit tests of the root SwiftPM package, offline.
# CLI tests use TAPTAPTAP_BIN_PATH so they always exercise the binary just built (never a stale one).
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "${ROOT}" || exit 1
sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip))' \
  swift build --disable-sandbox --disable-automatic-resolution > "${ROOT}/build_derived_data_dev.swift.log" 2>&1 \
  || { grep -E 'error:' "${ROOT}/build_derived_data_dev.swift.log" | sort -u | head -20; exit 1; }
TAPTAPTAP_BIN_PATH="${ROOT}/.build/debug/taptaptap" \
  sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip))' \
  swift test --disable-sandbox --disable-automatic-resolution 2>&1 \
  | tee "${ROOT}/build_derived_data_dev.test.log" | grep -E 'Test run with|✘|error:|recorded an issue' | head -40
exit "${PIPESTATUS[0]}"
