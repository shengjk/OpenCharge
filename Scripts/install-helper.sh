#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(/usr/bin/dirname "$0")/.." && pwd)"
if [[ $EUID -ne 0 ]]; then echo 'Run sudo ./Scripts/install-helper.sh after building and reviewing the helper.' >&2; exit 1; fi
BINARY="$PROJECT_DIR/dist/bin/charged"
if [[ ! -f "$BINARY" || -L "$BINARY" ]]; then echo 'Build first: ./Scripts/build-app.sh' >&2; exit 1; fi
/usr/bin/codesign --verify --strict "$BINARY"
helper_dir=/Library/PrivilegedHelperTools
plist_dir=/Library/LaunchDaemons
helper="$helper_dir/org.opencharge.charged"
plist="$plist_dir/org.opencharge.charged.plist"
required_owner=0
trusted_directory() {
 local owner mode
 [[ -d "$1" && ! -L "$1" ]] || return 1
 IFS=: read -r owner mode <<< "$(/usr/bin/stat -f '%u:%Lp' "$1")"
 [[ "$owner" == "$required_owner" && "$mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 0022) == 0 ))
}
trusted_leaf() {
 local owner mode links
 [[ -f "$1" && ! -L "$1" ]] || return 1
 IFS=: read -r owner mode links <<< "$(/usr/bin/stat -f '%u:%Lp:%l' "$1")"
 [[ "$owner" == "$required_owner" && "$links" == 1 && "$mode" =~ ^[0-7]{3,4}$ ]] && (( (8#$mode & 07022) == 0 ))
}
# Never follow an unexpected installed path or replace a native installation.
if [[ ! -e "$helper_dir" && ! -L "$helper_dir" ]]; then /usr/bin/install -d -o root -g wheel -m 755 "$helper_dir"; fi
for directory in "$helper_dir" "$plist_dir"; do
 trusted_directory "$directory" || { echo 'Unsafe service directory; installation refused.' >&2; exit 1; }
done
had_old=false
if [[ -e "$helper" || -L "$helper" || -e "$plist" || -L "$plist" ]]; then
 trusted_leaf "$helper" && trusted_leaf "$plist" || { echo 'Unexpected installed service files; installation refused.' >&2; exit 1; }
 had_old=true
fi
staged_helper= staged_plist= backup_helper= backup_plist=
changed=false
cleanup() {
 local status=$? retain_backups=false
 trap - EXIT
 if [[ $status -ne 0 && $changed == true ]]; then
  # Bootstrap failure can still leave a job or process. Establish quiescence
  # again before rollback; unresolved recovery keeps both new files and backups.
  if /bin/bash "$PROJECT_DIR/Scripts/uninstall-helper.sh" --prepare-update; then
   if [[ $had_old == true ]]; then
    if /bin/mv -f "$backup_helper" "$helper" && /bin/mv -f "$backup_plist" "$plist"; then
     backup_helper=; backup_plist=
     if /bin/launchctl bootstrap system "$plist"; then echo 'Previous service files restored and restart requested.' >&2
     else echo 'Previous files restored, but restart failed; inspect the service before retrying.' >&2; fi
    else retain_backups=true; echo 'Rollback incomplete; retained remaining backups.' >&2; fi
   else
    /bin/rm -f "$helper" "$plist" || true
   fi
  else
   retain_backups=true
   echo 'Update recovery could not establish a stopped service; installed files and backups retained.' >&2
  fi
 fi
 for path in "$staged_helper" "$staged_plist"; do [[ -z "$path" ]] || /bin/rm -f "$path"; done
 if [[ $retain_backups == true ]]; then
  for path in "$backup_helper" "$backup_plist"; do [[ -z "$path" ]] || printf 'Recovery backup: %s\n' "$path" >&2; done
 else
  for path in "$backup_helper" "$backup_plist"; do [[ -z "$path" ]] || /bin/rm -f "$path"; done
 fi
 exit "$status"
}
trap cleanup EXIT
staged_helper=$(/usr/bin/mktemp "$helper_dir/.org.opencharge.charged.new.XXXXXX")
staged_plist=$(/usr/bin/mktemp "$plist_dir/.org.opencharge.charged.new.XXXXXX")
/usr/bin/install -o root -g wheel -m 755 "$BINARY" "$staged_helper"
/usr/bin/codesign --verify --strict "$staged_helper"
PLIST="$staged_plist"
/bin/cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>org.opencharge.charged</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/org.opencharge.charged</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>30</integer>
</dict></plist>
PLIST
/bin/chmod 644 "$staged_plist"
if [[ $had_old == true ]]; then
 backup_helper=$(/usr/bin/mktemp "$helper_dir/.org.opencharge.charged.backup.XXXXXX")
 backup_plist=$(/usr/bin/mktemp "$plist_dir/.org.opencharge.charged.backup.XXXXXX")
 /bin/cp -p "$helper" "$backup_helper"
 /bin/cp -p "$plist" "$backup_plist"
fi
/bin/bash "$PROJECT_DIR/Scripts/uninstall-helper.sh" --prepare-update
trusted_directory "$helper_dir" && trusted_directory "$plist_dir" || { echo 'Service directory changed; installation refused.' >&2; exit 1; }
changed=true
/bin/mv -f "$staged_helper" "$helper"; staged_helper=
/bin/mv -f "$staged_plist" "$plist"; staged_plist=
/bin/launchctl bootstrap system "$plist"
echo 'Helper installed and service registration requested. Enable hardware control explicitly in OpenCharge settings.'
