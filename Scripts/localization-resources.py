#!/usr/bin/env python3
"""Prepare or read-only verify all source-owned language resources in an app bundle."""
from pathlib import Path
import argparse, plistlib, re, shutil

source = Path(__file__).resolve().parent.parent / 'Resources'

def inventory():
    result = {}
    for folder in sorted(source.glob('*.lproj')):
        language = folder.name[:-6]
        if folder.is_symlink() or not folder.is_dir() or not re.fullmatch(r'[a-z]{2,3}(?:-[A-Za-z0-9]{2,8})*', language):
            raise ValueError('Invalid source localization directory')
        files = {p.name: p for p in folder.iterdir()}
        if not {'Localizable.strings', 'AppShortcuts.strings'} <= files.keys() or not files.keys() <= {'Localizable.strings', 'AppShortcuts.strings', 'Localizable.stringsdict'}:
            raise ValueError('Unexpected source localization files: ' + language)
        if any(p.is_symlink() or not p.is_file() for p in files.values()):
            raise ValueError('Localization resources must be regular files')
        result[language] = files
    if set(result) != {'en', 'zh-Hans'}:
        raise ValueError('Only English and Simplified Chinese localizations are supported')
    return result

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('mode', choices=['prepare', 'verify'])
    parser.add_argument('app', type=Path)
    args = parser.parse_args()
    languages = inventory()
    resources = args.app / 'Contents/Resources'
    info_path = args.app / 'Contents/Info.plist'
    if args.app.is_symlink() or resources.is_symlink() or info_path.is_symlink():
        raise ValueError('App localization paths must not be symbolic links')
    info = plistlib.loads(info_path.read_bytes())
    if info.get('CFBundleDevelopmentRegion') != 'en':
        raise ValueError('Expected English development region')
    if args.mode == 'prepare':
        resources.mkdir(parents=True, exist_ok=True)
        existing = sorted(p.name for p in resources.glob('*.lproj'))
        if existing:
            raise ValueError('Prepare requires a clean localization destination')
        for language in languages:
            shutil.copytree(source / (language + '.lproj'), resources / (language + '.lproj'))
        info['CFBundleLocalizations'] = list(languages)
        info_path.write_bytes(plistlib.dumps(info, sort_keys=False))
    if info.get('CFBundleLocalizations') != list(languages):
        raise ValueError('Declared app languages differ from source resources')
    if sorted(p.name for p in resources.glob('*.lproj')) != [name + '.lproj' for name in languages]:
        raise ValueError('Packaged language directories differ from source resources')
    for language, files in languages.items():
        folder = resources / (language + '.lproj')
        if folder.is_symlink() or not folder.is_dir() or set(p.name for p in folder.iterdir()) != set(files):
            raise ValueError('Unexpected packaged localization files: ' + language)
        for name, original in files.items():
            path = folder / name
            if path.is_symlink() or not path.is_file() or path.read_bytes() != original.read_bytes():
                raise ValueError('Packaged localization differs from source: ' + language + '/' + name)
    print('Verified packaged localization declarations and exact resources: ' + ', '.join(languages))

if __name__ == '__main__':
    main()
