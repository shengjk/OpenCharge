#!/bin/bash
# Compile shared modules and update transport against the compatibility floor. This does not
# declare app support or execute hardware code on an older operating system.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
BUILD_DIR="$PROJECT_DIR/.build/shared-availability"
mkdir -p "$BUILD_DIR/module-cache" "$BUILD_DIR/ApplePowerConstants"
export CLANG_MODULE_CACHE_PATH="$BUILD_DIR/module-cache"
cp Sources/ApplePowerConstants/include/ApplePowerConstants.h "$BUILD_DIR/ApplePowerConstants/"
cat > "$BUILD_DIR/ApplePowerConstants/module.modulemap" <<'MODULE'
module ApplePowerConstants {
 header "ApplePowerConstants.h"
 export *
}
MODULE
for TEST_ARCH in arm64 x86_64; do
 mkdir -p "$BUILD_DIR/$TEST_ARCH"
 TRIPLE="$TEST_ARCH-apple-macosx11.0"
 clang -target "$TRIPLE" -I Sources/ApplePowerConstants/include -c \
  Sources/ApplePowerConstants/ApplePowerConstants.c -o "$BUILD_DIR/$TEST_ARCH/ApplePowerConstants.o"
 swiftc -target "$TRIPLE" -parse-as-library -emit-module -module-name ChargeCore \
  Sources/ChargeCore/*.swift -o "$BUILD_DIR/$TEST_ARCH/ChargeCore.swiftmodule"
 swiftc -target "$TRIPLE" -parse-as-library -emit-module -module-name ChargeHardware \
  -I "$BUILD_DIR/ApplePowerConstants" Sources/ChargeHardware/*.swift \
  -o "$BUILD_DIR/$TEST_ARCH/ChargeHardware.swiftmodule"
 swiftc -target "$TRIPLE" -parse-as-library -emit-module -module-name ReleaseNetwork \
  -I "$BUILD_DIR/$TEST_ARCH" Sources/OpenCharge/ReleaseHTTP.swift Sources/OpenCharge/ReleaseTransfer.swift \
  -o "$BUILD_DIR/$TEST_ARCH/ReleaseNetwork.swiftmodule"
 echo "PASS macOS 11 API availability: shared core, hardware, C bridge and update transport ($TEST_ARCH); no runtime or hardware action"
done
