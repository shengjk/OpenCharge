#!/bin/bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo 'Run sudo ./Scripts/uninstall-helper.sh' >&2; exit 1; fi
# SIGTERM gives the helper a chance to restore only keys it owns.
launchctl kill SIGTERM system/org.opencharge.charged 2>/dev/null || true
launchctl bootout system/org.opencharge.charged 2>/dev/null || true
# Never abandon any owned recovery record by removing its service, even if a
# record is malformed or an unexpected path blocks the helper from reading it.
for record in charge-recovery.json firmware-recovery.json magsafe-recovery.json sleep-recovery.json; do
 if [[ -e "/var/db/org.opencharge.charged/$record" || -L "/var/db/org.opencharge.charged/$record" ]]; then
  if [[ -f /Library/LaunchDaemons/org.opencharge.charged.plist ]]; then
    launchctl bootstrap system /Library/LaunchDaemons/org.opencharge.charged.plist 2>/dev/null || true
  fi
  echo 'Hardware recovery is pending. Helper files retained and restart requested; resolve recovery before retrying removal. Do not delete its recovery record.' >&2
  exit 1
 fi
done
rm -f /Library/LaunchDaemons/org.opencharge.charged.plist /Library/PrivilegedHelperTools/org.opencharge.charged
if [[ -S /var/run/opencharge.sock ]]; then rm /var/run/opencharge.sock; fi
echo 'Helper removed. User settings/history retained.'
