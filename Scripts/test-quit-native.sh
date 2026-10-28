#!/bin/bash
# Explicit native AppKit test: disposable fake-only fixture, no product/helper/hardware.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "$PROJECT_DIR/Scripts/build-quit-fixture.sh"
python3 "$PROJECT_DIR/Tests/QuitUI/scripted.py" "$PROJECT_DIR/.build/quit-validation/OpenCharge Exit Fixture.app"
