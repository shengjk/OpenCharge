#!/bin/bash
# Temporary Mach-O fixtures only. Does not launch OpenCharge or a hardware service.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
PYTHONDONTWRITEBYTECODE=1 python3 "$PROJECT_DIR/Tests/RuntimePackaging/check.py"
