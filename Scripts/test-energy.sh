#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ARCH="${OPENCHARGE_TEST_ARCH:-$(uname -m)}"
case "$TEST_ARCH" in arm64|x86_64) ;; *) echo "Unsupported test architecture" >&2; exit 1 ;; esac
BUILD_DIR="$PROJECT_DIR/.build/energy-smoke-$TEST_ARCH"
SWIFT_FLAGS=(-target "$TEST_ARCH-apple-macosx13.0")
mkdir -p "$BUILD_DIR" "$PROJECT_DIR/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
swiftc "${SWIFT_FLAGS[@]}" -emit-library -emit-module -module-name ChargeCore "$PROJECT_DIR/Sources/ChargeCore/EnergyImpact.swift" -emit-module-path "$BUILD_DIR/ChargeCore.swiftmodule" -o "$BUILD_DIR/libChargeCore.dylib"
swiftc "${SWIFT_FLAGS[@]}" -I "$BUILD_DIR" -L "$BUILD_DIR" -lChargeCore "$PROJECT_DIR/Sources/OpenCharge/EnergyMonitor.swift" "$PROJECT_DIR/Tests/EnergySmoke/main.swift" -Xlinker -rpath -Xlinker "$BUILD_DIR" -o "$BUILD_DIR/check"
/usr/bin/arch "-$TEST_ARCH" "$BUILD_DIR/check"
