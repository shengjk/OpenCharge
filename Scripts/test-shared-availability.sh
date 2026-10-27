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
 source "$PROJECT_DIR/Scripts/sparkle-fixture-flags.sh"
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
 swiftc -target "$TRIPLE" -parse-as-library -emit-module -module-name ServiceRegistration \
  -I "$BUILD_DIR/$TEST_ARCH" -I "$BUILD_DIR/ApplePowerConstants" Sources/OpenCharge/HelperService.swift Sources/OpenCharge/HelperInstallation.swift Sources/OpenCharge/LegacyHelperRegistration.swift -o "$BUILD_DIR/$TEST_ARCH/ServiceRegistration.swiftmodule"
 swiftc -target "$TRIPLE" -parse-as-library -warnings-as-errors -emit-module -module-name PresentationCompatibility \
  -I "$BUILD_DIR/$TEST_ARCH" -I "$BUILD_DIR/ApplePowerConstants" \
  Sources/OpenCharge/PresentationCompatibility.swift Sources/OpenCharge/SelectableStatusText.swift Sources/OpenCharge/Components.swift \
  Sources/OpenCharge/PowerFlowConnections.swift Sources/OpenCharge/PowerFlowArrows.swift Sources/OpenCharge/PowerFlowView.swift \
  Sources/OpenCharge/TrendPlot.swift Sources/OpenCharge/LegacyTrendChart.swift Sources/OpenCharge/LegacyTrendAccessibility.swift \
  Sources/OpenCharge/HistoryPoint.swift Sources/OpenCharge/TrendChart.swift \
  -o "$BUILD_DIR/$TEST_ARCH/PresentationCompatibility.swiftmodule"
 swiftc -target "$TRIPLE" -parse-as-library -warnings-as-errors -emit-module -module-name FullAppAvailability \
  -F "$SPARKLE_FIXTURE_DIR" -I "$BUILD_DIR/$TEST_ARCH" -I "$BUILD_DIR/ApplePowerConstants" Sources/OpenCharge/*.swift \
  -o "$BUILD_DIR/$TEST_ARCH/FullAppAvailability.swiftmodule"
 swiftc -target "$TRIPLE" -parse-as-library -emit-module -module-name StartupCompatibility \
  Sources/OpenCharge/LoginStartup.swift -o "$BUILD_DIR/$TEST_ARCH/StartupCompatibility.swiftmodule"
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
 swiftc -target "$TRIPLE" -parse-as-library -warnings-as-errors -I "$BUILD_DIR/$TEST_ARCH" -I "$BUILD_DIR/ApplePowerConstants" \
  Sources/OpenCharge/PresentationCompatibility.swift Sources/OpenCharge/SelectableStatusText.swift Sources/OpenCharge/PowerFlowConnections.swift \
  Sources/OpenCharge/TrendPlot.swift Sources/OpenCharge/LegacyTrendChart.swift Sources/OpenCharge/LegacyTrendAccessibility.swift \
  Sources/OpenCharge/HistoryPoint.swift Sources/OpenCharge/TrendChart.swift \
  Tests/DashboardSmoke/PowerFlowConnectionChecks.swift Tests/DashboardSmoke/TrendPlotChecks.swift Tests/DashboardSmoke/TrendAccessibilityChecks.swift Tests/DashboardSmoke/SelectableTextChecks.swift Tests/PresentationAvailability/main.swift \
  "$BUILD_DIR/$TEST_ARCH/libChargeCore.a" "$BUILD_DIR/$TEST_ARCH/libChargeHardware.a" \
  "$BUILD_DIR/$TEST_ARCH/ApplePowerConstants.o" -framework IOKit \
  -Xlinker -weak_framework -Xlinker Charts -Xlinker -weak_framework -Xlinker Accessibility -o "$BUILD_DIR/$TEST_ARCH/presentation-check"
 python3 - "$BUILD_DIR/$TEST_ARCH/presentation-check" <<'VERIFY_CHART'
import re,subprocess,sys
loads=subprocess.check_output(['/usr/bin/otool','-l',sys.argv[1]],text=True)
assert re.search(r'\bminos 11\.0\b',loads),'Unexpected presentation deployment floor'
for name in ['Charts','Accessibility']:
 frameworks=[chunk for chunk in loads.split('Load command ') if '/'+name+'.framework/' in chunk]
 assert len(frameworks)==1 and 'LC_LOAD_WEAK_DYLIB' in frameworks[0],name+' must load weakly'
print('PASS macOS 11 presentation binary and weak Charts/Accessibility load commands')
VERIFY_CHART
 /usr/bin/arch "-$TEST_ARCH" "$BUILD_DIR/$TEST_ARCH/presentation-check"
 echo "PASS macOS 11 API availability: complete app sources, shared modules, update transport and guarded automation ($TEST_ARCH); fixture runs on current OS only"
done
