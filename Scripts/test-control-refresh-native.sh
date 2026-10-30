#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "$PROJECT_DIR/Scripts/build-control-refresh-fixture.sh"
python3 "$PROJECT_DIR/Tests/ControlRefreshNative/scripted.py" "$PROJECT_DIR/.build/refresh-validation/Control Refresh Fixture.app"
