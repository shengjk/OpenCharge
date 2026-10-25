# Service management and diagnostics — 0.2.6

The native app now contains Contents/MacOS/charged and Contents/Library/LaunchDaemons/org.opencharge.charged.plist. The plist uses app-relative BundleProgram. The command-line development installer remains a separate route using a root-owned fixed absolute executable path and a legacy /Library/LaunchDaemons plist. The two mechanisms are not mixed: native registration detects the legacy installation and refuses to register until it is removed.

Apple's current SMAppService.h states that apps using SMAppService must be signed, apps containing LaunchDaemons must be notarized, and administrator approval in System Settings is required before the daemon bootstraps. The app independently displays registration status and IPC connection status. An enabled status means eligible to run, not proof of a working helper connection. Approval settings only open after an explicit button press.

Preflight checks bundle layout, executable presence and an Apple-issued valid signature across all architectures and nested code (anchor apple generic). This rejects local ad-hoc builds before register() is called. It is not a standalone notarization check: for eligible signatures, macOS remains responsible for checking notarization and authorization. The local build's register button is disabled and its developer installation guide is included. No identities, credentials, entitlements, license acceptance or notarization uploads are invented or performed.

On removal of an enabled native service, the app first asks the living daemon to restore owned SMC and LED values, then disables local control and waits for async unregister completion. A restoration/connection failure is surfaced and prevents claiming successful removal. User configuration and history remain. Updating a native registered daemon requires unregister completion, app replacement, then re-registration; see HELPER-SETUP.md.

Scripts/verify-helper-package.swift checks the exact label, relative program, launch properties, executable and guide. Scripts/test-helper-preflight.sh loads an actual ad-hoc app bundle and proves that signature preflight refuses registration before OS mutation. It is a local-development-build test; signed/notarized distribution should use system integration testing rather than this rejection harness.

The diagnostic export is an explicit Codable projection: application/OS version, architecture, non-unique model identifier, current SOC/temperature/connection/cycles, limit/mode/Sailing/thermal summary, task count, service registration state, allowlisted helper capability tags, action and error-present flag. It does not serialize raw IORegistry, environment, full config, schedule IDs/dates, departure plan, history, usernames, paths, serial numbers or raw errors. Helper text is bounded to 4096 characters and only predefined capability tags survive. NSSavePanel chooses a local file; no upload/send step exists.

Sources:
- https://developer.apple.com/documentation/servicemanagement/smappservice
- https://developer.apple.com/documentation/servicemanagement/updating-helper-executables-from-earlier-versions-of-macos
- https://developer.apple.com/documentation/security/secstaticcodecheckvalidity(_:_:_:)
- Local SDK ServiceManagement.framework/Headers/SMAppService.h

Actual administrator authorization, launchd installation, daemon start/stop/update, user switching and physical hardware recovery remain unverified. No system service was registered or installed during this implementation.

Live UI confirmation: the local build displays the signature restriction and disables registration. Local diagnostic export was exercised through NSSavePanel and its resulting JSON inspected. Universal embedded daemon slice parity and deep signatures were verified.

## User-authorized installation evidence

The user explicitly authorized development root-service installation and read-only detection. Noninteractive sudo required a password; the user completed the provided script locally and confirmed installation. Read-only checks then found launchd system/org.opencharge.charged running with a PID, root-owned helper mode 0755 and plist mode 0644, active-console-owned socket mode 0600, and an installed helper digest matching delivered 0.2.6. Root-authenticated IPC returned internal battery, CHTE/CHIE, recognized format, physicalEffects:unverified, lowPower battery=1/ac=0 and MagSafe unavailable. These are observed existing settings; no power-mode or SMC mutation was sent. App hardwareEnabled=false, systemActionsEnabled=false and system LED/no sleep suppression were verified.

The running daemon remains 0.2.6 while the client/source release advances to 0.3.1; their fixed IPC commands are unchanged. The application build update does not reinstall or restart the root-owned daemon. Native SMAppService authorization, uninstall/update, sleep/wake and physical controls remain untested. Legacy-service detection now labels the registration route explicitly rather than saying the whole service was not found.

## Development availability boundary

Service status and preflight use an application-owned status type and a version-gated registration backend. SMAppService access is confined to the macOS 13 backend. On a system without that backend, inspection and detection of an existing development service remain available; native register/unregister is explicitly unavailable. This is an intermediate compatibility change, not an implementation of older native privileged-service installation. The documented development installer remains a separate explicit administrator action. Login startup is handled separately; see LOGIN-STARTUP.md.

Removal validates that its registration route exists before the app changes local control flags or begins recovery. Legacy-service, unsupported-platform, layout, signature, unknown-status and backend failures are checked through isolated dependencies. The actual local ad-hoc preflight still rejects registration; fake valid-signature cases invoke only a fake backend. No test registers, unregisters, installs or restarts a system service.


## Older helper packaging prerequisites

The app now additionally packages a dedicated macOS 11 helper under Contents/Library/LaunchServices with embedded Info/launchd sections and reciprocal signing requirements. The ordinary SMAppService/development helper remains a different file. The requirements use the actual verified signing team; local ad-hoc packages use `never` for both sides. Per-slice metadata, identifier, version and signature checks run during native and universal builds. See [older helper packaging](LEGACY-HELPER.md).

This supplies installation prerequisites, not the older authorization/ownership/removal backend. Pre-13 in-app service registration remains unavailable, the public deployment floor remains macOS 13, and no helper was installed or restarted by this packaging work. The installation evidence above is historical; it is not evidence that the new route has been exercised.
