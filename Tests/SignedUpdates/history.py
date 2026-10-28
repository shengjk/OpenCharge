"""Authenticate and merge bounded stable/preview history using public RFC test data."""
from pathlib import Path
import argparse
import base64
import copy
import hashlib
import importlib.util
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT=Path(__file__).resolve().parents[2]
spec=importlib.util.spec_from_file_location('feed',ROOT/'Scripts/prepare-update-feed.py')
feed=importlib.util.module_from_spec(spec);spec.loader.exec_module(feed)
checks=0
(ROOT/'.build/module-cache').mkdir(parents=True,exist_ok=True)

def run(*command):
 result=subprocess.run([str(x) for x in command],capture_output=True,text=True)
 assert result.returncode==0,result.stderr
 return result.stdout.strip()

with tempfile.TemporaryDirectory(prefix='feed-history-fixture-',dir=ROOT/'.build') as temporary:
 root=Path(temporary);signer=root/'rfc-signer'
 run('/usr/bin/xcrun','swiftc','-module-cache-path',ROOT/'.build/module-cache',ROOT/'Tests/SignedUpdates/sign-fixture.swift','-o',signer)
 key=run(signer);serial=0
 def signature(data):
  global serial
  serial+=1;path=root/str(serial);path.write_bytes(data)
  return run(signer,path)
 def signed(content):
  return content+('<!-- sparkle-signatures:\nedSignature: '+signature(content)+'\nlength: '+str(len(content))+'\n-->\n').encode()
 def previous(content):return base64.b64encode(signed(content)).decode()
 archive_signature=signature(b'public fixture archive')
 def entry(number,channel='preview',old=None):
  return {'schema':2,'previous_feed':old,'public_key':key,'version':'1.0.'+str(number),'build':str(number),'channel':channel,'published':'2026-10-27T12:00:00Z','notes':'English notes & <literal>','archive_signature':archive_signature,'archive_sha256':hashlib.sha256(b'public fixture archive').hexdigest(),'archive_size':22}
 def items(content):return ET.fromstring(content).findall('./channel/item')
 def builds(content):return [x.findtext('{'+feed.NS+'}version') for x in items(content)]
 def rejected(value):
  global checks
  try:feed.render(value);raise AssertionError('invalid history accepted')
  except feed.FeedError:checks+=1
 stable=feed.render(entry(1,'stable'));preview=feed.render(entry(2,old=previous(stable)))
 assert builds(preview)==['2','1'] and items(preview)[1].find('{'+feed.NS+'}channel') is None;checks+=1
 content=feed.render(entry(3,old=previous(preview)))
 assert builds(content)==['3','2','1'];checks+=1
 promotion=entry(2,'stable',previous(content));promoted=feed.render(promotion)
 assert builds(promoted)==['3','2','1'] and items(promoted)[1].find('{'+feed.NS+'}channel') is None;checks+=1
 demotion=entry(2,old=previous(promoted));rejected(demotion)
 changed=entry(2,'stable',previous(content));changed['archive_signature']=signature(b'different archive');rejected(changed)
 changed=entry(2,'stable',previous(content));changed['archive_size']+=1;rejected(changed)
 changed=entry(2,'stable',previous(content));changed['build']='4';rejected(changed)
 changed=entry(4,old=previous(content));changed['build']='2';rejected(changed)
 changed=entry(2,old=previous(content));changed['build']='99';rejected(changed)
 changed=entry(4,old=previous(content));changed['build']='1';rejected(changed)
 # Stable and preview entries are retained under count and byte pressure.
 feed.MAX_ITEMS=4
 current=preview
 for number in range(3,9):current=feed.render(entry(number,old=previous(current)))
 assert builds(current)==['8','7','6','1'];checks+=1
 # Existing history can be promoted without losing a newer preview.
 latest_stable=feed.render(entry(8,'stable',previous(current)))
 assert builds(latest_stable)==['8','7','6','1'] and items(latest_stable)[0].find('{'+feed.NS+'}channel') is None;checks+=1
 feed.MAX_ITEMS=100
 # Raw test content need not pass current retention limits to be authenticated;
 # it must satisfy the source format and absolute read bounds first.
 many=feed.serialize([feed.render_item(entry(n,'stable' if n==1 else 'preview')) for n in range(100,0,-1)])
 many_merged=feed.render(entry(101,old=previous(many)))
 assert len(items(many_merged))==100 and builds(many_merged)[-1]=='1' and '2' not in builds(many_merged);checks+=1
 saved_limit=feed.MAX_FEED;feed.MAX_FEED=len(content)+10
 compact=feed.render(entry(4,old=previous(content)))
 assert len(compact)<=feed.MAX_FEED and {'4','1'}<=set(builds(compact));checks+=1
 feed.MAX_FEED=saved_limit
 # Corruption cannot be repaired by editing the public request/hash fields.
 raw=signed(stable)
 changed=entry(2,old=base64.b64encode(raw.replace(b'OpenCharge Updates',b'OpenCharge Changed')).decode());rejected(changed)
 changed=entry(2,old=base64.b64encode(raw.replace(('length: '+str(len(stable))).encode(),b'length: 1')).decode());rejected(changed)
 changed=entry(2,old=base64.b64encode(stable).decode());rejected(changed)
 changed=entry(2,old=base64.b64encode(raw+b'extra').decode());rejected(changed)
 changed=entry(2,old=base64.b64encode(raw).decode()+'\n');rejected(changed)
 changed=entry(2,old=123);rejected(changed)
 # These invalid XML structures carry a genuine signature. Rejection therefore
 # exercises parser/policy validation after successful authentication.
 mutations=[]
 doc=ET.fromstring(content);doc[0][3].append(copy.deepcopy(doc[0][3].find('enclosure')));mutations.append(ET.tostring(doc))
 doc=ET.fromstring(content);doc[0].append(copy.deepcopy(doc[0][3]));mutations.append(ET.tostring(doc))
 doc=ET.fromstring(content);doc[0][0].text='Different feed';mutations.append(ET.tostring(doc))
 doc=ET.fromstring(content);doc[0][3].find('enclosure').set('url','https://example.invalid/archive.zip');mutations.append(ET.tostring(doc))
 doc=ET.fromstring(content);doc[0][3].find('description').text='<pre><img src="https://example.invalid/pixel"></pre>';mutations.append(ET.tostring(doc))
 doc=ET.fromstring(content);doc[0][3].find('{'+feed.NS+'}channel').text='nightly';mutations.append(ET.tostring(doc))
 doc=ET.fromstring(content);doc[0][3],doc[0][4]=doc[0][4],doc[0][3];mutations.append(ET.tostring(doc))
 mutations.extend([b'<!DOCTYPE rss [<!ENTITY x "test">]>'+stable,b'<rss>',b'<!ENTITY x "test">'+stable])
 for bad in mutations:rejected(entry(4,old=previous(bad)))
 malformed_order=feed.serialize([feed.render_item(entry(3)),feed.render_item({**entry(4),'build':'2'}),feed.render_item(entry(1,'stable'))])
 rejected(entry(5,old=previous(malformed_order)))
 duplicate_build=feed.serialize([feed.render_item(entry(3)),feed.render_item({**entry(2),'build':'3'})])
 rejected(entry(4,old=previous(duplicate_build)))
 duplicate_version=feed.serialize([feed.render_item(entry(3)),feed.render_item({**entry(3),'build':'2'})])
 rejected(entry(4,old=previous(duplicate_version)))
 rejected(entry(4,old='A'*((feed.MAX_SIGNED_FEED+2)//3*4+4)))
 # CRLF notes from the original prototype normalize through XML without losing
 # a signed, valid historical release.
 crlf=entry(1,'stable');crlf['notes']='line one\r\nline two\r'
 retained=feed.render(entry(2,old=previous(feed.render(crlf))))
 assert builds(retained)==['2','1'];checks+=1
 # Preserve per-release platform floors when merging old and new packages.
 lower={**entry(2,old=previous(stable)),'minimum_system_version':'11.0.0'}
 mixed=feed.render(lower)
 assert [x.findtext('{'+feed.NS+'}minimumSystemVersion') for x in items(mixed)]==['11.0.0','13.0.0'];checks+=1
 promotion={**entry(2,'stable',previous(mixed)),'minimum_system_version':'11.0.0'}
 assert items(feed.render(promotion))[0].findtext('{'+feed.NS+'}minimumSystemVersion')=='11.0.0';checks+=1
 rejected(entry(2,'stable',previous(mixed)))
 rejected({**entry(3),'minimum_system_version':'10.15.0'})
 for invalid_minimum in [None,11,[]]:rejected({**entry(3),'minimum_system_version':invalid_minimum})
 print(f'Signed history: {checks} authentication/channel/promotion/retention/parser rejection checks passed; no updater or publication')
