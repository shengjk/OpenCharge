#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox
mkdir -p "$PROJECT_DIR/dist"
PACKAGE_DIR="$(mktemp -d "$PROJECT_DIR/.build/package.XXXXXX")"
APP="$PACKAGE_DIR/OpenCharge.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$PROJECT_DIR/dist/bin"
cp .build/release/OpenCharge "$APP/Contents/MacOS/OpenCharge"
cp .build/release/chargectl .build/release/charged "$PROJECT_DIR/dist/bin/"
cp .build/release/charged "$APP/Contents/MacOS/charged"
mkdir -p "$APP/Contents/Library/LaunchDaemons"
cat > "$APP/Contents/Library/LaunchDaemons/org.opencharge.charged.plist" <<'DAEMON'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>org.opencharge.charged</string>
<key>BundleProgram</key><string>Contents/MacOS/charged</string>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>30</integer>
</dict></plist>
DAEMON
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.opencharge.app</string>
<key>CFBundleName</key><string>OpenCharge</string>
<key>CFBundleDisplayName</key><string>OpenCharge</string>
<key>CFBundleExecutable</key><string>OpenCharge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.18</string>
<key>CFBundleVersion</key><string>30</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>opencharge</string></array><key>CFBundleURLName</key><string>org.opencharge.app</string></dict></array>
</dict></plist>
PLIST
cp "$PROJECT_DIR/docs/HELPER-SETUP.md" "$APP/Contents/Resources/HELPER-SETUP.md"
"$PROJECT_DIR/Scripts/extract-appintents.sh" "$APP" "$PROJECT_DIR/.build/release"
# Strip local source paths from release debug maps before signing.
/usr/bin/strip -S "$APP/Contents/MacOS/OpenCharge" "$APP/Contents/MacOS/charged" "$PROJECT_DIR/dist/bin/charged" "$PROJECT_DIR/dist/bin/chargectl"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$APP/Contents/MacOS/charged"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$APP"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$PROJECT_DIR/dist/bin/charged"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$PROJECT_DIR/dist/bin/chargectl"
/usr/bin/codesign --verify --deep --strict "$APP"
swift "$PROJECT_DIR/Scripts/verify-helper-package.swift" "$APP"
if [[ -d "$PROJECT_DIR/dist/OpenCharge.app" ]]; then
 mv "$PROJECT_DIR/dist/OpenCharge.app" "$PROJECT_DIR/.build/previous-app.$$.app"
fi
mv "$APP" "$PROJECT_DIR/dist/OpenCharge.app"
rmdir "$PACKAGE_DIR"
printf 'Built %s\n' "$PROJECT_DIR/dist/OpenCharge.app"
