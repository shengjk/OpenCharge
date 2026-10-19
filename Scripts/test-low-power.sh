#!/bin/bash
# Standalone fake-runner tests: never runs pmset or reads/writes user power preferences.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/opencharge-lowpower.XXXXXX")"
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT
TEST_CACHE_DIR="${OPENCHARGE_TEST_MODULE_CACHE:-$PROJECT_DIR/.build/module-cache}"
mkdir -p "$TEST_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$TEST_CACHE_DIR"
xcrun swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  "$PROJECT_DIR/Sources/ChargeHardware/PowerModeController.swift" \
  "$PROJECT_DIR/Tests/HardwareSmoke/LowPowerTests.swift" \
  -o "$TEST_BUILD_DIR/low-power-tests"
"$TEST_BUILD_DIR/low-power-tests"
