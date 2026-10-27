#!/bin/bash
# Native UI fixture only: fake helper/power callbacks, no installed-service operations.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-keychain --disable-netrc -c release --disable-sandbox
APP="$PROJECT_DIR/.build/quit-validation/OpenCharge Exit Fixture.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target "$(uname -m)-apple-macosx13.0" -parse-as-library -DOPENCHARGE_DASHBOARD_SMOKE \
 -I .build/release/Modules -I .build/release/ApplePowerConstants.build \
 Sources/OpenCharge/*.swift Tests/QuitUI/main.swift \
 .build/release/ChargeCore.build/*.o .build/release/ChargeHardware.build/*.o .build/release/ApplePowerConstants.build/*.o \
 -o "$APP/Contents/MacOS/QuitFixture"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.opencharge.quitfixture</string>
<key>CFBundleName</key><string>OpenCharge Exit Fixture</string>
<key>CFBundleExecutable</key><string>QuitFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
/usr/bin/codesign --force --sign - "$APP"
printf 'Built native fake-only fixture: %s\n' "$APP"
