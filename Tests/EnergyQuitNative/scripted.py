"""Normal quit and cancellation against Popen-owned disposable applications only."""
from pathlib import Path
import json, os, plistlib, shutil, subprocess, sys, tempfile, time, uuid
app=Path(sys.argv[1]).resolve(strict=True)
base=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert base['CFBundleIdentifier'].startswith('org.opencharge.energyquitfixture.') and base['CFBundleExecutable']=='EnergyQuitFixture'
assert 'CFBundleURLTypes' not in base
registry=Path('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister')
architecture=subprocess.check_output(['/usr/bin/lipo','-archs',str(app/'Contents/MacOS/EnergyQuitFixture')],text=True).strip()
assert architecture in ['arm64','x86_64']
results=[]
def events(path):
    if not path.exists():return []
    return [json.loads(line) for line in path.read_text().splitlines(keepends=True) if line.endswith('\n')]
def wait_for(predicate,child,seconds=8):
    deadline=time.monotonic()+seconds
    while time.monotonic()<deadline:
        if predicate():return
        if child.poll() is not None:raise AssertionError(('target exited early',child.returncode))
        time.sleep(.05)
    raise AssertionError('Owned fixture observation timed out')
with tempfile.TemporaryDirectory(prefix='native-energy-quit-run-',dir=app.parent) as temporary:
    root=Path(temporary).resolve()
    for scenario in ['allow','cancel']:
        case=root/scenario;case.mkdir();target=case/'EnergyQuitFixture.app';shutil.copytree(app,target,symlinks=True)
        info=dict(base);info['CFBundleIdentifier']='org.opencharge.energyquitfixture.'+uuid.uuid4().hex
        (target/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(target)],check=True,capture_output=True)
        home=case/'home';home.mkdir(mode=0o700)
        env=dict(os.environ,OPENCHARGE_ENERGY_QUIT_DIR=str(case),OPENCHARGE_ENERGY_QUIT_SCENARIO=scenario,CFFIXED_USER_HOME=str(home))
        executable=target/'Contents/MacOS/EnergyQuitFixture'
        child=subprocess.Popen([str(executable)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        log=case/'events.jsonl'
        try:
            wait_for(lambda:(case/'ready.json').exists() and any(x['event']=='ready' for x in events(log)),child)
            ready=json.loads((case/'ready.json').read_text())
            assert ready['pid']==child.pid and ready['bundle']==info['CFBundleIdentifier']
            request=subprocess.run([str(executable),'--request'],env=env,capture_output=True,text=True,timeout=8)
            assert request.returncode==0 and request.stdout.strip()=='requested',(request.returncode,request.stdout,request.stderr)
            if scenario=='allow':
                child.communicate(timeout=5)
                assert child.returncode==0 and [x['event'] for x in events(log)]==['ready','normal-quit-request','terminated']
            else:
                wait_for(lambda:any(x['event']=='normal-quit-request' for x in events(log)),child)
                assert child.poll() is None and [x['event'] for x in events(log)]==['ready','normal-quit-request']
                # The same production adapter can issue a new normal request after cancellation.
                retry=subprocess.run([str(executable),'--request'],env=env,capture_output=True,text=True,timeout=8)
                assert retry.returncode==0 and retry.stdout.strip()=='requested'
                wait_for(lambda:len(events(log))==3,child)
                assert child.poll() is None and [x['event'] for x in events(log)]==['ready','normal-quit-request','normal-quit-request']
                (case/'finish').write_text('finish')
                child.communicate(timeout=5)
                assert child.returncode==0 and events(log)[-1]['event']=='terminated'
            assert all(x['pid']==child.pid for x in events(log))
            results.append({'architecture':architecture,'scenario':scenario,'events':events(log),'request_result':'requested','cancellation_preserved':scenario=='cancel'})
            (app.parent/'native-energy-quit-results.json').write_text(json.dumps(results,indent=2)+'\n')
            print('PASS native owned application quit:',architecture,scenario,flush=True)
        except Exception:
            (app.parent/'native-energy-quit-failure.json').write_text(json.dumps({'scenario':scenario,'events':events(log),'stderr':child.communicate()[1].decode(errors='replace') if child.poll() is not None else 'target still running'},indent=2)+'\n')
            raise
        finally:
            if child.poll() is None:
                (case/'finish').write_text('finish')
                try:child.communicate(timeout=3)
                except subprocess.TimeoutExpired:
                    child.terminate()
                    try:child.communicate(timeout=3)
                    except subprocess.TimeoutExpired:child.kill();child.communicate()
            if registry.exists():subprocess.run([str(registry),'-u',str(target)],capture_output=True,timeout=10)
print('PASS production normal-quit adapter: owned temporary targets only; cancellation is not reported as exit; no user app/helper/hardware operation')
