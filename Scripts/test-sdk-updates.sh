#!/bin/bash
# Requires built modules and an AppKit desktop session. Only informational SDK
# checks against a fixture-owned loopback server; never installs an update.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export PYTHONDONTWRITEBYTECODE=1
python3 Tests/SignedUpdates/sdk.py "$@"
