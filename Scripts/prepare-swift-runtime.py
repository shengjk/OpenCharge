#!/usr/bin/env python3
"""Prepare or audit a staged OpenCharge package. Never installs or launches code."""
import argparse
import os
from pathlib import Path
import plistlib
import re
import shutil
import stat
import subprocess
import tempfile

CONCURRENCY = 'libswift_Concurrency.dylib'
SYSTEM_SWIFT = '/usr/lib/swift'
APP_FRAMEWORKS = '@executable_path/../Frameworks'
SUPPORTED_ARCHES = {'arm64', 'x86_64'}

class PackageError(Exception):
    pass

def require(condition, message):
    if not condition:
        raise PackageError(message)

def run(*args):
    result = subprocess.run([str(x) for x in args], capture_output=True, text=True)
    if result.returncode:
        raise PackageError('Tool failed: ' + str(args[0]) + '\n' + (result.stdout + result.stderr).strip())
    return result.stdout.strip()

def version(text):
    require(re.fullmatch(r'\d+(?:\.\d+){0,2}', text) is not None, 'Invalid deployment version')
    values = tuple(int(x) for x in text.split('.'))
    return values + (0,) * (3 - len(values))

def regular(path):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, 'Expected an unlinked regular file: ' + str(path))

def directory(path):
    require(path.is_dir() and not path.is_symlink(), 'Expected a real directory: ' + str(path))

def inspect(path):
    regular(path)
    arches = run('/usr/bin/lipo', '-archs', path).split()
    require(arches and set(arches) <= SUPPORTED_ARCHES, 'Unsupported Mach-O architectures')
    result = {}
    for arch in arches:
        loads = run('/usr/bin/otool', '-arch', arch, '-l', path)
        item = {'rpaths': [], 'dependencies': [], 'id': None, 'minimum': None}
        for chunk in loads.split('Load command ')[1:]:
            command = re.search(r'^\s*cmd (\S+)', chunk, re.M)
            if not command:
                continue
            command = command[1]
            if command == 'LC_RPATH':
                item['rpaths'].append(re.search(r'^\s*path (.+) \(offset ', chunk, re.M)[1])
            elif command in {'LC_LOAD_DYLIB', 'LC_LOAD_WEAK_DYLIB', 'LC_REEXPORT_DYLIB', 'LC_LOAD_UPWARD_DYLIB'}:
                item['dependencies'].append(re.search(r'^\s*name (.+) \(offset ', chunk, re.M)[1])
            elif command == 'LC_ID_DYLIB':
                item['id'] = re.search(r'^\s*name (.+) \(offset ', chunk, re.M)[1]
            elif command == 'LC_VERSION_MIN_MACOSX':
                item['minimum'] = version(re.search(r'^\s*version (\S+)', chunk, re.M)[1])
            elif command == 'LC_BUILD_VERSION' and re.search(r'^\s*platform (?:1|MACOS)\s*$', chunk, re.M):
                item['minimum'] = version(re.search(r'^\s*minos (\S+)', chunk, re.M)[1])
        require(item['minimum'] is not None, 'Missing macOS deployment command: ' + str(path))
        result[arch] = item
    return result

def is_system(name):
    return name.startswith('/System/Library/') or name.startswith('/usr/lib/')

def validate_dependencies(slices, role):
    for item in slices.values():
        for name in item['dependencies']:
            allowed = is_system(name) or name in {'@rpath/libswiftCore.dylib', '@rpath/' + CONCURRENCY}
            require(allowed, 'Unsupported non-system dependency in ' + role + ': ' + name)
            if Path(name).name == CONCURRENCY and item['minimum'] < (12, 0, 0):
                require(role == 'application', 'A standalone helper/tool cannot depend on the app backdeployment runtime')

def layout(app, tools):
    require(not app.is_symlink() and not tools.is_symlink(), 'Package roots cannot be symlinks')
    app = app.resolve(strict=True); tools = tools.resolve(strict=True)
    directory(app); directory(tools); directory(app / 'Contents')
    directory(app / 'Contents/MacOS')
    info = app / 'Contents/Info.plist'; regular(info)
    with info.open('rb') as stream:
        metadata = plistlib.load(stream)
    require(metadata.get('CFBundleIdentifier') == 'org.opencharge.app' and metadata.get('CFBundleExecutable') == 'OpenCharge', 'Unexpected application identity')
    floor = version(metadata['LSMinimumSystemVersion'])
    paths = [(app / 'Contents/MacOS/OpenCharge', 'application'),
             (app / 'Contents/MacOS/charged', 'embedded helper'),
             (tools / 'charged', 'standalone helper'), (tools / 'chargectl', 'CLI')]
    legacy = app / 'Contents/Library/LaunchServices/org.opencharge.charged'
    if 'SMPrivilegedExecutables' in metadata or legacy.exists() or legacy.is_symlink():
        directory(app / 'Contents/Library')
        directory(legacy.parent)
        paths.append((legacy, 'legacy privileged helper'))
    records = [(p, role, inspect(p)) for p, role in paths]
    arches = set(records[0][2])
    for path, role, slices in records:
        require(set(slices) == arches, 'Package executable architecture mismatch: ' + role)
        require(all(item['minimum'] <= floor for item in slices.values()), 'Binary requires a newer macOS than Info.plist: ' + role)
        validate_dependencies(slices, role)
    frameworks = app / 'Contents/Frameworks'
    if frameworks.exists() or frameworks.is_symlink():
        directory(frameworks)
        require(all(p.name == CONCURRENCY for p in frameworks.iterdir()), 'Unexpected file in staged Frameworks directory')
        if (frameworks / CONCURRENCY).exists() or (frameworks / CONCURRENCY).is_symlink():
            regular(frameworks / CONCURRENCY)
    needs_runtime = any(item['minimum'] < (12, 0, 0) and any(Path(d).name == CONCURRENCY for d in item['dependencies']) for item in records[0][2].values())
    return app, records, frameworks, needs_runtime

def rewrite(path, slices, wanted, change_concurrency=False):
    """Edit individual slices: universal input may mix prepared and raw RPATHs."""
    if all(item['rpaths'] == wanted and not (change_concurrency and '/usr/lib/swift/' + CONCURRENCY in item['dependencies']) for item in slices.values()):
        return
    with tempfile.TemporaryDirectory(prefix='.runtime-edit.', dir=path.parent) as temporary:
        temporary = Path(temporary)
        parts = []
        for arch, item in slices.items():
            part = temporary / arch
            if len(slices) == 1:
                shutil.copy2(path, part)
            else:
                run('/usr/bin/lipo', path, '-thin', arch, '-output', part)
            removals = []
            for old in item['rpaths']:
                removals += ['-delete_rpath', old]
            if removals:
                run('/usr/bin/install_name_tool', *removals, part)
            options = []
            for new in wanted:
                options += ['-add_rpath', new]
            if change_concurrency and '/usr/lib/swift/' + CONCURRENCY in item['dependencies']:
                options += ['-change', '/usr/lib/swift/' + CONCURRENCY, '@rpath/' + CONCURRENCY]
            if options:
                run('/usr/bin/install_name_tool', *options, part)
            parts.append(part)
        output = temporary / 'result'
        if len(parts) == 1:
            shutil.copy2(parts[0], output)
        else:
            run('/usr/bin/lipo', '-create', *parts, '-output', output)
        output.chmod(stat.S_IMODE(path.stat().st_mode))
        output.replace(path)

def validate_runtime(runtime, app_slices):
    slices = inspect(runtime)
    require(set(slices) == set(app_slices), 'Embedded runtime architecture mismatch')
    for arch, item in slices.items():
        require(item['id'] == '@rpath/' + CONCURRENCY, 'Unexpected runtime install name')
        require(item['minimum'] <= app_slices[arch]['minimum'], 'Embedded runtime requires a newer macOS than the app')
        require(all(p == SYSTEM_SWIFT for p in item['rpaths']), 'Embedded runtime contains a non-system RPATH')
        for dependency in item['dependencies']:
            require(is_system(dependency) or dependency == '@rpath/libswiftCore.dylib', 'Unsupported embedded runtime dependency')
    run('/usr/bin/codesign', '--verify', '--strict', runtime)

def embed_runtime(main, app_slices, frameworks, identity):
    compiler = Path(run('/usr/bin/xcrun', '--find', 'swiftc')).resolve()
    tool = compiler.parents[1] / 'bin/swift-stdlib-tool'
    source = compiler.parents[1] / 'lib/swift-5.5/macosx'
    regular(source / CONCURRENCY)
    source_slices = inspect(source / CONCURRENCY)
    require(set(app_slices) <= set(source_slices), 'Selected toolchain runtime lacks a required architecture')
    for arch, item in app_slices.items():
        require(source_slices[arch]['minimum'] <= item['minimum'], 'Selected runtime is too new for the app')
    printed = run(tool, '--print', '--scan-executable', main, '--platform', 'macosx', '--source-libraries', source)
    require(printed.splitlines() == [str(source / CONCURRENCY)], 'Unexpected Swift backdeployment dependency closure')
    with tempfile.TemporaryDirectory(prefix='.swift-runtime.', dir=frameworks.parent) as temporary:
        temporary = Path(temporary)
        run(tool, '--copy', '--scan-executable', main, '--platform', 'macosx', '--source-libraries', source,
            '--destination', temporary)
        require({p.name for p in temporary.iterdir()} == {CONCURRENCY}, 'Unexpected copied Swift runtime content')
        runtime = temporary / CONCURRENCY
        copied = inspect(runtime)
        if set(copied) != set(app_slices):
            thinned = temporary / 'thinned'
            options = []
            for arch in app_slices:
                options += ['-extract', arch]
            run('/usr/bin/lipo', runtime, *options, '-output', thinned)
            thinned.replace(runtime)
        run('/usr/bin/codesign', '--force', '--sign', identity, runtime)
        validate_runtime(runtime, app_slices)
        if not frameworks.exists():
            frameworks.mkdir()
        runtime.replace(frameworks / CONCURRENCY)

def audit(app, tools):
    app, records, frameworks, needed = layout(app, tools)
    for path, role, slices in records:
        expected = [SYSTEM_SWIFT, APP_FRAMEWORKS] if role == 'application' else [SYSTEM_SWIFT]
        require(all(item['rpaths'] == expected for item in slices.values()), 'Nonportable or incorrectly ordered RPATHs: ' + role)
        if needed and role == 'application':
            require(all('@rpath/' + CONCURRENCY in item['dependencies'] for item in slices.values()), 'Backdeployment dependency must use @rpath')
    runtime = frameworks / CONCURRENCY
    if needed:
        require(runtime.exists(), 'Missing Swift concurrency backdeployment runtime')
        validate_runtime(runtime, records[0][2])
    else:
        require(not runtime.exists(), 'Unnecessary/stale Swift concurrency runtime')
    print('Verified portable RPATHs in all executable slices; bundled Swift concurrency runtime: ' + ('required and validated' if needed else 'not required'))

def prepare(app, tools, identity):
    app, records, frameworks, needed = layout(app, tools)
    require(needed or not (frameworks / CONCURRENCY).exists(), 'Remove stale runtime by rebuilding a fresh staging package')
    for path, role, slices in records:
        wanted = [SYSTEM_SWIFT, APP_FRAMEWORKS] if role == 'application' else [SYSTEM_SWIFT]
        rewrite(path, slices, wanted, change_concurrency=needed and role == 'application')
    if needed:
        embed_runtime(records[0][0], inspect(records[0][0]), frameworks, identity)
    audit(app, tools)

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'verify'])
    parser.add_argument('app', type=Path)
    parser.add_argument('tools', type=Path)
    parser.add_argument('--identity', default='-')
    args = parser.parse_args()
    try:
        if args.mode == 'prepare':
            prepare(args.app, args.tools, args.identity)
        else:
            audit(args.app, args.tools)
    except (PackageError, OSError, ValueError, KeyError, plistlib.InvalidFileException) as error:
        parser.exit(1, 'Runtime package check failed: ' + str(error) + '\n')

if __name__ == '__main__':
    main()
