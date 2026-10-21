# Verification

Run deterministic checks from the repository root:

```sh
bash Scripts/check.sh
bash Scripts/build-app.sh
bash Scripts/test-helper-preflight.sh
```

`check.sh` runs core policy assertions, injected hardware/telemetry tests, isolated CLI/App Intents tests and the production dashboard fixture. The core adapter executes 95 canonical XCTest methods without the XCTest framework; use `swift test` with a full usable Xcode toolchain for framework execution. The adapter is not a substitute for an XCTest CI result.

Hardware planners use fake transports; Low Power Mode and sleep tests use injected runners/ownership state. The dashboard fixture uses isolated configuration and preferences with hardware/system actions disabled. App Intents setters only persist into their fixture. These tests never install a root service or change physical charging, LEDs or power modes.

## Optional integration

```sh
bash Scripts/test-energy.sh
bash Scripts/build-universal.sh
OPENCHARGE_TEST_ARCH=x86_64 bash Scripts/test-smc.sh
```

Energy smoke reads the optional system interface and its own CPU usage; restricted process access can make it unavailable. x86_64 execution requires an Intel host or already installed Rosetta. No scripts install Rosetta. Universal packaging verifies arm64/x86_64 executables, nested helper signatures and App Intents metadata (twelve declarations, five shortcuts).

## Existing validation boundary

Read-only telemetry and helper capabilities have been observed on MacBookPro17,1. Before 0.3.24, four native Shortcuts getters ran through the system UI and eleven declarations were discovered. Dashboard visibility/order and popup preview editing were inspected. Status-item overflow/multi-display behavior, real hardware writes, calibration cycles, sleep/wake recovery, user switching and notarized service lifecycle remain unverified. See [STATUS.md](STATUS.md).

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


## 0.3.15 required sleep protection and optional lid lock

Fresh read-only local settings inspection established required sleep protection during calibration and clamshell discharge, distinct from optional until-limit protection. A retained lock setting and private entry were traced statically; the independent lock toggle was not visible in the current reference UI. This is treated as an optional enhancement, not proof of current UI parity. No reference setting or operation was changed.

Three new core methods exercise independent lock conditions, one-attempt behavior over 1,000 duplicate observations, unknown state and rearming. Two more methods cover required full protection during ordinary clamshell-discharge opt-in and calibration's closed-lid draining/returning; existing sleep-plan checks cover mandatory calibration protection with the optional setting off and no assertions when monitoring/unplugged. Dashboard checks inject every helper/lock request, disable the real lid observer in the fixture, and reject any uninjected lock. They cover unsupported preflight before charge writes, conflicting sleep-policy suppression, acknowledged-session/console gating, duplicate/failure behavior, read-only inspection and cleanup after a failed override. The final 39-scenario sleep suite checks schema-2 output and schema-1 migration before compensation, including phase-free, setting and already-restoring records; schema-1-only released helpers reject version 2.

The optional `Scripts/test-sleep.sh --read-only-lid-lock` path only resolves the login SPI, registers/releases the read-only IOKit observer, and checks lid/session readability. It never invokes the lock function, creates a power assertion or sends a helper command. The command-line environment reported readable lid state but had no Quartz GUI session, so the console guard correctly returned inactive; this is a diagnostic result, not a lock test. Physical lid notification timing, actual lock outcome, real calibration/discharge and sleep/reboot transitions remain unverified.

Native 0.3.15 UI inspection found the lock entry and a valid foreground login session, kept the new toggle off and explicitly reported that no lock was requested. Sleep-interface inspection still reported the installed 0.3.13 recovery protocol as unsupported; all controls remained off. Final native/universal validation and translated x86_64 migration fixtures are recorded below after rebuilding.

The final rebuilt arm64 and translated x86_64 sleep fixtures each passed 39 scenarios including eight abrupt subprocesses. Final native/universal packages passed strict signature and embedded-helper checks. After reloading the final native package, both read-only buttons again reported the expected interface/session results with controls off. Two five-second static control-page CPU-time samples measured 0.00% and 1.20% of one core on one Mac; these are short observations, not general benchmarks. The reviewed installed 0.3.13 service bytes remained unchanged.


## 0.3.16 fresh-calibration reload

A red fixture invoked the actual start-calibration intent, confirmed its checkpoint was cleared on disk, then explicitly delivered the production reload callback. The live model still retained its interrupted flag and phase. The fixed fixture checks fresh-run reset, checkpoint-bearing updates retaining interruption, duplicate reloads, refusal to enable hardware from disk, leaving calibration and malformed reloads retaining previous state. The fixture uses a private data directory and disables the actual lid observer; every helper/lock path remains inactive or injected. This fixes a state transition and does not establish a real calibration cycle.

On the prior published package, native Shortcuts ran the four-getter workflow to completion and returned holding. A separate limit-setter workflow wrote 79, the live application displayed 79, and the same workflow restored 80. Hardware/system actions remained disabled. A preliminary immediate-sync assertion in an isolated fixture was discarded because that fixture suppresses distributed notification transport; it was not evidence of a production notification failure.

Native reproduction on the previous package also reached the same failure through system Shortcuts. With hardware/system actions off, a monitoring-only calibration checkpoint was created, the application was reopened into its interrupted state, and the start-calibration action cleared the disk checkpoint. The live Control page still showed its interruption/continue/cancel controls after a manual refresh. The test then cancelled back to automatic monitoring; no actual charge, discharge, assertion or lock request was made. The paused Overview snapshot was deliberately excluded from this conclusion.

The final 0.3.16 native package passed the same system-Shortcuts scenario in monitoring mode: it initially retained the interrupted prompt after relaunch, then removed the live Control-page interruption/continue/cancel controls after an explicit new-calibration intent and proceeded with the new logical run. The test restored automatic mode, limit 80 and a nil checkpoint. The temporary calibration shortcut action was undone and replaced with a read-only state getter. Hardware/system actions, sleep/lock options and the installed service remained unchanged. This is native configuration/state integration evidence, not a physical calibration cycle.

Final native/universal packages passed strict signature and embedded-helper checks. The final native Control-page CPU-time delta samples were 2.19% and 0.00% of one core over two five-second intervals on one Mac, not a general benchmark. The full local suite passed 95 core methods, 39 sleep scenarios (eight abrupt subprocesses), 49 charge-recovery and 47 LED-recovery scenarios plus existing integrations; the final affected dashboard fixture also passed after the opt-in persistence correction.

The final callback fixture additionally resumed an injected holding checkpoint with control disabled, issued the real set-mode calibration intent, and sampled the next policy evaluation. It verified the engine no longer remained in holding, so clearing the displayed phase alone cannot satisfy the regression; a repeated reload preserved the new phase. The resumed checkpoint is a fixture, not a real charging cycle.


## 0.3.17 required-protection ordering

The isolated dashboard harness calls the production `applyHardwareDecision` method with injected helper responses. The pre-fix code reproduced a charge/discharge command before the required protection request had succeeded. Both actions now require the sleep-override acknowledgement first. Failed protection sends only its attempted override and fixed restoration; successful protection precedes the sleep-entry policy and charge command. A later charge-command failure restores the session, while normal completion retains cleanup ownership until release. All helper calls in these cases are injected; no real power setter, sleep assertion or physical charge/discharge cycle is exercised.


## 0.3.18 discharge and lid transitions

Core checks cover manual/automatic closed-lid discharge without an extra opt-in, legacy true/false flag decoding without arming hardware, idle protection with optional settings off, open/closed/unknown lid states, display choices, completion, explicit unplugging and acknowledged input cuts. The dashboard harness injects all helper and idle-assertion operations. It checks idle-creation failure before any power request, closed → open → closed protection ordering, completion before release, immediate lid-edge callback delivery, duplicate/unknown observations and quit suppression. No real assertion, helper setter, physical lid transition or discharge cycle is exercised by these fixtures. Native monitoring-only validation is separate from these injected cases.


## 0.3.19 temperature waits and selected sleep protection

Corrects the 0.3.18 default that forced public idle inhibition during ordinary discharge. The updated lid fixtures require an explicit idle selection while retaining full closed-lid protection. Core cases distinguish confirmed thermal waiting from Sailing and manual pause, retain Top Up/departure targets, cover the inclusive 20% heat exemption and Sailing floor, and decode older decisions without the optional thermal flag. A production-model fixture follows a hot pause through cooling and target completion: the selected full override is acknowledged before each power command and released after completion. All helper and idle-assertion operations are injected; no physical temperature/sleep/charge behavior is established by these checks.


## 0.3.20 ordinary discharge and charging-temperature priority

Core cases cover ordinary manual/automatic discharge with high, missing and nonfinite temperature readings; hot target completion; stale charging-window removal; daily target completion below 100%; and reserve/target conflicts without charge pulses. The optional calibration-temperature enhancement still pauses calibration draining when selected. The dashboard fixture derives actual engine decisions from a hot sample, then injects all helper and idle operations for manual/automatic and open/closed cases. Required closed-lid protection remains before the discharge command. Additional unplug cases end manual discharge on explicit physical disconnection and preserve it during an acknowledged own input cut with unavailable raw presence. These are software regressions, not physical high-temperature discharge or cable tests.


## 0.3.21 fractional percentage boundaries

Core cases cover manual discharge completion and automatic-discharge entry at whole percentage boundaries, fractional configured daily limits, single-precision values near the next integer, fractional Sailing restart thresholds, and isolation from reserve and calibration comparisons. The production-model fixture follows closed-lid discharge from 90% to 80.6% with an 80% target; it verifies charging is inhibited before selected idle and full sleep protection are released. Helper, idle and lock operations are injected. No physical threshold, charge or lid behavior is established by these software checks.


## 0.3.22 full-charge top-off

Core cases cover ordinary 100% and Top Up continuing to allow charging at full, fractional control precision, recharge after a small drop, unplug completion, temperature/manual-pause priority, legacy decisions without the new optional flag, calibration isolation and active-policy MagSafe indication. The injected production-model fixture follows 90% to 100% to 99.5%, verifying protection before charging, release at full, and protection reacquisition below full. Menu-bar checks distinguish full top-off from observed monitoring, missing readings and unplugged state. All helper, idle and lock operations are injected; no physical charging, sleep or LED effect is established.


## 0.3.23 pause and native LED encoding

Pause fixtures inject OS and hardware percentages, exercise below-20%/nonfinite/missing-reading rejection without mutation, cancellation of calibration and temporary targets, and the transition from a current-limit pause into Sailing and charging. A full-percentage pause remains distinct from full-charge top-off. Explicit manual-mode selection clears resumable-pause behavior.

LED fixtures use fixed 1/2/4/6 values, retain read/recovery compatibility for legacy 3, suppress native blink on sleep entry, and avoid repeated heartbeat writes. Recovery includes 54 scenarios with 30 terminated file-backed subprocesses and explicit legacy/native journal cases. A shared app/CLI capability preflight and production-model injected IPC verify the exact capability read precedes every green/blink setter; legacy services receive no LED setter. Tests do not update or restart the installed helper. Physical colors, cadence, sleep and charging remain unverified.

## 0.3.24 live application state

The core adapter passed 135 methods, including typed phase transitions, full-charge versus observed-flow distinctions, current-limit pause resumption, thermal/calibration isolation, invalid-read retention and legacy decision decoding. The isolated intent harness invokes the actual getter with changing live providers, unavailable/throwing providers and byte-identical configuration checks. The production-model fixture reads engine-produced phases independently of presentation text, pending calibration and quit preparation; it verifies weak model lifetime and rejects stale state. All helper/lock operations in these fixtures are injected or disabled.

Native Shortcuts discovered all twelve actions. A new read-only application-state workflow returned `Sailing`, matching the running application's 79%/80% Sailing hold. After the application quit, running that workflow launched it and again returned `Sailing`. This establishes live and cold-start execution for that state on the validation Mac, not all state transitions or hardware effects. The existing observed power-flow getter retains its identifier and output contract.

## 0.3.25 thermal-window continuation

Core regressions follow an already-confirmed five-minute thermal pause from 21% through 20%, 19% and exactly 15%, require continued inhibition, and release below 15%. Additional cases cover cooling at 299/300 seconds, a renewed hot window, the thermal opt-out, fresh low-charge samples, explicit mode changes and switching to degree hysteresis. Calibration retains its separate optional thermal behavior. These are injected samples; physical battery discharge and temperature effects remain unverified.

## 0.3.26 thermal behavior switching

A regression switches from an active degree-hysteresis pause to five-minute behavior at 19%. The new behavior must apply its fresh low-charge exemption, rather than inherit the old behavior's pause. This supplements the five-minute-to-degree case and preserves established-window continuation. The 0.3.25 development release was withdrawn after this boundary was found before final publication verification.
