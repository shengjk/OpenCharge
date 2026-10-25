#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$PROJECT_DIR/dist/OpenCharge.app}"
mkdir -p "$PROJECT_DIR/.build/helper-validation" "$PROJECT_DIR/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
TEST_ARCH="${OPENCHARGE_TEST_ARCH:-$(uname -m)}"
case "$TEST_ARCH" in arm64|x86_64) ;; *) echo "Unsupported test architecture" >&2; exit 1 ;; esac
swiftc -target "$TEST_ARCH-apple-macosx11.0" -parse-as-library "$PROJECT_DIR/Sources/OpenCharge/HelperService.swift" "$PROJECT_DIR/Tests/HelperValidation/main.swift" -o "$PROJECT_DIR/.build/helper-validation/check-$TEST_ARCH"
/usr/bin/arch "-$TEST_ARCH" "$PROJECT_DIR/.build/helper-validation/check-$TEST_ARCH" "$APP"
