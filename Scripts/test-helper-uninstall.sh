#!/bin/bash
# Syntax + temporary-path/stub-service tests. Never invokes the real removal script as root.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
bash -n "$PROJECT_DIR/Scripts/uninstall-helper.sh"
python3 "$PROJECT_DIR/Tests/HelperUninstall/check.py"
