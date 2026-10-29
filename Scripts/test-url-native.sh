#!/bin/bash
# Opt-in AppKit URL test. Temporary target, isolated config; no default handler changes.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash "$PROJECT_DIR/Scripts/build-url-fixture.sh"
python3 "$PROJECT_DIR/Tests/URLNative/scripted.py" "$PROJECT_DIR/.build/url-validation/OpenCharge URL Fixture.app"
