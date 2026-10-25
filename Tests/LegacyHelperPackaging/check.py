import hashlib
import importlib.util
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
SCRIPT = ROOT / 'Scripts/legacy-helper-package.py'
BUILD = ROOT / '.build/legacy-package-tests'
BUILD.mkdir(parents=True, exist_ok=True)
ENV = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(BUILD / 'module-cache'))
spec = importlib.util.spec_from_file_location('legacy_package', SCRIPT)
module = importlib.util.module_from_spec(spec); spec.loader.exec_module(module)


def run(*args, ok=True):
    p = subprocess.run([str(x) for x in args], env=ENV, capture_output=True, text=True)
    if ok:
        assert p.returncode == 0, p.stdout + p.stderr
    else:
        assert p.returncode != 0, 'Invalid package accepted'
    return p.stdout + p.stderr


def verify(app, ok=True):
    return run(sys.executable, SCRIPT, 'verify', app, ok=ok)


def snapshot(root):
    return {str(p.relative_to(root)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in root.rglob('*') if p.is_file() and not p.is_symlink()}


def sign(app, helper=True):
    for path in [app / 'Contents/MacOS/charged', app.parent / 'bin/charged', app.parent / 'bin/chargectl']:
        if path.exists():
            run('/usr/bin/codesign', '--force', '--sign', '-', path)
    if helper:
        run('/usr/bin/codesign', '--force', '--sign', '-', '--identifier', module.LABEL,
            app / 'Contents/Library/LaunchServices' / module.LABEL)
    run('/usr/bin/codesign', '--force', '--sign', '-', '--identifier', module.APP_ID, app)


# Pure policy fixtures do not manufacture or import a signing identity.
assert module.requirements(None) == ('never', 'never')
for requirement in module.requirements('TESTTEAM01'):
    assert 'anchor apple generic' in requirement and 'certificate leaf[subject.OU] = "TESTTEAM01"' in requirement
    run('/usr/bin/csreq', '-r=' + requirement, '-t')
for bad in ['', 'lowercase1', 'TOOSHORT', 'TESTTEAM01" or always']:
    try:
        module.requirements(bad)
        raise AssertionError('Invalid team accepted')
    except module.PackageError:
        pass
assert not module.same_plist({'RunAtLoad': 1}, {'RunAtLoad': True})
original = module.command
calls = []
def fake_command(*args, **kwargs):
    calls.append(args)
    return subprocess.CompletedProcess(args, 0, '', 'TeamIdentifier=TESTTEAM01\n')
module.command = fake_command
assert module.signing_team(Path('fake-signed-file')) == 'TESTTEAM01'
assert calls[1][3] == '-R=anchor apple generic', 'codesign requirements must be literal, not filenames'
module.command = original

with tempfile.TemporaryDirectory(prefix='fixture.', dir=BUILD) as temporary:
    temp = Path(temporary)
    source = temp / 'Placeholder.c'; source.write_text('int main(void) { return 0; }\n')
    objects = {}
    for arch in ['arm64', 'x86_64']:
        target = temp / arch
        run('/usr/bin/xcrun', 'clang', '-target', arch + '-apple-macosx13.0', source, '-Wl,-headerpad_max_install_names', '-o', target)
        objects[arch] = target

    def create(name, arches):
        directory = temp / name; app = directory / 'OpenCharge.app'; tools = directory / 'bin'
        (app / 'Contents/MacOS').mkdir(parents=True); tools.mkdir()
        (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleIdentifier': module.APP_ID,
            'CFBundleExecutable': 'OpenCharge', 'CFBundlePackageType': 'APPL', 'CFBundleVersion': '42', 'LSMinimumSystemVersion': '13.0'}))
        for output in [app / 'Contents/MacOS/OpenCharge', app / 'Contents/MacOS/charged', tools / 'charged', tools / 'chargectl']:
            if len(arches) == 1:
                shutil.copy2(objects[arches[0]], output)
            else:
                run('/usr/bin/lipo', '-create', *[objects[a] for a in arches], '-output', output)
            run('/usr/bin/codesign', '--force', '--sign', '-', output)
        run(sys.executable, SCRIPT, 'prepare', app)
        run(sys.executable, ROOT / 'Scripts/prepare-swift-runtime.py', 'prepare', app, tools)
        sign(app)
        return app, tools

    def duplicate(app, name):
        target = temp / name / 'OpenCharge.app'; shutil.copytree(app, target); return target

    for arches in [['arm64'], ['arm64', 'x86_64']]:
        app, tools = create('positive-' + str(len(arches)), arches)
        before = snapshot(app)
        verify(app)
        assert snapshot(app) == before, 'Verification changed package bytes'
        for requirement in module.requirements(None):
            assert 'code failed' in run('/usr/bin/codesign', '--verify', '-R=' + requirement, app, ok=False)
        for arch in arches:
            info = module.embedded_plist(app / 'Contents/Library/LaunchServices' / module.LABEL, arch, '__info_plist')
            assert info['SMAuthorizedClients'] == ['never'] and info['OpenChargeInstallRoute'] == module.ROUTE
        run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)
        print('PASS legacy helper package', ','.join(arches), ': exact sections/version/identifiers, disabled ad-hoc requirements and read-only audit; no helper launched', flush=True)
        if len(arches) == 1:
            native = app
        else:
            universal = app

    def patch_section(app, name, transform, arch='arm64'):
        helper = app / 'Contents/Library/LaunchServices' / module.LABEL
        thins = []
        scratch = temp / ('edit-' + app.parent.name); scratch.mkdir()
        for item in module.native_arches(helper):
            thin = scratch / item
            if len(module.native_arches(helper)) == 1:
                shutil.copy2(helper, thin)
            else:
                run('/usr/bin/lipo', helper, '-thin', item, '-output', thin)
            if item == arch:
                loads = run('/usr/bin/otool', '-l', thin)
                sections = [part for part in loads.split('Section')[1:] if ('sectname ' + name + '\n') in part]
                assert len(sections) == 1
                import re
                size = int(re.search(r'^\s*size (\S+)', sections[0], re.M)[1], 16)
                offset = int(re.search(r'^\s*offset (\d+)', sections[0], re.M)[1])
                data = bytearray(thin.read_bytes())
                value = plistlib.loads(data[offset:offset + size]); transform(value)
                payload = plistlib.dumps(value).replace(b'\n', b'').replace(b'\t', b'')
                assert len(payload) <= size
                data[offset:offset + size] = payload + b' ' * (size - len(payload)); thin.write_bytes(data)
            # Sign each slice against its own embedded Info before combining.
            run('/usr/bin/codesign', '--force', '--sign', '-', '--identifier', module.LABEL, thin)
            thins.append(thin)
        if len(thins) == 1:
            shutil.copy2(thins[0], helper)
        else:
            run('/usr/bin/lipo', '-create', *thins, '-output', helper)
        sign(app, helper=False)

    wrong = duplicate(native, 'wrong-marker')
    patch_section(wrong, '__info_plist', lambda value: value.update(OpenChargeInstallRoute='foreignV1'))
    assert 'Info.plist mismatch' in verify(wrong, ok=False)
    wrong = duplicate(native, 'broad-authorized-client')
    patch_section(wrong, '__info_plist', lambda value: value.update(SMAuthorizedClients=['always']))
    assert 'Info.plist mismatch' in verify(wrong, ok=False)
    wrong = duplicate(native, 'integer-boolean')
    patch_section(wrong, '__launchd_plist', lambda value: value.update(RunAtLoad=1))
    assert 'launchd plist mismatch' in verify(wrong, ok=False)
    wrong = duplicate(universal, 'wrong-nonhost-slice')
    patch_section(wrong, '__info_plist', lambda value: value.update(CFBundleVersion='41'), arch='x86_64')
    assert 'Info.plist mismatch' in verify(wrong, ok=False)
    wrong = duplicate(native, 'wrong-ownership')
    info = wrong / 'Contents/Info.plist'; value = plistlib.loads(info.read_bytes()); value['SMPrivilegedExecutables'] = {module.LABEL: 'always'}
    info.write_bytes(plistlib.dumps(value)); sign(wrong, helper=False)
    assert 'ownership requirement mismatch' in verify(wrong, ok=False)
    wrong = duplicate(native, 'missing-helper')
    (wrong / 'Contents/Library/LaunchServices' / module.LABEL).unlink()
    assert 'Missing or linked' in verify(wrong, ok=False)
    wrong = duplicate(native, 'symlink-helper')
    helper = wrong / 'Contents/Library/LaunchServices' / module.LABEL; helper.unlink()
    helper.symlink_to(native / 'Contents/Library/LaunchServices' / module.LABEL)
    before = snapshot(native)
    assert 'Missing or linked' in verify(wrong, ok=False)
    assert snapshot(native) == before
    wrong = duplicate(native, 'symlink-directory')
    library = wrong / 'Contents/Library'; shutil.rmtree(library)
    outside = temp / 'outside'; outside.mkdir(); library.symlink_to(outside)
    assert 'Linked helper directory' in run(sys.executable, SCRIPT, 'prepare', wrong, ok=False)
    assert not list(outside.iterdir())
    print('PASS legacy package rejection: signed malformed metadata, integer booleans, nonhost version drift, broad ownership, missing/linked helper and linked directory; no authorization or system writes', flush=True)
