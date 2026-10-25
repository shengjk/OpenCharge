# Verification

Run deterministic checks from the repository root:

```sh
bash Scripts/check.sh
bash Scripts/build-app.sh
bash Scripts/test-helper-preflight.sh
```

`check.sh` runs core policy assertions, injected hardware/telemetry tests, isolated CLI/App Intents tests and the production dashboard fixture. The core adapter executes 233 canonical XCTest methods without the XCTest framework; use `swift test` with a full usable Xcode toolchain for framework execution. The adapter is not a substitute for an XCTest CI result.

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

## 0.3.27 thermal-state ordering

New core regressions first reproduced four failures (14 assertions) on 0.3.26: Sailing replacing an active thermal wait, truncation of fractional thermal targets, the full-target transition and loss of confirmed state on unavailable temperature. The corrected core suite passes 145 methods. Coverage includes cooling at the deadline, fresh hot re-entry after cooling, full-target pause persistence, missing/nonfinite temperature and explicit discharge preemption. Older expectations for a fixed charging allowance after cooling and immediate opt-out charging were replaced with state transitions: renewed heat starts a new wait; disabling active protection transitions through Pause.

The production-model fixture moves a confirmed heat wait into the Sailing band, removes temperature, cools before/at the deadline, then reaches the daily target. It requires selected system/lid protection before every control command until completion and release afterward. Helper, idle and lock operations are injected. Actual temperature, battery, lid and sleep effects remain unverified; Top Up and broader coordinator interactions remain separate work.

## 0.3.28 Top Up thermal selection and exit persistence

The core suite passes 160 methods. A full-charge thermal opt-out regression first failed nine assertions on 0.3.27; the corrected exit retains Pause through subsequent 100% updates and resumes below the target bin. Additional cases cover fractional targets and mode/thermal-behavior isolation. The production fixture checks inhibit-before-release ordering, no repeated full-sleep release during subsequent full-charge updates, and protection reacquisition before later charging. All actuators are injected.

Fresh Top Up tests cover hot, missing and nonfinite temperature, full-charge holding and an explicit thermal opt-in. Legacy JSON without the new option retains the previous thermal behavior, while a fresh policy persists an explicit false. In-memory JSON and backup round trips preserve absent/false/true preferences without resuming control. Ordinary automatic and calibration policies retain their independent temperature rules. Real charging/temperature effects remain unverified.

Native Charge Control on the validation Mac exposed the independent Top Up thermal checkbox as enabled for an older saved policy without that field, with calibration protection still off. No checkbox or actuator was toggled. The full-charge caption distinguishes ordinary top-off from explicit/thermal target pauses.


## 0.3.29 Sailing restart checkpoints

Core cases cover absent/charging/holding history, cold engine reconstruction, fractional runtime versus whole checkpoint boundaries, minimum-target branch ordering, Top Up and optional temperature-state isolation, daily versus departure targets, invalid readings, unplugged samples, changed daily limits and portable JSON/backup handling. Production-model fixtures inject battery readings at startup, preserve the checkpoint through external configuration reloads and calibration reconstruction, and check that stable refreshes do not rewrite the configuration. The CLI fixture verifies same-limit preservation, changed-limit reset and no-write explanation. All model fixtures retain monitoring-only hardware/system settings. These software checks do not establish physical charging, cable detection, full restart recovery after OS shutdown or every mode/setting transition.


## 0.3.30 power-flow animation lifecycle

A private, never-shown layer fixture checks missing/idle channel suppression, direction reversal, reactivation, the two-second cycle, stable animation timing during telemetry updates, compact and resized geometry, focus pause, Reduce Motion, hiding and detachment. Native full-size diagrams were compared visually in monitoring mode and their arrows observed at different positions. On the test host with a focused visible two-channel diagram, 0.3.29 consumed about 24–28% of one CPU core in two five-second samples; the layer candidate measured 0–1.6%. This measures the app process, not total GPU/window-server energy or a universal performance guarantee. Existing policy and hardware-fixture checks remain separate.


## 0.3.31 zero-size animation cleanup

The new zero-size lifecycle case failed on the 0.3.30 source with active compositor animations still attached. The host now removes both animations before returning for empty geometry, and the fixture checks restart after restoring its size, followed by detach cleanup. The 0.3.30 source tag is retained; compiled release packages start with 0.3.31 for this performance update.

### 0.3.32 temporary operation buttons

An isolated production-model fixture uses injected battery readings with hardware and system actions disabled. It checks Top Up start/stop, an idempotent explicit Top Up request, persistence of indefinite Pause below the daily limit, full-charge stop, manual and automatic discharge stop, thermal-phase separation and unplugged Top Up rejection. The daily limit stays at 80% throughout the stop cases. This verifies policy transitions without performing physical charge/discharge or clicking live control buttons.

### 0.3.33 scheduled current-limit Pause

Core cases cover every typed phase, the daily 100% Heat Protection exception, single-precision 20% boundaries, missing/nonfinite/out-of-range readings, interrupted calibration, context-free consumption and all repeat rules. The production-model fixture uses injected telemetry and disabled hardware/system actions for startup-due tasks, Sailing skips, current hardware percentage, missing selected hardware data, ordinary/full-target heat waits, active/pending calibration and ordered same-batch actions. The pre-integration startup check failed before model wiring. A further active-draining → Pause → Calibrate regression failed before explicit engine mode-transition handling; it now starts a fresh filling stage. The mode event also clears holding state without advancing a sample or losing the Sailing checkpoint. Execution history distinguishes accepted policies from skips and unconfirmed hardware effects. No real power, sleep, LED or lock setter is exercised.


## Menu-bar right-click — 0.3.34

Core cases cover all policy phases, the 100% thermal exception, fractional and invalid selected percentages, legacy/unknown action preferences, and repeated near-full charging after an explicit full-target restart. Production-model fixtures cover preference persistence, every action/click routing combination, Settings page selection, current-percentage pause, hardware-percentage selection without fallback, interrupted calibration preservation, and opt-in/capability/error boundaries for Low Power Mode. All telemetry and service setters are injected. Native status-button event delivery and UI presentation require separate checks; these fixtures do not prove physical charging or system-mode effects.

Native checks on the current Mac confirmed the four action choices, the default popover selection, and Command-3 opening and closing the actual anchored popover. Hardware and system actions remained off and the view returned to monitoring. Automated input did not locate the physical status icon for a right-click; in response to the OpenCharge 0.3.34 verification prompt, the user confirmed that right-clicking the status icon opens the popover and right-clicking again closes it. This is user-reported runtime evidence for that version and interaction; it does not establish later-build behavior or hardware effects.


## Explicit GUI mode selection — 0.3.35

The production SwiftUI picker binding is exercised directly with isolated configuration and injected telemetry. The baseline reproduced current-limit Pause → Automatic → Pause resuming automatically below the old limit. Cases cover the persisted indefinite-pause result, unplugged Top Up/Calibration rejection, interrupted Calibration preservation and cancellation, idempotent active selection, and cancellation/restart across a telemetry read failure. Quick-profile checks verify interrupted-calibration cleanup on disk and in the live model. Hardware and system actions remain off throughout. These checks do not establish physical calibration or charging effects.

Native inspection on the current Mac confirmed the five mode segments with Automatic selected, idle calibration, the unchanged 80% limit, and monitoring status. No segment, profile, calibration, hardware-control or system-mode action was clicked. Command-3 opened and closed the real popover, and the view returned to Overview. Binding behavior is established by the isolated regression above, not by this read-only UI inspection.


## Administrator charging-settings restriction — 0.3.36

Isolated UserDefaults/configuration tests exercise the actual production bindings, preference observation, defaults removal, and a binding created before locking. Protected fields, custom edits, limit setters, quick profiles, Save and the right-click charging toggle leave policy, limit identity, configuration bytes and telemetry-read count unchanged. Background Save and a due limit task still persist; Top Up, explicit modes, URL automation and injected Low Power Mode remain usable. No real control or system setter is invoked. Managed-profile deployment and physical charging effects remain unverified.

Native 0.3.36 validation used an isolated preferences suite, configuration directory and fixed battery telemetry. The charging limit, Sailing, temperature, sleep, reserve, departure and save controls were disabled while restricted; the mode picker and separate diagnostic, appearance, MagSafe and Low Power Mode controls remained available. Removing the isolated restriction immediately re-enabled the editors; reapplying it disabled backup restore while export remained available. No hardware or system-mode actions were invoked. External managed-profile deployment remains unverified.

Version 0.3.37 firmware coverage includes ten pure target-projection tests covering the distinct sleep and exit formulas, active/reset targets, Sailing flag differences, Float boundary rounding and truncation, the heat-state exception, unknown charging-control readings and invalid inputs. All 199 core test methods passed. This pure calculation layer performs no hardware access and is now used by the 0.3.37 app integration below. It does not establish firmware support, event ordering, physical cutoff or sleep/shutdown persistence.


The 0.3.37 numeric firmware controller adds 28 injected transaction/status/recovery/exit scenarios. These cover typed one-byte metadata, fixed key/value bounds, CH0B/BCLM/BSIn control-state interpretation, whole-plan ownership preflight, final full-profile readback, repeated requests, malformed and different-boot journals, disk/read/write failures, rollback retry, external changes and orderly-exit ownership release. Regression cases first reproduced a changed initially unchanged key escaping final validation and a known second-key conflict allowing a first-key write; both now pass.

A separate fixture terminates 32 subprocesses around journal saves/deletions and fake-register writes/readbacks during apply, restore and orderly exit. It uses the actual file-store implementation in disposable current-user directories, then constructs a fresh controller to recover. Before successful exit journal removal, recovery restores owned original values; after removal, it preserves the committed exit target. Repeated recovery is checked. These are process-termination tests, not power-loss or physical firmware tests.

The full check passed with 199 core methods and all injected suites. The SMC suites also passed as x86_64 processes under Rosetta on the same Apple Silicon Mac, including the 28 numeric scenarios and 32 subprocess terminations. This does not establish Intel hardware support. The mutation methods have the 0.3.37 helper integration described below; app integration is covered separately below. No real helper or hardware setter was called.


Version 0.3.37 SMC transport work adds 134 raw-frame and numeric-probe checks, passed as arm64 and x86_64 processes. Fixtures independently encode the C ABI's metadata size and FourCC integer, exercise malformed frame lengths and size endianness, preserve the trailing type space, distinguish missing keys from driver errors, reject unknown numeric metadata/keys/values before command 6, and check selected-model/architecture/battery gates without any key query for ineligible hosts. The real numeric controller is also exercised over these frame fixtures, including metadata changes after its last pre-write read and retained-journal recovery. Existing temperature payload decoding and ordinary sized writes are covered. All IOKit transport calls remain injected in these fixtures.

The full check passed with 199 core methods, 28 numeric transaction scenarios, 32 numeric process-termination cases and the 134 wire checks. A separate native `chargectl diagnose-smc` read-only run on MacBookPro17,1 retained CHTE/CHIE detection and reported numeric read/write unavailable. No service was installed or restarted, no settings were changed and no real setter was called. Accepted numeric profiles still need physical Intel validation.


Version 0.3.37 helper integration adds nine canonical core methods (208 total) covering all 248 finite firmware command forms, invalid/noncanonical input, helper callback ordering, rejected preflights, lease-neutral status, active-session/observer sleep guards, sleep targets, pending recovery and exit success/failure state. The production helper uses the same injected session component. Client whitelist checks reject malformed string and typed requests before IPC.

The exclusive backend fixture passes 53 checks using the actual ordinary/numeric controllers and the fixed file-store views. It exercises switching over overlapping CH0B state, cleanup failure before a new backend can write, unsupported/malformed preflight preserving ordinary ownership, pending recovery, cold-start dispatch, conflicting/malformed record preservation, committed exit, journal isolation and symlink refusal. These checks run as arm64 and x86_64 with fake registers and disposable current-user 0700 directories. The 32 numeric terminated-subprocess cases now use the actual distinct firmware record and assert that the ordinary record is absent. Path-remapped removal tests cover clean removal and regular, dangling-symlink and directory markers for all four recovery records (13 scenarios), with service calls stubbed.

These fixtures do not validate the installed privileged service, real authenticated numeric IPC, physical sleep/wake/exit effects, Intel hardware behavior or the pending app lifecycle handoff. The validation machine's installed helper and hardware settings remain unchanged.


Version 0.3.37 app-side protocol decoding adds five canonical core methods (213 total, all passed). Numeric control capability requires the exact protocol, readable fixed profile, writer protocol, recovery-ready state and internal battery; missing, old, pending, contradictory, repeated and oversized/framed capabilities are rejected. All recognized status limits and charging states are decoded without substituting an OS flag for unknown. Malformed status fields and noncanonical limits are rejected; unknown remains unknown when computing a sleep target.

The actual Settings service-inspection path uses this decoder. An injected production-model fixture checks that old/pending/duplicate capabilities stop after the capabilities query, valid profiles request only firmwareStatus, unknown remains unknown, malformed replies clear the previous reading, and configuration/control flags remain unchanged. The dashboard suite passed, including these cases. This diagnostic does not select a numeric control mode or establish an owned firmware session; app control handoff is a separate path covered below. No real helper request or hardware setter is used by this fixture.

Version 0.3.37 Intel inflow work adds 35 injected ownership/property checks to `Scripts/test-smc.sh`, passed as arm64 and x86_64 processes. The fixed `DisableInflow` component checks authorization before OS operations, records only its own process-local identifier, rechecks an existing assertion without creating another, and retains ownership after inspection or release failures. Pending cleanup prevents acquisition until an explicit successful restore. Fixtures cover denied authorization, failed creation, invalid identifiers, false/throwing inspection, release failure and retry, repeated restore, reacquisition, and exact property type/level matching including booleans, strings, fractional values and NaN. Every create/read/release operation is injected; no OS assertion is created or released.

The component now has the 0.3.37 backend/helper/app integration below. Assertion IDs must never be restored from a previous process. Readback confirms the assertion properties only, not physical power flow.

Version 0.3.37 discharge integration adds a separate `firmwareDischarge:inflowV1` command extension and a 249th finite command. Six additional canonical core methods (219 total) cover its independent capability requirement, owned-session/observer/sleep-target prerequisites, rejection of sleep-policy removal during discharge, failed transitions, sleep-entry cleanup retries and recovery after a control preflight fails before the mutation callback. Read-only failures remain separate from control failures.

A 95-check composition fixture connects the actual helper session, exclusive backend, numeric/ordinary controllers and fixed file store over injected SMC and IOPM callbacks. It checks journaled inhibition before assertion creation, identifier reuse, sleep and exit ordering, release before every backend transition, creation/inspection/release/write failures, immediate cleanup, blocked writes while cleanup is pending, retry at sleep entry, existing-firmware preflight failure and preservation of a healthy ordinary session. The production helper uses the same sleep-reconciliation method, including retrying recovery already pending before sleep. These are simulated transitions with disposable current-user files; neither the root service nor real hardware or assertions are used.


Version 0.3.37 atomic app control expands the finite command set from 249 to 496 forms. Fourteen additional canonical methods (233 total) cover atomic action/target publication, observer and existing-session gates, failed plans preserving recovery state, protocol extension validation, first-session protection bootstrap, bounded syntax, app heartbeat behavior, unknown control state, current Exit projection and ambiguous responses. The hardware/helper composition fixture now passes 101 checks, including first atomic allow, inhibition/discharge plans, sleep reconciliation and subsequent journal recovery.

The production-model dashboard fixture selects the numeric channel from the independent atomic extension and rejects an old helper for a required numeric profile. It uses the actual helper session with injected callbacks and the real active-session gate for sleep protection. It confirms inhibit/15 bootstrap before protection, protection before force, repeat heartbeat reuse, root sleep followed by wake reentry, no ordinary setter from the app's numeric sleep notification, current Exit limit despite ordinary stop flags, failed-response/failed-restore responsibility, disable and cancelled-exit cleanup. A protection failure restores the bootstrap without starting discharge. All helper transport, control and protection callbacks are injected; no real service request, SMC write or OS assertion is executed. Native and x86_64 builds remain distinct from physical Intel or special multi-display validation.


The numeric app queries the root-owned `firmwareSessionStatus` before every cached control transition. This query reports active/inactive separately from register values and does not acquire or renew a lease. A recovered or restarted root session stops cached allow, inhibit and discharge requests even when the observed limit matches a previous value; cleanup must be acknowledged before manual re-enabling. The additional tests cover both 15 and 80 as restored register values, and confirm that read-only session inspection cannot extend helper ownership.


## Popover manual-discharge control (development source)

The dedicated popover discharge button is disabled while automatic discharge is enabled, including its Stop presentation. Its action also checks the current setting before accepting an already captured click. Explicit mode requests retain their separate entry point. Isolated model checks cover inactive and discharging states, unchanged policy/persistence after rejected clicks and re-enabled control after automatic discharge is switched off. The production SwiftUI button and isolated UI harness compile, but native presentation and inherited disabled state remain unverified because the UI validation tool timed out before the fixture was running. No physical discharge is implied.


## Helper sleep-transition admission (development source)

The updated helper marks system sleep before charge preparation, rejects late ordinary/numeric charging and sleep-policy updates, and reopens admission on the completed IOKit wake notification. Read-only queries, recovery and explicit exit cleanup remain available. The exact `SUSPENDED sleep-transition` reply means the requested operation did not execute; the updated app retains its opt-in and existing recovery responsibility and retries after wake. Transport errors retain their existing ambiguous-failure handling.

Twelve additional canonical core methods (245 total) cover finite command admission and numeric ownership across suspension. Isolated production-model/helper-session checks exercise both app/root notification orders, early app wake, first numeric bootstrap, required-protection and discharge-request boundaries. New-helper app notifications do not send a competing ordinary action; legacy-helper behavior remains separate. The injected checks confirm no discharge before wake, no unnecessary restore of a healthy sleeping session and successful wake retry. No new root helper, real charge setter, sleep override or user-activity assertion was executed. Multi-display sleep-entry selection and physical sleep/display behavior remain incomplete or unverified.


The `chargeTransition:epochV1` extension issues a root-instance and sleep-event context. Each updated app policy round queries it once and wraps its finite charge/protection/status requests with the same token. Sleep, recovery and console-owner changes invalidate the context. A full sleep/wake between two IPC requests invalidates the remaining requests even after the root is awake again. The envelope is bounded to the existing 128-byte frame and a fixed command alphabet; peer and foreground-console checks still run before dispatch. Core checks cover stale rounds, helper restart, canonical syntax, duplicate events, all numeric command forms and independent capability parsing. A production-model fixture simulates an entire sleep/wake after protection succeeds and before ordinary/numeric control, verifying rejection without discharge and a fresh protected retry. An awake cleanup variant retires protection without a sleep cycle and must reject the same stale round. Cleanup and explicit exit remain unscoped and available.


### Unreleased ordinary protection bootstrap

The production-model fixture starts with no ordinary helper session and enforces the current-session prerequisite for sleep protection. It checks inhibition before protection and force, no repeated bootstrap in a healthy session, restoration after ambiguous bootstrap/protection/force replies, and retry after confirmed unexecuted bootstrap or protection suspension. The event-context fixture also starts its ordinary branch without a session. All setters and assertions are injected; this does not validate physical discharge or special multi-display sleep behavior.


### Development multi-display sleep-entry checks

Five new canonical core methods (250 total) exercise fixed discharge-only metadata, all policy phases, single/multiple screen counts, exact optional capability parsing, fresh/expired/unknown eligibility, every independent failure combination and event-context rejection before/after sleep. The longest wrapper, including the maximum event counter and numeric sleep target, remains below the 128-byte frame limit.

The production-model fixture covers ordinary and numeric backends, Discharging versus Calibration, one/two screens and selected display protection. It checks selection only after an accepted force/atomic discharge action, temporary numeric allowance without losing the registered sleep target, and revocation on the next accepted single-screen round. Sleep smoke fixtures inject every native function and check the owned activity identifier lifecycle, including failed declarations that change/clear an existing identifier, successful refresh replacement, zero-success rejection, failed release retry, and restoration alongside the existing sleep journal. No default OS setter or assertion callback is invoked. These checks do not prove instantaneous topology, asynchronous completion order, or physical sleep/charging effects.


### Development ordinary sleep opt-in

Three additional canonical methods (253 total) check that ordinary opt-out releases protection without a charge operation, opt-in orders inhibition before release for all failure combinations, and a policy without an owned session cannot start charge control at sleep. The same coordinator is used by the root observer and legacy app notification path. The production-model fixture covers allow/inhibit/discharge states, release failures and retry, unchanged saved configuration and discharge-exit responsibility, and independent release after an inhibition failure. Required protection does not suppress an explicit ordinary sleep policy during app dispatch. Numeric and multi-display checks remain separate. All transport and actuator callbacks are injected; physical sleep/adapter behavior remains unverified.


### Development app localization

The full check combines compiler-extracted and literal Foundation source keys for complete coverage of all 527 English/Simplified Chinese/Traditional Chinese entries, exact printf-placeholder parity, two English plural rules, and five separately localized App Shortcut phrases with intact named tokens. A private native bundle runs the production page/menu/domain labels and policy engine under English, Simplified Chinese, Traditional Chinese, Taiwan/Hong Kong language selections and an unsupported-language fallback. It checks interpolation, literal percent signs, plural forms, localized errors and identical encoded charge policy. Stored page, policy-mode and phase values remain unchanged. No GUI, runtime model, intent, root helper or actuator is launched. Visual English layout and live Shortcuts/Siri localization remain unverified.


### Development numeric model selection

Raw-frame fixtures exercise all seventeen selected numeric models, including MacBookPro13,1–13,3, MacBookPro14,1–14,3, MacBookPro15,1–15,4 and MacBookPro16,1–16,4. Each accepted model reads the same fixed CH0B/BCLM status without writes. Each is rejected before any transport call for an arm64/unknown process architecture or an absent internal battery. Mistyped/neighboring identifiers and Apple Silicon models remain rejected. Invalid CH0B or BCLM metadata is refused independently for each accepted model; model identity never bypasses typed-key checks. These injected checks do not establish physical charging, sleep or recovery on those notebooks.

### Development Apple silicon ordinary profiles

Injected-byte and journal checks select 29 known model identifiers under arm64 and x86_64 processes, preserve generic selection for other families, and exercise CH0C precedence over coexisting CHTE. They cover the distinct CH0C values for inhibition, discharge and retained inhibition, allowance reset order, CH0C-only layouts, unchanged unused keys, missing or invalid input controls, malformed/read-error refusal without fallback, repeated no-op requests and battery/permission guards. Recovery checks include interrupted generic journals, CH0C=1 crash records, generic-helper refusal without erasing a new record, failed rollback with retry, and partial write cleanup. No AppleSMC connection, helper request or OS assertion is used by these fixtures.

## Direct CLI charge boundary

Five core regression methods inject model-selection and request callbacks to check invalid/internal/unconfirmed actions, refusal of ordinary commands on numeric firmware models, model-inspection failure, exact ordinary request/reply forwarding and transport failure, and restore without model discovery. The CLI configuration script also invokes malformed/internal hardware requests and checks that they fail with the usage error while preserving configuration. No accepted live hardware action is invoked by these checks; physical control and authenticated IPC require separate validation.

## Shared-module macOS availability

`Scripts/test-shared-availability.sh` compiles the complete ChargeCore and ChargeHardware modules and the C power-message bridge with a macOS 11 deployment target for arm64 and x86_64. It runs during `Scripts/check.sh` and does not execute hardware code. The script also links and runs a macOS 11-target automation fixture on the current system with injected providers. Shared localization uses Foundation's older lookup API with the same source keys; the HTTP error preserves its signed 64-bit format argument. Native language fixtures check translated policy/domain/error strings and the HTTP status in six language selections.

The IOKit default-port accessor selects the SDK's modern constant on macOS 12 or later and its legacy name on macOS 11. Compilation with a deployment target establishes API availability only. The packaged application still requires macOS 13; SwiftUI, Charts, App Intents, service/login registration and actual older-system behavior need separate compatibility work and runtime validation.

The app lookup compatibility fixtures compare all 34 unique formatted app keys with native interpolation using four typed samples per key in each of the six language selections (816 comparisons per architecture). The script supports an explicit `OPENCHARGE_TEST_ARCH`; arm64 and x86_64 runs exercise the same cases. Cases include plural counts, signed and unsigned integers, multiple string arguments, Unicode and percent-containing input. The actual battery-specification minute formatter is checked for one/two minutes and unavailable telemetry. These checks run on the current system and do not establish older-system runtime or translated visual layout.

## Update transport compatibility

`Scripts/test-update-transport.sh` uses private URLProtocol fixtures rather than network connections. It checks fragmented bodies, request headers without credentials/cookies, declared and streamed size limits, HTTP errors, non-HTTP or unapproved final URLs, allowed/blocked redirects, exclusive file creation, symlink refusal, transport failures, cancellation before starting and after a file opens, file streaming/progress, checksum/API-digest/size failures, quarantine and failed-download cleanup. Cancellation from the completion progress callback verifies that external callbacks run outside the sink lock. The full check includes this suite; `OPENCHARGE_TEST_ARCH` selects arm64 or x86_64.

The macOS 11 availability gate includes the complete update transport for both architectures. This is a compile check, not older-system execution. `Scripts/test-updates-live.sh` separately checks the public release feed and a real published archive without credentials, archive execution, installation or hardware access.

A live anonymous check on the validation machine selected v0.3.37, rejected the archive under a 16-byte transfer limit, then streamed its 2,130,017-byte arm64 ZIP and verified exact size, SHA-256, the API digest and quarantine. The temporary download was removed; no archive, app or privileged service was installed or executed. This checks the current system and public endpoint, not macOS 11 runtime.

## Guarded App Intents availability

The compatibility fixture compiles shared static libraries, provider runtime and all guarded App Intents declarations with a macOS 11 deployment target for both architectures. It verifies the resulting minimum version and weak App Intents framework load command before running each binary on the current system. Missing/failed providers, all typed policy phases and injected pause telemetry are checked; the native policy intent runs only within a macOS 13 availability branch. No app model, configuration setter, hardware service or Shortcuts indexing update is started by this fixture. Native and universal package verification separately checks the metadata and one weak framework load per architecture. These checks do not establish older-system runtime or native Shortcuts discovery.

## Date and Low Power Mode presentation compatibility

Three core methods check that current-system date formatting matches the original three APIs, and exercise the macOS 11 formatter with full calendar years, abbreviated months, seconds, a Buddhist calendar, time-zone midnight differences and a daylight-saving transition. The injected model fixture checks that an unknown effective Low Power Mode state causes only a status query, leaves policy unchanged and sends no setter. Menu projection checks reject active-mode tint/announcements for unknown state.

The compatibility gate additionally compiles menu presentation against macOS 11 and runs its canonical icon projection, rendering, cache and forced legacy alpha-mask checks on the current system for both architectures. Read-only effective-state observation and optional notification names are version-gated. Pixel checks use the bitmap's encoded components without an extra calibrated-to-sRGB conversion. These checks do not prove macOS 11 runtime or physical power-mode effects.

## Hardware-service availability

`Scripts/test-helper-preflight.sh` builds a macOS 11-target facade fixture for the selected architecture (`OPENCHARGE_TEST_ARCH`). It checks actual local-development preflight, an unavailable backend, existing legacy service, unknown backend status, missing bundle layout, failed signature validation, fake registration/idempotence, removal busy state, failure propagation and explicit settings dispatch. All accepted actions use a fake backend. The injected application-model fixture also verifies that unavailable removal preserves the current opt-in and stored configuration before any cleanup. This does not prove older native service installation, signed/notarized authorization or a real root-daemon lifecycle.

## Login startup compatibility

The isolated macOS 11-target fixture checks read-only inspection, exact fixed arguments (including spaces/XML characters), enable/disable idempotence, owned relocation, malformed/oversized/foreign files, file and directory symlinks, hardlinks and write-permission refusal. Fake native/legacy coordination covers explicit disable, successful migration, unconfirmed native registration retaining an old route and unavailable read/write state. It runs as arm64 and x86_64 on the current system. No actual login registration, launchctl call or application launch is performed. Source availability compilation is part of the shared gate; actual login remains unverified.

## Shared SwiftUI presentation availability

The shared gate compiles the presentation palette and foreground modifiers with a macOS 11 target for arm64 and x86_64. On macOS 12 and later they retain the system mint and hierarchical foreground styles; the older path uses semantic secondary/orange colors and system teal. Numeric labels apply monospaced digits to their existing font sizes. Full native and universal package builds check integration, while the injected dashboard fixture checks model behavior without hardware actions. These checks do not establish old-system rendering, VoiceOver behavior or complete application compatibility; Charts, navigation and other newer UI APIs still require separate work. The supported application deployment floor remains macOS 13.


## Backgrounds and controls on older systems

The presentation module also compiles rounded card/error backgrounds, borders, accent colors, prominent/destructive buttons and Return submission against macOS 11 for both architectures. Current systems retain their existing native background and button APIs. The older path fills/strokes the same rounded shapes, supplies an accent-filled button style with pressed/disabled states, and uses an ordinary native button for destructive actions. Precise-limit validation and its action are unchanged; the older text field uses its Return callback instead of applying on focus or text changes. Full builds and injected model checks do not verify physical keyboard interaction, accessibility announcements, disabled-control rendering or old-system appearance; those remain UI acceptance checks.
