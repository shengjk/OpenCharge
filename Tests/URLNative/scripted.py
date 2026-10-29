"""Explicit-target native URL delivery; no protocol registration or default writes."""
from pathlib import Path
import json, os, plistlib, shutil, subprocess, sys, tempfile, time, uuid
app=Path(sys.argv[1]).resolve(strict=True)
base=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert base['CFBundleIdentifier'].startswith('org.opencharge.urlfixture.') and 'CFBundleURLTypes' not in base
assert base['CFBundleExecutable']=='URLFixture'
executable=app/'Contents/MacOS/URLFixture'
def query_handler():
    env=dict(os.environ);env.pop('CFFIXED_USER_HOME',None)
    return subprocess.check_output([str(executable),'--query-default-handler'],env=env,text=True).strip()
def events(path):
    if not path.exists():return []
    return [json.loads(line) for line in path.read_text().splitlines(keepends=True) if line.endswith('\n')]
def wait_event(path,kind,count,child):
    deadline=time.monotonic()+8
    while time.monotonic()<deadline:
        values=[x for x in events(path) if x['event']==kind]
        if len(values)>=count:return values[-1]
        if child.poll() is not None:raise AssertionError(('fixture exited early',child.returncode,events(path)))
        time.sleep(.05)
    raise AssertionError(('fixture event timeout',kind,events(path)))
before=query_handler();results=[]
registry=Path('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister')
with tempfile.TemporaryDirectory(prefix='native-url-run-',dir=app.parent) as temporary:
    root=Path(temporary).resolve()
    for scenario in ['normal','locked','calibration','interrupted','quit','reset']:
        case=root/scenario;case.mkdir();target=case/'URLFixture.app';shutil.copytree(app,target,symlinks=True)
        info=dict(base);info['CFBundleIdentifier']='org.opencharge.urlfixture.'+uuid.uuid4().hex
        (target/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(target)],check=True,capture_output=True)
        data=case/'data';data.mkdir(mode=0o700);home=case/'home';home.mkdir(mode=0o700)
        env=dict(os.environ,OPENCHARGE_DATA_DIR=str(data),OPENCHARGE_URL_SCENARIO=scenario,CFFIXED_USER_HOME=str(home))
        child=subprocess.Popen([str(target/'Contents/MacOS/URLFixture')],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        log=data/'events.jsonl'
        try:
            ready=wait_event(log,'ready',1,child)
            assert ready['pid']==child.pid and ready['identity']==info['CFBundleIdentifier'] and not ready['hardware']
            assert ready['locked']==(scenario=='locked')
            values=[20,100,75.5] if scenario=='normal' else [75]
            previous=ready
            for number,value in enumerate(values,1):
                url='opencharge://limit?value='+('75%2E5' if value==75.5 else str(value))
                # Full app path + explicit URL: never asks the default URL handler.
                command=['/usr/bin/open','-g','-a',str(target),'--env','OPENCHARGE_DATA_DIR='+str(data),'--env','OPENCHARGE_URL_SCENARIO='+scenario,'--env','CFFIXED_USER_HOME='+str(home),'-u',url]
                opened=subprocess.run(command,capture_output=True,text=True,timeout=8)
                assert opened.returncode==0,(scenario,opened.stderr)
                received=wait_event(log,'url',number,child)
                assert received['pid']==child.pid and not received['hardware']
                if scenario in ['normal','locked']:
                    assert received['limit']==value and received['hash']!=previous['hash']
                else:
                    for key in ['limit','mode','checkpoint','changeID','hash','reads']:assert received[key]==ready[key],(scenario,key,ready,received)
                previous=received
            (data/'finish').write_text('finish')
            stdout,stderr=child.communicate(timeout=5)
            assert child.returncode==0 and events(log)[-1]['event']=='terminated'
            assert not any(x['event']=='watchdog' for x in events(log))
            assert query_handler()==before,'Default protocol handler changed'
            result={'scenario':scenario,'events':events(log),'default_handler_unchanged':True};results.append(result)
            (app.parent/'native-url-results.json').write_text(json.dumps(results,indent=2)+'\n')
            print('PASS native explicit-target URL:',scenario,flush=True)
        except Exception:
            (app.parent/'native-url-last-failure.json').write_text(json.dumps({'scenario':scenario,'events':events(log)},indent=2)+'\n')
            raise
        finally:
            if child.poll() is None:
                child.terminate()
                try:child.communicate(timeout=3)
                except subprocess.TimeoutExpired:child.kill();child.communicate()
            # Remove only the temporary app's own registration, after it exits.
            if registry.exists():subprocess.run([str(registry),'-u',str(target)],capture_output=True,timeout=10)
assert query_handler()==before
print('PASS production URL delegate via native delivery: isolated scenarios, no protocol/default registration, no hardware or installed app operation')
