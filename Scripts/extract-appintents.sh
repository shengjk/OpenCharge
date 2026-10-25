#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$PROJECT_DIR/dist/OpenCharge.app}"
BIN_DIR="${2:-$PROJECT_DIR/.build/release}"
PROCESSOR="${OPENCHARGE_APPINTENTS_PROCESSOR:-}"
if [[ -z "$PROCESSOR" ]]; then
 PROCESSOR="$(xcrun --find appintentsmetadataprocessor 2>/dev/null || true)"
fi
# Use an existing processor with the currently selected, already usable compiler/SDK.
# This does not invoke xcodebuild, accept licenses, or change xcode-select globally.
if [[ -z "$PROCESSOR" && -x /Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor ]]; then
 PROCESSOR=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/appintentsmetadataprocessor
fi
if [[ ! -x "$PROCESSOR" ]]; then
 echo 'App Intents metadata processor unavailable; this build will not expose native Shortcuts actions.' >&2
 if [[ "${OPENCHARGE_REQUIRE_APPINTENTS:-0}" == 1 ]]; then exit 1; fi
 exit 0
fi
STAGING="$PROJECT_DIR/.build/appintents"
mkdir -p "$STAGING" "$APP/Contents/Resources"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
printf '%s\n' '["AppIntent", "AppEnum", "AppShortcutsProvider", "AppEntity", "EntityQuery"]' > "$STAGING/protocols.json"
# Whole-module emission includes the shared providers without running an app or intent.
swiftc -emit-object -whole-module-optimization -parse-as-library -module-name OpenCharge \
 -o "$STAGING/Intents.o" -I "$BIN_DIR/Modules" -I "$BIN_DIR/ApplePowerConstants.build" \
 -emit-const-values-path "$STAGING/Intents.swiftconstvalues" \
 -Xfrontend -const-gather-protocols-file -Xfrontend "$STAGING/protocols.json" \
 "$PROJECT_DIR/Sources/OpenCharge/Intents.swift" "$PROJECT_DIR/Sources/OpenCharge/AutomationRuntime.swift"
test -s "$STAGING/Intents.swiftconstvalues"
printf '%s\n' "$PROJECT_DIR/Sources/OpenCharge/Intents.swift" "$PROJECT_DIR/Sources/OpenCharge/AutomationRuntime.swift" > "$STAGING/sources.list"
printf '%s\n' "$STAGING/Intents.swiftconstvalues" > "$STAGING/const.list"
SDK_ROOT="$(xcrun --sdk macosx --show-sdk-path)"
XCODE_VERSION="${OPENCHARGE_XCODE_BUILD_VERSION:-}"
if [[ -z "$XCODE_VERSION" && -f /Applications/Xcode.app/Contents/version.plist ]]; then
 XCODE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :ProductBuildVersion' /Applications/Xcode.app/Contents/version.plist)"
fi
if [[ -z "$XCODE_VERSION" ]]; then
 echo 'Set OPENCHARGE_XCODE_BUILD_VERSION to the build version of the metadata processor.' >&2; exit 1
fi
"$PROCESSOR" --output "$APP/Contents/Resources" \
 --toolchain-dir "$(dirname "$(dirname "$(xcrun --find swiftc)")")" \
 --module-name OpenCharge --sdk-root "$SDK_ROOT" --xcode-version "$XCODE_VERSION" \
 --platform-family macOS --deployment-target 13.0 --target-triple "$(uname -m)-apple-macosx13.0" \
 --source-file-list "$STAGING/sources.list" --swift-const-vals-list "$STAGING/const.list"
swift "$PROJECT_DIR/Scripts/verify-appintents.swift" "$APP"
