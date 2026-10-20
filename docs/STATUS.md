# Status — 0.3.16

This is a development release. Implemented policy, OS integration and physical hardware validation are separate milestones.

| Area | Implemented | Remaining validation or scope |
| --- | --- | --- |
| Charge policies | Limits, Sailing, thermal windows, Top Up, discharge, calibration checkpoints | Real cutoff/discharge/calibration and interrupted recovery |
| Quit lifecycle | Deferred cleanup, stable OS power-source checks after owned discharge, error/timeout choices and monitoring after cancellation | Physical adapter/display transitions, logout/shutdown, user switching and forced process termination |
| Automation | Recurrence and DST anchors, templates, history, CLI, URL scheme, eleven intents | System UI execution of setters; more calendar/session environments |
| Menu-bar appearance | Four icon styles, observed battery fill, opt-in Low Power Mode tint and accessible state | Broader native appearance, multi-display and accessibility environments |
| Dashboard / popup | Native status popover, independent components, focus/background snapshots, preview | Multi-display placement, status-item overflow/autohide and broader session restoration remain unverified |
| Telemetry / flow | OS/raw percentage, capacity, temperature, measured power and weighted averages | Cross-model sensor accuracy and physical transitions |
| Energy applications | Optional system metric reader, bounded ranking and CPU display | More OS versions; private API may be unavailable |
| Hardware helper | Fixed authenticated IPC, protocol checks, readback, same-boot charge/LED recovery journals | Real writes, physical charge/LED crash recovery, user switching and reboot behavior |
| Sleep control | Public idle assertion; required calibration/clamshell protection; optional until-limit system/lid SPI; schema-2 global recovery and same-boot lid cleanup; opt-in foreground lid-lock request | Physical lid/display transitions, private-interface compatibility, powerd interference, actual sleep/boot recovery |
| MagSafe / power modes | Fixed colors, automatic policy, blink/sleep suppression, per-source Low Power Mode | Physical effects, MagSafe generations and real sleep/wake |
| Software updates | Manual / opt-in scheduled checks, preview channel, bounded verified ZIP download with quarantine metadata | Signed automatic installation, notarization and broader network environments |
| Distribution | Native and universal builds, local signatures, CI definition | Notarized releases and broader model matrix |

Unsupported or incomplete: BCLM-only firmware control, guaranteed forced-clamshell behavior, powered-off charging guarantees, desktop widgets and macOS versions older than 13. Unknown hardware profiles are refused rather than guessed.

The installed development helper was validated only through read-only capabilities. Hardware control and scheduled system actions remain disabled on the validation machine. No physical effects are claimed from capability detection or fake-backend tests.
