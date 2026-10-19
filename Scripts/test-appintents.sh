#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox
mkdir -p .build/appintents-validation
swiftc -parse-as-library -I .build/release/Modules -I .build/release/ApplePowerConstants.build \
 Sources/OpenCharge/Intents.swift Tests/AppIntentsValidation/main.swift \
 .build/release/ChargeCore.build/*.o .build/release/ChargeHardware.build/*.o .build/release/ApplePowerConstants.build/*.o \
 -o .build/appintents-validation/check
OPENCHARGE_DATA_DIR="$PROJECT_DIR/.build/appintents-validation/fixture" .build/appintents-validation/check
