"""Start the real SDK for informational checks in uniquely identified temporary apps.
Uses a private loopback HTTP server and public RFC test signatures. No archive
request, installation, AppModel, service operation or hardware control is invoked.
Requires an active macOS AppKit session; cannot run in a GUI-restricted sandbox.
"""
from pathlib import Path
import argparse
import base64
import copy
import hashlib
import http.server
import importlib.util
import json
import os
import platform
import plistlib
import shutil
import subprocess
import tempfile
import threading
import urllib.parse
import uuid
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser(description=__doc__)
parser.add_argument('--build-root',type=Path,default=ROOT)
parser.add_argument('--arch',choices=['native','arm64','x86_64','all'],default='native')
args=parser.parse_args();args.build_root=args.build_root.resolve()
arches=[platform.machine()] if args.arch=='native' else ['arm64','x86_64'] if args.arch=='all' else [args.arch]
assert platform.machine()=='arm64' or arches==['x86_64'],'This host cannot execute arm64 fixtures'

def load(name,path):
 spec=importlib.util.spec_from_file_location(name,path);module=importlib.util.module_from_spec(spec);spec.loader.exec_module(module);return module
feed=load('feed',ROOT/'Scripts/prepare-update-feed.py')
config=load('metadata',ROOT/'Scripts/signed-update-configuration.py')

def run(*command,env=None,timeout=90):
 result=subprocess.run([str(x) for x in command],capture_output=True,text=True,env=env,timeout=timeout)
 if result.returncode:raise RuntimeError('Fixture command failed ('+str(result.returncode)+'): '+(result.stdout+result.stderr)[-3000:])
 return result.stdout.strip()

(ROOT/'.build/module-cache').mkdir(parents=True,exist_ok=True)
results=[]
with tempfile.TemporaryDirectory(prefix='real-sdk-probe-',dir=ROOT/'.build') as temporary:
 root=Path(temporary)
 signer=root/'rfc-signer'
 run('/usr/bin/xcrun','swiftc','-module-cache-path',ROOT/'.build/module-cache',ROOT/'Tests/SignedUpdates/sign-fixture.swift','-o',signer)
 key=run(signer);serial=0
 def signature(content):
  global serial
  serial+=1;path=root/str(serial);path.write_bytes(content);return run(signer,path)
 def signed(content):return content+('<!-- sparkle-signatures:\nedSignature: '+signature(content)+'\nlength: '+str(len(content))+'\n-->\n').encode()
 dummy=b'not downloaded by informational probe'
 archive_signature=signature(dummy)
 def entry(version,build,channel):
  return {'public_key':key,'version':version,'build':build,'channel':channel,'published':'2026-10-27T12:00:00Z','notes':'SDK fixture','archive_signature':archive_signature,'archive_size':len(dummy),'archive_sha256':hashlib.sha256(dummy).hexdigest()}
 stable=feed.render_item(entry('1.0.1','2','stable'))
 preview=feed.render_item(entry('1.0.2','3','preview'))
 content=feed.serialize([preview,stable]);valid=signed(content)
 def changed_item(field,value):
  item=copy.deepcopy(stable)
  if field=='url':item.find('enclosure').set('url',value)
  elif field=='installationType':item.find('enclosure').set('{'+feed.NS+'}installationType',value)
  elif field=='minimumSystemVersion':item.find('{'+feed.NS+'}minimumSystemVersion').text=value
  return signed(feed.serialize([item]))
 bodies={
  'stable':valid,'preview':valid,'unsigned':content,'wrong-key':valid,
  'newer-system-required':changed_item('minimumSystemVersion','99.0.0'),
  'tampered':valid.replace(b'OpenCharge Updates',b'OpenCharge Changed'),
  'wrong-length':valid.replace(('length: '+str(len(content))).encode(),b'length: 1'),
  'busy':valid,'foreign-archive':changed_item('url','https://example.invalid/OpenCharge-macOS-universal.zip'),
  'package':changed_item('installationType','package'),
  'arm-archive':changed_item('url','https://github.com/shengjk/OpenCharge/releases/download/v1.0.1/OpenCharge-macOS-arm64.zip'),
  'downgrade':signed(feed.serialize([feed.render_item(entry('0.9.9','99','stable'))])),
  'empty-stable':signed(feed.serialize([preview]))
 }
 routes={};requests=[];lock=threading.Lock()
 class Handler(http.server.BaseHTTPRequestHandler):
  def do_GET(self):
   path=urllib.parse.urlsplit(self.path).path
   with lock:requests.append(self.path);body=routes.get(path)
   self.send_response(200 if body is not None else 404)
   self.send_header('Content-Type','application/xml');self.send_header('Cache-Control','no-store')
   self.send_header('Content-Length',str(len(body or b'')));self.end_headers()
   if body is not None:self.wfile.write(body)
  def log_message(self,*arguments):pass
 with http.server.ThreadingHTTPServer(('127.0.0.1',0),Handler) as server:
  thread=threading.Thread(target=server.serve_forever,daemon=True);thread.start()
  try:
   source=Path(run('python3',ROOT/'Scripts/sparkle-package.py','source',args.build_root/'.build/artifacts'))
   for cpu in arches:
    binary_root=args.build_root/'.build/release' if cpu==platform.machine() else args.build_root/('.build/universal-'+cpu)/(cpu+'-apple-macosx/release')
    assert (binary_root/'Modules/ChargeCore.swiftmodule').exists(),'Build the native/universal products first'
    app=root/cpu/'Template.app';mac=app/'Contents/MacOS';mac.mkdir(parents=True)
    run('/usr/bin/xcrun','swiftc','-module-cache-path',ROOT/'.build/module-cache','-parse-as-library','-target',cpu+'-apple-macosx13.0','-I',binary_root/'Modules','-F',source.parent,'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',ROOT/'Sources/OpenCharge/SignedUpdateDriver.swift',ROOT/'Tests/SignedUpdates/SDKProbe.swift',*sorted((binary_root/'ChargeCore.build').glob('*.o')),'-o',mac/'OpenCharge')
    base={'CFBundleIdentifier':'org.opencharge.app','CFBundleExecutable':'OpenCharge','CFBundleName':'OpenCharge SDK Fixture','CFBundlePackageType':'APPL','CFBundleShortVersionString':'1.0.0','CFBundleVersion':'1','LSMinimumSystemVersion':'13.0','CFBundleDevelopmentRegion':'en','CFBundleLocalizations':['en','zh-Hans'],'LSUIElement':True,'SUPublicEDKey':key}
    base.update(config.DEFAULTS);(app/'Contents/Info.plist').write_bytes(plistlib.dumps(base))
    # The package helper audits/trims the real SDK before the fixture identity
    # changes. The org.opencharge.app identity is never executed or registered.
    run('python3',ROOT/'Scripts/sparkle-package.py','prepare',app,'--source',source)
    (mac/'OpenCharge').rename(mac/'SDKProbe')
    for name,body in bodies.items():
     case=root/cpu/name;case.mkdir();target=case/'Fixture.app';shutil.copytree(app,target,symlinks=True)
     identity='org.opencharge.sdk-probe.'+uuid.uuid4().hex
     path='/'+uuid.uuid4().hex+'/appcast.xml'
     with lock:routes[path]=body
     info=dict(base)
     if name=='wrong-key':
      # Public key from RFC 8032 test vector 2, not a deployment credential.
      info['SUPublicEDKey']=base64.b64encode(bytes.fromhex('3d4017c3e843895a92b70aa74d1b7ebc9c982ccf2ec4968cc0cd55f12af4660c')).decode()
     info.update({'CFBundleIdentifier':identity,'CFBundleExecutable':'SDKProbe','SUFeedURL':'http://127.0.0.1:'+str(server.server_port)+path})
     (target/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
     run('/usr/bin/codesign','--force','--sign','-','--identifier',identity,target)
     run('/usr/bin/codesign','--verify','--deep','--all-architectures','--strict',target)
     home=case/'home';home.mkdir();(home/'Library/Preferences').mkdir(parents=True);(home/'Library/Caches').mkdir(parents=True)
     env=dict(os.environ);env['CFFIXED_USER_HOME']=str(home)
     output=run('/usr/bin/arch','-'+cpu,target/'Contents/MacOS/SDKProbe','informational','preview' if name=='preview' else 'stable','busy' if name=='busy' else 'idle',env=env,timeout=35)
     line=next(x for x in output.splitlines() if x.startswith('SDK_PROBE '));value=json.loads(line[len('SDK_PROBE '):])
     with lock:seen=[x for x in requests if urllib.parse.urlsplit(x).path==path]
     assert value['identity']==identity and not value['automaticChecks'] and not value['automaticDownloads'] and not value['sendsSystemProfile']
     value.update({'architecture':cpu,'case':name,'loopbackRequests':len(seen)})
     results.append(value)
     print('OBSERVED '+json.dumps(value,sort_keys=True),flush=True)
     if name=='busy':
      assert value['denied'] and value['admitted']==0 and not seen and value['found'] is None
     else:
      assert value['finished'] and not value['denied'] and len(seen)==1
      # In pinned SDK 2.9.6, a valid full-content signature is accepted
      # despite a wrong unsigned trailer length. This case records that
      # behavior; strict envelope-length rejection belongs to our feed tool.
      if name in ['stable','preview','wrong-length'] or (name=='arm-archive' and cpu=='arm64'):
       expected='1.0.2' if name=='preview' else '1.0.1'
       assert value['found']==expected and value['errorCode'] is None and value['admitted']==1 and value['policyChecks']==1
      else:
       assert value['found'] is None and value['errorCode'] is not None and value['admitted']==0
       if name in ['unsigned','tampered','wrong-key']:assert value['errorDomain']=='SUSparkleErrorDomain' and value['errorCode']==1000 and value['policyChecks']==0
       if name in ['empty-stable','newer-system-required']:assert value['errorDomain']=='SUSparkleErrorDomain' and value['errorCode']==1001 and value['policyChecks']==0
       if name in ['foreign-archive','package','downgrade'] or (name=='arm-archive' and cpu=='x86_64'):assert value['policyChecks']==1
     print('PASS real SDK informational check '+cpu+' '+name,flush=True)
  finally:server.shutdown();thread.join()
print('Real SDK: '+str(len(results))+' informational channel/signature/admission checks passed; private loopback and RFC fixtures only; no archive download, installation or publication')
