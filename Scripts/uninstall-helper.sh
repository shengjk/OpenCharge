#!/bin/bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo 'Run sudo ./Scripts/uninstall-helper.sh' >&2; exit 1; fi
# SIGTERM gives the helper a chance to restore only keys it owns.
launchctl kill SIGTERM system/org.opencharge.charged 2>/dev/null || true
launchctl bootout system/org.opencharge.charged 2>/dev/null || true
rm -f /Library/LaunchDaemons/org.opencharge.charged.plist /Library/PrivilegedHelperTools/org.opencharge.charged
if [[ -S /var/run/opencharge.sock ]]; then rm /var/run/opencharge.sock; fi
echo 'Helper removed. User settings/history retained.'
