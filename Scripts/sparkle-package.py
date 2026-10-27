#!/usr/bin/env python3
"""Prepare/audit the pinned updater framework in a staged app. Never starts it."""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import os
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile

_spec = importlib.util.spec_from_file_location('runtime_package', Path(__file__).with_name('prepare-swift-runtime.py'))
runtime = importlib.util.module_from_spec(_spec)
_spec.loader.exec_module(runtime)
VERSION = '2.9.6'
TABLE_HASHES = {'en': 'bf93bdde8ad020f2ba210ecfa0e84b5365d0342355a3ca39d88fec0acb1e4a40', 'zh-Hans': 'e7f543b92977e9abc907241c411d8db0f59c4fee480859b3e88e4b495e0976c8'}
LICENSE_HASH = '389a4e4e9a32f059775b13a06e25a591445ba229d2838d26dd3e7c0c45127cfe'
INSTALL_NAME = '@rpath/Sparkle.framework/Versions/B/Sparkle'
LINKS = {name:'Versions/Current/'+name for name in ('PrivateHeaders','Resources','Autoupdate','Updater.app','Headers','Modules','Sparkle')}
LINKS['Versions/Current'] = 'B'
COMPONENTS = ['Versions/B/Sparkle','Versions/B/Autoupdate','Versions/B/Updater.app/Contents/MacOS/Updater']
LICENSE = Path(__file__).resolve().parents[1] / 'docs/licenses/Sparkle.txt'

class FrameworkError(Exception):
    pass

def require(condition, message):
    if not condition: raise FrameworkError(message)

def run(*args):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True)
    require(result.returncode == 0, 'Tool failed: '+str(args[0])+'\n'+result.stderr.strip())
    return result.stdout.strip()

def tree(framework, original=False):
    require(framework.is_dir() and not framework.is_symlink(), 'Expected a real framework directory')
    expected = dict(LINKS)
    if original: expected['XPCServices'] = 'Versions/Current/XPCServices'
    actual = {}
    entries = list(framework.rglob('*'))
    require(len(entries) <= 500, 'Unexpectedly large framework tree')
    size = 0
    for path in entries:
        relative = str(path.relative_to(framework))
        info = path.lstat()
        if stat.S_ISLNK(info.st_mode):
            actual[relative] = os.readlink(path)
            require(relative in expected and actual[relative] == expected[relative], 'Unexpected framework alias: '+relative)
            require(path.resolve(strict=True).is_relative_to(framework.resolve()), 'Escaping framework alias')
        elif stat.S_ISREG(info.st_mode):
            require(info.st_nlink == 1, 'Hard-linked framework file')
            size += info.st_size
        else: require(stat.S_ISDIR(info.st_mode), 'Unexpected framework object type')
    require(actual == expected, 'Missing or changed framework aliases')
    require(size <= 64*1024*1024, 'Framework exceeds package limit')

def metadata(path):
    require(path.is_file() and not path.is_symlink(), 'Missing regular framework metadata')
    value = plistlib.loads(path.read_bytes())
    require(isinstance(value,dict), 'Invalid framework metadata')
    return value

def write_metadata(path, value):
    mode = stat.S_IMODE(path.stat().st_mode)
    path.write_bytes(plistlib.dumps(value)); path.chmod(mode)

def verify_framework(framework, arches=None, floor=(13,0,0), original=False):
    tree(framework,original)
    version = framework/'Versions/B'
    info = metadata(version/'Resources/Info.plist')
    require(info.get('CFBundleIdentifier') == 'org.sparkle-project.Sparkle' and info.get('CFBundleShortVersionString') == VERSION and info.get('CFBundleVersion') == '2061' and info.get('CFBundleExecutable') == 'Sparkle', 'Unexpected pinned framework identity')
    updater = metadata(version/'Updater.app/Contents/Info.plist')
    require(updater.get('CFBundleIdentifier') == 'org.sparkle-project.Sparkle.Updater' and updater.get('CFBundleExecutable') == 'Updater', 'Unexpected updater identity')
    for record in (info,updater): require(runtime.version(record['LSMinimumSystemVersion']) <= floor, 'Framework metadata requires a newer system')
    if not original:
        for record in (info,updater):
            require(record.get('CFBundleLocalizations') == ['en','zh-Hans'] and record.get('CFBundleDevelopmentRegion') == 'en', 'Unexpected framework language declaration')
        localized = {str(p.relative_to(framework)) for p in framework.rglob('*.lproj')}
        require(localized == {'Versions/B/Resources/en.lproj','Versions/B/Resources/zh-Hans.lproj'}, 'Unexpected framework localization resources')
        require(not any(p.suffix == '.xpc' for p in framework.rglob('*')), 'Sandbox XPC services are not part of this app layout')
        for language,digest in TABLE_HASHES.items():
            table = version/('Resources/'+language+'.lproj/Sparkle.strings')
            require(table.is_file() and not table.is_symlink() and hashlib.sha256(table.read_bytes()).hexdigest() == digest, 'Missing or changed pinned framework language table')
        require(hashlib.sha256((version/'Resources/OpenCharge-Sparkle-LICENSE.txt').read_bytes()).hexdigest() == LICENSE_HASH and hashlib.sha256(LICENSE.read_bytes()).hexdigest() == LICENSE_HASH, 'Missing or changed framework license notices')
    selected = None
    for name in COMPONENTS:
        path = framework/name
        require(path.stat().st_mode & stat.S_IXUSR, 'Framework component is not executable')
        slices = runtime.inspect(path)
        if selected is None: selected = set(slices)
        require(set(slices) == selected and (arches is None or set(slices) == set(arches)), 'Framework architecture mismatch')
        for cpu,item in slices.items():
            require(item['minimum'] <= floor and not item['rpaths'], 'Nonportable framework deployment or RPATH')
            require(all(runtime.is_system(dep) for dep in item['dependencies']), 'Unexpected framework component dependency')
            require(item['id'] == (INSTALL_NAME if name == COMPONENTS[0] else None), 'Unexpected framework install name')
            details = subprocess.run(['/usr/bin/codesign','-d','--verbose=4','--arch',cpu,str(path)],capture_output=True,text=True,check=True).stderr
            flags = re.search(r'flags=0x([0-9a-f]+)',details)
            require(flags is not None and int(flags[1],16) & 0x10000, 'Framework component lost Hardened Runtime')
        run('/usr/bin/codesign','--verify','--all-architectures','--strict',path)
    run('/usr/bin/codesign','--verify','--all-architectures','--deep','--strict',framework)
    # Resource files cannot hide additional Mach-O executables.
    for path in framework.rglob('*'):
        if path.is_symlink() or not path.is_file(): continue
        with path.open('rb') as stream: magic = stream.read(4)
        if magic in (b'\xcf\xfa\xed\xfe',b'\xfe\xed\xfa\xcf',b'\xca\xfe\xba\xbe',b'\xbe\xba\xfe\xca',b'\xca\xfe\xba\xbf',b'\xbf\xba\xfe\xca',b'\xce\xfa\xed\xfe',b'\xfe\xed\xfa\xce'):
            relative = str(path.relative_to(framework))
            if original and '/XPCServices/' in relative: continue
            require(relative in COMPONENTS, 'Unexpected executable in framework')
    return selected

def app_layout(app):
    for path in (app,app/'Contents',app/'Contents/MacOS'):
        require(path.is_dir() and not path.is_symlink(), 'Expected regular staged app directories')
    info = metadata(app/'Contents/Info.plist')
    require(info.get('CFBundleIdentifier') == 'org.opencharge.app' and info.get('CFBundleExecutable') == 'OpenCharge', 'Unexpected staged application')
    main = runtime.inspect(app/'Contents/MacOS/OpenCharge')
    floor = runtime.version(info['LSMinimumSystemVersion'])
    require(all(value['minimum'] <= floor for value in main.values()), 'App deployment metadata mismatch')
    destination = app/'Contents/Frameworks'
    if destination.exists() or destination.is_symlink(): require(destination.is_dir() and not destination.is_symlink(), 'Unsafe Frameworks directory')
    return set(main),floor,destination/'Sparkle.framework'

def prepare(app, source, identity):
    arches,floor,destination = app_layout(app)
    original_arches = verify_framework(source,floor=floor,original=True)
    require(arches <= original_arches, 'Source framework lacks app architectures')
    if destination.exists() or destination.is_symlink(): verify_framework(destination,floor=floor)
    with tempfile.TemporaryDirectory(prefix='.sparkle-package.',dir=app/'Contents') as temporary:
        temporary = Path(temporary); staged = temporary/'Sparkle.framework'
        shutil.copytree(source,staged,symlinks=True)
        resources = staged/'Versions/B/Resources'
        require((resources/'Base.lproj').is_dir() and (resources/'zh_CN.lproj').is_dir(), 'Missing pinned language sources')
        for path in list(staged.rglob('*.lproj')):
            if path not in (resources/'Base.lproj',resources/'zh_CN.lproj'): shutil.rmtree(path)
        (resources/'Base.lproj').rename(resources/'en.lproj')
        (resources/'zh_CN.lproj').rename(resources/'zh-Hans.lproj')
        (staged/'XPCServices').unlink()
        shutil.rmtree(staged/'Versions/B/XPCServices')
        for path in [resources/'Info.plist', staged/'Versions/B/Updater.app/Contents/Info.plist']:
            info = metadata(path); info['CFBundleDevelopmentRegion'] = 'en'; info['CFBundleLocalizations'] = ['en','zh-Hans']; write_metadata(path,info)
        shutil.copyfile(LICENSE,resources/'OpenCharge-Sparkle-LICENSE.txt')
        for name in COMPONENTS:
            path = staged/name
            if arches != original_arches:
                output = temporary/'thinned'
                options = [value for cpu in sorted(arches) for value in ('-extract',cpu)]
                run('/usr/bin/lipo',path,*options,'-output',output)
                mode = stat.S_IMODE(path.stat().st_mode); output.chmod(mode); output.replace(path)
        # Sign from the innermost executable/bundle out; keep runtime and entitlements.
        for path in [staged/'Versions/B/Autoupdate',staged/'Versions/B/Updater.app',staged]:
            run('/usr/bin/codesign','--force','--sign',identity,'--options','runtime','--preserve-metadata=identifier,entitlements,flags',path)
        verify_framework(staged,arches,floor)
        destination.parent.mkdir(exist_ok=True)
        backup = temporary/'previous.framework'
        if destination.exists(): destination.rename(backup)
        try:
            staged.rename(destination)
            verify_framework(destination,arches,floor)
        except Exception:
            if destination.exists(): shutil.rmtree(destination)
            if backup.exists(): backup.rename(destination)
            raise
    print('Prepared Sparkle '+VERSION+': '+','.join(sorted(arches))+'; English/Simplified Chinese only; updater not started')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode',choices=['prepare','verify','source'])
    parser.add_argument('app',type=Path)
    parser.add_argument('--source',type=Path)
    parser.add_argument('--identity',default='-')
    args = parser.parse_args()
    try:
        if args.mode == 'source':
            require(args.app.is_dir() and not args.app.is_symlink(), 'Expected a real artifact directory')
            candidates = list(args.app.rglob('Sparkle.framework/Versions/B/Resources/Info.plist'))
            require(len(candidates) == 1, 'Expected exactly one resolved pinned framework')
            framework = candidates[0].parents[3]
            info = metadata(candidates[0])
            require(info.get('CFBundleIdentifier') == 'org.sparkle-project.Sparkle' and info.get('CFBundleShortVersionString') == VERSION, 'Unexpected resolved framework identity')
            print(framework.resolve())
        elif args.mode == 'prepare':
            require(args.source is not None, 'Supply the checksum-verified pinned source framework')
            prepare(args.app,args.source,args.identity)
        else:
            arches,floor,framework = app_layout(args.app); verify_framework(framework,arches,floor)
            print('Verified Sparkle layout, languages, architecture, deployment and nested signatures; updater not started')
    except (FrameworkError,runtime.PackageError,OSError,ValueError,KeyError,plistlib.InvalidFileException,subprocess.CalledProcessError) as error:
        parser.exit(1,'Sparkle package check failed: '+str(error)+'\n')

if __name__ == '__main__': main()
