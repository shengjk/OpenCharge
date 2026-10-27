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
 run('python3',tool,'finalize','--public-key',key,'--prepared',prepared,'--signature',feed_signature,'--output',signed);checks+=1
 data=signed.read_bytes();assert data.startswith(content) and b'<!-- sparkle-signatures:\n' in data;ET.fromstring(data)
 def rejected(command):
  global checks
  result=subprocess.run([str(x) for x in command],capture_output=True,text=True)
  assert result.returncode!=0,'unexpectedly accepted invalid input';checks+=1
 # Verify both signatures through the exact official executable from the
 # checksum-pinned distribution. Explicit RFC key path avoids Keychain lookup.
 matches=list((args.build_root/'.build/artifacts').rglob('bin/sign_update'));assert len(matches)==1
 official=matches[0]
 assert hashlib.sha256(official.read_bytes()).hexdigest()=='bfb52400c3da18bb4c251ac4818c2c2e1e31c2e649a45b31c11109b6e57b34ad'
 run('/usr/bin/codesign','--verify','--all-architectures','--strict',official)
 fixture_key=root/'rfc-fixture-key';swift('fixture-key',fixture_key);fixture_key.chmod(0o600)
 run(official,'--verify','--ed-key-file',fixture_key,archive,signature);checks+=1
 run(official,'--verify','--ed-key-file',fixture_key,signed);checks+=1
 # Historical item metadata is synthetic here; actual current archive bytes
 # and matching built app are still audited by prepare. These tests do not
 # claim a historical archive installation or SDK item selection.
 historical=dict(request);historical['previous_feed']=None
 components=list(map(int,info['CFBundleShortVersionString'].split('.')))
 assert components[-1]>0 and int(info['CFBundleVersion'])>1
 components[-1]-=1;historical['version']='.'.join(map(str,components));historical['build']=str(int(info['CFBundleVersion'])-1);historical['channel']='stable'
 history_content=feed.render(historical)
 history_file=root/'previous.xml';history_input=root/'previous-unsigned.xml';history_input.write_bytes(history_content)
 history_file.write_bytes(history_content+('<!-- sparkle-signatures:\nedSignature: '+swift(history_input)+'\nlength: '+str(len(history_content))+'\n-->\n').encode())
 merged=root/'merged'
 run('python3',tool,'prepare',*common,'--previous-feed',history_file,'--output',merged)
 merged_items=ET.fromstring((merged/'appcast-unsigned.xml').read_bytes()).findall('./channel/item')
 assert len(merged_items)==2 and merged_items[1].find('{'+feed.NS+'}channel') is None;checks+=1
 merged_file=root/'merged.xml'
 run('python3',tool,'finalize','--public-key',key,'--prepared',merged,'--signature',swift(merged/'appcast-unsigned.xml'),'--output',merged_file)
 run(official,'--verify','--ed-key-file',fixture_key,merged_file);checks+=1
 # Promotion must preserve archive bytes and remove duplicate preview entries.
 promoted=root/'promoted';stable_common=list(common);stable_common[stable_common.index('--channel')+1]='stable'
 run('python3',tool,'prepare',*stable_common,'--previous-feed',signed,'--output',promoted)
 promoted_items=ET.fromstring((promoted/'appcast-unsigned.xml').read_bytes()).findall('./channel/item')
 assert len(promoted_items)==1 and promoted_items[0].find('{'+feed.NS+'}channel') is None;checks+=1
 promoted_file=root/'promoted.xml'
 run('python3',tool,'finalize','--public-key',key,'--prepared',promoted,'--signature',swift(promoted/'appcast-unsigned.xml'),'--output',promoted_file)
 run(official,'--verify','--ed-key-file',fixture_key,promoted_file);checks+=1
 rejected(['python3',tool,'prepare',*common,'--previous-feed',history_input,'--output',root/'unsigned-history'])
 bad_history=root/'bad-history.xml';bad_history.write_bytes(history_file.read_bytes().replace(b'OpenCharge Updates',b'OpenCharge Changed'))
 rejected(['python3',tool,'prepare',*common,'--previous-feed',bad_history,'--output',root/'corrupt-history'])
 # Existing v1 signing requests remain finalizable without adding history.
 legacy=root/'legacy';shutil.copytree(prepared,legacy)
 legacy_request=dict(request);legacy_request['schema']=1;legacy_request.pop('previous_feed')
 (legacy/'signing-request.json').write_text(json.dumps(legacy_request))
 run('python3',tool,'finalize','--public-key',key,'--prepared',legacy,'--signature',feed_signature,'--output',root/'legacy.xml');checks+=1
 replaced_key=dict(legacy_request);replaced_key['public_key']=base64.b64encode(bytes(32)).decode()
 (legacy/'signing-request.json').write_text(json.dumps(replaced_key))
 rejected(['python3',tool,'finalize','--public-key',key,'--prepared',legacy,'--signature',feed_signature,'--output',root/'replaced-key.xml'])
 # A changed history inside the public request cannot be smuggled into a feed
 # signature that authenticated a different merged template.
 merged_request=json.loads((merged/'signing-request.json').read_text());merged_request['previous_feed']=base64.b64encode(bad_history.read_bytes()).decode()
 (merged/'signing-request.json').write_text(json.dumps(merged_request))
 rejected(['python3',tool,'finalize','--public-key',key,'--prepared',merged,'--signature',feed_signature,'--output',root/'changed-history.xml'])
 for name,value in [('signature',base64.b64encode(bytes(64)).decode()),('public-key',base64.b64encode(bytes(32)).decode()),('build','999999'),('version','1.02.3'),('channel','nightly'),('published','2026-02-30T00:00:00Z')]:
  bad=list(common);bad[bad.index('--'+name)+1]=value
  rejected(['python3',tool,'prepare',*bad,'--output',root/('bad-'+name)])
  assert not (root/('bad-'+name)).exists()
 rejected(['python3',tool,'prepare',*common,'--output',prepared])
 before=signed.read_bytes();rejected(['python3',tool,'finalize','--public-key',key,'--prepared',prepared,'--signature',feed_signature,'--output',signed]);assert signed.read_bytes()==before
 rejected(['python3',tool,'finalize','--public-key',key,'--prepared',prepared,'--signature',base64.b64encode(bytes(64)).decode(),'--output',root/'bad-feed.xml'])
 (prepared/'appcast-unsigned.xml').write_bytes(content+b' ')
 rejected(['python3',tool,'finalize','--public-key',key,'--prepared',prepared,'--signature',feed_signature,'--output',root/'changed-feed.xml'])
 (prepared/'appcast-unsigned.xml').write_bytes(content)
 original_request=(prepared/'signing-request.json').read_bytes()
 (prepared/'signing-request.json').write_bytes(original_request.replace(b'"schema": 2',b'"schema": 2, "schema": 2'))
 rejected(['python3',tool,'finalize','--public-key',key,'--prepared',prepared,'--signature',feed_signature,'--output',root/'duplicate-field.xml'])
 (prepared/'signing-request.json').write_bytes(original_request)
 linked=root/'archive-link';linked.symlink_to(archive)
 bad=list(common);bad[bad.index('--archive')+1]=str(linked)
 rejected(['python3',tool,'prepare',*bad,'--output',root/'linked-archive'])
 # A validly signed different archive still cannot differ from verified inputs.
 with zipfile.ZipFile(root/'different.zip','w') as z:z.writestr('extra','test')
 bad=list(common);bad[bad.index('--archive')+1]=str(root/'different.zip');bad[bad.index('--signature')+1]=swift(root/'different.zip')
 rejected(['python3',tool,'prepare',*bad,'--output',root/'different'])
 # A checkout containing a live appcast cannot accidentally bootstrap a
 # single-item replacement merely because --previous-feed was omitted.
 guarded=root/'guarded-checkout';(guarded/'Scripts').mkdir(parents=True);(guarded/'updates').mkdir()
 shutil.copyfile(tool,guarded/'Scripts/prepare-update-feed.py');shutil.copyfile(history_file,guarded/'updates/appcast.xml')
 rejected(['python3',guarded/'Scripts/prepare-update-feed.py','prepare',*common,'--output',root/'missing-history-option'])
 # Stable feed omits the preview channel; escaped notes cannot inject an item.
 stable=dict(request);stable['channel']='stable';assert ET.fromstring(feed.render(stable)).find('./channel/item/{'+feed.NS+'}channel') is None;checks+=1
 print(f'Signed feed: {checks} package/cryptographic/template/rejection checks passed; RFC public test vector only; no updater, service or publication')
