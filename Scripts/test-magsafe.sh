#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/.build/module-cache" "$PROJECT_DIR/.build/magsafe-tests"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
swiftc "$PROJECT_DIR/Sources/ChargeHardware/BatteryReader.swift" "$PROJECT_DIR/Sources/ChargeHardware/TelemetryMath.swift" "$PROJECT_DIR/Sources/ChargeHardware/MagSafeController.swift" "$PROJECT_DIR/Sources/ChargeHardware/MagSafeSession.swift" "$PROJECT_DIR/Tests/HardwareSmoke/MagSafeTests.swift" -o "$PROJECT_DIR/.build/magsafe-tests/check"
"$PROJECT_DIR/.build/magsafe-tests/check"
swiftc "$PROJECT_DIR/Sources/ChargeCore/HelperClient.swift" "$PROJECT_DIR/Tests/HardwareSmoke/HelperCommandTests.swift" -o "$PROJECT_DIR/.build/magsafe-tests/commands"
"$PROJECT_DIR/.build/magsafe-tests/commands"
