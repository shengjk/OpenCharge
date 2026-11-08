#!/bin/bash
# Tri-state tests use a fake runner and never access system power preferences.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEST_BUILD_DIR="$(mktemp -d "${TMPDIR:-/tmp}/opencharge-energymode.XXXXXX")"
trap 'rm -rf "$TEST_BUILD_DIR"' EXIT
TEST_CACHE_DIR="${OPENCHARGE_TEST_MODULE_CACHE:-$PROJECT_DIR/.build/module-cache}"
mkdir -p "$TEST_CACHE_DIR"
export CLANG_MODULE_CACHE_PATH="$TEST_CACHE_DIR"
xcrun swiftc -module-cache-path "$CLANG_MODULE_CACHE_PATH" \
  "$PROJECT_DIR/Sources/ChargeHardware/PowerModeController.swift" \
  "$PROJECT_DIR/Tests/HardwareSmoke/EnergyModeTests.swift" \
  -o "$TEST_BUILD_DIR/energy-mode-tests"
"$TEST_BUILD_DIR/energy-mode-tests"
