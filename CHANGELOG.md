# Changelog

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
