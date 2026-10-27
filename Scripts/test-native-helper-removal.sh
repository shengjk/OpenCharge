#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
TEST_ARCH="${OPENCHARGE_TEST_ARCH:-$(uname -m)}"
BUILD_ARGS=(-c release --disable-sandbox)
case "$TEST_ARCH" in arm64|x86_64) ;; *) exit 1 ;; esac
if [[ "$TEST_ARCH" != "$(uname -m)" ]]; then BUILD_ARGS+=(--scratch-path "$PROJECT_DIR/.build/universal-$TEST_ARCH" --triple "$TEST_ARCH-apple-macosx13.0");fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p .build/native-helper-removal
swiftc -target "$TEST_ARCH-apple-macosx13.0" -parse-as-library -I "$BIN_DIR/Modules" -I "$BIN_DIR/ApplePowerConstants.build" \
 Tests/NativeHelperRemoval/main.swift "$BIN_DIR"/ChargeCore.build/*.o "$BIN_DIR"/ChargeHardware.build/*.o "$BIN_DIR"/ApplePowerConstants.build/*.o \
 -o ".build/native-helper-removal/check-$TEST_ARCH"
/usr/bin/arch "-$TEST_ARCH" ".build/native-helper-removal/check-$TEST_ARCH"
