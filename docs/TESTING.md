# Verification

Run deterministic checks from the repository root:

```sh
bash Scripts/check.sh
bash Scripts/build-app.sh
bash Scripts/test-helper-preflight.sh
```

`check.sh` runs core policy assertions, injected hardware/telemetry tests, isolated CLI/App Intents tests and the production dashboard fixture. The core adapter executes 90 canonical XCTest methods without the XCTest framework; use `swift test` with a full usable Xcode toolchain for framework execution. The adapter is not a substitute for an XCTest CI result.

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

0.3.8 extends `Scripts/test-magsafe.sh` with 47 LED recovery scenarios, passing on arm64 and x86_64 under the existing Rosetta runtime. Each run includes 25 abruptly exited subprocesses using file-backed fake ACLC values, including a cached blink transition. Additional checks cover all five captured values, boot mismatch, malformed records, missing registers, pre-write storage failure, failed restore/removal, external ownership, independent charge/LED files and symbolic-link rejection. A 1000-tick memory-store fixture verifies only two saves before restoration for the captured value 2. The unified local check passed all existing core, charge, telemetry, CLI, Intents and dashboard fixtures. Universal packaging and strict signatures passed. No physical LED writes or installed-helper restart were performed.

0.3.9 adds 70 production menu-bar projection/rendering checks to the dashboard fixture. They cover four styles and display modes, charging/plugged-discharge/idle/battery/missing states, physical adapter handling, invalid values, opt-in low-power tint precedence, text-only preservation and strictly growing rendered fill across 0/25/50/75/100%. An optional `OPENCHARGE_ICON_PREVIEW_DIR` exports an artificial light/dark contact sheet for visual review; it never changes system settings. The unified local check and universal build passed. Native UI checks confirmed all four style choices, selecting colored battery, numeric-only disabling of style/tint controls, and restoration of the previous display/style. Actual system Low Power Mode transitions, notification delivery and broader native appearance remain unverified; no system power setting was changed.

0.3.10 adds seven redraw-cache checks (77 menu-bar checks total), including 1000 duplicate presentations without a new image assignment. Native 0.3.9 profiling found repeated status-item snapshot/appearance callbacks; the static settings window consumed 3.32 CPU seconds in a 5.054-second sample (65.7% of one core). That release was returned to draft, with tags preserved. The fixed controller observes application appearance, filters identical names and guards image assignments with a semantic cache; tooltip changes are independent. Native CPU remeasurement is a separate required release gate, not inferred from fixture success.

Native 0.3.10 CPU remeasurement in the same static settings context passed: two 5-second CPU-time-delta samples were 2.39% and 0.00% of one core, compared with the 0.3.9 sample's 65.70%. Selecting colored battery still worked and its following 5-second sample was 1.80%; the original style was restored. These are short observations on one validation Mac, not a general performance benchmark. The complete unified check (including 77 appearance checks) and universal build passed before the native gate. The installed helper remained unchanged and hardware/system actions stayed disabled.


0.3.11 adds 13 core methods for semantic-version precedence, channel filtering, architecture fallback, repository URL constraints, bounded feeds/assets, checksum ambiguity and clock changes. The production dashboard fixture also checks known SHA-256 vectors, wrong size/content, redirect allowlisting and isolated update defaults without network. `bash Scripts/test-updates-live.sh` is a separate opt-in public-network smoke: it checks the real catalog, rejects an over-limit transfer, downloads a published ZIP into a disposable directory, verifies exact size / published SHA-256 / available API digest and asserts the on-disk quarantine attribute. It does not execute, extract or install the archive, touch the helper or modify hardware. Network availability and rate limits can make this optional check fail independently of deterministic tests.

The live smoke selected public 0.3.10 and passed with its 1,540,160-byte arm64 ZIP, including quarantine metadata. The fixture intentionally uses version 0.0.0 to exercise the download branch; the production app always reads its bundle version. Native UI and CPU validation are recorded separately from this backend test.


Native 0.3.11 validation opened the update window from the application menu, confirmed its actual bundle version and a successful public check reporting local 0.3.11 ahead of published 0.3.10, and inspected the same state in settings. Automatic checks remained off. Two 5-second CPU-time-delta samples with the update window open measured 3.39% and 1.00% of one core; two with settings open measured 1.99% and 0.00%. The first window sample can include completing the check. These short observations on one Mac are a release gate, not a general benchmark. Native download-button behavior with a newer release, automatic scheduling over a real 12-hour interval and automatic installation were not verified. Deterministic checks and the universal build passed; installed-helper bytes were unchanged and hardware/system actions stayed disabled.


0.3.12 adds eight pure discharge-exit methods covering stable external power, explicit physical unplugging, duplicate timestamps, long sampling gaps, transient unknown/battery readings, cleanup failure/retry, cancellation, timeout without automatic force, and invalid monotonic times. The production-model fixture injects helper responses and verifies restore versus retained inhibition, paused policy refreshes during quit, and monitoring after cancellation; it makes no real helper requests. `bash Scripts/build-quit-fixture.sh` builds a separate native harness whose helper and power inputs are entirely fake; it never creates ChargeModel or reads battery/SMC state. Native UI validation exercised cleanup failure → cancel, failure → retry → confirmed exit, timeout → window close → cancel, and timeout → explicit exit. Its event logs confirmed `reply(false)` keeps the app running and `reply(true)` reaches termination through the real AppKit deferred-termination loop. These checks do not establish real discharge/display recovery, logout/shutdown behavior or physical effects.


Final 0.3.12 validation also confirmed that the choice window stops polling while awaiting a decision: two static 5-second CPU-time-delta samples in the fake-only native harness measured 0.00% of one core. Retrying restarted the timer and reached confirmed termination. The final dashboard fixture passed after that change, and the final native/universal builds passed strict signatures. CPU samples are short observations on one Mac, not a general benchmark.


The actual 0.3.12 application also launched in monitoring mode, quit normally without a recovery dialog, and reopened with hardware/system actions still disabled. Two 5-second CPU-time-delta samples in its static settings window measured 2.99% and 0.00% of one core. The installed helper's bytes matched the existing baseline. This does not exercise the real active-control branch.


0.3.13 adds five pure sleep-plan methods covering monitoring, unplug/unknown adapter, physical power during discharge, completion/pause/invalid values, independent opt-ins, calibration display precedence, incompatible settings and backup import. `Scripts/test-sleep.sh` uses entirely injected state and private files, including abrupt subprocess exits around global/lid writes and restores. The optional `--read-only-api` mode resolves the installed SPI and compares stored/effective global state; it never calls a power setter, creates an assertion or opens the lid-control user client. It does not prove that either private write interface will succeed. The installed service is kept unchanged; newer helper interfaces cannot be exercised through the old installed service.


The production-model fixture also verifies that a read-only sleep-interface inspection neither clears a prior failed-write stop state nor resumes enabling requests. Service replies and failures are injected, with no real helper traffic.


The sleep suite passed 31 fake/file scenarios including eight abruptly exited subprocesses. A separate four-case removal test runs the actual uninstall script with system paths remapped into a temporary tree and launchctl replaced by a recording stub; root identity is bypassed only in that fixture. It verifies successful ordinary removal and preservation/restart requests for regular, dangling-link and directory recovery markers. No actual service command or system-path mutation is performed. The read-only SPI preflight on the validation Mac found consistent effective/stored state; pmset preference snapshots before/after were identical.

Native 0.3.13 inspection confirmed both prevention options off, display-sleep preference disabled until full control is selected, and the older installed helper explicitly reported as lacking sleep interfaces. That read-only detection result remained visible after a monitoring refresh. The static control-page CPU samples in the final package were 1.20% and 0.00% of one core over two 5-second intervals (short one-host observations). No prevention checkbox, hardware toggle or power action was enabled. Source review and the final injected fixture also ensure that inspection does not restart failed writes. New-helper installation, private setters, assertions, physical lid/display transitions and actual boot recovery remain unverified; the installed helper was unchanged. Final affected dashboard checks and native/universal builds passed after the UI fixes.


## 0.3.14 recovery phases

An injected regression reproduced cached false clearing a pending global restore after a simulated failed persistent write. This is a modelled backend failure, not evidence of a real power-setting failure on the validation Mac. The fixed sleep suite covers 37 fake/file scenarios including eight abrupt subprocesses: same-/cross-boot retry, partially committed enable with stale readback, legacy phase-free records, restore-intent save barriers and unknown-phase rejection. No production setter or assertion is called. The extra core method checks exact interface/protocol fields; the dashboard fixture checks read-only inspection cannot restart failed writes.

After the user manually installed the published 0.3.13 helper, its SHA-256 matched the reviewed binary and its read-only capability request succeeded with sleep interfaces detected. Hardware control, system actions and system/lid sleep prevention remained off. This verifies connection and interface detection only; the installed helper lacks the 0.3.14 recovery-phase marker. No real write, sleep, lid transition or reboot recovery was tested.

Final arm64 and x86_64 (translated on the validation Mac) sleep fixtures each passed all 37 scenarios; this is not an Intel hardware result. Native/universal packages passed strict signature and embedded-helper checks. The native 0.3.14 UI remained in monitoring mode, kept both prevention options off and correctly reported the installed 0.3.13 recovery protocol as unsupported. Two five-second static control-page CPU-time samples measured 0.00% and 1.00% of one core; these are short one-host observations. Public source and complete binary ZIP contents passed old-brand and credential-pattern scans.
