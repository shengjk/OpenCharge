#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-}"
mkdir -p "$PROJECT_DIR/.build/helper-validation" "$PROJECT_DIR/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
TEST_ARCH="${OPENCHARGE_TEST_ARCH:-$(uname -m)}"
case "$TEST_ARCH" in arm64|x86_64) ;; *) echo "Unsupported test architecture" >&2; exit 1 ;; esac
cd "$PROJECT_DIR"
COMPAT="$PROJECT_DIR/.build/helper-validation/core-$TEST_ARCH"
mkdir -p "$COMPAT"
swiftc -target "$TEST_ARCH-apple-macosx11.0" -parse-as-library -emit-module -emit-library -static -module-name ChargeCore Sources/ChargeCore/*.swift -emit-module-path "$COMPAT/ChargeCore.swiftmodule" -o "$COMPAT/libChargeCore.a"
if [[ -z "$APP" ]]; then
 FIXTURE="$(mktemp -d "$PROJECT_DIR/.build/helper-validation/package.XXXXXX")"
 APP="$FIXTURE/OpenCharge.app"
 mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Library/LaunchServices" "$APP/Contents/Library/LaunchDaemons"
 /usr/bin/xcrun clang -target "$TEST_ARCH-apple-macosx11.0" -x c -o "$APP/Contents/MacOS/OpenCharge" - <<'C'
int main(void) { return 0; }
C
 cp "$APP/Contents/MacOS/OpenCharge" "$APP/Contents/MacOS/charged"
 cp "$APP/Contents/MacOS/OpenCharge" "$APP/Contents/Library/LaunchServices/org.opencharge.charged"
 python3 - "$APP" <<'PYFIXTURE'
from pathlib import Path
import plistlib,sys
app=Path(sys.argv[1]);(app/'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.opencharge.app','CFBundleExecutable':'OpenCharge','CFBundleVersion':'1','CFBundlePackageType':'APPL'}))
(app/'Contents/Library/LaunchDaemons/org.opencharge.charged.plist').write_bytes(plistlib.dumps({'Label':'org.opencharge.charged'}))
PYFIXTURE
 for item in "$APP/Contents/MacOS/charged" "$APP/Contents/Library/LaunchServices/org.opencharge.charged" "$APP"; do /usr/bin/codesign --force --sign - "$item"; done
fi
APP="$(cd "$APP" && pwd)"
mkdir -p "$PROJECT_DIR/.build/helper-validation/ApplePowerConstants"
cp "$PROJECT_DIR/Sources/ApplePowerConstants/include/ApplePowerConstants.h" "$PROJECT_DIR/.build/helper-validation/ApplePowerConstants/"
printf 'module ApplePowerConstants { header "ApplePowerConstants.h" export * }\n' > "$PROJECT_DIR/.build/helper-validation/ApplePowerConstants/module.modulemap"
swiftc -I "$COMPAT" -I "$PROJECT_DIR/.build/helper-validation/ApplePowerConstants" -target "$TEST_ARCH-apple-macosx11.0" -parse-as-library "$PROJECT_DIR/Sources/OpenCharge/HelperService.swift" "$PROJECT_DIR/Sources/OpenCharge/HelperInstallation.swift" "$PROJECT_DIR/Sources/OpenCharge/LegacyHelperRegistration.swift" "$PROJECT_DIR/Tests/HelperValidation/"*.swift "$COMPAT/libChargeCore.a" -o "$PROJECT_DIR/.build/helper-validation/check-$TEST_ARCH"
/usr/bin/arch "-$TEST_ARCH" "$PROJECT_DIR/.build/helper-validation/check-$TEST_ARCH" "$APP"
