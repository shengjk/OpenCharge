#!/bin/bash
# Requires built native/universal apps. Creates signed copies with public RFC
# test data, verifies them offline, and never starts an updater or installer.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export PYTHONDONTWRITEBYTECODE=1
python3 Tests/SignedUpdates/feed.py "$@"
