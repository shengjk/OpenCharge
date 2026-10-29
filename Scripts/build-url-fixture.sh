#!/bin/bash
# Native URL fixture only: no URL-scheme registration or product/helper/hardware operations.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-keychain --disable-netrc -c release --disable-sandbox
APP="$PROJECT_DIR/.build/url-validation/OpenCharge URL Fixture.app"
mkdir -p "$APP/Contents/MacOS"
source "$PROJECT_DIR/Scripts/sparkle-fixture-flags.sh"
swiftc -O -target "$(uname -m)-apple-macosx13.0" -parse-as-library -DOPENCHARGE_DASHBOARD_SMOKE \
 -I .build/release/Modules -I .build/release/ApplePowerConstants.build \
 "${SPARKLE_FIXTURE_FLAGS[@]}" Sources/OpenCharge/*.swift Tests/URLNative/main.swift \
 .build/release/ChargeCore.build/*.o .build/release/ChargeHardware.build/*.o .build/release/ApplePowerConstants.build/*.o \
 -o "$APP/Contents/MacOS/URLFixture"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.opencharge.urlfixture.template</string>
<key>CFBundleName</key><string>OpenCharge URL Fixture</string>
<key>CFBundleExecutable</key><string>URLFixture</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSPrincipalClass</key><string>NSApplication</string>
</dict></plist>
PLIST
python3 - "$APP" <<'PYMETA'
from pathlib import Path
import plistlib,sys,uuid
p=Path(sys.argv[1])/'Contents/Info.plist';d=plistlib.loads(p.read_bytes());d['CFBundleIdentifier']='org.opencharge.urlfixture.'+uuid.uuid4().hex
assert 'CFBundleURLTypes' not in d
p.write_bytes(plistlib.dumps(d))
PYMETA
/usr/bin/codesign --force --sign - "$APP"
printf 'Built native fake-only fixture: %s\n' "$APP"
