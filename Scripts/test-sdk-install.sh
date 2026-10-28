#!/bin/bash
# AppKit desktop required. SDK may replace/relaunch ONLY random-ID disposable
# test apps in /private/tmp. Never target the product app or hardware service.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export PYTHONDONTWRITEBYTECODE=1
python3 Tests/SignedUpdates/install.py "$@"
