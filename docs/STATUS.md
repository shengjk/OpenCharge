# Status — 0.3.7

This is a development release. Implemented policy, OS integration and physical hardware validation are separate milestones.

| Area | Implemented | Remaining validation or scope |
| --- | --- | --- |
| Charge policies | Limits, Sailing, thermal windows, Top Up, discharge, calibration checkpoints | Real cutoff/discharge/calibration and interrupted recovery |
| Automation | Recurrence and DST anchors, templates, history, CLI, URL scheme, eleven intents | System UI execution of setters; more calendar/session environments |
| Dashboard / popup | Native status popover, independent components, focus/background snapshots, preview | Multi-display placement, status-item overflow/autohide and broader session restoration remain unverified |
| Telemetry / flow | OS/raw percentage, capacity, temperature, measured power and weighted averages | Cross-model sensor accuracy and physical transitions |
| Energy applications | Optional system metric reader, bounded ranking and CPU display | More OS versions; private API may be unavailable |
| Hardware helper | Fixed authenticated IPC, protocol checks, readback, same-boot charge recovery journal | Real writes, physical crash recovery, LED crash recovery, user switching and reboot behavior |
| MagSafe / power modes | Fixed colors, automatic policy, blink/sleep suppression, per-source Low Power Mode | Physical effects, MagSafe generations and real sleep/wake |
| Distribution | Native and universal builds, local signatures, CI definition | Notarized releases, updater and broader model matrix |

Unsupported or incomplete: BCLM-only firmware control, forced clamshell wake, powered-off charging guarantees, desktop widgets and macOS versions older than 13. Unknown hardware profiles are refused rather than guessed.

The installed development helper was validated only through read-only capabilities. Hardware control and scheduled system actions remain disabled on the validation machine. No physical effects are claimed from capability detection or fake-backend tests.
