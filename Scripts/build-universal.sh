#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
 arm64) OTHER_ARCH=x86_64 ;;
 x86_64) OTHER_ARCH=arm64 ;;
 *) echo "Unsupported build host: $HOST_ARCH" >&2; exit 1 ;;
esac
bash "$PROJECT_DIR/Scripts/build-app.sh"
CROSS_BUILD="$PROJECT_DIR/.build/universal-$OTHER_ARCH"
TRIPLE="$OTHER_ARCH-apple-macosx13.0"
swift build -c release --disable-sandbox --scratch-path "$CROSS_BUILD" --triple "$TRIPLE"
CROSS_BIN="$(swift build -c release --disable-sandbox --scratch-path "$CROSS_BUILD" --triple "$TRIPLE" --show-bin-path)"
STAGING="$(mktemp -d "$PROJECT_DIR/.build/universal-package.XXXXXX")"
/usr/bin/ditto "$PROJECT_DIR/dist/OpenCharge.app" "$STAGING/OpenCharge.app"
mkdir -p "$STAGING/bin"
for name in OpenCharge charged chargectl; do
 if [[ "$name" == OpenCharge ]]; then
  HOST_BIN="$PROJECT_DIR/dist/OpenCharge.app/Contents/MacOS/OpenCharge"
  OUTPUT_BIN="$STAGING/OpenCharge.app/Contents/MacOS/OpenCharge"
 else
  HOST_BIN="$PROJECT_DIR/dist/bin/$name"
  OUTPUT_BIN="$STAGING/bin/$name"
 fi
 /usr/bin/lipo -create "$HOST_BIN" "$CROSS_BIN/$name" -output "$OUTPUT_BIN"
 /usr/bin/lipo "$OUTPUT_BIN" -verify_arch arm64 x86_64
 chmod 755 "$OUTPUT_BIN"
done
# Intent declarations are architecture-independent; native extraction already validated them.
cp "$STAGING/bin/charged" "$STAGING/OpenCharge.app/Contents/MacOS/charged"
/usr/bin/strip -S "$STAGING/OpenCharge.app/Contents/MacOS/OpenCharge" "$STAGING/OpenCharge.app/Contents/MacOS/charged" "$STAGING/bin/charged" "$STAGING/bin/chargectl"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$STAGING/OpenCharge.app/Contents/MacOS/charged"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$STAGING/bin/charged"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$STAGING/bin/chargectl"
/usr/bin/codesign --force --sign "${OPENCHARGE_SIGNING_IDENTITY:--}" "$STAGING/OpenCharge.app"
/usr/bin/codesign --verify --deep --strict "$STAGING/OpenCharge.app"
swift "$PROJECT_DIR/Scripts/verify-helper-package.swift" "$STAGING/OpenCharge.app"
/usr/bin/codesign --verify --strict "$STAGING/bin/charged"
/usr/bin/codesign --verify --strict "$STAGING/bin/chargectl"
if [[ -d "$PROJECT_DIR/dist-universal" ]]; then mv "$PROJECT_DIR/dist-universal" "$PROJECT_DIR/.build/previous-universal.$$.dist"; fi
mv "$STAGING" "$PROJECT_DIR/dist-universal"
printf 'Built universal arm64/x86_64 app and tools: %s\n' "$PROJECT_DIR/dist-universal"
