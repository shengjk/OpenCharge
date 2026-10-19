#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
mkdir -p "$PROJECT_DIR/.build/module-cache" "$PROJECT_DIR/.build/telemetry-tests"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
swiftc "$PROJECT_DIR/Sources/ChargeHardware/BatteryReader.swift" "$PROJECT_DIR/Sources/ChargeHardware/TelemetryMath.swift" "$PROJECT_DIR/Sources/ChargeHardware/SleepController.swift" "$PROJECT_DIR/Tests/HardwareSmoke/TelemetryTests.swift" -o "$PROJECT_DIR/.build/telemetry-tests/check"
"$PROJECT_DIR/.build/telemetry-tests/check"
