"""Run production installer/remover with temporary paths and stubbed service commands.
No root action, real service command, signature operation, or system-path write.
"""
from pathlib import Path
import os
import subprocess
import tempfile

project = Path(__file__).resolve().parents[2]
installer = (project / 'Scripts/install-helper.sh').read_text()
remover = (project / 'Scripts/uninstall-helper.sh').read_text()
cases = ['fresh', 'upgrade', 'stop_failure', 'pending_recovery', 'altered_plist',
         'source_link', 'installed_link', 'installed_hardlink', 'writable_directory',
         'source_signature_failure', 'staged_signature_failure', 'bootstrap_failure',
         'bootstrap_failure_running', 'rollback_pending', 'second_rename_failure',
         'fresh_bootstrap_failure', 'stopped_upgrade', 'writable_helper', 'writable_plist',
         'missing_helper', 'missing_plist', 'plist_link', 'first_rename_failure']
for case in cases:
    with tempfile.TemporaryDirectory(prefix='OpenCharge-upgrade-') as temporary:
        root = Path(temporary)
        (root / 'Scripts').mkdir()
        source = root / 'dist/bin/charged'
        source.parent.mkdir(parents=True)
        source.write_text('new helper')
        source.chmod(0o755)
        helper = root / 'Library/PrivilegedHelperTools/org.opencharge.charged'
        plist = root / 'Library/LaunchDaemons/org.opencharge.charged.plist'
        helper.parent.mkdir(parents=True)
        plist.parent.mkdir(parents=True)
        template = installer.split("cat > \"$PLIST\" <<'PLIST'\n", 1)[1].split('\nPLIST\n', 1)[0] + '\n'
        template = template.replace('/Library/', str(root / 'Library') + '/')
        old = case not in ('fresh', 'fresh_bootstrap_failure')
        active = root / 'active'
        if old:
            helper.write_text('old helper')
            helper.chmod(0o755)
            plist.write_text(template)
            plist.chmod(0o644)
            active.touch()
        if case == 'stopped_upgrade': active.unlink()
        if case == 'writable_helper': helper.chmod(0o777)
        if case == 'writable_plist': plist.chmod(0o666)
        if case == 'missing_helper': helper.unlink()
        if case == 'missing_plist': plist.unlink()
        if case == 'plist_link':
            plist.rename(plist.with_name('plist-target')); plist.symlink_to('plist-target')
        if case == 'altered_plist': plist.write_text('unknown service configuration')
        if case == 'source_link':
            source.rename(source.with_name('source-target'))
            source.symlink_to('source-target')
        if case == 'installed_link':
            helper.unlink()
            helper.symlink_to('missing')
        if case == 'installed_hardlink': os.link(helper, helper.with_name('other-link'))
        if case == 'writable_directory': helper.parent.chmod(0o777)
        marker = root / 'var/db/org.opencharge.charged/sleep-recovery.json'
        if case == 'pending_recovery':
            marker.parent.mkdir(parents=True)
            marker.write_text('pending')
        log = root / 'calls'
        log.write_text('')
        stubs = root / 'stubs'
        stubs.mkdir()
        launchctl = stubs / 'launchctl'
        launchctl.write_text('''#!/bin/bash
printf '%s\n' "$*" >> "$LOG"
case "$1" in
 print)
  [[ -e "$ACTIVE" ]] || exit 113
  echo " program = $HELPER"
  echo ' pid = 123';;
 kill) exit 0;;
 bootout)
  [[ "$CASE" == stop_failure ]] && exit 5
  /bin/rm -f "$ACTIVE";;
 bootstrap)
  if [[ "$CASE" == bootstrap_failure || "$CASE" == bootstrap_failure_running || "$CASE" == rollback_pending || "$CASE" == fresh_bootstrap_failure ]]; then
   if [[ ! -e "$FAILED" ]]; then
    /usr/bin/touch "$FAILED"
    [[ "$CASE" == bootstrap_failure_running ]] && /usr/bin/touch "$ACTIVE"
    if [[ "$CASE" == rollback_pending ]]; then /bin/mkdir -p "${MARKER%/*}"; echo pending > "$MARKER"; fi
    exit 5
   fi
  fi
  /usr/bin/touch "$ACTIVE";;
esac
''')
        codesign = stubs / 'codesign'
        codesign.write_text('''#!/bin/bash
printf 'codesign %s\n' "$*" >> "$LOG"
if [[ "$CASE" == source_signature_failure ]]; then exit 1; fi
if [[ "$CASE" == staged_signature_failure && "$*" == *'.new.'* ]]; then exit 1; fi
exit 0
''')
        ps = stubs / 'ps'
        ps.write_text('''#!/bin/bash
if [[ "$1" == -p ]]; then [[ -e "$ACTIVE" ]] && exit 0 || exit 1; fi
[[ ! -e "$ACTIVE" ]] || echo "123 $HELPER"
exit 0
''')
        sleep = stubs / 'sleep'
        sleep.write_text('#!/bin/bash\nexit 0\n')
        mv = stubs / 'mv'
        mv.write_text('''#!/bin/bash
if [[ "$CASE" == first_rename_failure && "$2" == *'/PrivilegedHelperTools/'*'.new.'* && ! -e "$FAILED" ]]; then
 /usr/bin/touch "$FAILED"; exit 1
fi
if [[ "$CASE" == second_rename_failure && "$2" == *'/LaunchDaemons/'*'.new.'* && ! -e "$FAILED" ]]; then
 /usr/bin/touch "$FAILED"; exit 1
fi
exec /bin/mv "$@"
''')
        for stub in stubs.iterdir(): stub.chmod(0o755)
        for name, text in [('install-helper.sh', installer), ('uninstall-helper.sh', remover)]:
            text = text.replace('$EUID -ne 0', '0 -ne 0').replace('required_owner=0', f'required_owner={os.getuid()}')
            text = text.replace(' -o root -g wheel', '')
            for original, replacement in [('/usr/bin/codesign', str(codesign)), ('/bin/launchctl', str(launchctl)),
                                          ('/bin/ps', str(ps)), ('/bin/sleep', str(sleep)), ('/bin/mv', str(mv)),
                                          ('/Library/', str(root / 'Library') + '/'),
                                          ('/var/db/', str(root / 'var/db') + '/'),
                                          ('/var/run/', str(root / 'var/run') + '/')]:
                text = text.replace(original, replacement)
            (root / 'Scripts' / name).write_text(text)
        env = dict(os.environ, CASE=case, HELPER=str(helper), LOG=str(log), ACTIVE=str(active),
                   FAILED=str(root / 'failed'), MARKER=str(marker))
        result = subprocess.run(['/bin/bash', str(root / 'Scripts/install-helper.sh')], env=env, capture_output=True, text=True)
        success = case in ('fresh', 'upgrade', 'stopped_upgrade')
        assert (result.returncode == 0) == success, (case, result.stdout, result.stderr)
        if success:
            assert helper.read_text() == 'new helper' and plist.read_text() == template and active.exists(), case
            assert helper.stat().st_mode & 0o777 == 0o755 and plist.stat().st_mode & 0o777 == 0o644
            assert 'Helper installed' in result.stdout
        elif case == 'rollback_pending':
            assert helper.read_text() == 'new helper' and plist.read_text() == template
            assert marker.read_text() == 'pending\n' and 'backups retained' in result.stderr
            backups = list(root.glob('Library/*/.*.backup.*'))
            assert len(backups) == 2 and any(p.read_text() == 'old helper' for p in backups)
        else:
            if not old:
                assert not helper.exists() and not plist.exists() and not active.exists(), case
            else:
                if case == 'installed_link': assert helper.is_symlink()
                elif case == 'missing_helper': assert not helper.exists()
                else: assert helper.read_text() == 'old helper', (case, result.stderr)
                if case == 'missing_plist': assert not plist.exists()
                else: assert plist.read_text() == ('unknown service configuration' if case == 'altered_plist' else template)
            assert 'Helper installed' not in result.stdout
        if case == 'pending_recovery': assert marker.read_text() == 'pending'
        if case in ('source_link', 'installed_link', 'installed_hardlink', 'writable_directory',
                    'source_signature_failure', 'staged_signature_failure', 'altered_plist',
                    'writable_helper', 'writable_plist', 'missing_helper', 'missing_plist', 'plist_link'):
            assert not any(line.startswith(('kill ', 'bootout ', 'bootstrap ')) for line in log.read_text().splitlines()), case
        if case != 'rollback_pending':
            assert not list(root.glob('Library/*/.*.new.*')) and not list(root.glob('Library/*/.*.backup.*')), case
print(f'Helper installation/upgrade: {len(cases)} isolated scenarios passed; no real service or system-path writes')
