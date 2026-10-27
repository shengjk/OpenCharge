#!/bin/bash
# Source only for compiler fixtures; production packages use audited relative RPATHs.
SPARKLE_FIXTURE_SOURCE="$(python3 "$PROJECT_DIR/Scripts/sparkle-package.py" source "$PROJECT_DIR/.build/artifacts")"
SPARKLE_FIXTURE_DIR="$(dirname "$SPARKLE_FIXTURE_SOURCE")"
SPARKLE_FIXTURE_FLAGS=(-F "$SPARKLE_FIXTURE_DIR" -framework Sparkle -Xlinker -rpath -Xlinker "$SPARKLE_FIXTURE_DIR")
