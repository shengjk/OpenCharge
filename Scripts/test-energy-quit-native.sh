#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ARCH="$(uname -m)"
if [[ $# -gt 0 ]]; then
 [[ $# == 2 && "$1" == "--arch" ]] || { echo "Usage: $0 [--arch arm64|x86_64|all]" >&2; exit 2; }
 ARCH="$2"
fi
case "$ARCH" in arm64|x86_64) ARCHES=("$ARCH") ;; all) ARCHES=(arm64 x86_64) ;; *) exit 2 ;; esac
for CPU in "${ARCHES[@]}"; do
 bash "$PROJECT_DIR/Scripts/build-energy-quit-fixture.sh" "$CPU"
 python3 "$PROJECT_DIR/Tests/EnergyQuitNative/scripted.py" "$PROJECT_DIR/.build/energy-quit-validation/$CPU/Energy Quit Fixture.app"
done
