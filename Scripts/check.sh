#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
swift build -c release --disable-sandbox
BIN_DIR="$(swift build -c release --disable-sandbox --show-bin-path)"
for check in core shared-availability localization low-power helper-uninstall sleep telemetry telemetry-reader magsafe smc cli appintents dashboard update-transport login-startup runtime-package legacy-helper-package helper-installation helper-preflight native-helper-removal; do
  if [[ "$check" == cli ]]; then
    bash "$PROJECT_DIR/Scripts/test-cli.sh" "$BIN_DIR/chargectl"
  else
    bash "$PROJECT_DIR/Scripts/test-$check.sh"
  fi
done
