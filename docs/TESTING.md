# Verification

Run deterministic checks from the repository root:

```sh
bash Scripts/check.sh
bash Scripts/build-app.sh
bash Scripts/test-helper-preflight.sh
```

`check.sh` runs core policy assertions, injected hardware/telemetry tests, isolated CLI/App Intents tests and the production dashboard fixture. The core adapter executes 63 canonical XCTest methods without the XCTest framework; use `swift test` with a full usable Xcode toolchain for framework execution. The adapter is not a substitute for an XCTest CI result.

Hardware planners use fake transports; Low Power Mode and sleep tests use injected runners/ownership state. The dashboard fixture uses isolated configuration and preferences with hardware/system actions disabled. App Intents setters only persist into their fixture. These tests never install a root service or change physical charging, LEDs or power modes.

## Optional integration

```sh
bash Scripts/test-energy.sh
bash Scripts/build-universal.sh
OPENCHARGE_TEST_ARCH=x86_64 bash Scripts/test-smc.sh
```

Energy smoke reads the optional system interface and its own CPU usage; restricted process access can make it unavailable. x86_64 execution requires an Intel host or already installed Rosetta. No scripts install Rosetta. Universal packaging verifies arm64/x86_64 executables, nested helper signatures and App Intents metadata (eleven declarations, four shortcuts).

## Existing validation boundary

Read-only telemetry and helper capabilities have been observed on MacBookPro17,1. Four native Shortcuts getters ran through the system UI; eleven declarations were discovered. Dashboard visibility/order and popup preview editing were inspected. Status-item overflow/multi-display behavior, real hardware writes, calibration cycles, sleep/wake recovery, user switching and notarized service lifecycle remain unverified. See [STATUS.md](STATUS.md).

The GitHub workflow is a validation definition; local checks do not prove that remote CI has run.

0.3.3 adds 26 injected source/capacity/format/legacy decoding checks through `Scripts/test-telemetry-reader.sh`, plus production history source round-trip and backward decoding. These checks do not access SMC.

0.3.4 preview UI validation exercised long press into editing, native handle-to-row drag in both directions, invalid drops without order changes, persisted ordering and accessible arrow controls. This is actual native UI interaction with the shared popup view, not a simulated drag-state test. The production-model fixture recompiles the app sources with isolated configuration; physical controls remain disabled.

0.3.5 expands the production fixture with four menu display modes, missing/invalid values and independent preview/status consumer shutdown. The real anchored NSPopover was opened through the native status button action and dismissed through toggle/Escape; the settings activity indicator confirmed energy pause when no eligible display remained. Automated dragging did not establish a real-popup row drop; the user manually confirmed normal native-popup sorting on 2026-10-18.

0.3.6 production-model checks confirm editor state is separate for preview/status and does not survive a newly created preferences object. Universal builds and strict signatures passed. Native UI checks confirmed Command-4 opens the real editor from closed and already visible states, the settings button opens that same editor, and Escape followed by ordinary opening restores display mode. The animation checkbox and Reduce Motion explanation were inspected; frame timing and changing the system Reduce Motion setting were not tested. The previous 0.3.5 drag confirmation is separate evidence.

0.3.7 adds a real-file recovery suite to `Scripts/test-smc.sh`. Its subprocesses terminate intentionally while operating file-backed fake registers; neither AppleSMC nor the real helper is invoked. Checks cover interrupted writes/restores for modern/legacy protocols and every adapter key, boot mismatch, external changes, malformed/unknown entries, save/removal failures, missing registers and unsafe file objects. Actual installed-helper crash recovery remains unverified.

The 0.3.7 recovery suite passed 49 scenarios on arm64 and x86_64 under the existing Rosetta runtime, in addition to the 24 protocol scenarios on each architecture. The normal unified check passed all 63 core methods and the hardware/CLI/Intents/dashboard fixtures. A separate read-only call verified the boot-identity parser on this host without printing the identifier. Subprocess termination uses `_exit` against file-backed fake registers; it is not a real hardware SIGKILL or reboot trial.
