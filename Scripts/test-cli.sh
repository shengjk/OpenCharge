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
assert c['sailingCheckpoint'] is True
c['sailingCheckpoint']=False
(root/'configuration.json').write_text(json.dumps(c))
subprocess.run([executable,'limit','70'],check=True)
assert json.loads((root/'configuration.json').read_text())['sailingCheckpoint'] is False
before=(root/'configuration.json').read_bytes()
result=subprocess.run([executable,'explain'],capture_output=True,text=True)
assert result.returncode==0 and json.loads(result.stdout)['phase']=='Pause'
assert (root/'configuration.json').read_bytes()==before, 'read-only explanation rewrote settings'
subprocess.run([executable,'limit','71'],check=True)
assert json.loads((root/'configuration.json').read_text())['sailingCheckpoint'] is True
identifier=c['schedules'][0]['id']
subprocess.run([executable,'schedule-remove',identifier],check=True)
assert json.loads((root/'configuration.json').read_text())['schedules']==[]
result=subprocess.run([executable,'low-power','on'],capture_output=True,text=True)
assert result.returncode!=0 and '--confirm' in result.stderr
for arguments in (['magsafe','green'], ['magsafe','orange-blinking'], ['magsafe','blue','--confirm'], ['magsafe','restore']):
 result=subprocess.run([executable]+arguments,capture_output=True,text=True)
 assert result.returncode!=0 and 'requires' in result.stderr
before_hardware=(root/'configuration.json').read_bytes()
for arguments in (['hardware'], ['hardware','allowCharge'], ['hardware','restore'],
                  ['hardware','retainChargeInhibit','--confirm'], ['hardware','firmwareAllow','--confirm'],
                  ['hardware','sleepPolicyOn','--confirm'], ['hardware','unknown','--confirm'],
                  ['hardware','allowCharge','--confirm','extra']):
 result=subprocess.run([executable]+arguments,capture_output=True,text=True)
 assert result.returncode!=0 and 'hardware allowCharge|inhibitCharge|forceDischarge|restore --confirm' in result.stderr
 assert (root/'configuration.json').read_bytes()==before_hardware, 'rejected hardware request rewrote settings'
# Direct limit changes cannot override a calibration, including its checkpoints.
c=json.loads((root/'configuration.json').read_text()); c['policy']['mode']='calibration'
(root/'configuration.json').write_text(json.dumps(c)); before_calibration=(root/'configuration.json').read_bytes()
for limit in ('20','75','100'):
 result=subprocess.run([executable,'limit',limit],capture_output=True,text=True)
 assert result.returncode!=0 and 'calibration' in result.stderr
 assert (root/'configuration.json').read_bytes()==before_calibration, 'CLI limit rewrote calibration'
c['policy']['mode']='paused';(root/'configuration.json').write_text(json.dumps(c))
# Read-only inspection and rejected direct mutations must preserve recovery intent.
c=json.loads((root/'configuration.json').read_text())
c['pendingOrdinaryQuitRecovery']=True; c['hardwareEnabled']=True
(root/'configuration.json').write_text(json.dumps(c))
before_recovery=(root/'configuration.json').read_bytes()
for arguments in (['explain'], ['help'], ['hardware','allowCharge'], ['magsafe','green']):
 result=subprocess.run([executable]+arguments,capture_output=True,text=True)
 assert result.returncode == (0 if arguments[0] in ('explain','help') else 1)
 assert (root/'configuration.json').read_bytes()==before_recovery, 'read/rejected request changed pending recovery'
print('CLI isolated configuration, pending recovery reads and rejected hardware checks passed; no hardware commands executed')
PY
