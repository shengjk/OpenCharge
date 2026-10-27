"""Use the real pinned framework only in temporary, unregistered app fixtures.
No updater is started; framework loading only reads localization resources.
"""
from pathlib import Path
import argparse
import importlib.util
import json
import os
import plistlib
import shutil
import stat
import subprocess
import tempfile
import zipfile

project = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--source',type=Path)
args = parser.parse_args()
if args.source is None:
    matches = list((project/'.build/artifacts').rglob('Sparkle.framework/Versions/B/Resources/Info.plist'))
    assert len(matches) == 1, 'Resolve the pinned public dependency first, or supply --source'
    source = matches[0].parents[3]
else:
    source = args.source.resolve()
script = project/'Scripts/sparkle-package.py'
spec = importlib.util.spec_from_file_location('release_payload',project/'Scripts/package-release.py')
payload = importlib.util.module_from_spec(spec)
spec.loader.exec_module(payload)
spec = importlib.util.spec_from_file_location('runtime_payload',project/'Scripts/prepare-swift-runtime.py')
runtime = importlib.util.module_from_spec(spec)
spec.loader.exec_module(runtime)

def run(*command):
    return subprocess.run([str(x) for x in command],capture_output=True,text=True,check=True).stdout

def verify(app):
    return run('python3',script,'verify',app)

def resign(framework):
    run('/usr/bin/codesign','--force','--sign','-','--options','runtime','--preserve-metadata=identifier,entitlements,flags',framework)

checks = 0
with tempfile.TemporaryDirectory(prefix='OpenCharge-framework-package-',dir=project/'.build') as temporary:
    root = Path(temporary)
    native = None
    for arches in [['arm64'],['arm64','x86_64']]:
        folder = root/('-'.join(arches)); app = folder/'dist/OpenCharge.app'
        (app/'Contents/MacOS').mkdir(parents=True)
        info = {'CFBundleIdentifier':'org.opencharge.app','CFBundleExecutable':'OpenCharge','CFBundleVersion':'1','CFBundleShortVersionString':'0.0.0','LSMinimumSystemVersion':'11.0','CFBundleLocalizations':['en','zh-Hans']}
        (app/'Contents/Info.plist').write_bytes(plistlib.dumps(info))
        parts = []
        for cpu in arches:
            part = folder/cpu
            subprocess.run(['/usr/bin/xcrun','clang','-target',cpu+'-apple-macosx11.0','-x','c','-o',str(part),'-'],input='int main(void) { return 0; }\n',capture_output=True,text=True,check=True)
            parts.append(part)
        binary = app/'Contents/MacOS/OpenCharge'
        if len(parts)==1: shutil.copyfile(parts[0],binary); binary.chmod(0o755)
        else: run('/usr/bin/lipo','-create',*parts,'-output',binary)
        run('python3',script,'prepare',app,'--source',source)
        verify(app)
        framework = app/'Contents/Frameworks/Sparkle.framework'
        if native is None: native = app
        # Real ZIP/ditto round trip exercises directory and executable framework aliases.
        payload.ROOT = folder
        archive = folder/'framework.zip'
        members = payload.files(folder/'dist')
        with zipfile.ZipFile(archive,'w',zipfile.ZIP_DEFLATED) as package:
            for path in members: payload.write_member(package,path,Path('fixture/dist')/path.relative_to(folder/'dist'))
        with zipfile.ZipFile(archive) as package:
            links = [x for x in package.infolist() if stat.S_ISLNK(x.external_attr>>16)]
            assert len(links)==8
            for entry in links:
                assert entry.create_system==3 and not Path(package.read(entry).decode()).is_absolute()
        extraction = folder/'extracted'
        run('/usr/bin/ditto','-x','-k',archive,extraction)
        extracted = extraction/'fixture/dist/OpenCharge.app'
        verify(extracted)
        for path in members:
            other = extraction/'fixture/dist'/path.relative_to(folder/'dist')
            if path.is_symlink(): assert other.is_symlink() and os.readlink(other)==os.readlink(path)
            else: assert other.read_bytes()==path.read_bytes() and stat.S_IMODE(other.stat().st_mode)==stat.S_IMODE(path.stat().st_mode)
        checks += 1
        # Load actual transformed code in a disposable CLI fixture. No AppModel,
        # updater controller, keychain, network request or installer is invoked.
        probe = folder/'probe.swift'
        probe.write_text('''import Foundation
import Sparkle
@main struct FrameworkLanguageProbe {
 static func main() {
  let language = CommandLine.arguments.last!
  let bundle = Bundle(for: SPUUpdater.self)
  precondition(bundle.preferredLocalizations.first == language)
  let text = bundle.localizedString(forKey: "Cancel", value: nil, table: "Sparkle")
  precondition(text == (language == "en" ? "Cancel" : "取消"))
  print("PASS transformed framework language " + language + "; no updater started")
 }
}
''')
        probe_parts = []
        cache = project/'.build/module-cache'
        sdk = run('/usr/bin/xcrun','--show-sdk-path').strip()
        for cpu in arches:
            output = folder/('probe-'+cpu)
            run('/usr/bin/xcrun','swiftc','-parse-as-library','-module-cache-path',cache,'-target',cpu+'-apple-macosx11.0','-sdk',sdk,'-F',framework.parent,'-framework','Sparkle','-Xlinker','-rpath','-Xlinker','@executable_path/../Frameworks',probe,'-o',output)
            probe_parts.append(output)
        if len(probe_parts)==1: shutil.copyfile(probe_parts[0],binary)
        else: run('/usr/bin/lipo','-create',*probe_parts,'-output',binary)
        binary.chmod(0o755)
        run('/usr/bin/codesign','--force','--sign','-',binary)
        for cpu in arches:
            for language in ['en','zh-Hans']:
                print(run('/usr/bin/arch','-'+cpu,binary,'-AppleLanguages','('+language+')',language).strip())
                checks += 1
        tools = folder/'bin'; tools.mkdir()
        helper = tools/'charged'
        if len(parts)==1: shutil.copyfile(parts[0],helper)
        else: run('/usr/bin/lipo','-create',*parts,'-output',helper)
        helper.chmod(0o755)
        shutil.copyfile(helper,tools/'chargectl'); (tools/'chargectl').chmod(0o755)
        shutil.copyfile(helper,app/'Contents/MacOS/charged'); (app/'Contents/MacOS/charged').chmod(0o755)
        runtime.layout(app,tools); checks += 1
        # Only the main app may link this framework; never the daemon or CLI.
        for role in ['embedded helper','standalone helper','CLI']:
            try: runtime.validate_dependencies(runtime.inspect(binary),role); raise AssertionError('accepted updater-linked '+role)
            except runtime.PackageError: checks += 1
        if len(arches)==1:
            held = folder/'held.framework'; framework.rename(held)
            try:
                try: runtime.layout(app,tools); raise AssertionError('accepted missing framework')
                except runtime.PackageError: checks += 1
            finally: held.rename(framework)
            saved = binary.read_bytes()
            try:
                shutil.copyfile(parts[0],binary)
                try: runtime.layout(app,tools); raise AssertionError('accepted stale framework')
                except runtime.PackageError: checks += 1
            finally: binary.write_bytes(saved)
        else:
            saved = binary.read_bytes()
            try:
                # One architecture links the updater while the other does not.
                run('/usr/bin/lipo','-create',probe_parts[0],parts[1],'-output',binary)
                try: runtime.layout(app,tools); raise AssertionError('accepted asymmetric updater dependency')
                except runtime.PackageError: checks += 1
            finally: binary.write_bytes(saved)
    # Copy only our staged fixture, never the user's application or SDK cache.
    cases = ['escaping_alias','extra_alias','extra_language','wrong_table','wrong_identity','rpath','unsigned','runtime_flag','wrong_arch']
    for case in cases:
        app = root/case/'OpenCharge.app'
        shutil.copytree(native,app,symlinks=True)
        framework = app/'Contents/Frameworks/Sparkle.framework'; version = framework/'Versions/B'
        if case=='escaping_alias':
            (framework/'Resources').unlink(); (framework/'Resources').symlink_to('/tmp')
        elif case=='extra_alias': (version/'Resources/extra').symlink_to('en.lproj')
        elif case=='extra_language':
            (version/'Resources/fr.lproj').mkdir(); resign(framework)
        elif case=='wrong_table':
            shutil.copyfile(version/'Resources/en.lproj/Sparkle.strings',version/'Resources/zh-Hans.lproj/Sparkle.strings'); resign(framework)
        elif case=='wrong_identity':
            path=version/'Resources/Info.plist'; info=plistlib.loads(path.read_bytes()); info['CFBundleShortVersionString']='2.9.5'; path.write_bytes(plistlib.dumps(info)); resign(framework)
        elif case=='rpath':
            run('/usr/bin/install_name_tool','-add_rpath','/tmp',version/'Sparkle'); resign(framework)
        elif case=='unsigned': run('/usr/bin/codesign','--remove-signature',version/'Autoupdate')
        elif case=='runtime_flag': run('/usr/bin/codesign','--force','--sign','-','--options=0',framework)
        else:
            run('/usr/bin/lipo',source/'Versions/B/Updater.app/Contents/MacOS/Updater','-extract','x86_64','-output',root/'wrong-arch')
            shutil.copyfile(root/'wrong-arch',version/'Updater.app/Contents/MacOS/Updater')
            run('/usr/bin/codesign','--force','--sign','-','--options','runtime',version/'Updater.app'); resign(framework)
        result=subprocess.run(['python3',str(script),'verify',str(app)],capture_output=True,text=True)
        assert result.returncode!=0,case
        checks += 1
    # The archive helper must continue rejecting links outside the exact layout.
    folder=root/'payload-rejections'; (folder/'docs').mkdir(parents=True)
    (folder/'docs/alias').symlink_to('/tmp')
    payload.ROOT=folder
    try: payload.files(folder/'docs'); raise AssertionError('accepted unrelated symlink')
    except ValueError: checks += 1
print(f'Sparkle package: {checks} real-framework packaging/localization/rejection checks passed; no updater or installer started')
