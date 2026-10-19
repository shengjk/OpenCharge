"""Run the real removal script with fixed paths remapped to a temporary tree.
Only the root-identity check is bypassed; launchctl is a recording stub. No sudo,
real service action, or write below /Library or /var/db occurs.
"""
from pathlib import Path
import os, subprocess, tempfile

project = Path(__file__).resolve().parents[2]
source = (project / "Scripts/uninstall-helper.sh").read_text()
assert "$EUID -ne 0" in source
for marker in [None, "regular", "symlink", "directory"]:
    with tempfile.TemporaryDirectory(prefix="OpenCharge-uninstall-fixture-") as temporary:
        root = Path(temporary)
        helper = root / "Library/PrivilegedHelperTools/org.opencharge.charged"
        plist = root / "Library/LaunchDaemons/org.opencharge.charged.plist"
        record = root / "var/db/org.opencharge.charged/sleep-recovery.json"
        helper.parent.mkdir(parents=True)
        plist.parent.mkdir(parents=True)
        record.parent.mkdir(parents=True)
        helper.write_text("fake helper")
        plist.write_text("fake plist")
        if marker == "regular":
            record.write_text("unresolved record, even if malformed")
        elif marker == "symlink":
            record.symlink_to("missing-target")
        elif marker == "directory":
            record.mkdir()
        commands = root / "commands.log"
        commands.write_text("")
        binaries = root / "bin"
        binaries.mkdir()
        stub = binaries / "launchctl"
        stub.write_text('#!/bin/bash\nprintf "%s\\n" "$*" >> "$OPENCHARGE_UNINSTALL_FIXTURE_LOG"\nexit 0\n')
        stub.chmod(0o755)
        fixture = root / "remove.sh"
        fixture.write_text(source.replace("$EUID -ne 0", "0 -ne 0")
                          .replace("/Library/", str(root / "Library") + "/")
                          .replace("/var/db/", str(root / "var/db") + "/")
                          .replace("/var/run/", str(root / "var/run") + "/"))
        env = dict(os.environ)
        env["PATH"] = str(binaries) + os.pathsep + env.get("PATH", "")
        env["OPENCHARGE_UNINSTALL_FIXTURE_LOG"] = str(commands)
        result = subprocess.run(["/bin/bash", str(fixture)], env=env, capture_output=True, text=True)
        calls = commands.read_text().splitlines()
        assert calls[:2] == ["kill SIGTERM system/org.opencharge.charged", "bootout system/org.opencharge.charged"]
        if marker is None:
            assert result.returncode == 0 and not helper.exists() and not plist.exists(), result.stderr
            assert len(calls) == 2
            assert "Helper removed" in result.stdout
        else:
            assert result.returncode != 0 and helper.read_text() == "fake helper" and plist.read_text() == "fake plist"
            assert calls[2] == "bootstrap system " + str(plist)
            assert "recovery is pending" in result.stderr and "Helper removed" not in result.stdout
            if marker == "regular":
                assert record.read_text() == "unresolved record, even if malformed"
            elif marker == "symlink":
                assert record.is_symlink() and os.readlink(record) == "missing-target"
            else:
                assert record.is_dir()
print("Helper removal: 4 path-remapped/stub-service scenarios passed; no real service or system-path writes")
