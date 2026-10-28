"""Run only our fake AppKit fixture; quit/cancel it through its own scripted events."""
from pathlib import Path
import json, os, plistlib, subprocess, sys, tempfile
app = Path(sys.argv[1]).resolve(strict=True)
info = plistlib.loads((app/'Contents/Info.plist').read_bytes())
assert info['CFBundleIdentifier'] == 'org.opencharge.quitfixture'
executable = app/'Contents/MacOS/QuitFixture'
results = []
with tempfile.TemporaryDirectory(prefix='opencharge-quit-native-') as temporary:
    for scenario in ['commit-success','prepare-cancel','commit-retry','commit-force','prepare-retry','local-final-cancel','lease-renew-cancel']:
        log = Path(temporary)/(scenario+'.json')
        env = dict(os.environ, OPENCHARGE_QUIT_SCRIPT=scenario, OPENCHARGE_QUIT_LOG=str(log))
        # Popen owns this exact child. No application lookup or broad process termination.
        child = subprocess.Popen([str(executable)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        try:
            stdout, stderr = child.communicate(timeout=20)
        except subprocess.TimeoutExpired:
            child.terminate()
            try: child.communicate(timeout=5)
            except subprocess.TimeoutExpired: child.kill(); child.communicate()
            raise AssertionError('Owned fake fixture timed out: '+scenario)
        assert child.returncode == 0, (scenario, stderr.decode(errors='replace')[-2000:])
        events = json.loads(log.read_text())
        assert events[0] == 'started' and events[-1] == 'terminated', (scenario, events)
        (app.parent/'scripted-last-events.json').write_text(json.dumps({'scenario':scenario,'events':events},indent=2)+'\n')
        preparations = [x for x in events if x.startswith('prepare-')]
        confirmations = [x for x in events if x.startswith('confirm-')]
        assert len(preparations) == (2 if scenario == 'prepare-retry' else 1), (scenario, events)
        if scenario in ['prepare-cancel','local-final-cancel','lease-renew-cancel']:
            assert events.count('cancel-control') == 1 and events.count('reply-no') == 1, (scenario, events)
            assert 'reply-yes' not in events and events[-2] == 'ordinary-quit'
            assert len(confirmations) == (1 if scenario == 'local-final-cancel' else 0)
        else:
            assert 'cancel-control' not in events and 'reply-no' not in events and events.count('reply-yes') == 1
            assert len(confirmations) == (2 if scenario == 'commit-retry' else 1)
            assert events.index(confirmations[-1]) < events.index('reply-yes') < events.index('terminated')
        if scenario == 'lease-renew-cancel':
            assert 'renew' in events and events.index('renew') < events.index('cancel-control')
            assert all(x != 'power-read' for x in events[events.index('renew')+1:]), events
        results.append({'scenario':scenario,'events':events})
        print('PASS actual AppKit deferred quit:',scenario,flush=True)
    (app.parent/'scripted-results.json').write_text(json.dumps(results,indent=2)+'\n')
