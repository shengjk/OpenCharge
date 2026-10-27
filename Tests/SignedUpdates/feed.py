"""Real package/feed signatures with public RFC test data; no updater or deployment keys."""
from pathlib import Path
import argparse
import base64
import hashlib
import importlib.util
import json
import os
import plistlib
import shutil
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT=Path(__file__).resolve().parents[2]
parser=argparse.ArgumentParser();parser.add_argument('--build-root',type=Path,default=ROOT);args=parser.parse_args();args.build_root=args.build_root.resolve()
spec=importlib.util.spec_from_file_location('feed',ROOT/'Scripts/prepare-update-feed.py')
feed=importlib.util.module_from_spec(spec);spec.loader.exec_module(feed)

def run(*command,env=None):
 result=subprocess.run([str(x) for x in command],capture_output=True,text=True,env=env)
 if result.returncode:
  detail=(result.stdout+result.stderr)[:1200]
  if 'fixture_key' in globals() and fixture_key.exists():detail=detail.replace(fixture_key.read_text(),'<public RFC test vector>')
  raise RuntimeError(detail)
 return result.stdout.strip()

def swift(*arguments):
 return run('/usr/bin/xcrun','swift','-module-cache-path',ROOT/'.build/module-cache',ROOT/'Tests/SignedUpdates/sign-fixture.swift',*arguments)

checks=0
(ROOT/'.build/module-cache').mkdir(parents=True,exist_ok=True)
with tempfile.TemporaryDirectory(prefix='signed-feed-fixture-',dir=ROOT/'.build') as temporary:
 root=Path(temporary); package_root=root/'package';package_root.mkdir()
 for name in ['dist','dist-universal','docs']:
  shutil.copytree(args.build_root/name,package_root/name,symlinks=True)
 (package_root/'Scripts').mkdir()
 for name in ['install-helper.sh','uninstall-helper.sh']:shutil.copyfile(ROOT/'Scripts'/name,package_root/'Scripts'/name)
 for name in ['LICENSE','SECURITY.md','CONTRIBUTING.md','CHANGELOG.md']:shutil.copyfile(ROOT/name,package_root/name)
 key=swift();assert base64.b64decode(key).hex()=='d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a'
 for folder in ['dist','dist-universal']:
  app=package_root/folder/'OpenCharge.app'
  env=dict(os.environ);env['OPENCHARGE_UPDATE_PUBLIC_KEY']=key
  run('python3',ROOT/'Scripts/signed-update-configuration.py',app,env=env)
  run('/usr/bin/codesign','--force','--sign','-','--identifier','org.opencharge.app',app)
 module=feed.load_package_module(package_root)
 import sys
 old=sys.argv;sys.argv=['package-release','--output',str(root/'archives')]
 try:module.main()
 finally:sys.argv=old
 archive=root/'archives/OpenCharge-macOS-universal.zip'
 info=plistlib.loads((package_root/'dist-universal/OpenCharge.app/Contents/Info.plist').read_bytes())
 signature=swift(archive)
 notes=root/'notes.md';notes.write_text('English release notes\n<script>alert("test")</script> & text\n')
 common=['--archive',str(archive),'--package-root',str(package_root),'--notes',str(notes),'--public-key',key,'--signature',signature,'--version',info['CFBundleShortVersionString'],'--build',info['CFBundleVersion'],'--channel','preview','--published','2026-10-27T12:00:00Z']
 tool=ROOT/'Scripts/prepare-update-feed.py'
 prepared=root/'prepared';run('python3',tool,'prepare',*common,'--output',prepared);checks+=1
 content=(prepared/'appcast-unsigned.xml').read_bytes();request=json.loads((prepared/'signing-request.json').read_text())
 assert request['content_length']==len(content) and request['content_sha256']==hashlib.sha256(content).hexdigest()
 document=ET.fromstring(content);item=document.find('./channel/item');ns={'s':feed.NS}
 assert item.findtext('s:channel',namespaces=ns)=='preview' and item.findtext('s:minimumSystemVersion',namespaces=ns)=='13.0.0'
 assert item.findtext('description').startswith('<pre>') and '<script>' not in item.findtext('description')
 assert item.find('enclosure').get('url').endswith('/OpenCharge-macOS-universal.zip');checks+=1
 signed=root/'appcast.xml';feed_signature=swift(prepared/'appcast-unsigned.xml')
 run('python3',tool,'finalize','--prepared',prepared,'--signature',feed_signature,'--output',signed);checks+=1
 data=signed.read_bytes();assert data.startswith(content) and b'<!-- sparkle-signatures:\n' in data;ET.fromstring(data)
 # Verify both signatures through the exact official executable from the
 # checksum-pinned distribution. Explicit RFC key path avoids Keychain lookup.
 matches=list((args.build_root/'.build/artifacts').rglob('bin/sign_update'));assert len(matches)==1
 official=matches[0]
 assert hashlib.sha256(official.read_bytes()).hexdigest()=='bfb52400c3da18bb4c251ac4818c2c2e1e31c2e649a45b31c11109b6e57b34ad'
 run('/usr/bin/codesign','--verify','--all-architectures','--strict',official)
 fixture_key=root/'rfc-fixture-key';swift('fixture-key',fixture_key);fixture_key.chmod(0o600)
 run(official,'--verify','--ed-key-file',fixture_key,archive,signature);checks+=1
 run(official,'--verify','--ed-key-file',fixture_key,signed);checks+=1
 def rejected(command):
  global checks
  result=subprocess.run([str(x) for x in command],capture_output=True,text=True)
  assert result.returncode!=0,'unexpectedly accepted invalid input';checks+=1
 for name,value in [('signature',base64.b64encode(bytes(64)).decode()),('public-key',base64.b64encode(bytes(32)).decode()),('build','999999'),('version','1.02.3'),('channel','nightly'),('published','2026-02-30T00:00:00Z')]:
  bad=list(common);bad[bad.index('--'+name)+1]=value
  rejected(['python3',tool,'prepare',*bad,'--output',root/('bad-'+name)])
  assert not (root/('bad-'+name)).exists()
 rejected(['python3',tool,'prepare',*common,'--output',prepared])
 before=signed.read_bytes();rejected(['python3',tool,'finalize','--prepared',prepared,'--signature',feed_signature,'--output',signed]);assert signed.read_bytes()==before
 rejected(['python3',tool,'finalize','--prepared',prepared,'--signature',base64.b64encode(bytes(64)).decode(),'--output',root/'bad-feed.xml'])
 (prepared/'appcast-unsigned.xml').write_bytes(content+b' ')
 rejected(['python3',tool,'finalize','--prepared',prepared,'--signature',feed_signature,'--output',root/'changed-feed.xml'])
 (prepared/'appcast-unsigned.xml').write_bytes(content)
 original_request=(prepared/'signing-request.json').read_bytes()
 (prepared/'signing-request.json').write_bytes(original_request.replace(b'"schema": 1',b'"schema": 1, "schema": 1'))
 rejected(['python3',tool,'finalize','--prepared',prepared,'--signature',feed_signature,'--output',root/'duplicate-field.xml'])
 (prepared/'signing-request.json').write_bytes(original_request)
 linked=root/'archive-link';linked.symlink_to(archive)
 bad=list(common);bad[bad.index('--archive')+1]=str(linked)
 rejected(['python3',tool,'prepare',*bad,'--output',root/'linked-archive'])
 # A validly signed different archive still cannot differ from verified inputs.
 with zipfile.ZipFile(root/'different.zip','w') as z:z.writestr('extra','test')
 bad=list(common);bad[bad.index('--archive')+1]=str(root/'different.zip');bad[bad.index('--signature')+1]=swift(root/'different.zip')
 rejected(['python3',tool,'prepare',*bad,'--output',root/'different'])
 # Stable feed omits the preview channel; escaped notes cannot inject an item.
 stable=dict(request);stable['channel']='stable';assert ET.fromstring(feed.render(stable)).find('./channel/item/{'+feed.NS+'}channel') is None;checks+=1
 print(f'Signed feed: {checks} package/cryptographic/template/rejection checks passed; RFC public test vector only; no updater, service or publication')
