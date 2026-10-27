"""Exercise the removal script against temporary paths and simulated processes."""
from pathlib import Path
import os
import subprocess
import tempfile

project = Path(__file__).resolve().parents[2]
source = (project / 'Scripts/uninstall-helper.sh').read_text()
assert '$EUID -ne 0' in source
cases = [('registered', None), ('absent', None), ('unknown', None),
         ('wrong_program', None), ('still_job', None), ('ps_error', None),
         ('pid_alive', None), ('orphan', None), ('helper_link', None),
         ('plist_directory', None), ('altered_plist', None), ('prepare', None)]
cases += [(scenario, ('sleep-recovery.json', 'regular')) for scenario in ('changed_during_stop', 'restart_failure')]
cases += [('marker', (name, kind)) for name in
          ('sleep-recovery.json', 'charge-recovery.json', 'firmware-recovery.json', 'magsafe-recovery.json')
          for kind in ('regular', 'symlink', 'directory')]
for scenario, marker in cases:
    with tempfile.TemporaryDirectory(prefix='OpenCharge-uninstall-') as temporary:
        root = Path(temporary)
        helper = root / 'Library/PrivilegedHelperTools/org.opencharge.charged'
        plist = root / 'Library/LaunchDaemons/org.opencharge.charged.plist'
        helper.parent.mkdir(parents=True)
        plist.parent.mkdir(parents=True)
        helper.write_text('fake helper')
        install = (project / 'Scripts/install-helper.sh').read_text()
        template = install.split("cat > \"$PLIST\" <<'PLIST'\n", 1)[1].split("\nPLIST\n", 1)[0] + "\n"
        plist.write_text(template.replace('/Library/PrivilegedHelperTools/org.opencharge.charged', str(helper)))
        if scenario == 'altered_plist':
            plist.write_text('unexpected configuration')
        if scenario == 'helper_link':
            helper.unlink()
            helper.symlink_to('missing')
        if scenario == 'plist_directory':
            plist.unlink()
            plist.mkdir()
        if marker:
            record = root / 'var/db/org.opencharge.charged' / marker[0]
            record.parent.mkdir(parents=True)
            if marker[1] == 'regular': record.write_text('pending')
            elif marker[1] == 'symlink': record.symlink_to('missing')
            else: record.mkdir()
        log = root / 'calls'
        log.write_text('')
        stub = root / 'launchctl'
        stub.write_text('''#!/bin/bash
printf '%s\\n' "$*" >> "$LOG"
case "$1" in
 print)
  if [[ "$CASE" == unknown ]]; then exit 5; fi
  if [[ "$CASE" == absent || "$CASE" == orphan ]]; then exit 113; fi
  if [[ -e "$STOPPED" && "$CASE" != still_job ]]; then exit 113; fi
  if [[ "$CASE" == wrong_program ]]; then echo ' program = /unexpected'; else echo " program = $HELPER"; fi
  echo ' pid = 123';;
 bootout) touch "$STOPPED"; if [[ "$CASE" == changed_during_stop ]]; then echo changed > "$PLIST"; fi;;
 bootstrap) [[ "$CASE" == restart_failure ]] && exit 5 || exit 0;;
esac
''')
        stub.chmod(0o755)
        ps = root / 'ps'
        ps.write_text('''#!/bin/bash
if [[ "$CASE" == ps_error ]]; then exit 2; fi
if [[ "$1" == -p ]]; then [[ "$CASE" == pid_alive ]] && exit 0 || exit 1; fi
if [[ "$CASE" == orphan ]]; then echo "123 $HELPER"; fi
exit 0
''')
        ps.chmod(0o755)
        sleep = root / 'sleep'
        sleep.write_text('#!/bin/bash\nexit 0\n')
        sleep.chmod(0o755)
        fixture_source = source.replace('$EUID -ne 0', '0 -ne 0')
        for original, replacement in [('/bin/launchctl', str(stub)), ('/bin/ps', str(ps)), ('/bin/sleep', str(sleep)),
                                      ('/Library/', str(root / 'Library') + '/'),
                                      ('/var/db/', str(root / 'var/db') + '/'),
                                      ('/var/run/', str(root / 'var/run') + '/')]:
            assert original in fixture_source
            fixture_source = fixture_source.replace(original, replacement)
        fixture = root / 'remove.sh'
        fixture.write_text(fixture_source)
        env = dict(os.environ, CASE=scenario, LOG=str(log), STOPPED=str(root / 'stopped'), HELPER=str(helper), PLIST=str(plist))
        result = subprocess.run(['/bin/bash', str(fixture)] + (['--prepare-update'] if scenario == 'prepare' else []), env=env, capture_output=True, text=True)
        calls = log.read_text().splitlines()
        success = scenario in ('registered', 'absent')
        if scenario == 'prepare':
            assert result.returncode == 0 and helper.exists() and plist.exists(), result.stderr
            assert 'installed files retained' in result.stdout
            assert 'Helper removed' not in result.stdout
        elif success:
            assert result.returncode == 0 and not helper.exists() and not plist.exists(), (scenario, result.stderr)
            assert 'Helper removed' in result.stdout
        else:
            assert result.returncode != 0 and (helper.exists() or helper.is_symlink()) and plist.exists(), (scenario, result.stderr)
            assert 'Helper removed' not in result.stdout
        if marker:
            assert record.exists() or record.is_symlink()
            if scenario == 'changed_during_stop':
                assert not any(call.startswith('bootstrap system ') for call in calls)
            else:
                assert any(call.startswith('bootstrap system ') for call in calls)
            if scenario in ('changed_during_stop', 'restart_failure'):
                assert 'automatic restart failed or the configuration changed' in result.stderr
                assert 'restart requested' not in result.stderr
        if scenario in ('absent', 'orphan', 'unknown', 'wrong_program', 'helper_link', 'plist_directory', 'altered_plist'):
            assert not any(call.startswith(('kill ', 'bootout ')) for call in calls), (scenario, calls)
print(f'Helper removal: {len(cases)} isolated scenarios passed; no real service or system-path writes')
