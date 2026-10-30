#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/.build/ordinary-exit-tests/module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/ordinary-exit-tests/module-cache"
# Native execution by default; the current Apple silicon validation host can
# opt into its installed x86_64 translation runtime as a separate execution check.
for TEST_ARCH in ${OPENCHARGE_TEST_ARCHES:-$(uname -m)}; do
 case "$TEST_ARCH" in arm64|x86_64) ;; *) echo "Unsupported test architecture" >&2; exit 1 ;; esac
 swiftc -target "$TEST_ARCH-apple-macosx13.0" \
  "$PROJECT_DIR/Sources/ChargeHardware/BatteryReader.swift" \
  "$PROJECT_DIR/Sources/ChargeHardware/TelemetryMath.swift" \
  "$PROJECT_DIR/Sources/ChargeHardware/SMCChargeController.swift" \
  "$PROJECT_DIR/Sources/ChargeHardware/ChargeRecoveryStore.swift" \
  "$PROJECT_DIR/Sources/ChargeCore/FirmwareCommand.swift" \
  "$PROJECT_DIR/Sources/ChargeCore/OrdinaryExitSession.swift" \
  "$PROJECT_DIR/Tests/HardwareSmoke/OrdinaryExitRecoveryTests.swift" \
  -o "$PROJECT_DIR/.build/ordinary-exit-tests/check-$TEST_ARCH"
 /usr/bin/arch "-$TEST_ARCH" "$PROJECT_DIR/.build/ordinary-exit-tests/check-$TEST_ARCH"
done
