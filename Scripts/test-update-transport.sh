#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
TEST_ARCH="${OPENCHARGE_TEST_ARCH:-$(uname -m)}"
case "$TEST_ARCH" in arm64|x86_64) ;; *) echo "Unsupported test architecture" >&2; exit 1 ;; esac
BUILD_ARGS=(-c release --disable-sandbox)
if [[ "$TEST_ARCH" != "$(uname -m)" ]]; then BUILD_ARGS+=(--scratch-path "$PROJECT_DIR/.build/universal-$TEST_ARCH" --triple "$TEST_ARCH-apple-macosx13.0"); fi
swift build "${BUILD_ARGS[@]}" --product chargectl
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p .build/update-transport
swiftc -target "$TEST_ARCH-apple-macosx13.0" -parse-as-library -I "$BIN_DIR/Modules" \
 Sources/OpenCharge/ReleaseHTTP.swift Sources/OpenCharge/ReleaseTransfer.swift Tests/UpdateTransport/main.swift \
 "$BIN_DIR"/ChargeCore.build/*.o -o ".build/update-transport/check-$TEST_ARCH"
/usr/bin/arch "-$TEST_ARCH" ".build/update-transport/check-$TEST_ARCH"
