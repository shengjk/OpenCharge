#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$PROJECT_DIR/Scripts/install-helper.sh"
bash -n "$PROJECT_DIR/Scripts/uninstall-helper.sh"
python3 "$PROJECT_DIR/Tests/HelperUpgrade/check.py"
