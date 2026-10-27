#!/bin/bash
set -euo pipefail
if [[ $EUID -ne 0 ]]; then echo 'Run sudo ./Scripts/uninstall-helper.sh' >&2; exit 1; fi
job=system/org.opencharge.charged
helper=/Library/PrivilegedHelperTools/org.opencharge.charged
plist=/Library/LaunchDaemons/org.opencharge.charged.plist
for path in "$helper" "$plist"; do
 if [[ -L "$path" || ( -e "$path" && ! -f "$path" ) ]]; then
  echo 'Unexpected helper file type; files retained.' >&2; exit 1
 fi
done
# Only manage the exact launchd configuration produced by the development installer.
# A changed configuration could run another command when recovery is restarted.
valid_plist() {
 [[ -f "$plist" && ! -L "$plist" ]] && /usr/bin/cmp -s "$plist" <(/bin/cat <<'EXPECTED_PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>org.opencharge.charged</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/org.opencharge.charged</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>30</integer>
</dict></plist>
EXPECTED_PLIST
 )
}
if [[ -f "$plist" ]] && ! valid_plist; then
 echo 'Unexpected service configuration; files retained.' >&2; exit 1
fi
# Distinguish a missing job from a failed launchctl query. Unknown statuses fail closed.
status=0
job_info=$(/bin/launchctl print "$job" 2>/dev/null) || status=$?
if [[ $status -eq 0 ]]; then
 program=$(printf '%s\n' "$job_info" | /usr/bin/awk -F ' = ' '$1 ~ /^[[:space:]]*program$/ {print $2; exit}')
 if [[ "$program" != "$helper" ]]; then echo 'Unexpected service program; files retained.' >&2; exit 1; fi
 pid=$(printf '%s\n' "$job_info" | /usr/bin/awk -F ' = ' '$1 ~ /^[[:space:]]*pid$/ {print $2; exit}')
 if [[ -n "$pid" && ! "$pid" =~ ^[0-9]+$ ]]; then echo 'Unexpected service PID; files retained.' >&2; exit 1; fi
 # Give the helper a chance to restore only keys it owns, then unload its job.
 /bin/launchctl kill SIGTERM "$job" 2>/dev/null || true
 /bin/launchctl bootout "$job" 2>/dev/null || true
else
 if [[ $status -ne 113 ]]; then echo 'Cannot inspect service; files retained.' >&2; exit 1; fi
 pid=
fi
# Verify the job is gone and no instance of the fixed helper remains running.
for attempt in {1..30}; do
 status=0
 /bin/launchctl print "$job" >/dev/null 2>&1 || status=$?
 if [[ $status -ne 0 && $status -ne 113 ]]; then echo 'Cannot verify service state; files retained.' >&2; exit 1; fi
 processes=$(/bin/ps -axo pid=,comm=) || { echo 'Cannot inspect processes; files retained.' >&2; exit 1; }
 running=$(printf '%s\n' "$processes" | /usr/bin/awk -v path="$helper" '$2 == path {print $1; exit}')
 pid_status=1
 if [[ -n "$pid" ]]; then /bin/ps -p "$pid" -o comm= >/dev/null 2>&1 && pid_status=0 || pid_status=$?; fi
 if [[ $pid_status -gt 1 ]]; then echo 'Cannot inspect service PID; files retained.' >&2; exit 1; fi
 if [[ $status -eq 113 && -z "$running" && $pid_status -eq 1 ]]; then break; fi
 if [[ $attempt -eq 30 ]]; then echo 'Service or helper is still running; files retained.' >&2; exit 1; fi
 /bin/sleep 0.1
done
# Never abandon a recovery record, including malformed files and dangling links.
for record in charge-recovery.json firmware-recovery.json magsafe-recovery.json sleep-recovery.json; do
 if [[ -e "/var/db/org.opencharge.charged/$record" || -L "/var/db/org.opencharge.charged/$record" ]]; then
  if valid_plist && /bin/launchctl bootstrap system "$plist" 2>/dev/null; then
   echo 'Hardware recovery is pending. Helper files retained and restart requested; resolve recovery before retrying removal. Do not delete its recovery record.' >&2
  else
   echo 'Hardware recovery is pending. Helper files retained; automatic restart failed or the configuration changed. Resolve recovery before retrying removal. Do not delete its recovery record.' >&2
  fi
  exit 1
 fi
done
/bin/rm -f "$plist" "$helper"
if [[ -S /var/run/opencharge.sock ]]; then /bin/rm /var/run/opencharge.sock; fi
echo 'Helper removed. User settings/history retained.'
