# Changelog

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
