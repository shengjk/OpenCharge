#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox
mkdir -p .build/dashboard-validation
swiftc -target "$(uname -m)-apple-macosx13.0" -parse-as-library -DOPENCHARGE_DASHBOARD_SMOKE -I .build/release/Modules -I .build/release/ApplePowerConstants.build \
 Sources/OpenCharge/*.swift Tests/DashboardSmoke/main.swift \
 .build/release/ChargeCore.build/*.o .build/release/ChargeHardware.build/*.o .build/release/ApplePowerConstants.build/*.o \
 -o .build/dashboard-validation/check
FIXTURE_DIR="$(mktemp -d "$PROJECT_DIR/.build/dashboard-validation/fixture.XXXXXX")"
OPENCHARGE_DATA_DIR="$FIXTURE_DIR" .build/dashboard-validation/check
