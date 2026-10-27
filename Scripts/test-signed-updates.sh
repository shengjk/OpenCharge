#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export PYTHONDONTWRITEBYTECODE=1
mkdir -p "$PROJECT_DIR/.build"
python3 Tests/SignedUpdates/configuration.py
python3 Tests/SignedUpdates/package.py "$@"
