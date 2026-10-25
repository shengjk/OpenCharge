# Login startup

Enable or disable login startup in Settings. Inspection is read-only; only the explicit button changes registration. The packaged app still requires macOS 13. The compatibility implementation below is development source, not proof of execution on macOS 11/12.

On macOS 13 and later, the app uses SMAppService.mainApp. Earlier systems use an owned per-user plist at `~/Library/LaunchAgents/org.opencharge.login.plist`, with a fixed `/usr/bin/open -g` argument array pointing to this app. `RunAtLoad` is true and `KeepAlive` is false. No shell, root helper, current-session bootstrap, background worker or immediate app launch is added. File changes take effect at the next login.

The legacy route validates ownership, permissions, regular-file type, link count, size and an exact schema/version before changing its file. Missing records stay missing during inspection. Foreign, malformed, oversized, symlinked, hardlinked or writable-by-others records are rejected. Application relocation is handled by replacing an owned record with the current validated app path. Unrelated agents are not enumerated or changed.

After an OS upgrade, an existing owned legacy registration remains visible. Explicit disable clears both owned routes. Explicit native enable removes the old registration only after successful native readback, retaining it while native registration is unconfirmed. Read/write failures remain visible rather than reporting a false enabled/disabled state.

The legacy enabled state confirms a validated owned plist targeting the current app. It does not query launchd override databases or prove actual logout/login, LaunchServices launch success or older-system runtime. Removing the file does not terminate an already running app or forcibly unload a current-session job.

`Scripts/test-login-startup.sh` uses temporary app bundles/directories and fake native registration. It never writes real login preferences, calls launchctl, opens an app or invokes native registration. `OPENCHARGE_TEST_ARCH` selects an explicit architecture. Real login behavior and native System Settings interaction need separate authorized verification.

Apple's [Creating Launch Daemons and Agents](https://developer.apple.com/library/archive/documentation/MacOSX/Conceptual/BPSystemStartup/Chapters/CreatingLaunchdJobs.html) describes per-user LaunchAgents directories and property-list jobs.
