#!/bin/bash
# Native normal-quit verification for disposable owned targets only.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
TARGET_ARCH="${1:-$(uname -m)}"
case "$TARGET_ARCH" in arm64|x86_64) ;; *) echo "Expected arm64 or x86_64" >&2; exit 2 ;; esac
APP="$PROJECT_DIR/.build/energy-quit-validation/$TARGET_ARCH/Energy Quit Fixture.app"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -target "$TARGET_ARCH-apple-macosx13.0" -parse-as-library Sources/OpenCharge/EnergyApplicationQuit.swift Tests/EnergyQuitNative/main.swift -o "$APP/Contents/MacOS/EnergyQuitFixture"
python3 - "$APP" <<'PYMETA'
from pathlib import Path
import plistlib,sys,uuid
p=Path(sys.argv[1])/'Contents/Info.plist'
p.write_bytes(plistlib.dumps({'CFBundleIdentifier':'org.opencharge.energyquitfixture.'+uuid.uuid4().hex,'CFBundleName':'Energy Quit Fixture','CFBundleExecutable':'EnergyQuitFixture','CFBundlePackageType':'APPL','LSMinimumSystemVersion':'13.0','NSPrincipalClass':'NSApplication'}))
PYMETA
/usr/bin/codesign --force --sign - "$APP"
printf 'Built disposable native quit fixture: %s\n' "$APP"
