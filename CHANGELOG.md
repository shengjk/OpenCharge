# Changelog

## Unreleased

- Bind each updated app policy round to a helper-instance and sleep-event context. Reject stale charge/protection requests across sleep/wake, preserve opt-in and recovery responsibility for confirmed unexecuted requests, and reacquire protection on a fresh round.
- Disable the dedicated popover manual-discharge button while automatic discharge is enabled, including its Stop presentation. Check the current setting before accepting a captured click.

## 0.3.37

- Add experimental numeric firmware control for three selected Intel Air profiles, with typed capability checks and explicit refusal when the required helper protocol is unavailable.
- Integrate app policy, atomic action/sleep plans, session ownership, sleep/wake handoff and daily-limit exit handling. Refuse ambiguous or expired ownership until cleanup succeeds and control is explicitly enabled again.
- Add exclusive charge-backend recovery and owned process-local inflow assertions. Preserve pending recovery after ambiguous acknowledgements or failed cleanup; release owned assertions before changing backend or relinquishing control.
- Explain numeric firmware behavior in the charge-control page and disable ordinary sleep/quit switches that do not apply to that channel.
- Expand isolated policy, helper, journal, crash and application lifecycle coverage. No physical Intel charging, discharge or sleep effects are claimed; special multi-display behavior and broader hardware coverage remain unverified.

## 0.3.36

- Read the administrator settingsLock preference, off by default. Restrict interactive charge-policy editors, quick profiles, backup restore and the right-click charging toggle, with a visible lock notice.
- Re-check the current restriction before each protected edit, including bindings and input drafts created before locking. Observe preference changes and retain periodic refresh.
- Keep mode actions, Top Up, Low Power Mode, appearance, background tasks, automation and recovery on their existing paths. MagSafe controls remain separate.
- Add isolated binding, preference-observation and persistence regressions. The user confirmed default menu-bar right-click opening/closing on the current Mac.

## 0.3.35

- Route the charge-control mode picker through the shared explicit GUI mode request. Clear current-percentage Pause state, save accepted changes immediately, and enforce the existing connection and calibration guards.
- Apply accepted mode changes to the policy engine before reading telemetry, so cancellation cannot resume an old calibration stage after a temporary read failure.
- Let quick profiles cancel interrupted calibration through the same Automatic-mode request and clear stale checkpoints.
- Add production-binding regressions for the Pause round trip, unplugged requests, interrupted calibration, failed telemetry and profile cleanup.

## 0.3.34

- Configure menu-bar right-click to toggle the popover, open Settings, toggle charging, or toggle Low Power Mode. Left click and Command-3 always toggle the popover.
- Toggle charging between conditional current-percentage Pause and ordinary charging with a 100% daily target. Preserve selected telemetry and interrupted calibration, and clear runtime Sailing holds when starting full-target charging.
- Require the system-actions opt-in and available service support before the Low Power Mode shortcut; invert actual system activity instead of a saved preference.
- Add isolated routing, preference, policy and IPC checks. Global settings locking and physical hardware effects remain incomplete or unverified.

## 0.3.33

- Apply scheduled Pause at the current selected control percentage only in eligible policy phases. Retain the original policy when the phase or reading is unsuitable, and record the skip while consuming the scheduled occurrence.
- Project current and same-batch policy states on an engine copy; preserve an interrupted calibration until explicit continuation or cancellation.
- End an active calibration immediately when a scheduled Pause is accepted, including when a later task starts a new calibration in the same refresh. Keep Sailing history and record intermediate daily-limit changes.
- Distinguish accepted strategy updates from confirmed hardware effects in execution history; explicit schedule mode requests clear the current-limit Pause flag.

## 0.3.32

- Let the Top Up and Discharge buttons stop their active operation and enter persistent Pause without changing the daily charge limit. Show the corresponding Stop label while the operation is active.
- Use the current policy phase for this toggle, including automatic discharge; a thermal wait does not become a Stop selection solely because Top Up remains configured.
- Preserve explicit mode requests from CLI, URLs and Shortcuts. Add isolated production-model checks for repeated clicks, full charge, persistence, thermal state and unplugged Top Up.

## 0.3.31

- Stop compositor animation when the power-flow host shrinks to zero size, and restart correctly when usable geometry returns.
- Includes the power-flow performance optimization from the source-only 0.3.30 tag.

## 0.3.30

- Move power-flow arrows with system layer animation while keeping telemetry labels and power-width paths outside frame updates. Preserve the two-second cycle and charging/discharging directions in the dashboard and compact popover.
- Keep Reduce Motion, focus pause, hide/detach cleanup and resize behavior; live telemetry does not restart unchanged animation geometry.
- Add private layer lifecycle checks and native visible-animation performance validation.

## 0.3.29

- Persist the daily Sailing checkpoint and restore charging versus holding history across app restarts; preserve older configurations without the new field.
- Record whole-percentage restart boundaries separately from the fractional runtime Sailing boundary, with the Top Up exception and minimum-target ordering.
- Reset target history when the daily limit changes through the GUI, CLI or Shortcuts. Carry it through calibration reconstruction, and clear it on portable backup restore.
- Share production policy evaluation with isolated telemetry fixtures; stable samples and read-only CLI explanations do not rewrite settings.

## 0.3.28

- Separate Top Up from the ordinary charging temperature pause in fresh configurations; add an independent optional Top Up thermal guard. Older saved policies retain their previous temperature behavior until explicitly changed.
- Preserve thermal-exit Pause at full charge when protection is disabled, including subsequent updates and later recharge.
- Cover legacy/new preference round trips, backup restore, mode isolation and production protection ordering with injected actuators.

## 0.3.27

- Evaluate an established ordinary five-minute thermal wait before Sailing and integer target projection; compare its target at control precision.
- Preserve confirmed thermal state and selected protection when temperature is temporarily unavailable. Resume charging when the cooling window completes; renewed heat can start a fresh wait immediately.
- Move a completed thermal wait to target pause, including at 100%, and exit disabled thermal protection through a pause transition. Clear thermal state on explicit mode changes.

## 0.3.26

- Prevent a pause from degree hysteresis from being reused as an existing five-minute window when switching behavior at low charge.
- Includes the low-charge window correction from withdrawn development build 0.3.25.

## 0.3.25 (withdrawn)

- Preserve an existing five-minute thermal pause below its 20% entry threshold until the battery falls below 15% or the cooling window completes.
- Keep fresh low-charge readings, explicit mode changes, calibration and optional degree hysteresis independent of that continuation rule.

## 0.3.24

- Add a read-only live application-state action alongside the existing power-flow getter.
- Carry typed policy phases through ordinary charging, Sailing, pauses, thermal protection, Top Up and calibration. Preserve legacy decision decoding.
- Reject unavailable runtime state instead of guessing from configuration or presentation text.

## 0.3.23

- Correct fixed MagSafe green to ACLC 2 and use the native orange-blink pattern 6; retain legacy value 3 for readback and recovery.
- Expose orange blinking in settings and the LED shortcut. Require the exact native-encoding capability before green/blink setters, so older services receive only read-only inspection.
- Preserve captured-state recovery for native patterns and legacy journals; suppress native blink during sleep and restore the selected pattern on wake.
- Make the dedicated Pause Charging shortcut set the current selected control percentage as its limit, reject invalid/below-20% readings, cancel temporary targets, and resume ordinary policy after the percentage falls. Explicit manual pause remains indefinite.
- Add fixed-value, native-pattern, same-boot recovery, pause and injected service-compatibility checks.

## 0.3.22

- Keep ordinary 100% targets and Top Up available for system-managed top-off instead of forcing charge inhibition at full. Top Up remains active until unplugged or explicitly changed.
- Add a separate full-charge decision flag, a full/managed-top-off menu-bar state, and active-policy green MagSafe indication without changing observed telemetry.
- Release selected until-target sleep protection at full, including single-precision boundary values; preserve calibration requirements and existing temperature pauses.
- Refresh the menu-bar presentation when its decision or control configuration changes, retaining the render cache.
- Add policy, compatibility, indicator and injected production-model full-charge regressions.

## 0.3.21

- Compare ordinary daily charge/discharge targets in whole percentage bins using single-precision input values, including fractional hardware readings and fractional configured limits.
- Preserve fractional Sailing lower boundaries and the independent reserve/calibration behavior.
- Add boundary regressions and injected production-model completion checks that release selected sleep protection after stopping discharge at 80.6% for an 80% target.

## 0.3.20

- Resolve ordinary manual/automatic discharge and target completion before the charging-temperature gate, including unavailable temperature readings. Keep required lid protection and the optional calibration-temperature enhancement.
- End manual discharge on confirmed unplugging, while preserving an acknowledged input-cut fallback.
- Clear stale charging-temperature windows when entering discharge, and stop completed daily limits below 100% before classifying a thermal wait.
- When the discharge reserve is above a lower target, hold charging off instead of requesting charge pulses at the reserve; preserve manual completion even when temperature prevents recharge.
- Add policy and injected production-model regressions for temperature/discharge priority, reserve conflicts, completion and calibration isolation.

## 0.3.19

- Restore user-selected idle behavior during ordinary discharge: open-lid discharge no longer forces the idle assertion introduced in 0.3.18. Required closed-lid and calibration protection is retained.
- Keep selected until-target sleep protection during confirmed thermal waits, using a typed decision flag; release it for Sailing holds and manual pauses.
- Preserve Top Up and departure targets while temperature protection pauses charging. Apply the inclusive 20% heat-protection exemption and 20% Sailing floor.
- Add policy, legacy-decision and injected production-model regressions for thermal wait, cooling, target completion and optional idle behavior.

## 0.3.18

- Remove the separate clamshell-discharge gate. Manual and automatic discharge now select required protection from lid state while preserving the hardware-control opt-in.
- Require idle protection during active discharge, full protection with a closed or unreadable lid, and acknowledge required protection before power commands. Keep explicit unplugging authoritative over an owned input cut.
- Refresh enabled control immediately on lid edges and release full protection on reopening when the optional until-limit setting is off. Keep idle protection until discharge completes.
- Make the display-sleep preference available independently of the optional until-limit setting. Add legacy-configuration, policy-transition and injected production-model regressions. Physical lid/discharge behavior remains unverified.

## 0.3.17

- Require an acknowledged system/lid sleep override before sending charge or discharge commands for a protected session. Capability detection alone no longer permits the charge action.
- If protection fails, disable control and attempt restoration before any new charge action; preserve cleanup after a later charge-command failure.
- Add injected production-model regression coverage for both charge and discharge ordering. No physical power operation was performed.

## 0.3.16

- Reset the live calibration engine, displayed phase and interrupted flag when an external start request clears its checkpoint.
- Preserve interruption for ordinary checkpoint-bearing updates and keep the running hardware-control opt-in, including correcting a stale saved flag.
- Retain the last valid configuration on reload errors. Added actual-Intent/production-callback regression checks in an isolated configuration.

## 0.3.15

- Make calibration sleep protection independent of the optional until-limit setting and allow closed-lid calibration draining/returning.
- Preflight required sleep support and stop/restore on failed protection. Add default-off foreground lid-lock requests with one attempt per closure.
- Use schema-2 sleep journals and migrate legacy uncertain operations before compensation; older schema-1-only helpers refuse the new format.

## 0.3.14

- Journal setting, active and restoring phases so a failed persistent setter cannot clear recovery solely from cached false readback.
- Require exact sleep-interface and recovery-protocol capability fields. Added stale-cache, legacy-record and save-barrier fixtures.

## 0.3.13

- Added opt-in system/lid sleep control through fixed helper commands and dynamically resolved power-management interfaces; disabled by default.
- Added a separate persistent sleep-recovery record: global state is recovered across boots, while a prior boot’s lid flag is never replayed. Display assertions remain process-owned.
- Added helper heartbeat, console-user, sleep-entry and exit cleanup; preserve an already-disabled global sleep setting and report partial restoration failures.
- Use physical adapter presence during owned discharge, keep idle sleep inhibited during active calibration, and separate display-sleep preferences from system/lid control.
- Added fake/file recovery fixtures and abrupt subprocess boundaries. Physical lid/display/sleep behavior remains unverified; the installed helper was not updated.

## 0.3.12

- Added deferred native quit handling: finish session cleanup and, after owned active discharge, wait for stable OS power-source recovery before exiting.
- Suspend policy refreshes and new in-app hardware actions during quit preparation; preserve the selected restore / retain-charge-inhibition policy.
- Report cleanup errors and power-state timeouts with retry, cancel and explicit exit choices. Cancellation disables charge control and keeps the app open; interrupted calibration requires explicit continuation.
- Added pure exit-policy tests, injected production-model checks and a native fake-only AppKit termination harness. Real discharge exit, display transitions and logout remain unverified.

## 0.3.11

- Added an application-menu update window and settings card, manual checks and opt-in checks every 12 hours.
- Select the highest compatible published SemVer release, with optional development previews and architecture-specific packages.
- Download ZIPs only on request; enforce HTTPS host, size and pagination limits, verify published SHA-256 / available API digest, and preserve macOS quarantine metadata.
- Keep application and privileged-service replacement manual; automatic checking defaults off and sends no battery readings or device identifiers.
- Added deterministic release-selection and download-validation fixtures plus an optional anonymous public-network smoke test.

## 0.3.10

- Prevented status-item image reassignment when the observed label and semantic appearance are unchanged.
- Ignored appearance notifications whose old/new appearance names match; updated tooltips independently from icon rendering.
- Added a regression fixture for 1000 repeated callbacks while preserving updates for real appearance, display, telemetry and power-state changes.
- Supersedes the withdrawn 0.3.9 preview, whose native validation exposed sustained status-item redraws. Its release remains a draft.

## 0.3.9

- Added dynamic-status, monochrome battery, colored battery and OpenCharge menu-bar icon styles.
- Battery icons use a continuous fill from observed OS charge; charging, plugged discharge, connected idle and unknown data remain distinct.
- Added opt-in yellow icon tint for the system's actual Low Power Mode, updated through read-only power-state notifications.
- Icon-only display now hides text without changing the selected icon style. Numeric-only modes stay icon-free.
- Added production projection/rendering checks and light/dark contact-sheet verification; retained existing display/default preferences.

## 0.3.8

- Added a separate same-boot MagSafe recovery journal, sharing the helper's private directory and lifetime lock with charge recovery.
- Recover captured LED values before new LED actions; preserve external changes and keep failed restoration retryable.
- Reuse a durable record when it already covers both blink states, avoiding a disk sync on every blink.
- Added abrupt-subprocess LED recovery and shared-store isolation fixtures. Physical LED/crash recovery remains unverified; the installed helper is unchanged.

## 0.3.7

- Added a bounded, boot-scoped write-ahead journal for helper charge writes, with startup compare-and-restore before accepting new charge actions.
- Added private file ownership/permission checks, descriptor-relative operations, exclusive directory locking and synchronized atomic replacement.
- Added terminated-subprocess recovery fixtures using fake registers. The installed helper is unchanged; physical crash recovery remains unverified.

## 0.3.6

- Added a direct native popup editor entry in settings and Command-4.
- Kept editing sessions separate for preview and real popup, and reset them on close without resetting the saved layout.
- Added a persisted popup animation preference; system Reduce Motion always takes precedence.

## 0.3.5

- Added an explicitly owned native status item/popover and Command-3 to activate the real status button.
- Kept preview and status popover consumers independent, so closing one cannot disable another active consumer.
- Added a standard settings window, visible energy-read activity and shared appearance preferences.
- Preserved four menu display modes with deterministic label checks and kept the app running after its windows close.
- Verified real anchored popup open/toggle/Escape closure and energy pause; the user manually confirmed real-popup sorting on the current Mac.

## 0.3.4

- Fixed popup reordering with native drag handles and full-row destinations while preserving accessible arrow controls.
- Limited accepted drags to visible components in the same preferences instance; invalid drops leave order unchanged.
- Verified long press and bidirectional row drops in the popup preview; native status-item lifecycle remains separate.
- Renamed the edit footer to Done Editing to describe immediate persistence accurately.

## 0.3.3

- Unified read-only temperature selection across the app, CLI and native automation, with a fixed SMC battery sensor and identified registry fallback.
- Preserved alternate temperatures, separated raw/nominal capacity and macOS health/maintenance fields, and recorded source metadata in new history/CSV entries.
- Added twenty-six deterministic telemetry checks and legacy history compatibility checks; no physical hardware effects are claimed.

## 0.3.2

- Organized application lifecycle, model, navigation, shared components and individual views into separate files.
- Added English/Chinese entry documentation, architecture, usage/status guides, contribution/security policies and GitHub collaboration templates.
- Removed product-specific comparison material, local investigation notes and brand-specific detection/messages.
- Added a single deterministic verification entry point and preserved stable runtime behavior and third-party notices.
- Removed local source paths from packaged executable debug maps before signing.

## 0.3.1

- Added configurable popover components, inline editing, accessible reordering and preview.
- Coordinated energy queries across independent dashboard and popover consumers.

## 0.3.0

- Added dashboard layout/specification preferences and independent focus/background display snapshots.

## 0.2.x

- Added policies, recurring schedules, calibration checkpoints, configuration backup and diagnostics.
- Added fixed hardware plans, ownership/readback recovery, optional LED and power-mode control.
- Added App Intents, measured power flow, energy attribution and universal packaging.
