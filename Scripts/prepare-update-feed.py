#!/usr/bin/env python3
"""Prepare/finalize an authenticated appcast locally. Never signs, uploads or reads private keys."""
from pathlib import Path
import argparse
import base64
import copy
import datetime
import email.utils
import hashlib
import html
import importlib.util
import json
import os
import plistlib
import re
import stat
import subprocess
import tempfile
import xml.etree.ElementTree as ET
import zipfile

ROOT = Path(__file__).resolve().parent.parent
NS = 'http://www.andymatuschak.org/xml-namespaces/sparkle'
FEED = 'https://raw.githubusercontent.com/shengjk/OpenCharge/main/updates/appcast.xml'
MAX_ARCHIVE = 64*1024*1024
MAX_FEED = 2*1024*1024
MAX_SIGNED_FEED = MAX_FEED+512
MAX_REQUEST = 4*1024*1024
MAX_ITEMS = 100
ET.register_namespace('sparkle',NS)

class FeedError(Exception): pass

def require(value,message):
    if not value: raise FeedError(message)

def read(path,limit):
    require(not path.is_symlink(), 'Input must be a regular, unlinked file')
    fd=os.open(path,os.O_RDONLY | os.O_NOFOLLOW)
    with os.fdopen(fd,'rb') as stream:
        before=os.fstat(stream.fileno())
        require(stat.S_ISREG(before.st_mode) and before.st_nlink==1 and before.st_size<=limit,'Invalid input type or size')
        data=stream.read(limit+1); after=os.fstat(stream.fileno())
    require(len(data)<=limit and (before.st_size,before.st_mtime_ns,before.st_ino)==(after.st_size,after.st_mtime_ns,after.st_ino),'Input changed during read')
    return data

def b64(value,length):
    try: raw=base64.b64decode(value,validate=True)
    except (ValueError,TypeError): raise FeedError('Invalid public key or signature encoding') from None
    require(len(raw)==length and base64.b64encode(raw).decode()==value,'Noncanonical public key or signature')
    return value

def verify(data,key,signature):
    b64(key,32); b64(signature,64)
    cache=ROOT/'.build/module-cache'; cache.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='feed-verify-',dir=ROOT/'.build') as temporary:
        path=Path(temporary)/'content'; path.write_bytes(data); path.chmod(0o400)
        result=subprocess.run(['/usr/bin/xcrun','swift','-module-cache-path',str(cache),str(ROOT/'Scripts/verify-ed25519.swift'),key,signature,str(path)],capture_output=True,text=True)
        require(result.returncode==0,'Ed25519 signature verification failed')

def metadata(value, require_digest=True):
    require(isinstance(value,dict),'Invalid signing request')
    require(isinstance(value.get('version'),str) and len(value['version'])<=128 and re.fullmatch(r'(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)',value['version']),'Invalid release version')
    require(all(int(part)<=9223372036854775807 for part in value['version'].split('.')),'Release version exceeds application comparison bounds')
    require(isinstance(value.get('build'),str) and re.fullmatch(r'[1-9][0-9]{0,17}',value['build']),'Invalid release build')
    require(value.get('channel') in ['stable','preview'],'Invalid release channel')
    minimum=value.get('minimum_system_version','13.0.0')
    require(isinstance(minimum,str) and minimum in {'11.0.0','13.0.0'},'Unsupported minimum system version')
    require(isinstance(value.get('notes'),str) and len(value['notes'].encode())<=65536 and all(ord(c)>=32 or c in '\n\t\r' for c in value['notes']),'Invalid release notes')
    try: published=datetime.datetime.strptime(value['published'],'%Y-%m-%dT%H:%M:%SZ').replace(tzinfo=datetime.timezone.utc)
    except (KeyError,TypeError,ValueError): raise FeedError('Use a valid UTC publication timestamp') from None
    require(published.strftime('%Y-%m-%dT%H:%M:%SZ')==value['published'],'Noncanonical publication timestamp')
    b64(value.get('public_key'),32); b64(value.get('archive_signature'),64)
    require(type(value.get('archive_size')) is int and 0<value['archive_size']<=MAX_ARCHIVE,'Invalid archive size')
    if require_digest: require(isinstance(value.get('archive_sha256'),str) and re.fullmatch('[0-9a-f]{64}',value['archive_sha256']),'Invalid archive digest')
    return published

def render_item(value, require_digest=True):
    published=metadata(value,require_digest)
    item=ET.Element('item'); ET.SubElement(item,'title').text='OpenCharge '+value['version']
    ET.SubElement(item,'link').text='https://github.com/shengjk/OpenCharge/releases/tag/v'+value['version']
    ET.SubElement(item,'{'+NS+'}version').text=value['build']
    ET.SubElement(item,'{'+NS+'}shortVersionString').text=value['version']
    ET.SubElement(item,'{'+NS+'}minimumSystemVersion').text=value.get('minimum_system_version','13.0.0')
    if value['channel']=='preview': ET.SubElement(item,'{'+NS+'}channel').text='preview'
    ET.SubElement(item,'pubDate').text=email.utils.format_datetime(published,usegmt=True)
    ET.SubElement(item,'description').text='<pre>'+html.escape(value['notes'])+'</pre>'
    ET.SubElement(item,'enclosure',{'url':'https://github.com/shengjk/OpenCharge/releases/download/v'+value['version']+'/OpenCharge-macOS-universal.zip','length':str(value['archive_size']),'type':'application/octet-stream','{'+NS+'}edSignature':value['archive_signature'],'{'+NS+'}installationType':'application'})
    return item

def serialize(items):
    rss=ET.Element('rss',{'version':'2.0'}); channel=ET.SubElement(rss,'channel')
    ET.SubElement(channel,'title').text='OpenCharge Updates'
    ET.SubElement(channel,'link').text='https://github.com/shengjk/OpenCharge/releases'
    ET.SubElement(channel,'description').text='Signed OpenCharge application updates'
    for item in items: channel.append(copy.deepcopy(item))
    return ET.tostring(rss,encoding='utf-8',xml_declaration=True)+b'\n'

def item_values(item,key):
    required={'title','link','{'+NS+'}version','{'+NS+'}shortVersionString','{'+NS+'}minimumSystemVersion','pubDate','description','enclosure'}
    tags=[child.tag for child in item]
    require(item.tag=='item' and not item.attrib and len(tags)==len(set(tags)) and set(tags) in [required,required|{'{'+NS+'}channel'}],'Unsupported historical item structure')
    enclosure=item.find('enclosure'); description=item.findtext('description')
    require(isinstance(description,str) and description.startswith('<pre>') and description.endswith('</pre>'),'Unsupported historical release notes')
    try:
        published=email.utils.parsedate_to_datetime(item.findtext('pubDate'))
        require(published.utcoffset()==datetime.timedelta(0),'Historical timestamp must use UTC')
        date=published.strftime('%Y-%m-%dT%H:%M:%SZ')
        size=int(enclosure.get('length',''))
    except (TypeError,ValueError,AttributeError): raise FeedError('Invalid historical release metadata') from None
    channel=item.findtext('{'+NS+'}channel')
    require(channel is None or channel=='preview','Unsupported historical channel')
    value={'minimum_system_version':item.findtext('{'+NS+'}minimumSystemVersion'),'public_key':key,'version':item.findtext('{'+NS+'}shortVersionString'),'build':item.findtext('{'+NS+'}version'),'channel':'stable' if channel is None else channel,'published':date,'notes':html.unescape(description[5:-6]),'archive_signature':enclosure.get('{'+NS+'}edSignature'),'archive_size':size}
    expected=render_item(value,False)
    require(ET.tostring(item)==ET.tostring(expected),'Historical item differs from supported template')
    return value

def authenticated_history(encoded,key):
    if encoded is None: return []
    require(isinstance(encoded,str) and len(encoded)<=(MAX_SIGNED_FEED+2)//3*4,'Historical feed exceeds size limit')
    try: raw=base64.b64decode(encoded,validate=True)
    except (ValueError,TypeError): raise FeedError('Invalid historical feed encoding') from None
    require(base64.b64encode(raw).decode()==encoded and len(raw)<=MAX_SIGNED_FEED,'Noncanonical historical feed')
    match=re.fullmatch(rb'(.*)<!-- sparkle-signatures:\nedSignature: ([A-Za-z0-9+/]{86}==)\nlength: ([1-9][0-9]{0,7})\n-->\n',raw,re.S)
    require(match is not None,'Historical feed requires the canonical signed envelope')
    content,signature,length=match.groups()
    require(len(content)<=MAX_FEED and len(content)==int(length) and b'<!-- sparkle-signatures:' not in content,'Historical feed length/envelope mismatch')
    verify(content,key,signature.decode())
    require(b'<!DOCTYPE' not in content.upper() and b'<!ENTITY' not in content.upper(),'Unsupported historical XML declarations')
    try: document=ET.fromstring(content)
    except ET.ParseError: raise FeedError('Invalid historical XML') from None
    require(document.tag=='rss' and document.attrib=={'version':'2.0'} and len(document)==1 and document[0].tag=='channel' and not document[0].attrib,'Unsupported historical RSS structure')
    children=list(document[0]);items=children[3:]
    require(1<=len(items)<=MAX_ITEMS and [child.tag for child in children[:3]]==['title','link','description'],'Unsupported historical channel structure')
    values=[item_values(item,key) for item in items]
    require(len({x['build'] for x in values})==len(values) and len({x['version'] for x in values})==len(values),'Duplicate historical version/build')
    require([int(x['build']) for x in values]==sorted((int(x['build']) for x in values),reverse=True),'Historical builds are not ordered')
    versions=[tuple(map(int,x['version'].split('.'))) for x in values]
    require(versions==sorted(versions,reverse=True),'Historical version/build order conflicts')
    require(serialize(items)==ET.tostring(document,encoding='utf-8',xml_declaration=True)+b'\n','Historical feed differs from supported template')
    return items

def render(value):
    item=render_item(value)
    history=authenticated_history(value.get('previous_feed'),value['public_key'])
    current_version=tuple(map(int,value['version'].split('.')))
    existing=[(old,item_values(old,value['public_key'])) for old in history]
    same=[(old,fields) for old,fields in existing if fields['build']==value['build'] or fields['version']==value['version']]
    if same:
        require(len(same)==1,'Conflicting historical release')
        _,previous=same[0]
        require(previous['build']==value['build'] and previous['version']==value['version'] and previous['archive_signature']==value['archive_signature'] and previous['archive_size']==value['archive_size'] and previous['minimum_system_version']==value.get('minimum_system_version','13.0.0'),'Existing version/build must keep its original archive; use a new version for a rebuild')
        require(previous['channel']==value['channel'] or (previous['channel']=='preview' and value['channel']=='stable'),'A stable release cannot be demoted to preview')
    elif existing:
        require(int(value['build'])>max(int(x['build']) for _,x in existing) and current_version>max(tuple(map(int,x['version'].split('.'))) for _,x in existing),'New version/build must advance together; out-of-order backports need a separate feed strategy')
    items=[item]+[old for old,fields in existing if fields['build']!=value['build']]
    items.sort(key=lambda x:int(x.findtext('{'+NS+'}version')),reverse=True)
    protected={value['build']}
    for preview in [False,True]:
        newest=next((x for x in items if (x.find('{'+NS+'}channel') is not None)==preview),None)
        if newest is not None: protected.add(newest.findtext('{'+NS+'}version'))
    while len(items)>MAX_ITEMS or len(serialize(items))>MAX_FEED:
        removable=next((x for x in reversed(items) if x.findtext('{'+NS+'}version') not in protected),None)
        require(removable is not None,'Protected channel entries exceed feed bounds')
        items.remove(removable)
    data=serialize(items)
    require(b'<!-- sparkle-signatures:' not in data,'Feed exceeds template constraints')
    return data

def load_package_module(root):
    spec=importlib.util.spec_from_file_location('release_payload',ROOT/'Scripts/package-release.py')
    module=importlib.util.module_from_spec(spec); spec.loader.exec_module(module)
    module.ROOT=root
    return module

def inspect_archive(data,root,value):
    package=load_package_module(root)
    version,build=package.inspect(root/'dist-universal','universal')
    require((version,build)==(value['version'],value['build']),'Release version/build do not match verified package')
    info=plistlib.loads(read(root/'dist-universal/OpenCharge.app/Contents/Info.plist',1024*1024))
    spec=importlib.util.spec_from_file_location('update_metadata',ROOT/'Scripts/signed-update-configuration.py')
    config=importlib.util.module_from_spec(spec); spec.loader.exec_module(config)
    require(value['minimum_system_version']==info['LSMinimumSystemVersion']+'.0','Feed minimum does not match verified package')
    require(info.get('SUPublicEDKey')==value['public_key'] and info.get('SUFeedURL')==FEED,'Package has no matching update public key/feed')
    for key,expected in config.DEFAULTS.items():
        require(type(info.get(key)) is type(expected) and info[key]==expected,'Unsafe package updater metadata')
    payload=package.release_payload('dist-universal','universal',version)
    expected={str(name):path for path,name in payload}
    import io
    with zipfile.ZipFile(io.BytesIO(data)) as archive:
        entries=archive.infolist()
        require(len(entries)==len(expected) and {x.filename for x in entries}==set(expected),'Archive entries differ from verified package')
        require(sum(x.file_size for x in entries)<=256*1024*1024,'Archive expands beyond package limit')
        for item in entries:
            original=expected[item.filename]; content=package.content(original)
            require(not item.flag_bits & 1 and item.file_size==len(content) and item.create_system==3,'Unexpected archive member metadata')
            require(item.external_attr>>16==original.lstat().st_mode,'Archive mode/type differs from verified package')
            require(archive.read(item)==content,'Archive bytes differ from verified package')

def prepare(args):
    existing_feed=ROOT/'updates/appcast.xml'
    require(args.previous_feed is not None or not (existing_feed.exists() or existing_feed.is_symlink()),'Existing appcast found; explicitly provide --previous-feed to preserve authenticated channel history')
    key=b64(args.public_key,32); signature=b64(args.signature,64)
    archive=read(args.archive,MAX_ARCHIVE)
    info=plistlib.loads(read(args.package_root/'dist-universal/OpenCharge.app/Contents/Info.plist',1024*1024))
    value={'schema':3,'minimum_system_version':info['LSMinimumSystemVersion']+'.0','previous_feed':base64.b64encode(read(args.previous_feed,MAX_SIGNED_FEED)).decode() if args.previous_feed else None,'public_key':key,'version':args.version,'build':args.build,'channel':args.channel,'published':args.published,'notes':read(args.notes,65536).decode('utf-8').replace('\r\n','\n').replace('\r','\n'),'archive_signature':signature,'archive_sha256':hashlib.sha256(archive).hexdigest(),'archive_size':len(archive)}
    content=render(value)
    verify(archive,key,signature)
    inspect_archive(archive,args.package_root.resolve(strict=True),value)
    value['content_sha256']=hashlib.sha256(content).hexdigest(); value['content_length']=len(content)
    args.output.mkdir() # Exclusive: never overwrite frozen preparation files.
    (args.output/'appcast-unsigned.xml').write_bytes(content)
    (args.output/'signing-request.json').write_text(json.dumps(value,indent=2,ensure_ascii=False)+'\n')
    print('Prepared unsigned appcast and public signing request; no private keys read and nothing published')

def unique_object(pairs):
    result={}
    for key,value in pairs:
        require(key not in result,'Duplicate signing-request field'); result[key]=value
    return result

def finalize(args):
    require(args.prepared.is_dir() and not args.prepared.is_symlink(),'Invalid preparation directory')
    value=json.loads(read(args.prepared/'signing-request.json',MAX_REQUEST),object_pairs_hook=unique_object)
    required={'schema','public_key','version','build','channel','published','notes','archive_signature','archive_sha256','archive_size','content_sha256','content_length'}
    require(isinstance(value,dict) and type(value.get('schema')) is int and ((value['schema']==1 and set(value)==required) or (value['schema']==2 and set(value)==required|{'previous_feed'}) or (value['schema']==3 and set(value)==required|{'previous_feed','minimum_system_version'})),'Invalid signing-request schema')
    expected_key=b64(args.public_key,32)
    require(value['public_key']==expected_key,'Signing request does not match the explicitly expected public key')
    content=read(args.prepared/'appcast-unsigned.xml',MAX_FEED)
    require(type(value['content_length']) is int and value['content_length']==len(content) and value['content_sha256']==hashlib.sha256(content).hexdigest() and render(value)==content,'Prepared feed or signing request changed')
    signature=b64(args.signature,64); verify(content,value['public_key'],signature)
    signed=content+('<!-- sparkle-signatures:\nedSignature: '+signature+'\nlength: '+str(len(content))+'\n-->\n').encode()
    with args.output.open('xb') as stream: stream.write(signed)
    print('Finalized locally verified signed appcast; nothing uploaded or published')

def main():
    parser=argparse.ArgumentParser(description=__doc__); commands=parser.add_subparsers(dest='mode',required=True)
    p=commands.add_parser('prepare')
    for name in ['archive','notes','output']:p.add_argument('--'+name,type=Path,required=True)
    p.add_argument('--package-root',type=Path,default=ROOT)
    p.add_argument('--previous-feed',type=Path)
    for name in ['public-key','signature','version','build','channel','published']:p.add_argument('--'+name,required=True)
    p=commands.add_parser('finalize');p.add_argument('--public-key',required=True);p.add_argument('--prepared',type=Path,required=True);p.add_argument('--signature',required=True);p.add_argument('--output',type=Path,required=True)
    args=parser.parse_args()
    try:
        prepare(args) if args.mode=='prepare' else finalize(args)
    except (FeedError,OSError,ValueError,KeyError,zipfile.BadZipFile,subprocess.CalledProcessError) as error:
        parser.exit(1,'Update feed preparation failed: '+str(error)+'\n')

if __name__=='__main__':main()
