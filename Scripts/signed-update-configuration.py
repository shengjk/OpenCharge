#!/usr/bin/env python3
"""Apply build-time public update metadata; never generates or reads private keys."""
from pathlib import Path
import base64
import binascii
import os
import plistlib
import stat
import sys
import tempfile

FEED = 'https://raw.githubusercontent.com/shengjk/OpenCharge/main/updates/appcast.xml'
DEFAULTS = {
    'SUEnableAutomaticChecks': False,
    'SUAutomaticallyUpdate': False,
    'SUAllowsAutomaticUpdates': True,
    'SUEnableSystemProfiling': False,
    'SUVerifyUpdateBeforeExtraction': True,
    'SURequireSignedFeed': True,
    'SUEnableJavaScript': False,
    'SUEnableInstallerLauncherService': False,
    'SUEnableDownloaderService': False,
    'SUSignedFeedFailureExpirationInterval': 0,
}

def configure(app, public_key):
    contents = app / 'Contents'
    path = contents / 'Info.plist'
    if app.is_symlink() or contents.is_symlink() or path.is_symlink() or not path.is_file():
        raise ValueError('Expected a regular application Info.plist')
    raw = path.read_bytes()
    if len(raw) > 1024 * 1024:
        raise ValueError('Application metadata exceeds the build limit')
    info = plistlib.loads(raw)
    if not isinstance(info, dict) or info.get('CFBundleIdentifier') != 'org.opencharge.app':
        raise ValueError('Unexpected application identifier')
    if public_key is not None:
        try:
            key = base64.b64decode(public_key, validate=True)
        except (binascii.Error, ValueError):
            raise ValueError('Update public key must be a canonical 32-byte base64 value') from None
        if len(key) != 32 or base64.b64encode(key).decode() != public_key:
            raise ValueError('Update public key must be a canonical 32-byte base64 value')
    info.update(DEFAULTS)
    if public_key is None:
        info.pop('SUPublicEDKey', None)
        info.pop('SUFeedURL', None)
    else:
        info['SUPublicEDKey'] = public_key
        info['SUFeedURL'] = FEED
    output = plistlib.dumps(info)
    temporary = None
    try:
        with tempfile.NamedTemporaryFile(dir=contents, prefix='.update-info-', delete=False) as stream:
            temporary = Path(stream.name)
            stream.write(output)
            stream.flush()
            os.fsync(stream.fileno())
        temporary.chmod(stat.S_IMODE(path.stat().st_mode))
        temporary.replace(path)
    finally:
        if temporary is not None and temporary.exists():
            temporary.unlink()
    print('Signed-update metadata: ' + ('unconfigured; manual download route retained' if public_key is None else 'public key and fixed feed configured'))

if __name__ == '__main__':
    if len(sys.argv) != 2:
        raise SystemExit('Usage: signed-update-configuration.py /path/to/OpenCharge.app')
    try:
        configure(Path(sys.argv[1]), os.environ.get('OPENCHARGE_UPDATE_PUBLIC_KEY'))
    except (ValueError, OSError, plistlib.InvalidFileException) as error:
        raise SystemExit(str(error))
