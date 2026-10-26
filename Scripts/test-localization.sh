#!/bin/bash
# Private native bundles only. No UI, hardware setters, root service or user settings.
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
cd "$PROJECT_DIR"
export CLANG_MODULE_CACHE_PATH="$PROJECT_DIR/.build/module-cache"
export SWIFTPM_MODULECACHE_OVERRIDE="$CLANG_MODULE_CACHE_PATH"
TEST_ARCH="${OPENCHARGE_TEST_ARCH:-$(uname -m)}"
case "$TEST_ARCH" in arm64|x86_64) ;; *) echo "Unsupported test architecture" >&2; exit 1 ;; esac
BUILD_ARGS=(-c release --disable-sandbox)
if [[ "$TEST_ARCH" != "$(uname -m)" ]]; then
 BUILD_ARGS+=(--scratch-path "$PROJECT_DIR/.build/universal-$TEST_ARCH" --triple "$TEST_ARCH-apple-macosx13.0")
fi
swift build "${BUILD_ARGS[@]}"
BIN_DIR="$(swift build "${BUILD_ARGS[@]}" --show-bin-path)"
mkdir -p .build/localization-validation
FIXTURE_DIR="$(mktemp -d "$PROJECT_DIR/.build/localization-validation/fixture.XXXXXX")"
mkdir -p "$FIXTURE_DIR/core" "$FIXTURE_DIR/hardware" "$FIXTURE_DIR/app"
swiftc -target "$TEST_ARCH-apple-macosx13.0" -parse-as-library -emit-module -module-name ChargeCore \
 -emit-localized-strings -emit-localized-strings-path "$FIXTURE_DIR/core" \
 Sources/ChargeCore/*.swift -o "$FIXTURE_DIR/core/ChargeCore.swiftmodule"
swiftc -target "$TEST_ARCH-apple-macosx13.0" -parse-as-library -emit-module -module-name ChargeHardware \
 -I "$BIN_DIR/ApplePowerConstants.build" -emit-localized-strings -emit-localized-strings-path "$FIXTURE_DIR/hardware" \
 Sources/ChargeHardware/*.swift -o "$FIXTURE_DIR/hardware/ChargeHardware.swiftmodule"
swiftc -target "$TEST_ARCH-apple-macosx13.0" -parse-as-library \
 -I "$BIN_DIR/Modules" -I "$BIN_DIR/ApplePowerConstants.build" \
 -emit-localized-strings -emit-localized-strings-path "$FIXTURE_DIR/app" \
 Sources/OpenCharge/*.swift "$BIN_DIR"/ChargeCore.build/*.o "$BIN_DIR"/ChargeHardware.build/*.o "$BIN_DIR"/ApplePowerConstants.build/*.o \
 -o "$FIXTURE_DIR/extraction-only"
python3 Scripts/verify-localizations.py "$FIXTURE_DIR/core" "$FIXTURE_DIR/hardware" "$FIXTURE_DIR/app"
APP="$FIXTURE_DIR/LocalizationFixture.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.opencharge.localization.fixture</string>
<key>CFBundleName</key><string>LocalizationFixture</string>
<key>CFBundleExecutable</key><string>check</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleDevelopmentRegion</key><string>en</string>
</dict></plist>
PLIST
python3 Scripts/localization-resources.py prepare "$APP"
swiftc -target "$TEST_ARCH-apple-macosx13.0" -parse-as-library \
 -DOPENCHARGE_DASHBOARD_SMOKE -I "$BIN_DIR/Modules" -I "$BIN_DIR/ApplePowerConstants.build" Sources/OpenCharge/*.swift Tests/LocalizationSmoke/*.swift \
 "$BIN_DIR"/ChargeCore.build/*.o "$BIN_DIR"/ChargeHardware.build/*.o "$BIN_DIR"/ApplePowerConstants.build/*.o \
 -o "$APP/Contents/MacOS/check"
python3 - "$APP/Contents/MacOS/check" "$TEST_ARCH" <<'PYTEST'
import base64,subprocess,sys
snapshots=[]
for requested,expected in [('en','en'),('zh-Hans','zh-Hans'),('zh-Hant','zh-Hant'),('zh-TW','zh-Hant'),('zh-HK','zh-Hant'),('ja','ja'),('ja-JP','ja'),('fr,ja','ja'),('fr','en')]:
 output=subprocess.check_output(['/usr/bin/arch','-'+sys.argv[2],sys.argv[1],'-AppleLanguages','('+requested+')',expected],text=True)
 lines=output.splitlines(); snapshots.append(base64.b64decode(next(line[14:] for line in lines if line.startswith('POLICY_BASE64 '))))
 for line in lines:
  if line.startswith('PASS '):print(line)
assert all(value==snapshots[0] for value in snapshots),'Language changed encoded charge policy'
print('PASS identical encoded charge policy across all supported languages, regional selections and fallback language')
PYTEST

# Mutate only isolated copies to ensure publication cannot silently omit a language.
python3 - "$APP" <<'PACKAGE_TEST'
from pathlib import Path
import plistlib,shutil,subprocess,sys,tempfile
source=Path(sys.argv[1])
script=Path('Scripts/localization-resources.py').resolve()
with tempfile.TemporaryDirectory(prefix='opencharge-language-package-') as temporary:
 for kind in ['declaration','missing','changed','extra','symlink']:
  app=Path(temporary)/(kind+'.app');shutil.copytree(source,app)
  resources=app/'Contents/Resources'
  if kind=='declaration':
   info=app/'Contents/Info.plist';value=plistlib.loads(info.read_bytes());value['CFBundleLocalizations'].remove('ja');info.write_bytes(plistlib.dumps(value))
  elif kind=='missing':shutil.rmtree(resources/'ja.lproj')
  elif kind=='changed':(resources/'ja.lproj/Localizable.strings').write_text('changed')
  elif kind=='extra':(resources/'xx.lproj').mkdir()
  else:
   original=resources/'ja.lproj/Localizable.strings';original.unlink();original.symlink_to(source/'Contents/Resources/ja.lproj/Localizable.strings')
  before={str(p.relative_to(app)):p.read_bytes() for p in app.rglob('*') if p.is_file()}
  result=subprocess.run([sys.executable,str(script),'verify',str(app)],capture_output=True,text=True)
  assert result.returncode!=0,kind+' accepted'
  assert 'ValueError:' in result.stderr,result.stderr
  assert before=={str(p.relative_to(app)):p.read_bytes() for p in app.rglob('*') if p.is_file()},'verify mutated '+kind
print('PASS localization package rejection: missing declarations/resources, changed bytes, extra languages and symlinks; verification is read-only')
PACKAGE_TEST
