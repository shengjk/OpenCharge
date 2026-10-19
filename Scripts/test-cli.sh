#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BIN="${1:-$PROJECT_DIR/dist/bin/chargectl}"
mkdir -p "$PROJECT_DIR/.build/cli-tests"
export OPENCHARGE_DATA_DIR="$(mktemp -d "$PROJECT_DIR/.build/cli-tests/run.XXXXXX")"
trap 'rm -rf "$OPENCHARGE_DATA_DIR"' EXIT
"$BIN" limit 75
"$BIN" profile desk
"$BIN" mode paused
"$BIN" schedule 2028-02-29T09:00:00-08:00 lowPowerOn yearly > "$OPENCHARGE_DATA_DIR/task.json"
python3 - "$OPENCHARGE_DATA_DIR" "$BIN" <<'PY'
import json, pathlib, subprocess, sys
root=pathlib.Path(sys.argv[1]); executable=sys.argv[2]
c=json.loads((root/'configuration.json').read_text())
assert c['policy']['limit']==70 and c['policy']['mode']=='paused'
assert c['schedules'][0]['repeatRule']=='yearly' and c['schedules'][0]['action']=='lowPowerOn'
before=(root/'configuration.json').read_bytes()
for value in ('nan','inf','19','101'):
 result=subprocess.run([executable,'limit',value],capture_output=True,text=True)
 assert result.returncode!=0
 assert (root/'configuration.json').read_bytes()==before
identifier=c['schedules'][0]['id']
subprocess.run([executable,'schedule-remove',identifier],check=True)
assert json.loads((root/'configuration.json').read_text())['schedules']==[]
result=subprocess.run([executable,'low-power','on'],capture_output=True,text=True)
assert result.returncode!=0 and '--confirm' in result.stderr
for arguments in (['magsafe','green'], ['magsafe','blue','--confirm'], ['magsafe','restore']):
 result=subprocess.run([executable]+arguments,capture_output=True,text=True)
 assert result.returncode!=0 and 'requires' in result.stderr
print('CLI isolated configuration checks passed; no hardware commands executed')
PY
