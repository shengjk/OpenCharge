#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox
PACKAGE_DIR="$(mktemp -d "$PROJECT_DIR/.build/package.XXXXXX")"
APP="$PACKAGE_DIR/OpenCharge.app"
TOOLS="$PACKAGE_DIR/bin"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$TOOLS"
cp .build/release/OpenCharge "$APP/Contents/MacOS/OpenCharge"
cp .build/release/chargectl .build/release/charged "$TOOLS/"
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
<key>CFBundleDevelopmentRegion</key><string>en</string>
<key>CFBundleName</key><string>OpenCharge</string>
<key>CFBundleDisplayName</key><string>OpenCharge</string>
<key>CFBundleExecutable</key><string>OpenCharge</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.3.40</string>
<key>CFBundleVersion</key><string>52</string>
<key>LSMinimumSystemVersion</key><string>13.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>CFBundleURLTypes</key><array><dict><key>CFBundleURLSchemes</key><array><string>opencharge</string></array><key>CFBundleURLName</key><string>org.opencharge.app</string></dict></array>
</dict></plist>
PLIST
python3 "$PROJECT_DIR/Scripts/localization-resources.py" prepare "$APP"
cp "$PROJECT_DIR/docs/HELPER-SETUP.md" "$APP/Contents/Resources/HELPER-SETUP.md"
"$PROJECT_DIR/Scripts/extract-appintents.sh" "$APP" "$PROJECT_DIR/.build/release"
# Strip local source paths from release debug maps before signing.
/usr/bin/strip -S "$APP/Contents/MacOS/OpenCharge" "$APP/Contents/MacOS/charged" "$TOOLS/charged" "$TOOLS/chargectl"
# Sign the normal helper first so the legacy ownership requirements use its real team.
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$APP/Contents/MacOS/charged"
python3 "$PROJECT_DIR/Scripts/legacy-helper-package.py" prepare "$APP"
python3 "$PROJECT_DIR/Scripts/prepare-swift-runtime.py" prepare "$APP" "$TOOLS" --identity "${OPENCHARGE_SIGNING_IDENTITY:--}"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$APP/Contents/MacOS/charged"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" --identifier org.opencharge.charged "$APP/Contents/Library/LaunchServices/org.opencharge.charged"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" --identifier org.opencharge.app "$APP"
# Reuse the final signed helper so embedded and standalone code identities agree.
cp "$APP/Contents/MacOS/charged" "$TOOLS/charged"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$TOOLS/chargectl"
/usr/bin/codesign --verify --deep --strict "$APP"
python3 "$PROJECT_DIR/Scripts/prepare-swift-runtime.py" verify "$APP" "$TOOLS"
python3 "$PROJECT_DIR/Scripts/legacy-helper-package.py" verify "$APP"
swift "$PROJECT_DIR/Scripts/verify-helper-package.swift" "$APP"
python3 "$PROJECT_DIR/Scripts/localization-resources.py" verify "$APP"
# Keep app and tools in the same staging tree until every check has passed.
if [[ -d "$PROJECT_DIR/dist" ]]; then
 mv "$PROJECT_DIR/dist" "$PROJECT_DIR/.build/previous-native.$$.dist"
fi
mv "$PACKAGE_DIR" "$PROJECT_DIR/dist"
printf 'Built %s\n' "$PROJECT_DIR/dist/OpenCharge.app"
