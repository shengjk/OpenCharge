import hashlib
import os
from pathlib import Path
import plistlib
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
BUILD = ROOT / '.build/runtime-packaging'
BUILD.mkdir(parents=True, exist_ok=True)
ENV = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(BUILD / 'module-cache'))
SCRIPT = ROOT / 'Scripts/prepare-swift-runtime.py'


def command(*args, ok=True):
    result = subprocess.run([str(x) for x in args], env=ENV, capture_output=True, text=True)
    if ok and result.returncode:
        raise AssertionError('Command failed: ' + str(args[0]) + '\n' + result.stdout + result.stderr)
    if not ok:
        assert result.returncode != 0, 'Malformed package unexpectedly accepted'
        return result.stdout + result.stderr
    return result.stdout


def package_command(mode, app, tools, ok=True):
    return command(sys.executable, SCRIPT, mode, app, tools, ok=ok)


def snapshot(folder):
    return {str(p.relative_to(folder)): hashlib.sha256(p.read_bytes()).hexdigest()
            for p in folder.rglob('*') if p.is_file() and not p.is_symlink()}


def sign(app, tools):
    for path in [app / 'Contents/MacOS/charged', tools / 'charged', tools / 'chargectl']:
        command('/usr/bin/codesign', '--force', '--sign', '-', path)
    command('/usr/bin/codesign', '--force', '--sign', '-', app)
    command('/usr/bin/codesign', '--verify', '--deep', '--strict', app)


with tempfile.TemporaryDirectory(prefix='fixture.', dir=BUILD) as temporary:
    temp = Path(temporary)
    source = temp / 'AsyncProbe.swift'
    source.write_text('''import Foundation
import MachO
@main struct AsyncProbe {
 static func main() async {
  await Task.yield()
  print("async-probe 42")
  for index in 0..<_dyld_image_count() {
   if let raw = _dyld_get_image_name(index) {
    let name = String(cString: raw)
    if name.hasSuffix("/libswift_Concurrency.dylib") { print("runtime " + name) }
   }
  }
 }
}
''')
    sync = temp / 'Helper.c'; sync.write_text('int main(void) { return 0; }\n')
    binaries = {}
    for arch in ['arm64', 'x86_64']:
        for floor in [11, 13]:
            binary = temp / ('async-' + arch + '-' + str(floor))
            command('/usr/bin/xcrun', 'swiftc', '-parse-as-library', '-target', arch + '-apple-macosx' + str(floor) + '.0', source,
                    '-Xlinker', '-headerpad_max_install_names', '-o', binary)
            binaries[arch, floor] = binary
        binary = temp / ('helper-' + arch)
        command('/usr/bin/xcrun', 'clang', '-target', arch + '-apple-macosx11.0', sync,
                '-Wl,-headerpad_max_install_names', '-Wl,-rpath,/usr/lib/swift', '-Wl,-rpath,/tmp/developer-tools/runtime', '-o', binary)
        binaries[arch, 'helper'] = binary

    def create(name, floor, arches):
        directory = temp / name; app = directory / 'Runtime Fixture.app'; tools = directory / 'bin'
        (app / 'Contents/MacOS').mkdir(parents=True); tools.mkdir()
        with (app / 'Contents/Info.plist').open('wb') as stream:
            plistlib.dump({'CFBundleIdentifier': 'org.opencharge.app', 'CFBundleExecutable': 'OpenCharge',
                          'CFBundlePackageType': 'APPL', 'LSMinimumSystemVersion': str(floor) + '.0'}, stream)
        for dest, kind in [(app / 'Contents/MacOS/OpenCharge', floor), (app / 'Contents/MacOS/charged', 'helper'),
                           (tools / 'charged', 'helper'), (tools / 'chargectl', 'helper')]:
            inputs = [binaries[a, kind] for a in arches]
            if len(inputs) == 1:
                shutil.copy2(inputs[0], dest)
            else:
                command('/usr/bin/lipo', '-create', *inputs, '-output', dest)
        return app, tools

    def duplicate(name, app, tools):
        directory = temp / name
        shutil.copytree(app.parent, directory)
        return directory / app.name, directory / tools.name

    cases = {}
    for floor in [11, 13]:
        for arches in [['arm64'], ['arm64', 'x86_64']]:
            app, tools = create('package-' + str(floor) + '-' + str(len(arches)), floor, arches)
            package_command('prepare', app, tools)
            runtime = app / 'Contents/Frameworks/libswift_Concurrency.dylib'
            assert runtime.exists() == (floor == 11)
            if runtime.exists():
                assert set(command('/usr/bin/lipo', '-archs', runtime).split()) == set(arches)
            sign(app, tools)
            before = snapshot(app.parent)
            package_command('verify', app, tools)
            assert snapshot(app.parent) == before, 'Read-only verification changed package bytes'
            package_command('prepare', app, tools)
            sign(app, tools)
            package_command('verify', app, tools)
            moved, moved_tools = duplicate('Moved packages 移动 ' + str(floor) + str(len(arches)), app, tools)
            package_command('verify', moved, moved_tools)
            for arch in arches:
                output = command('/usr/bin/arch', '-' + arch, moved / 'Contents/MacOS/OpenCharge')
                assert 'async-probe 42' in output
                assert 'runtime /usr/lib/swift/libswift_Concurrency.dylib' in output, 'Newer OS must prefer its system runtime'
            cases[floor, len(arches)] = app, tools
            print('PASS runtime package: macOS target', floor, 'architectures', ','.join(arches), flush=True)

    # Universal input can mix a prepared host slice and an unprepared cross slice.
    app, tools = create('mixed-slices', 11, ['arm64', 'x86_64'])
    prepared = cases[11, 1][0] / 'Contents/MacOS/OpenCharge'
    command('/usr/bin/lipo', '-create', prepared, binaries['x86_64', 11], '-output', app / 'Contents/MacOS/OpenCharge')
    package_command('prepare', app, tools); sign(app, tools); package_command('verify', app, tools)

    base_app, base_tools = cases[11, 2]
    app, tools = duplicate('missing-runtime', base_app, base_tools)
    (app / 'Contents/Frameworks/libswift_Concurrency.dylib').unlink()
    assert 'Missing Swift concurrency' in package_command('verify', app, tools, ok=False)
    app, tools = duplicate('wrong-runtime-architecture', base_app, base_tools)
    shutil.copy2(cases[11, 1][0] / 'Contents/Frameworks/libswift_Concurrency.dylib', app / 'Contents/Frameworks/libswift_Concurrency.dylib')
    assert 'architecture mismatch' in package_command('verify', app, tools, ok=False)
    app, tools = duplicate('runtime-signature', base_app, base_tools)
    runtime = app / 'Contents/Frameworks/libswift_Concurrency.dylib'
    contents = bytearray(runtime.read_bytes())
    magic = int.from_bytes(contents[:4], 'big')
    offset = int.from_bytes(contents[16:20], 'big') if magic == 0xcafebabe else int.from_bytes(contents[16:24], 'big') if magic == 0xcafebabf else 0
    contents[offset + 4096] ^= 1; runtime.write_bytes(contents)
    assert 'codesign' in package_command('verify', app, tools, ok=False)
    app, tools = duplicate('toolchain-rpath', base_app, base_tools)
    command('/usr/bin/install_name_tool', '-add_rpath', '/tmp/accidental-toolchain', app / 'Contents/MacOS/OpenCharge')
    assert 'Nonportable' in package_command('verify', app, tools, ok=False)
    app, tools = create('unsupported-helper-runtime', 11, ['arm64'])
    shutil.copy2(binaries['arm64', 11], tools / 'charged')
    before = snapshot(app.parent)
    assert 'standalone helper/tool' in package_command('prepare', app, tools, ok=False)
    assert snapshot(app.parent) == before
    app, tools = create('inaccurate-floor', 13, ['arm64'])
    metadata = app / 'Contents/Info.plist'
    with metadata.open('rb') as stream:
        value = plistlib.load(stream)
    value['LSMinimumSystemVersion'] = '11.0'
    with metadata.open('wb') as stream:
        plistlib.dump(value, stream)
    before = snapshot(app.parent)
    assert 'newer macOS than Info.plist' in package_command('prepare', app, tools, ok=False)
    assert snapshot(app.parent) == before
    app, tools = duplicate('symlink-runtime', base_app, base_tools)
    runtime = app / 'Contents/Frameworks/libswift_Concurrency.dylib'; runtime.unlink()
    runtime.symlink_to(base_app / 'Contents/Frameworks/libswift_Concurrency.dylib')
    before = snapshot(base_app.parent)
    assert 'regular file' in package_command('prepare', app, tools, ok=False)
    assert snapshot(base_app.parent) == before
    app, tools = duplicate('unknown-framework', base_app, base_tools)
    (app / 'Contents/Frameworks/foreign.dylib').write_text('foreign file')
    before = snapshot(app.parent)
    assert 'Unexpected file' in package_command('prepare', app, tools, ok=False)
    assert snapshot(app.parent) == before
    print('PASS runtime rejection: missing/wrong-arch/invalid-signature runtime, SDK RPATH, helper dependency, false floor, symlink and unknown framework; no installed app/service touched', flush=True)
