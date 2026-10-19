#!/bin/bash
# Fake/file fixtures by default. Optional --read-only-api inspects symbols/preferences only.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox
mkdir -p .build/sleep-validation
swiftc -O -target "$(uname -m)-apple-macosx13.0" -parse-as-library \
 -I .build/release/Modules -I .build/release/ApplePowerConstants.build \
 Tests/SleepSmoke/main.swift \
 .build/release/ChargeCore.build/*.o .build/release/ChargeHardware.build/*.o .build/release/ApplePowerConstants.build/*.o \
 -o .build/sleep-validation/check
if [[ "${1:-}" != --build-only ]]; then .build/sleep-validation/check "$@"; fi
