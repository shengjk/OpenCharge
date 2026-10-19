#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox
mkdir -p .build/telemetry-reader-tests
swiftc -parse-as-library -I .build/release/Modules -I .build/release/ApplePowerConstants.build \
 Tests/HardwareSmoke/TelemetryReaderTests.swift \
 .build/release/ChargeHardware.build/*.o .build/release/ApplePowerConstants.build/*.o \
 -o .build/telemetry-reader-tests/check
.build/telemetry-reader-tests/check
