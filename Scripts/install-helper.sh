#!/bin/bash
set -euo pipefail
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
if [[ $EUID -ne 0 ]]; then echo 'Run sudo ./Scripts/install-helper.sh after building and reviewing the helper.' >&2; exit 1; fi
BINARY="$PROJECT_DIR/dist/bin/charged"
if [[ ! -f "$BINARY" ]]; then echo 'Build first: ./Scripts/build-app.sh' >&2; exit 1; fi
/usr/bin/codesign --verify --strict "$BINARY"
launchctl bootout system/org.opencharge.charged 2>/dev/null || true
# Root executes only an owned, non-user-writable copy. Never point launchd into a user checkout.
install -d -o root -g wheel -m 755 /Library/PrivilegedHelperTools
install -o root -g wheel -m 755 "$BINARY" /Library/PrivilegedHelperTools/org.opencharge.charged
PLIST=/Library/LaunchDaemons/org.opencharge.charged.plist
cat > "$PLIST" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>Label</key><string>org.opencharge.charged</string>
<key>ProgramArguments</key><array><string>/Library/PrivilegedHelperTools/org.opencharge.charged</string></array>
<key>RunAtLoad</key><true/><key>KeepAlive</key><true/>
<key>ThrottleInterval</key><integer>30</integer>
</dict></plist>
PLIST
chown root:wheel "$PLIST"; chmod 644 "$PLIST"
launchctl bootstrap system "$PLIST"
echo 'Helper installed. Enable hardware control explicitly in OpenCharge settings.'
