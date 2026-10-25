#!/bin/bash
# Compile/package and inspect only. No authorization, install, service or IPC calls.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 "$PROJECT_DIR/Tests/LegacyHelperPackaging/check.py"
