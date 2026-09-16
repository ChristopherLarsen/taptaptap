#!/bin/bash
# Release build of the root SwiftPM package: arm64 + x86_64 slices, lipo, rpath sweep, ad-hoc sign.
# No xcodegen, no xcodebuild, no frameworks: every target links statically into one executable.
#   - SwiftPM never resolves on its own (--disable-automatic-resolution).
#   - Run it under the network-deny sandbox for the offline proof:
#       sandbox-exec -p '(version 1)(allow default)(deny network-outbound (remote ip))' scripts/build.sh
#     (--disable-sandbox is always passed: SwiftPM's own sandbox-exec cannot nest inside another.)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${ROOT}/build_products"
PRODUCT="taptaptap"
SWIFTPM_FLAGS=(--configuration release --disable-automatic-resolution --disable-sandbox)

step() { printf '\n==> %s\n' "$*"; }
START=$SECONDS

step "Clean ${OUT} and release build directories"
rm -rf "${OUT}" "${ROOT}/.build/release" "${ROOT}/.build/arm64-apple-macosx/release" "${ROOT}/.build/x86_64-apple-macosx/release"
mkdir -p "${OUT}"

cd "${ROOT}"
for arch in arm64 x86_64; do
  step "swift build (${arch})"
  swift build "${SWIFTPM_FLAGS[@]}" --arch "${arch}" --product "${PRODUCT}"
  bin_path="$(swift build "${SWIFTPM_FLAGS[@]}" --arch "${arch}" --show-bin-path)"
  cp "${bin_path}/${PRODUCT}" "${OUT}/${PRODUCT}-${arch}"
done
lipo -create -output "${OUT}/${PRODUCT}" "${OUT}/${PRODUCT}-arm64" "${OUT}/${PRODUCT}-x86_64"
rm -f "${OUT}/${PRODUCT}-arm64" "${OUT}/${PRODUCT}-x86_64"

step "Remove toolchain rpaths"
otool -l "${OUT}/${PRODUCT}" | awk '/LC_RPATH/{r=1} r&&/path/{print $2; r=0}' | { grep "/Applications/Xcode" || true; } | sort -u |
  while IFS= read -r p; do install_name_tool -delete_rpath "$p" "${OUT}/${PRODUCT}" || true; done

step "Ad-hoc sign"
codesign --force --sign - "${OUT}/${PRODUCT}"
codesign --verify --strict "${OUT}/${PRODUCT}"
for arch in arm64 x86_64; do lipo "${OUT}/${PRODUCT}" -verify_arch "${arch}"; done

{
  echo "XCODE_VERSION=$(xcodebuild -version | tr '\n' ' ')"
  echo "SWIFT_VERSION=$(swiftc --version 2>&1 | head -1)"
  echo "SWIFTPM_FLAGS=${SWIFTPM_FLAGS[*]}"
  echo "RPATHS=$(otool -l "${OUT}/${PRODUCT}" | awk '/LC_RPATH/{r=1} r&&/path/{print $2; r=0}' | tr '\n' ' ')"
  echo "SHA256=$(shasum -a 256 "${OUT}/${PRODUCT}" | cut -d' ' -f1)"
  echo "BUILD_SECONDS=$((SECONDS - START))"
} > "${OUT}/BUILD_EVIDENCE.txt"

step "Done in $((SECONDS - START)) s"
cat "${OUT}/BUILD_EVIDENCE.txt"
