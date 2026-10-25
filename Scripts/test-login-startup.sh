#!/bin/bash
# Temporary-directory and fake-system tests only. No real LaunchAgents or SMAppService writes.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_ARCH="${OPENCHARGE_TEST_ARCH:-$(uname -m)}"
case "$TEST_ARCH" in arm64|x86_64) ;; *) echo "Unsupported test architecture" >&2; exit 1 ;; esac
mkdir -p "$PROJECT_DIR/.build/login-startup" "$PROJECT_DIR/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
swiftc -target "$TEST_ARCH-apple-macosx11.0" -parse-as-library \
 "$PROJECT_DIR/Sources/OpenCharge/LoginStartup.swift" "$PROJECT_DIR/Tests/LoginStartup/main.swift" \
 -o "$PROJECT_DIR/.build/login-startup/check-$TEST_ARCH"
/usr/bin/arch "-$TEST_ARCH" "$PROJECT_DIR/.build/login-startup/check-$TEST_ARCH"
