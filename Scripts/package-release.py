#!/usr/bin/env python3
"""Package already-built native/universal apps with matching CLI, service scripts and guides."""
from pathlib import Path
import argparse, hashlib, plistlib, re, stat, subprocess, tempfile, zipfile

ROOT = Path(__file__).resolve().parent.parent
ASSETS = [('dist', 'arm64'), ('dist-universal', 'universal')]

def command(*args):
    return subprocess.check_output(args, text=True).strip()

def files(folder):
    result = []
    for path in sorted(folder.rglob('*')):
        if path.is_symlink():
            raise ValueError('Symbolic links are not supported in this release layout')
        if path.is_file():
            result.append(path)
        elif not path.is_dir():
            raise ValueError('Unexpected package entry type')
    return result

def inspect(folder, architecture):
    app = folder / 'OpenCharge.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    version, build = info['CFBundleShortVersionString'], info['CFBundleVersion']
    if not re.fullmatch(r'\d+\.\d+\.\d+', version) or not re.fullmatch(r'\d+', build):
        raise ValueError('Invalid package version')
    if info.get('LSMinimumSystemVersion') != '13.0' or info.get('CFBundleLocalizations') != ['en', 'zh-Hans']:
        raise ValueError('Unsupported deployment or language declaration')
    subprocess.run(['python3', str(ROOT / 'Scripts/localization-resources.py'), 'verify', str(app)], check=True)
    expected = {'arm64'} if architecture == 'arm64' else {'arm64', 'x86_64'}
    binaries = [app / 'Contents/MacOS/OpenCharge', app / 'Contents/MacOS/charged',
                app / 'Contents/Library/LaunchServices/org.opencharge.charged',
                folder / 'bin/charged', folder / 'bin/chargectl']
    for binary in binaries:
        if not binary.is_file() or binary.is_symlink() or not binary.stat().st_mode & stat.S_IXUSR:
            raise ValueError('Missing regular executable: ' + binary.name)
        if set(command('/usr/bin/lipo', '-archs', str(binary)).split()) != expected:
            raise ValueError('Unexpected executable architecture')
        subprocess.run(['/usr/bin/codesign', '--verify', '--all-architectures', '--strict', str(binary)], check=True)
    def code_hashes(binary):
        hashes = {}
        for cpu in sorted(expected):
            result = subprocess.run(['/usr/bin/codesign', '-d', '--verbose=4', '--arch', cpu, str(binary)], capture_output=True, text=True, check=True)
            matches = re.findall(r'^CandidateCDHashFull sha256=([0-9a-f]{64})$', result.stderr, re.M)
            if len(matches) != 1:
                raise ValueError('Missing unambiguous full code-directory hash')
            hashes[cpu] = matches[0]
        return hashes
    if code_hashes(app / 'Contents/MacOS/charged') != code_hashes(folder / 'bin/charged'):
        raise ValueError('Embedded and standalone helper code differs')
    subprocess.run(['/usr/bin/codesign', '--verify', '--all-architectures', '--deep', '--strict', str(app)], check=True)
    files(folder)
    return version, build

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--output', required=True, type=Path)
    args = parser.parse_args()
    versions = [inspect(ROOT / folder, architecture) for folder, architecture in ASSETS]
    if versions[0] != versions[1]:
        raise ValueError('Native and universal versions differ')
    version, _ = versions[0]
    destinations = [args.output / ('OpenCharge-macOS-' + architecture + '.zip') for _, architecture in ASSETS]
    manifest_path = args.output / 'SHA256SUMS.txt'
    if any(path.exists() or path.is_symlink() for path in [*destinations, manifest_path]):
        raise ValueError('Release output already exists; refusing to overwrite frozen assets')
    payloads = []
    for folder, architecture in ASSETS:
        prefix = Path('OpenCharge-' + version + '-' + architecture)
        payload = [(path, prefix / 'dist' / path.relative_to(ROOT / folder)) for path in files(ROOT / folder)]
        for name in ['install-helper.sh', 'uninstall-helper.sh']:
            payload.append((ROOT / 'Scripts' / name, prefix / 'Scripts' / name))
        for path in files(ROOT / 'docs'):
            payload.append((path, prefix / 'docs' / path.relative_to(ROOT / 'docs')))
        payload.append((ROOT / 'docs/DOWNLOADS.md', prefix / 'README.md'))
        payload.extend((ROOT / name, prefix / name) for name in ['LICENSE', 'SECURITY.md', 'CONTRIBUTING.md', 'CHANGELOG.md'])
        for original, relative in payload:
            if original.is_symlink() or not original.is_file():
                raise ValueError('Release inputs must be regular files')
            content = original.read_bytes()
            if re.search(rb'gh[pousr]_[A-Za-z0-9_]{20,}|github_pat_[A-Za-z0-9_]{20,}', content):
                raise ValueError('Credential pattern found in release input')
            if re.search(r'decision|rationale|整理决策', str(relative), re.I):
                raise ValueError('Excluded document in release input')
        payloads.append(payload)
    args.output.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='opencharge-release-', dir=args.output) as temporary:
        staged = []
        for destination, payload in zip(destinations, payloads):
            archive = Path(temporary) / destination.name
            with zipfile.ZipFile(archive, 'w', zipfile.ZIP_DEFLATED) as package:
                for original, relative in payload:
                    package.write(original, str(relative))
            staged.append(archive)
        manifest = ''.join(hashlib.sha256(path.read_bytes()).hexdigest() + '  ' + path.name + '\n' for path in staged)
        for path, destination in zip(staged, destinations):
            path.replace(destination)
        manifest_path.write_text(manifest)
    print('Packaged ' + version + ': ' + ', '.join(path.name for path in destinations) + ', SHA256SUMS.txt')

if __name__ == '__main__':
    main()
