#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build --disable-keychain --disable-netrc -c release --disable-sandbox
APP="$PROJECT_DIR/.build/refresh-validation/Control Refresh Fixture.app"
mkdir -p "$APP/Contents/MacOS"
source "$PROJECT_DIR/Scripts/sparkle-fixture-flags.sh"
swiftc -O -target "$(uname -m)-apple-macosx13.0" -parse-as-library -DOPENCHARGE_DASHBOARD_SMOKE \
 -I .build/release/Modules -I .build/release/ApplePowerConstants.build "${SPARKLE_FIXTURE_FLAGS[@]}" \
 Sources/OpenCharge/*.swift Tests/ControlRefreshNative/main.swift \
 .build/release/ChargeCore.build/*.o .build/release/ChargeHardware.build/*.o .build/release/ApplePowerConstants.build/*.o \
 -o "$APP/Contents/MacOS/RefreshFixture"
python3 - "$APP" <<'PYMETA'
from pathlib import Path
import plistlib,sys,uuid
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.opencharge.refreshfixture.'+uuid.uuid4().hex,'CFBundleExecutable':'RefreshFixture','CFBundleName':'Control Refresh Fixture','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'13.0','NSPrincipalClass':'NSApplication'}))
PYMETA
/usr/bin/codesign --force --sign - "$APP"
printf 'Built isolated control-refresh fixture: %s\n' "$APP"
