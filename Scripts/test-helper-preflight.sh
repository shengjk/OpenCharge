#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:-$PROJECT_DIR/dist/OpenCharge.app}"
mkdir -p "$PROJECT_DIR/.build/helper-validation" "$PROJECT_DIR/.build/module-cache"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
swiftc -parse-as-library "$PROJECT_DIR/Sources/OpenCharge/HelperService.swift" "$PROJECT_DIR/Tests/HelperValidation/main.swift" -o "$PROJECT_DIR/.build/helper-validation/check"
"$PROJECT_DIR/.build/helper-validation/check" "$APP"
