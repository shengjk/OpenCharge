# Status — 0.3.42 and development source

This is a development release. Implemented policy, OS integration and physical hardware validation are separate milestones.

| Area | Implemented | Remaining validation or scope |
| --- | --- | --- |
| Firmware limits | Separate fixed CH0B+BCLM and BCLM-only backends, distinct journal kinds, atomic action/sleep plans and app sleep/wake/exit handoff; development source selects 17 paired and 50 legacy Intel notebook identifiers | Physical Intel validation, special multi-display sleep behavior, broader model matrix and native deployment remain unverified |
| Intel inflow assertion | Fixed process-local ownership, backend/helper/app integration, protected startup, sleep-entry recovery and retryable cleanup | Protocol acceptance and readback do not establish physical discharge or OS/model compatibility |
| Administrator restriction | Scoped charge-setting UI/binding and right-click guards; read-only preference, observation, isolated tests | Managed-profile deployment and broader enterprise/session environments |
| Setup wizard | First-run/upgrade presentation, four questions, preview, guarded apply and optional duplicate-aware calibration schedules; named tasks/history | Live interaction, actual helper registration and physical charge/calibration effects remain unverified |
| Settings reset | Confirmed, scoped reset of configuration and app-owned UI/update preferences; owned-session cleanup, failure retry and retained observation history | Actual administrator/device recovery and live native interaction remain unverified |
| Charge policies | Limits, Sailing, thermal windows, Top Up, discharge, calibration checkpoints | Real cutoff/discharge/calibration and interrupted recovery |
| Ordinary key profiles | Generic profiles plus development platform-specific Apple silicon CH0C/CHTE selection, allowance, inhibition, discharge, retained inhibition and owned recovery | Physical model/OS validation, quit/sleep/boot behavior and additional adapter families |
| Quit lifecycle | Deferred cleanup, stable OS power-source checks after owned discharge, error/timeout choices and monitoring after cancellation | Physical adapter/display transitions, logout/shutdown, user switching and forced process termination |
| Automation | Recurrence and DST anchors, templates, history, CLI, URL scheme, twelve intents | Full policy-state transition and hardware validation; broader system UI execution of setters and calendar/session environments |
| Menu-bar appearance | Four icon styles, observed battery fill, opt-in Low Power Mode tint, configurable right-click and accessible state | Broader native appearance, multi-display and accessibility environments |
| Dashboard / popup | Native status popover, independent components, focus/background snapshots, preview | Multi-display placement, status-item overflow/autohide and broader session restoration remain unverified |
| Telemetry / flow | OS/raw percentage, capacity, temperature, measured power and weighted averages | Cross-model sensor accuracy and physical transitions |
| Energy applications | Optional system metric reader, bounded ranking and CPU display | More OS versions; private API may be unavailable |
| Helper registration | SMAppService on macOS 13+; signed Authorization Services/SMJobBless and owned job unregistration in macOS 11/12 source; serialized operations | Actual administrator interaction, legacy runtime, complete file removal, migration and production signing/notarization |
| Hardware helper | Fixed authenticated IPC, protocol checks, readback, same-boot charge/LED recovery journals | Real writes, physical charge/LED crash recovery, user switching and reboot behavior |
| Sleep control | Helper-owned sleep admission and app suspension handling; public idle assertion; required calibration/clamshell protection; optional until-limit system/lid SPI; schema-2 global recovery and same-boot lid cleanup; opt-in foreground lid-lock request | Physical lid/display transitions, private-interface compatibility, powerd interference, actual sleep/boot recovery |
| MagSafe / power modes | Fixed colors, automatic policy, blink/sleep suppression, per-source Low Power Mode | Physical effects, MagSafe generations and real sleep/wake |
| Software updates | Manual / opt-in scheduled checks, preview channel, bounded verified ZIP download with quarantine metadata | Signed automatic installation, notarization and broader network environments |
| Languages | Packages include native English and Simplified Chinese resources, localized dynamic statuses and App Shortcut phrases, plural rules, and native bundle fallback checks | Visual layout and accessibility review, live Shortcuts/Siri localization, CLI help and raw helper diagnostic text remain incomplete or unverified |
| Distribution | Native and universal builds, local signatures, CI definition | Notarized releases and broader model matrix |

Unsupported or incomplete: guaranteed forced-clamshell behavior, powered-off charging guarantees, desktop widgets and macOS versions older than 13. Unknown hardware profiles are refused rather than guessed.

The installed development helper was validated only through read-only capabilities. Hardware control and scheduled system actions remain disabled on the validation machine. No physical effects are claimed from capability detection or fake-backend tests.


Version 0.3.38 fixes fresh ordinary-session startup when the selected policy requires system/lid sleep protection. It establishes inhibition before protection and enters the requested action only after protection succeeds; subsequent healthy policy rounds reuse the session. This applies to the updated app with the existing sleep-capable helper protocol. An independently restarted helper can still reject a previously cached app session; that failure requires recovery and re-enabling control. No hardware or sleep effects have been physically verified by this increment.


Version 0.3.38 includes a matching-app/helper multi-display Discharging sleep-entry path. It combines phase/display metadata atomically with discharge, rechecks root lid/adapter state and snapshot age, and separately attempts allowance, selected sleep protection and local user activity. Failure recovery and wake cleanup are implemented. Display topology is a bounded app snapshot; physical multi-display behavior, exact asynchronous ordering and the wider hardware/profile matrix remain unverified. The matching helper is included in the 0.3.38 packages; the installed validation helper has not been updated.


Version 0.3.38 ordinary sleep preparation honors pause-on-sleep directly: opt-out releases only sleep protection; opt-in attempts inhibition before release and preserves pending recovery on failure. It does not infer opt-in from a forced-discharge action. The complete change requires matching updated helper source; the validation machine’s installed helper remains unchanged. Software request ordering does not establish physical sleeping charge behavior.

Shared-module compatibility work: application/policy/hardware lookup calls retain the existing keys through older Foundation APIs, and IOKit default-port selection uses the system-appropriate SDK name. A dedicated compile gate targets macOS 11 on both architectures, including the streaming update transport, menu presentation and guarded automation declarations. A linked provider fixture checks weak App Intents loading and runs injected read-only providers on the current system. This does not establish full application or daemon operation on macOS 11/12; the packaged app minimum remains macOS 13.

Date display and effective Low Power Mode observation now use version-gated APIs with explicit legacy formatting and unknown-state handling. The menu icon has a legacy alpha-mask tint path. These changes retain the packaged macOS 13 requirement; complete macOS 11-target compilation and presentation fallbacks do not establish older-system runtime or native privileged installation.

Hardware-service inspection now separates its application status/preflight from the macOS 13 SMAppService backend. The macOS 11/12 source backend implements signed, authorized installation and job unregistration. Installed-file deletion, migration and actual old-system runtime acceptance remain unfinished; the packaged minimum stays macOS 13.

Login-startup development source now separates the macOS 13 native backend from an owned per-user LaunchAgent fallback for earlier systems, with fake-backend and temporary-directory tests. Actual logout/login, launchd overrides, native registration and old-system runtime have not been exercised. See [login startup](LOGIN-STARTUP.md).

Version 0.3.38 includes read-only installed-service classification, portable runtime preparation and an embedded older-helper metadata candidate. These are not a pre-13 authorization or removal backend. The development package remains ad-hoc signed and unnotarized; no administrator installation was exercised. Its fallback history view supplies native reading nodes and macOS 12 chart descriptors, but hosted assistive-technology reachability and actual audio playback remain unverified. Interface resources are intentionally limited to Simplified Chinese and English.


Version 0.3.42 implements the macOS 11/12 native registration backend with Authorization Services and SMJobBless, plus SMJobRemove for explicit job unregistration. Matching Apple-issued app/helper signatures, reciprocal ownership metadata and known installed-file ownership are required. Blocking authorization/removal run outside the main thread and overlapping operations are refused. Unregistration stops the job but retains installed files; complete native file removal and migration to SMAppService remain unfinished. The current ad-hoc packages cannot use this route. Physical macOS 11/12 execution, administrator interaction and a production signing/notarization pipeline remain unverified; the packaged minimum remains macOS 13.
