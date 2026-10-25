# App Intents and Shortcuts

The package declares twelve native actions and five App Shortcuts. Actions include battery/temperature/limit/state getters and explicit policy/LED configuration. Setters report saved configuration; hardware application still depends on app policy and explicit control opt-in.

```sh
OPENCHARGE_REQUIRE_APPINTENTS=1 bash Scripts/build-app.sh
bash Scripts/test-appintents.sh
```

Packaging extracts constant values from `Intents.swift`, invokes an installed `appintentsmetadataprocessor`, validates declarations/parameters, then signs the bundle. Metadata is under `Contents/Resources/Metadata.appintents`. Set `OPENCHARGE_APPINTENTS_PROCESSOR` and optionally `OPENCHARGE_XCODE_BUILD_VERSION` for another existing installation. Required mode fails if a processor is unavailable; no toolchain/license settings are changed.

The isolated native harness tests invalid/valid limits, mode mappings, calibration constraints and LED configuration. Before 0.3.24, eleven actions were discovered in the local Shortcuts UI and four getters ran successfully. The limit setter also ran through the system UI with hardware control off: 80 → 79 → 80 was reflected in the live app and persisted configuration. Physical effects remain unverified.

References: [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts), [AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider).


A fresh calibration request clears the saved checkpoint. The running app reload now distinguishes this transition from an ordinary checkpoint-bearing configuration update: it resets the live engine, displayed phase and interrupted flag, while preserving the current hardware-control opt-in. If incoming data disagrees with that opt-in, the preserved value is also written back, rather than leaving a stale enabled flag for a later relaunch. A write failure is reported. Ordinary updates keep an interrupted calibration pending. Duplicate reloads do not restart the new cycle; malformed files keep the last valid configuration. This addresses state synchronization, not completion of a real calibration cycle.

The dashboard fixture invokes the actual calibration intent against a private configuration, then explicitly calls the production reload callback because its isolated data-directory mode suppresses distributed notifications. It is a test of the callback's behavior, not notification delivery. The earlier native limit-setter check separately exercised delivery. No fixture helper or lock action is invoked.

Native 0.3.16 verification also exercised the new-calibration request while hardware control was off: the live interrupted prompt cleared, the new logical phase began, and the test then restored ordinary automatic monitoring. No physical cycle or power action was performed.

The separate **Get Application State** action reads the live typed policy state. Native Shortcuts executed it both while the app was running and after quitting it, returning `Sailing` in the current monitoring session. It does not replace **Get Charge State** or its observed-flow output. See [Shortcuts actions](SHORTCUTS.md) for state names and lifetime behavior.

App Intents declarations are explicitly available from macOS 13. The app checks that version before updating App Shortcut parameters and links the framework weakly. Framework-independent policy and pause-telemetry providers live in `AutomationRuntime.swift`; their state names and errors are unchanged. Constant-value extraction includes both source files, and packaging checks all twelve actions, five shortcuts, parameters and weak framework load commands for every binary architecture.

The macOS 11-target fixture injects providers and telemetry, checks unavailable/error states and all policy phases, and invokes the policy getter only when App Intents is available. It runs on the current test system and does not index Shortcuts or change configuration. Compilation and weak loading do not prove operation on an older system; the packaged app minimum remains macOS 13, and older automation integration and concurrency-runtime packaging remain unverified.
