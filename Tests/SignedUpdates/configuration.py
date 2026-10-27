"""Build metadata checks only: no updater, network, keychain, or real application."""
from pathlib import Path
import base64
import os
import plistlib
import subprocess
import tempfile

project = Path(__file__).resolve().parents[2]
script = project / 'Scripts/signed-update-configuration.py'
key = base64.b64encode(bytes(range(32))).decode()
cases = [None, key, '', key + '\n', ' ' + key, '!' * 44,
         base64.b64encode(bytes(31)).decode(), base64.b64encode(bytes(33)).decode(),
         'wrong-bundle', 'linked-info', 'linked-app']
for value in cases:
    with tempfile.TemporaryDirectory(prefix='OpenCharge-update-info-') as directory:
        root = Path(directory)
        app = root / 'OpenCharge.app'
        (app / 'Contents').mkdir(parents=True)
        info = app / 'Contents/Info.plist'
        identity = 'org.example.other' if value == 'wrong-bundle' else 'org.opencharge.app'
        original = plistlib.dumps({'CFBundleIdentifier':identity, 'CFBundleVersion':'58', 'CFBundleLocalizations':['en', 'zh-Hans'], 'SUPublicEDKey':'stale', 'SUFeedURL':'https://example.invalid/stale'})
        info.write_bytes(original)
        info.chmod(0o644)
        if value == 'linked-info':
            info.rename(info.with_name('original.plist'))
            info.symlink_to('original.plist')
        if value == 'linked-app':
            app.rename(root / 'real.app')
            app.symlink_to('real.app')
        env = dict(os.environ)
        env.pop('OPENCHARGE_UPDATE_PUBLIC_KEY', None)
        if value is not None:
            env['OPENCHARGE_UPDATE_PUBLIC_KEY'] = key if value in ('wrong-bundle', 'linked-info', 'linked-app') else value
        result = subprocess.run(['python3', str(script), str(app)], env=env, capture_output=True, text=True)
        if value in (None, key):
            assert result.returncode == 0, result.stderr
            parsed = plistlib.loads(info.read_bytes())
            assert parsed['CFBundleVersion'] == '58' and parsed['CFBundleLocalizations'] == ['en','zh-Hans']
            assert info.stat().st_mode & 0o777 == 0o644
            for field, expected in [('SUEnableAutomaticChecks',False), ('SUAutomaticallyUpdate',False), ('SUEnableSystemProfiling',False), ('SUVerifyUpdateBeforeExtraction',True), ('SURequireSignedFeed',True), ('SUEnableJavaScript',False)]:
                assert type(parsed[field]) is bool and parsed[field] == expected
            assert type(parsed['SUSignedFeedFailureExpirationInterval']) is int and parsed['SUSignedFeedFailureExpirationInterval'] == 0
            if value is None:
                assert 'SUPublicEDKey' not in parsed and 'SUFeedURL' not in parsed
            else:
                assert parsed['SUPublicEDKey'] == key
                assert parsed['SUFeedURL'] == 'https://raw.githubusercontent.com/shengjk/OpenCharge/main/updates/appcast.xml'
        else:
            assert result.returncode != 0 and info.read_bytes() == original
            assert key not in result.stdout + result.stderr
        assert not list((app / 'Contents').glob('.update-info-*'))
print(f'Signed-update build metadata: {len(cases)} isolated scenarios passed; no keys generated or updater started')
