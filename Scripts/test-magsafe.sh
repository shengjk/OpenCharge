#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/.build/module-cache" "$PROJECT_DIR/.build/magsafe-tests"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
TEST_ARCH="${OPENCHARGE_TEST_ARCH:-$(uname -m)}"
case "$TEST_ARCH" in arm64|x86_64) ;; *) echo "Unsupported test architecture" >&2; exit 1 ;; esac
swiftc -target "$TEST_ARCH-apple-macosx13.0" "$PROJECT_DIR/Sources/ChargeHardware/BatteryReader.swift" "$PROJECT_DIR/Sources/ChargeHardware/TelemetryMath.swift" "$PROJECT_DIR/Sources/ChargeHardware/ChargeRecoveryStore.swift" "$PROJECT_DIR/Sources/ChargeHardware/MagSafeController.swift" "$PROJECT_DIR/Sources/ChargeHardware/MagSafeSession.swift" "$PROJECT_DIR/Tests/HardwareSmoke/MagSafeTests.swift" -o "$PROJECT_DIR/.build/magsafe-tests/check-$TEST_ARCH"
/usr/bin/arch "-$TEST_ARCH" "$PROJECT_DIR/.build/magsafe-tests/check-$TEST_ARCH"
swiftc -target "$TEST_ARCH-apple-macosx13.0" "$PROJECT_DIR/Sources/ChargeCore/HelperClient.swift" "$PROJECT_DIR/Tests/HardwareSmoke/HelperCommandTests.swift" -o "$PROJECT_DIR/.build/magsafe-tests/commands-$TEST_ARCH"
/usr/bin/arch "-$TEST_ARCH" "$PROJECT_DIR/.build/magsafe-tests/commands-$TEST_ARCH"
swiftc -target "$TEST_ARCH-apple-macosx13.0" "$PROJECT_DIR/Sources/ChargeHardware/BatteryReader.swift" "$PROJECT_DIR/Sources/ChargeHardware/TelemetryMath.swift" "$PROJECT_DIR/Sources/ChargeHardware/ChargeRecoveryStore.swift" "$PROJECT_DIR/Sources/ChargeHardware/MagSafeController.swift" "$PROJECT_DIR/Sources/ChargeHardware/MagSafeSession.swift" "$PROJECT_DIR/Tests/HardwareSmoke/MagSafeRecoveryTests.swift" -o "$PROJECT_DIR/.build/magsafe-tests/recovery-$TEST_ARCH"
/usr/bin/arch "-$TEST_ARCH" "$PROJECT_DIR/.build/magsafe-tests/recovery-$TEST_ARCH"
