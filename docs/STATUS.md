# Status — 0.3.37 and development source

This is a development release. Implemented policy, OS integration and physical hardware validation are separate milestones.

| Area | Implemented | Remaining validation or scope |
| --- | --- | --- |
| Firmware limits | Fixed CH0B/BCLM backend, exclusive recovery, atomic action/sleep plans, app policy selection and sleep/wake/exit handoff; development source selects seventeen Intel notebook identifiers | Physical Intel validation, special multi-display sleep behavior, broader model matrix and native deployment remain unverified |
| Intel inflow assertion | Fixed process-local ownership, backend/helper/app integration, protected startup, sleep-entry recovery and retryable cleanup | Protocol acceptance and readback do not establish physical discharge or OS/model compatibility |
| Administrator restriction | Scoped charge-setting UI/binding and right-click guards; read-only preference, observation, isolated tests | Managed-profile deployment and broader enterprise/session environments |
| Charge policies | Limits, Sailing, thermal windows, Top Up, discharge, calibration checkpoints | Real cutoff/discharge/calibration and interrupted recovery |
| Ordinary key profiles | Generic profiles plus development platform-specific Apple silicon CH0C/CHTE selection, allowance, inhibition, discharge, retained inhibition and owned recovery | Physical model/OS validation, quit/sleep/boot behavior and additional adapter families |
| Quit lifecycle | Deferred cleanup, stable OS power-source checks after owned discharge, error/timeout choices and monitoring after cancellation | Physical adapter/display transitions, logout/shutdown, user switching and forced process termination |
| Automation | Recurrence and DST anchors, templates, history, CLI, URL scheme, twelve intents | Full policy-state transition and hardware validation; broader system UI execution of setters and calendar/session environments |
| Menu-bar appearance | Four icon styles, observed battery fill, opt-in Low Power Mode tint, configurable right-click and accessible state | Broader native appearance, multi-display and accessibility environments |
| Dashboard / popup | Native status popover, independent components, focus/background snapshots, preview | Multi-display placement, status-item overflow/autohide and broader session restoration remain unverified |
| Telemetry / flow | OS/raw percentage, capacity, temperature, measured power and weighted averages | Cross-model sensor accuracy and physical transitions |
| Energy applications | Optional system metric reader, bounded ranking and CPU display | More OS versions; private API may be unavailable |
| Hardware helper | Fixed authenticated IPC, protocol checks, readback, same-boot charge/LED recovery journals | Real writes, physical charge/LED crash recovery, user switching and reboot behavior |
| Sleep control | Development source adds helper-owned sleep admission and app suspension handling; public idle assertion; required calibration/clamshell protection; optional until-limit system/lid SPI; schema-2 global recovery and same-boot lid cleanup; opt-in foreground lid-lock request | Physical lid/display transitions, private-interface compatibility, powerd interference, actual sleep/boot recovery |
| MagSafe / power modes | Fixed colors, automatic policy, blink/sleep suppression, per-source Low Power Mode | Physical effects, MagSafe generations and real sleep/wake |
| Software updates | Manual / opt-in scheduled checks, preview channel, bounded verified ZIP download with quarantine metadata | Signed automatic installation, notarization and broader network environments |
| Languages | Development source includes native English, Simplified Chinese and Traditional Chinese resources, localized dynamic statuses and App Shortcut phrases, plural rules, and native bundle fallback checks | Additional languages, visual layout and accessibility review, live Shortcuts/Siri localization, CLI help and raw helper diagnostic text remain incomplete or unverified |
| Distribution | Native and universal builds, local signatures, CI definition | Notarized releases and broader model matrix |

Unsupported or incomplete: BCLM-only firmware control, guaranteed forced-clamshell behavior, powered-off charging guarantees, desktop widgets and macOS versions older than 13. Unknown hardware profiles are refused rather than guessed.

The installed development helper was validated only through read-only capabilities. Hardware control and scheduled system actions remain disabled on the validation machine. No physical effects are claimed from capability detection or fake-backend tests.


Unreleased source fixes fresh ordinary-session startup when the selected policy requires system/lid sleep protection. It establishes inhibition before protection and enters the requested action only after protection succeeds; subsequent healthy policy rounds reuse the session. This applies to the updated app with the existing sleep-capable helper protocol. An independently restarted helper can still reject a previously cached app session; that failure requires recovery and re-enabling control. No hardware or sleep effects have been physically verified by this increment.


Development source includes a matching-app/helper multi-display Discharging sleep-entry path. It combines phase/display metadata atomically with discharge, rechecks root lid/adapter state and snapshot age, and separately attempts allowance, selected sleep protection and local user activity. Failure recovery and wake cleanup are implemented. Display topology is a bounded app snapshot; physical multi-display behavior, exact asynchronous ordering and the wider hardware/profile matrix remain unverified. This source increment has not updated the installed helper or existing release packages.


Development ordinary sleep preparation now honors pause-on-sleep directly: opt-out releases only sleep protection; opt-in attempts inhibition before release and preserves pending recovery on failure. It does not infer opt-in from a forced-discharge action. The complete change requires matching updated helper source; the validation machine and existing release packages remain unchanged. Software request ordering does not establish physical sleeping charge behavior.

Shared-module compatibility work: policy/hardware localization retains the existing keys through older Foundation APIs, and IOKit default-port selection uses the system-appropriate SDK name. A dedicated compile gate targets macOS 11 on both architectures. This does not establish full application or daemon operation on macOS 11/12; the packaged app minimum remains macOS 13.
