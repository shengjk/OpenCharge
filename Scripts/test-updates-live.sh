#!/bin/bash
# Optional public-network smoke: downloads a published ZIP into a disposable fixture only.
# No credentials, archive execution, app/helper installation or hardware changes.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox
mkdir -p .build/update-live
swiftc -O -target "$(uname -m)-apple-macosx13.0" -parse-as-library -DOPENCHARGE_DASHBOARD_SMOKE \
 -I .build/release/Modules -I .build/release/ApplePowerConstants.build \
 Sources/OpenCharge/*.swift Tests/UpdateLive/main.swift \
 .build/release/ChargeCore.build/*.o .build/release/ChargeHardware.build/*.o .build/release/ApplePowerConstants.build/*.o \
 -o .build/update-live/check
if [[ "${1:-}" != --build-only ]]; then .build/update-live/check; fi
