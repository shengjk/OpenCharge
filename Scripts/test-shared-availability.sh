#!/bin/bash
# Compile compatibility modules and run an injected automation fixture on the
# current OS. This does not declare app support or execute hardware code.
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
 swiftc -target "$TRIPLE" -parse-as-library -emit-module -emit-library -static -module-name ChargeCore \
  Sources/ChargeCore/*.swift -emit-module-path "$BUILD_DIR/$TEST_ARCH/ChargeCore.swiftmodule" \
  -o "$BUILD_DIR/$TEST_ARCH/libChargeCore.a"
 swiftc -target "$TRIPLE" -parse-as-library -emit-module -emit-library -static -module-name ChargeHardware \
  -I "$BUILD_DIR/ApplePowerConstants" Sources/ChargeHardware/*.swift \
  -emit-module-path "$BUILD_DIR/$TEST_ARCH/ChargeHardware.swiftmodule" \
  -o "$BUILD_DIR/$TEST_ARCH/libChargeHardware.a"
 swiftc -target "$TRIPLE" -parse-as-library -emit-module -module-name ReleaseNetwork \
  -I "$BUILD_DIR/$TEST_ARCH" Sources/OpenCharge/ReleaseHTTP.swift Sources/OpenCharge/ReleaseTransfer.swift \
  -o "$BUILD_DIR/$TEST_ARCH/ReleaseNetwork.swiftmodule"
 swiftc -target "$TRIPLE" -parse-as-library -emit-module -module-name MenuPresentation \
  -I "$BUILD_DIR/$TEST_ARCH" -I "$BUILD_DIR/ApplePowerConstants" Sources/OpenCharge/MenuBarAppearance.swift \
  -o "$BUILD_DIR/$TEST_ARCH/MenuPresentation.swiftmodule"
 swiftc -target "$TRIPLE" -parse-as-library -I "$BUILD_DIR/$TEST_ARCH" -I "$BUILD_DIR/ApplePowerConstants" \
  Sources/OpenCharge/AutomationRuntime.swift Sources/OpenCharge/Intents.swift Sources/OpenCharge/MenuBarAppearance.swift \
  Tests/DashboardSmoke/MenuBarAppearanceChecks.swift Tests/AutomationAvailability/main.swift \
  "$BUILD_DIR/$TEST_ARCH/libChargeCore.a" "$BUILD_DIR/$TEST_ARCH/libChargeHardware.a" \
  "$BUILD_DIR/$TEST_ARCH/ApplePowerConstants.o" -framework IOKit \
  -Xlinker -weak_framework -Xlinker AppIntents -o "$BUILD_DIR/$TEST_ARCH/automation-check"
 python3 - "$BUILD_DIR/$TEST_ARCH/automation-check" <<'VERIFY'
import re,subprocess,sys
binary=sys.argv[1]
loads=subprocess.check_output(['/usr/bin/otool','-l',binary],text=True)
assert re.search(r'\bminos 11\.0\b',loads),'Unexpected automation deployment floor'
frameworks=[chunk for chunk in loads.split('Load command ') if '/AppIntents.framework/' in chunk]
assert len(frameworks)==1 and 'LC_LOAD_WEAK_DYLIB' in frameworks[0],'App Intents must load weakly'
print('PASS macOS 11 deployment and weak App Intents load command')
VERIFY
 OPENCHARGE_ICON_PREVIEW_DIR="" /usr/bin/arch "-$TEST_ARCH" "$BUILD_DIR/$TEST_ARCH/automation-check"
 echo "PASS macOS 11 API availability: shared modules, update transport and guarded automation ($TEST_ARCH); fixture runs on current OS only"
done
