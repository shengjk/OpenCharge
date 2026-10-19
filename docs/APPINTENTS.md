# App Intents and Shortcuts

The package declares eleven native actions and four App Shortcuts. Actions include battery/temperature/limit/state getters and explicit policy/LED configuration. Setters report saved configuration; hardware application still depends on app policy and explicit control opt-in.

```sh
OPENCHARGE_REQUIRE_APPINTENTS=1 bash Scripts/build-app.sh
bash Scripts/test-appintents.sh
```

Packaging extracts constant values from `Intents.swift`, invokes an installed `appintentsmetadataprocessor`, validates declarations/parameters, then signs the bundle. Metadata is under `Contents/Resources/Metadata.appintents`. Set `OPENCHARGE_APPINTENTS_PROCESSOR` and optionally `OPENCHARGE_XCODE_BUILD_VERSION` for another existing installation. Required mode fails if a processor is unavailable; no toolchain/license settings are changed.

The isolated native harness tests invalid/valid limits, mode mappings, calibration constraints and LED configuration. Eleven actions were discovered in the local Shortcuts UI; four getters ran successfully. Setter execution through the system UI and physical effects remain unverified.

References: [App Shortcuts](https://developer.apple.com/documentation/appintents/app-shortcuts), [AppShortcutsProvider](https://developer.apple.com/documentation/appintents/appshortcutsprovider).
