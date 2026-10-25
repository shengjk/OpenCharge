#!/usr/bin/env python3
"""Build or verify the signed package needed by the older privileged-helper API.
No authorization, installation, launchd or helper IPC operation is performed.
"""
import argparse
import hashlib
import os
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import tempfile

LABEL = 'org.opencharge.charged'
APP_ID = 'org.opencharge.app'
ROUTE = 'blessedV1'
ARCHES = {'arm64', 'x86_64'}

class PackageError(Exception):
    pass

def require(condition, message):
    if not condition:
        raise PackageError(message)

def command(*args, allow_failure=False, env=None):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True, env=env)
    if result.returncode and not allow_failure:
        raise PackageError('Tool failed: ' + str(args[0]) + '\n' + result.stdout + result.stderr)
    return result

def output(*args):
    return command(*args).stdout.strip()

def requirements(team):
    if team is None:
        return 'never', 'never'
    require(re.fullmatch(r'[A-Z0-9]{10}', team) is not None, 'Invalid signing team')
    common = ' and anchor apple generic and certificate leaf[subject.OU] = "' + team + '"'
    return 'identifier "' + LABEL + '"' + common, 'identifier "' + APP_ID + '"' + common

def signing_team(path):
    command('/usr/bin/codesign', '--verify', '--strict', path)
    valid = command('/usr/bin/codesign', '--verify', '--strict', '-R=anchor apple generic', path, allow_failure=True)
    if valid.returncode:
        return None
    text = command('/usr/bin/codesign', '--display', '--verbose=4', path).stderr
    team = re.search(r'^TeamIdentifier=([A-Z0-9]{10})$', text, re.M)
    require(team is not None, 'Apple-issued signature has no signing team')
    return team[1]

def candidate(app):
    require(not app.is_symlink(), 'Application cannot be a symlink')
    for directory in [app, app / 'Contents', app / 'Contents/MacOS']:
        require(directory.is_dir() and not directory.is_symlink(), 'Missing or linked application directory')
    info = app / 'Contents/Info.plist'
    require(info.is_file() and not info.is_symlink(), 'Missing application Info.plist')
    metadata = plistlib.loads(info.read_bytes())
    require(metadata.get('CFBundleIdentifier') == APP_ID and metadata.get('CFBundleExecutable') == 'OpenCharge', 'Unexpected application identity')
    require(isinstance(metadata.get('CFBundleVersion'), str) and re.fullmatch(r'\d+(?:\.\d+){0,2}', metadata['CFBundleVersion']) is not None, 'Invalid helper build version')
    return app / 'Contents/Library/LaunchServices' / LABEL, metadata

def native_arches(path):
    values = output('/usr/bin/lipo', '-archs', path).split()
    require(values and set(values) <= ARCHES, 'Unsupported helper architectures')
    return values

def embedded_plist(binary, arch, name):
    """Read the exact section size; ignore linker alignment padding after it."""
    with tempfile.TemporaryDirectory(prefix='opencharge-section.') as temporary:
        thin = Path(temporary) / 'helper'
        if len(native_arches(binary)) == 1:
            shutil.copy2(binary, thin)
        else:
            command('/usr/bin/lipo', binary, '-thin', arch, '-output', thin)
        loads = output('/usr/bin/otool', '-l', thin)
        matches = []
        for section in loads.split('Section')[1:]:
            if re.search(r'^\s*sectname ' + re.escape(name) + r'\s*$', section, re.M) and re.search(r'^\s*segname __TEXT\s*$', section, re.M):
                size = int(re.search(r'^\s*size (\S+)', section, re.M)[1], 16)
                offset = int(re.search(r'^\s*offset (\d+)', section, re.M)[1])
                require(0 < size <= 16384 and offset + size <= thin.stat().st_size, 'Invalid embedded plist bounds')
                with thin.open('rb') as stream:
                    stream.seek(offset); matches.append(plistlib.loads(stream.read(size)))
        require(len(matches) == 1, 'Missing or duplicated embedded plist: ' + name)
        return matches[0]

def same_plist(left, right):
    return plistlib.dumps(left, sort_keys=True) == plistlib.dumps(right, sort_keys=True)

def expected_info(metadata, client):
    return {'CFBundleIdentifier': LABEL, 'CFBundleInfoDictionaryVersion': '6.0',
            'CFBundleName': 'OpenCharge Hardware Helper', 'CFBundleVersion': metadata['CFBundleVersion'],
            'SMAuthorizedClients': [client], 'OpenChargeInstallRoute': ROUTE}

def expected_launchd():
    return {'Label': LABEL, 'RunAtLoad': True, 'KeepAlive': True, 'ThrottleInterval': 30, 'ProcessType': 'Interactive'}

def build_modules(project, arch, compiler):
    root = project / '.build/legacy-helper' / arch
    root.mkdir(parents=True, exist_ok=True)
    files = sorted(list((project / 'Sources/ChargeCore').glob('*.swift')) + list((project / 'Sources/ChargeHardware').glob('*.swift')) +
                   list((project / 'Sources/ApplePowerConstants').rglob('*.h')) + list((project / 'Sources/ApplePowerConstants').glob('*.c')))
    digest = hashlib.sha256()
    for path in files:
        digest.update(str(path.relative_to(project)).encode()); digest.update(path.read_bytes())
    digest.update(output(compiler, '--version').encode())
    sdk = Path(output('/usr/bin/xcrun', '--show-sdk-path'))
    digest.update(str(sdk).encode())
    for name in ['SDKSettings.json', 'SDKSettings.plist']:
        if (sdk / name).exists():
            digest.update((sdk / name).read_bytes())
    digest.update(output('/usr/bin/xcrun', '--show-sdk-version').encode())
    digest.update(b'macos11-static-optimized-v1')
    fingerprint = digest.hexdigest()
    stamp = root / 'sources.sha256'
    artifacts = [root / name for name in ['ChargeCore.swiftmodule', 'libChargeCore.a', 'ChargeHardware.swiftmodule', 'libChargeHardware.a', 'ApplePowerConstants.o']]
    env = dict(os.environ, CLANG_MODULE_CACHE_PATH=str(project / '.build/legacy-helper/module-cache'))
    if stamp.exists() and stamp.read_text() == fingerprint and all(p.exists() for p in artifacts):
        return root, env
    bridge = root / 'ApplePowerConstants'; bridge.mkdir(exist_ok=True)
    shutil.copy2(project / 'Sources/ApplePowerConstants/include/ApplePowerConstants.h', bridge)
    (bridge / 'module.modulemap').write_text('module ApplePowerConstants { header "ApplePowerConstants.h" export * }\n')
    triple = arch + '-apple-macosx11.0'
    command('/usr/bin/xcrun', 'clang', '-target', triple, '-I', project / 'Sources/ApplePowerConstants/include', '-c',
            project / 'Sources/ApplePowerConstants/ApplePowerConstants.c', '-o', root / 'ApplePowerConstants.o', env=env)
    for module in ['ChargeCore', 'ChargeHardware']:
        command(compiler, '-sdk', sdk, '-O', '-target', triple, '-parse-as-library', '-emit-module', '-emit-library', '-static', '-module-name', module,
                '-I', bridge, *sorted((project / ('Sources/' + module)).glob('*.swift')), '-emit-module-path', root / (module + '.swiftmodule'),
                '-o', root / ('lib' + module + '.a'), env=env)
    stamp.write_text(fingerprint)
    return root, env

def prepare(app, project):
    helper, metadata = candidate(app)
    current = app / 'Contents/MacOS/charged'
    team = signing_team(current)
    tool_requirement, client_requirement = requirements(team)
    for requirement in [tool_requirement, client_requirement]:
        command('/usr/bin/csreq', '-r=' + requirement, '-t')
    parent = helper.parent
    for directory in [app / 'Contents/Library', parent]:
        if directory.exists() or directory.is_symlink():
            require(directory.is_dir() and not directory.is_symlink(), 'Linked helper directory')
        else:
            directory.mkdir()
    require(not helper.is_symlink(), 'Helper cannot be a symlink')
    compiler = output('/usr/bin/xcrun', '--find', 'swiftc')
    sdk = output('/usr/bin/xcrun', '--show-sdk-path')
    arches = native_arches(app / 'Contents/MacOS/OpenCharge')
    with tempfile.TemporaryDirectory(prefix='.legacy-helper.', dir=project / '.build') as temporary:
        temporary = Path(temporary)
        info = temporary / 'Info.plist'; launchd = temporary / 'launchd.plist'
        info.write_bytes(plistlib.dumps(expected_info(metadata, client_requirement)))
        launchd.write_bytes(plistlib.dumps(expected_launchd()))
        outputs = []
        for arch in arches:
            modules, env = build_modules(project, arch, compiler)
            binary = temporary / arch
            command(compiler, '-sdk', sdk, '-O', '-target', arch + '-apple-macosx11.0', '-module-name', 'charged',
                    '-I', modules, '-I', modules / 'ApplePowerConstants', project / 'Sources/charged/main.swift',
                    modules / 'libChargeCore.a', modules / 'libChargeHardware.a', modules / 'ApplePowerConstants.o', '-framework', 'IOKit',
                    '-Xlinker', '-headerpad_max_install_names',
                    '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__info_plist', '-Xlinker', info,
                    '-Xlinker', '-sectcreate', '-Xlinker', '__TEXT', '-Xlinker', '__launchd_plist', '-Xlinker', launchd,
                    '-o', binary, env=env)
            outputs.append(binary)
        combined = temporary / LABEL
        if len(outputs) == 1:
            shutil.copy2(outputs[0], combined)
        else:
            command('/usr/bin/lipo', '-create', *outputs, '-output', combined)
        command('/usr/bin/strip', '-S', combined)
        combined.chmod(0o755); combined.replace(helper)
    metadata['SMPrivilegedExecutables'] = {LABEL: tool_requirement}
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps(metadata))
    print('Prepared embedded legacy helper metadata; authorization requirements: ' + ('signing team' if team else 'disabled (no Apple-issued team)'))

def verify(app):
    helper, metadata = candidate(app)
    require(helper.is_file() and not helper.is_symlink() and helper.stat().st_nlink == 1, 'Missing or linked legacy helper')
    arches = native_arches(helper)
    require(set(arches) == set(native_arches(app / 'Contents/MacOS/OpenCharge')), 'Legacy helper architecture mismatch')
    team = signing_team(app)
    tool_requirement, client_requirement = requirements(team)
    require(metadata.get('SMPrivilegedExecutables') == {LABEL: tool_requirement}, 'App helper ownership requirement mismatch')
    require(signing_team(helper) == team, 'Legacy helper signing team mismatch')
    command('/usr/bin/codesign', '--verify', '--strict', '-R=identifier "' + APP_ID + '"', app)
    for arch in arches:
        loads = output('/usr/bin/otool', '-arch', arch, '-l', helper)
        require(re.search(r'\bminos 11\.0\s', loads) is not None, 'Legacy helper must target macOS 11')
        require(same_plist(embedded_plist(helper, arch, '__info_plist'), expected_info(metadata, client_requirement)), 'Embedded helper Info.plist mismatch')
        require(same_plist(embedded_plist(helper, arch, '__launchd_plist'), expected_launchd()), 'Embedded launchd plist mismatch')
        command('/usr/bin/codesign', '--verify', '--strict', '--arch', arch, '-R=identifier "' + LABEL + '"', helper)
        if team:
            command('/usr/bin/codesign', '--verify', '--strict', '--arch', arch, '-R=' + tool_requirement, helper)
            command('/usr/bin/codesign', '--verify', '--strict', '--arch', arch, '-R=' + client_requirement, app)
    print('Verified legacy helper sections, identifiers and versions in ' + str(len(arches)) + ' slice(s); reciprocal authorization: ' + ('signing team verified' if team else 'disabled by never requirements') + '; installation not performed')

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'verify'])
    parser.add_argument('app', type=Path)
    parser.add_argument('--project', type=Path, default=Path(__file__).resolve().parent.parent)
    args = parser.parse_args()
    try:
        if args.mode == 'prepare':
            prepare(args.app, args.project)
        else:
            verify(args.app)
    except (PackageError, OSError, ValueError, KeyError, TypeError, plistlib.InvalidFileException) as error:
        parser.exit(1, 'Legacy helper package check failed: ' + str(error) + '\n')

if __name__ == '__main__':
    main()
