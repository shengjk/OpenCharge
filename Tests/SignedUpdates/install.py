"""Real SDK archive installation only into random-ID disposable apps in /private/tmp.
No production AppModel, URL/identity exception, admin/TCC grant, hardware service,
deployment key, real product-app operation or release publication is involved.
Requires an AppKit session and built modules/pinned SDK. x86_64 runs use Rosetta
when the host is Apple Silicon. Test-owned SDK caches are removed after exit.
"""
from pathlib import Path
import argparse
import base64
import hashlib
import http.server
import importlib.util
import json
import os
import platform
import plistlib
import shutil
import signal
import stat
import subprocess
import tempfile
import threading
import time
import uuid
import zipfile

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-root',type=Path,default=ROOT)
parser.add_argument('--arch',choices=['native','arm64','x86_64','all'],default='native')
parser.add_argument('--evidence-output',type=Path)
MODES=['plain','cancel-once','on-quit','cancel-once-on-quit','resume-on-quit','busy-resume-on-quit','bad-signature','tampered-archive']
parser.add_argument('--case',action='append',choices=MODES,help='Run selected cases; default runs all cases')
args=parser.parse_args();args.build_root=args.build_root.resolve()
arches=[platform.machine()] if args.arch=='native' else ['arm64','x86_64'] if args.arch=='all' else [args.arch]
assert platform.machine()=='arm64' or arches==['x86_64'],'Use native Apple Silicon Python for arm64/all; Intel hosts support x86_64 only'

def run(*command,timeout=90):
 result=subprocess.run([str(x) for x in command],capture_output=True,text=True,timeout=timeout)
 if result.returncode:raise RuntimeError('Fixture command failed: '+(result.stdout+result.stderr)[-3000:])
 return result.stdout.strip()

def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
feed=load('feed',ROOT/'Scripts/prepare-update-feed.py');config=load('metadata',ROOT/'Scripts/signed-update-configuration.py')

def fingerprint(app):
 digest=hashlib.sha256()
 for path in sorted(app.rglob('*')):
  relative=str(path.relative_to(app));value=path.lstat();digest.update(relative.encode());digest.update(str(value.st_mode).encode())
  if path.is_symlink():digest.update(os.readlink(path).encode())
  elif path.is_file():digest.update(path.read_bytes())
 return digest.hexdigest()

def archive_app(app,destination,cpu):
 with zipfile.ZipFile(destination,'w',zipfile.ZIP_DEFLATED) as archive:
  for path in sorted(app.rglob('*')):
   relative=Path('OpenCharge-1.0.1-'+cpu)/'dist/Fixture.app'/path.relative_to(app)
   if path.is_symlink():
    item=zipfile.ZipInfo(str(relative));item.create_system=3;item.external_attr=path.lstat().st_mode<<16;archive.writestr(item,os.readlink(path).encode())
   elif path.is_file():archive.write(path,str(relative))
  # Match the distribution's versioned-root/dist/app layout and ancillary
  # guide/script/tool folders. These inert files must never be executed.
  prefix='OpenCharge-1.0.1-'+cpu+'/'
  archive.writestr(prefix+'docs/README.md','Fixture guide only')
  archive.writestr(prefix+'Scripts/install-helper.sh','# Fixture text only; no service operation\n')
  archive.writestr(prefix+'dist/bin/chargectl','Fixture text only; not executable')

def own_helpers(case,identity):
 listing=run('ps','-axo','uid=,pid=,command=');found=[]
 for line in listing.splitlines():
  parts=line.strip().split(None,2)
  if len(parts)!=3 or int(parts[0])!=os.getuid():continue
  command=parts[2]
  if (str(case) in command or identity in command) and any(token in command for token in ['/Autoupdate ','/Updater ','/SDKInstallFixture']):found.append(int(parts[1]))
 return found

def cleanup(case,identity,process):
 # All target PIDs must contain this invocation's random path/identity and run
 # as this user. No process-name-wide stop or service command is used.
 if process is not None:
  process.poll()
  if process.returncode is None:
   process.terminate()
   try:process.wait(timeout=3)
   except subprocess.TimeoutExpired:process.kill();process.wait()
 end=time.monotonic()+5
 while own_helpers(case,identity) and time.monotonic()<end:time.sleep(0.1)
 leftovers=own_helpers(case,identity)
 for pid in leftovers:
  # Revalidate immediately to avoid acting on a stale/reused PID.
  if pid in own_helpers(case,identity):os.kill(pid,signal.SIGTERM)
 if leftovers:time.sleep(0.3)
 remaining=own_helpers(case,identity)
 for pid in remaining:
  if pid in own_helpers(case,identity):os.kill(pid,signal.SIGKILL)
 assert not own_helpers(case,identity),'Owned fixture helper still running'
 for path in [Path.home()/'Library/Caches'/identity,Path.home()/'Library/Preferences'/(identity+'.plist')]:
  if path.exists() and not path.is_symlink() and path.stat().st_uid==os.getuid():
   if path.is_dir():shutil.rmtree(path)
   elif path.is_file() and path.stat().st_nlink==1:path.unlink()

(ROOT/'.build/module-cache').mkdir(parents=True,exist_ok=True)
results=[]
with tempfile.TemporaryDirectory(prefix='opencharge-sdk-install-',dir='/private/tmp') as temporary:
 root=Path(temporary);signer=root/'rfc-signer'
 run('/usr/bin/xcrun','swiftc','-module-cache-path',ROOT/'.build/module-cache',ROOT/'Tests/SignedUpdates/sign-fixture.swift','-o',signer);key=run(signer)
 source=Path(run('python3',ROOT/'Scripts/sparkle-package.py','source',args.build_root/'.build/artifacts'))
 for cpu in arches:
  template=root/cpu/'Template.app';mac=template/'Contents/MacOS';mac.mkdir(parents=True)
  run('/usr/bin/xcrun','swiftc','-module-cache-path',ROOT/'.build/module-cache','-parse-as-library','-target',cpu+'-apple-macosx13.0','-F',source.parent,'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',ROOT/'Tests/SignedUpdates/SDKInstallFixture.swift','-o',mac/'OpenCharge')
  base={'CFBundleIdentifier':'org.opencharge.app','CFBundleExecutable':'OpenCharge','CFBundleName':'SDK Installation Fixture','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0.0','CFBundleVersion':'1','LSMinimumSystemVersion':'13.0','CFBundleDevelopmentRegion':'en','CFBundleLocalizations':['en','zh-Hans'],'LSUIElement':True,'SUPublicEDKey':key}
  base.update(config.DEFAULTS);(template/'Contents/Info.plist').write_bytes(plistlib.dumps(base))
  run('python3',ROOT/'Scripts/sparkle-package.py','prepare',template,'--source',source);(mac/'OpenCharge').rename(mac/'SDKInstallFixture')
  for mode in args.case or MODES:
   scheduled_quit=mode.endswith('on-quit')
   case=root/(cpu+'-'+mode);case.mkdir();app=case/'Fixture.app';shutil.copytree(template,app,symlinks=True)
   identity='org.opencharge.sdk-install.'+uuid.uuid4().hex
   bodies={};requests=[];lock=threading.Lock();process=None;log=None
   class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
     with lock:requests.append(self.path);data=bodies.get(self.path)
     self.send_response(200 if data is not None else 404);self.send_header('Content-Length',str(len(data or b'')));self.send_header('Cache-Control','no-store');self.send_header('Content-Type','application/xml' if self.path.endswith('.xml') else 'application/octet-stream');self.end_headers()
     if data is not None:self.wfile.write(data)
    def log_message(self,*arguments):pass
   try:
    with http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler) as server:
     thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
     try:
      url='http://127.0.0.1:'+str(server.server_port)
      info=dict(base);info.update({'CFBundleIdentifier':identity,'CFBundleExecutable':'SDKInstallFixture','SUFeedURL':url+'/appcast.xml','FixtureEvidenceDirectory':str(case),'FixtureQuitMode':mode})
      (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info));run('/usr/bin/codesign','--force','--sign','-','--identifier',identity,app)
      original=fingerprint(app)
      new=case/'new/Fixture.app';shutil.copytree(app,new,symlinks=True);newinfo=dict(info);newinfo.update({'CFBundleShortVersionString':'1.0.1','CFBundleVersion':'2'});(new/'Contents/Info.plist').write_bytes(plistlib.dumps(newinfo));run('/usr/bin/codesign','--force','--sign','-','--identifier',identity,new)
      archive=case/'update.zip';archive_app(new,archive,cpu);signature=run(signer,archive);data=archive.read_bytes()
      if mode=='bad-signature':signature=base64.b64encode(bytes(64)).decode()
      if mode=='tampered-archive':
       altered=bytearray(data);altered[200]^=1;data=bytes(altered)
      value={'public_key':key,'version':'1.0.1','build':'2','channel':'stable','published':'2026-10-27T12:00:00Z','notes':'Owned fixture','archive_signature':signature,'archive_size':len(data),'archive_sha256':hashlib.sha256(data).hexdigest()}
      item=feed.render_item(value);item.find('enclosure').set('url',url+'/archive.zip');content=feed.serialize([item]);unsigned=case/'unsigned.xml';unsigned.write_bytes(content)
      bodies['/appcast.xml']=content+('<!-- sparkle-signatures:\nedSignature: '+run(signer,unsigned)+'\nlength: '+str(len(content))+'\n-->\n').encode();bodies['/archive.zip']=data
      home=case/'home';(home/'Library/Preferences').mkdir(parents=True);(home/'Library/Caches').mkdir(parents=True)
      env=dict(os.environ);env['CFFIXED_USER_HOME']=str(home)
      log=(case/'process.log').open('w');process=subprocess.Popen(['/usr/bin/arch','-'+cpu,str(app/'Contents/MacOS/SDKInstallFixture')],env=env,stdout=log,stderr=log)
      deadline=time.monotonic()+45;events=[]
      while time.monotonic()<deadline:
       process.poll() # Reap exit promptly: the SDK observes the target PID.
       event_file=case/'events.jsonl';events=[json.loads(x) for x in event_file.read_text().splitlines()] if event_file.exists() else []
       if any(x['event'] in ['relaunched-new-version','update-error','start-error'] for x in events):break
       if scheduled_quit and process.returncode is not None and plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='1.0.1':break
       time.sleep(0.05)
      if scheduled_quit:
       print('ON-QUIT '+json.dumps({'architecture':cpu,'case':mode,'events':events,'oldExit':process.poll(),'processLog':(case/'process.log').read_text()[-2500:]}),flush=True)
       assert process.poll()==0,'Ordinary fixture quit did not finish'
       assert not any(x['event']=='relaunched-new-version' for x in events),'On-quit installation unexpectedly relaunched'
       assert plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']=='1.0.1','On-quit replacement not completed'
       # Ordinary quit installs silently, without SDK relaunch. Open the owned
       # replacement explicitly to verify it runs; record who initiated launch.
       with (case/'events.jsonl').open('a') as evidence:
        evidence.write(json.dumps({'event':'harness-open-replacement','time':time.time()})+'\n')
       reopened=subprocess.Popen(['/usr/bin/arch','-'+cpu,str(app/'Contents/MacOS/SDKInstallFixture')],env=env,stdout=log,stderr=log)
       try:assert reopened.wait(timeout=10)==0
       finally:
        if reopened.poll() is None:reopened.terminate();reopened.wait(timeout=5)
       events=[json.loads(x) for x in (case/'events.jsonl').read_text().splitlines()]
      names=[x['event'] for x in events];version=plistlib.loads((app/'Contents/Info.plist').read_bytes())['CFBundleShortVersionString']
      result={'architecture':cpu,'case':mode,'events':events,'requests':list(requests),'version':version,'oldExit':process.poll(),'identity':identity,'archiveLayout':'versioned-root/dist/app'};results.append(result)
      print('OBSERVED '+json.dumps(result,sort_keys=True),flush=True)
      assert requests.count('/appcast.xml')==1 and requests.count('/archive.zip')==1
      assert 'download-end' in names and 'start-error' not in names
      if mode in ['bad-signature','tampered-archive']:
       assert 'update-error' in names and 'install-begin' not in names and 'ready' not in names and 'relaunched-new-version' not in names
       assert version=='1.0.0' and fingerprint(app)==original,'Rejected archive changed original app'
      else:
       assert version=='1.0.1' and 'update-error' not in names and 'relaunched-new-version' in names
       for before,after in [('download-end','did-extract-callback'),('did-extract-callback','ready'),('ready','cleanup-begin'),('cleanup-begin','cleanup-complete'),('cleanup-complete','terminated'),('terminated','relaunched-new-version')]:assert names.index(before)<names.index(after),(before,after)
       assert next(x['pid'] for x in events if x['event']=='launched')!=next(x['pid'] for x in events if x['event']=='relaunched-new-version')
       if mode.startswith('cancel-once'):
        retry='retry-normal-quit' if scheduled_quit else 'retry-install'
        assert names.count('quit-request')==2 and names.index('quit-cancelled')<names.index(retry)<names.index('cleanup-begin')
       else:assert names.count('quit-request')==1
       if scheduled_quit:
        assert 'request-install' not in names and 'retry-install' not in names
        assert names.index('ready')<names.index('cycle-end')<names.index('request-normal-quit')
        assert names.index('terminated')<names.index('harness-open-replacement')<names.index('relaunched-new-version')
       if 'resume' in mode:
        assert names.count('candidate')==1 and names.count('valid-update')==2,'Resume policy callback behavior changed'
        assert names.count('check-admission')==(3 if mode.startswith('busy-') else 2)
        assert names.index('ready')<names.index('request-resume-info')<names.index('request-normal-quit')
        if mode.startswith('busy-'):
         assert names.index('request-resume-info')<names.index('maintenance-rejected')<names.index('retry-resume-info')<names.index('request-normal-quit')
       run('/usr/bin/codesign','--verify','--deep','--all-architectures','--strict',app)
       assert set(run('/usr/bin/lipo','-archs',app/'Contents/MacOS/SDKInstallFixture').split())=={cpu}
      print('PASS real SDK archive fixture '+cpu+' '+mode,flush=True)
     finally:server.shutdown();thread.join()
   finally:
    cleanup(case,identity,process)
    if log:log.close()
    if args.evidence_output:
     args.evidence_output.write_text(json.dumps(results,indent=2)+'\n')
print('Real SDK installer: '+str(len(results))+' signed-download/replace/relaunch/cancel/rejection cases passed in disposable app identities; no real product/service/hardware/publication operation')
