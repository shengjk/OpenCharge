"""Production model timer under native AppKit loops; no control is enabled."""
from pathlib import Path
import json,os,plistlib,shutil,subprocess,sys,tempfile,uuid
app=Path(sys.argv[1]).resolve(strict=True)
base=plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert base['CFBundleIdentifier'].startswith('org.opencharge.refreshfixture.') and base['CFBundleExecutable']=='RefreshFixture'
registry=Path('/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister')
with tempfile.TemporaryDirectory(prefix='modal-heartbeat-run-',dir=app.parent) as temporary:
    root=Path(temporary).resolve();target=root/'RefreshFixture.app';shutil.copytree(app,target,symlinks=True)
    info=dict(base);info['CFBundleIdentifier']='org.opencharge.refreshfixture.'+uuid.uuid4().hex
    (target/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
    subprocess.run(['/usr/bin/codesign','--force','--sign','-',str(target)],check=True,capture_output=True)
    config=root/'config';config.mkdir(mode=0o700);home=root/'home';home.mkdir(mode=0o700)
    env=dict(os.environ,OPENCHARGE_DATA_DIR=str(config),CFFIXED_USER_HOME=str(home))
    child=subprocess.Popen([str(target/'Contents/MacOS/RefreshFixture')],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
    try:
        stdout,stderr=child.communicate(timeout=40)
        result=json.loads((config/'result.json').read_text())
        (app.parent/'control-refresh-results.json').write_text(json.dumps(result,indent=2)+'\n')
        assert child.returncode==0 and result['pid']==child.pid and not result['hardware_enabled'],(child.returncode,stderr.decode(errors='replace'))
        print(json.dumps(result),flush=True)
        assert result['modal_finished'] and result['modal_refreshes']>0 and result['tracking_refreshes']>0,'Production refresh stopped inside a native run-loop mode'
        print('PASS actual model refresh timer in native modal and event-tracking loops; isolated config/fake battery/control disabled')
    finally:
        if child.poll() is None:
            child.terminate()
            try:child.communicate(timeout=3)
            except subprocess.TimeoutExpired:child.kill();child.communicate()
        if registry.exists():subprocess.run([str(registry),'-u',str(target)],capture_output=True,timeout=10)
