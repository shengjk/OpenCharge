# Hardware support and evidence — 0.2.5

## Protocol sources

- [beltex/SMCKit](https://github.com/beltex/SMCKit/blob/master/SMCKit/SMC.swift), MIT: 80-byte AppleSMC ABI, driver selector 2, commands 9/5/6, missing-key result 132. OpenCharge uses initialized byte buffers rather than Swift nested-struct layout.
- [actuallymentor/battery](https://github.com/actuallymentor/battery/blob/main/battery.sh), MIT: modern CHTE four-byte 01000000/00000000; legacy CH0B+CH0C one-byte 02/00; adapter inhibition CHIE 08/00, CH0J or CH0I 01/00. We independently implement these fixed operations, without its sudoers/updater policy.
- [zackelia/bclm](https://github.com/zackelia/bclm), MIT: BCLM/CHWA numeric firmware limits differ from active charge inhibition. Its current README reports macOS 15+ entitlement restrictions. BCLM-only Intel firmware support remains incomplete; no arbitrary fallback or security bypass is implemented.
- SDK IOPowerSources/IOKit headers: real battery and power-source telemetry. Temperature in the AppleSmartBattery IORegistry is centi-Celsius, as corroborated by [beltex/SystemKit](https://github.com/beltex/SystemKit) and [exelban/stats](https://github.com/exelban/stats); it is not raw Smart Battery tenths-Kelvin.

License notices remain in docs/licenses. Only application source and required notices belong in source distributions.

## Eligibility and protocol validation

0.2.5 removes the two-model allowlist. Model names are diagnostic information, not proof of a firmware protocol. A real internal battery and recognized SMC byte format/state are required. No internal battery means no charging actions. This admits other Intel/Apple Silicon notebooks only when they expose a recognized profile; it does not claim that all notebooks work.

CHTE takes precedence. If it exists with an unexpected format or read error, control fails without falling back to legacy writes. Without CHTE, BOTH CH0B and CH0C must be present and recognized. Force discharge separately requires a recognized adapter key, preferring CHIE, then CH0J, then CH0I. Missing adapter control does not prevent normal charging actions, but forced discharge is refused. Unknown adapter state refuses the profile.

The complete operation plan and its original-state snapshot are validated before any write. Root authorization remains required. Every mutation has readback. No caller can pass raw keys, arbitrary values, selectors or shell commands through the daemon IPC. The transport and fixed-key planner are separated so tests exercise the same planner used by production.

The charge journal tracks only values actually changed by this instance. A helper-provided file store persists the fixed charge entries before each hardware mutation; ordinary read-only clients have no store. Original values survive multiple requests. Restore is a no-op before a write and preserves externally changed current values. Failed rollback entries remain retryable. Firmware operations are not atomic; identical values cannot identify their writer, and compare-and-restore has a race window. Same-boot helper restart attempts compare-and-restore using its validated record before new charge commands. Real hardware crash recovery, reboot behavior and entitlement restrictions remain unverified.

MagSafe is independent of charge eligibility. ACLC byte format and captured-state restoration are documented in MAGSAFE.md. Detection of a key never proves a connected adapter or physical LED effect.

## Read-only host evidence

2026-10-16T01:35Z: MacBookPro17,1, macOS 26.3. Outside the execution sandbox, the non-root diagnostic reported internal battery present, CHTE charge control, CHIE forced discharge, recognized format, physical effects unverified, and writes requiring privileged helper. No ACLC capability was reported. Inside the sandbox, earlier IOServiceOpen returned -536870174.

At the same read-only snapshot: OS 80%, raw 76.72%, 30.63°C, 11971 mV, 0 mA, 130 cycles, full/design capacity 4432/5103 mAh (86.85% ratio), adapter negotiated 55 W, measured input/system load 24.062 W. These readings are transient telemetry, not a charge-cycle or battery health diagnosis. Serial identifiers are excluded.

## Verification and remaining scope

Scripts/test-smc.sh injects byte transport into the production planner. 24 scenarios cover modern/legacy charge profiles and all three adapter keys, priority, no-op ownership, malformed/missing data, no battery, denied authorization, read errors, complete-plan preflight, snapshot races, readback mismatch, partial failure/rollback, restoration retry and external interference. No fixture accesses AppleSMC. Read-only production probing still identifies this host's original CHTE/CHIE profile after refactoring.

Universal cross-compilation and runtime verification are recorded in TESTING.md. A successfully built Intel binary is not proof of Intel hardware behavior. Actual charge cutoff, adapter inhibition, root entitlement availability, sleep/quit recovery, firmware-only Intel limits, model matrix and multiuser tests remain required for hardware support validation. The user later installed the 0.2.6 privileged helper with explicit read-only scope; authenticated connection was verified. No SMC write was performed.

0.2.5 universal binaries contain both arm64/x86_64 and pass strict signatures. On the existing Rosetta runtime, x86_64 telemetry and SMC read-only probing succeeded and all 24 fake protocol scenarios passed. This is cross-architecture execution evidence on the same M1 hardware; Intel firmware remains unverified.

## Same-boot charge recovery — 0.3.7

The helper uses `/var/db/org.opencharge.charged/charge-recovery.json` in a root-owned 0700 directory, with a 0600 regular file and an exclusive directory lock. File operations are descriptor-relative, refuse symbolic/hard links or unexpected ownership/permissions, and bound input to 8192 bytes. Records permit only the six fixed charge/adapter keys and their recognized values; no IPC request can provide paths or recovery bytes. Write-ahead snapshots are fsynced before firmware writes; completed restore entries are removed through fsynced atomic replacement. A failed disk save prevents the next hardware write. Cleanup failures retain entries for retry.

The record includes the kernel boot-session UUID. Same-boot entries block new charge actions until restored; a different boot discards the record without writing hardware. Startup recovery releases even a previous retain-on-quit session: retain is not a promise to survive a helper crash. A malformed record blocks charge control and is preserved for diagnosis. External current values outside the owned expected/previous states are left unchanged. Atomic file replacement does not make firmware compare-and-restore atomic, identify identical external writes, or guarantee power-loss durability.

The production planner and file store are tested with disposable fake registers, including terminated subprocesses at write/restore boundaries. These tests never restart the production daemon, create its root recovery directory or perform physical SMC writes. Since 0.3.8, LED recovery uses a separate bounded record in the shared private directory; persistent macOS Low Power Mode settings are deliberately excluded.

Recovery-directory safety/locking or boot-identity failures refuse daemon startup before its socket is changed. The directory lock stays held for the entire daemon lifetime, including when SMC is unavailable but power-mode service remains available.


## Experimental numeric firmware backend — 0.3.37

An injected controller implements only the fixed CH0B/BCLM profile for a caller-established eligible host with an internal battery. It requires one-byte `ui8 ` metadata, accepts recognized current values, and exposes bounded limits from 20 through 100 plus a separate internal inhibit target of 15. Read-only status uses CH0B and BCLM, consulting BSIn bit 0 only when CH0B is zero and BCLM is 15; unavailable BSIn leaves that control state unknown. It does not substitute OS charging or measured power flow.

Transactions save owned original/expected/previous values before writes and validate readback and the final full profile. Crash recovery compares owned values before restoring originals. Orderly exit applies a separate explicit target and relinquishes ownership only after validation and successful journal removal; subsequent restore must preserve that target. Malformed recovery data and incomplete rollback block further mutation. The recovery schema is distinct from the ordinary charge journal and uses the fixed `firmware-recovery.json` view in the same locked root directory. Compare-and-restore remains subject to external-writer races and cannot identify an identical external value.

The 0.3.37 helper and app connect these mutations through fixed requests and exclusive backend ownership. Process-crash fixtures establish recovery behavior for injected registers and local file operations only; real sleep, shutdown, charging effects, reboot and power-loss behavior remain unverified.


The production SMC client now shares metadata/payload decoding with raw 80-byte frame fixtures. Its read-only numeric probe selects MacBookAir8,1, MacBookAir8,2, MacBookAir9,1, MacBookPro15,1–15,4 and MacBookPro16,1–16,4 in an x86_64 process with an internal battery, then validates CH0B/BCLM metadata and recognized values. These eleven identifiers select the fixed numeric protocol; other model families are not inferred from a similar name or readable key. This is not a physically validated hardware matrix. Model identity alone does not establish physical effects. Rosetta on an Apple Silicon model does not select this profile. `chargectl diagnose-smc` reports numeric read availability, limit and firmware charging-control state separately from ordinary charge capabilities. Direct diagnostic clients have no firmware recovery store and cannot use numeric write methods.

The development app and helper share this model selection. These Intel models require the numeric service protocol; an older service that only advertises ordinary control is refused rather than silently using ordinary charge commands. Source-only updates do not replace an installed service or enable hardware control.

A fixed numeric byte-write primitive rechecks metadata immediately before command 6. The 0.3.37 helper advertises `firmwareProtocol:fixedV1`, `chargeRecovery:ready` or `pending`, and `firmwareWrite:fixedV1` only for a readable selected profile with a recovery store. On the current MacBookPro17,1, the new native read-only diagnostic preserves recognized CHTE/CHIE observation and reports numeric read/write unavailable. This is a refusal check on Apple Silicon, not an Intel firmware validation.


## Experimental helper ownership and fixed numeric protocol — 0.3.37

The fixed inflow extension is advertised separately as `firmwareDischarge:inflowV1` for a readable selected numeric profile with a recovery store. It requests journaled CH0B/BCLM inhibition before acquiring the process-local `DisableInflow` assertion. The assertion is released before limits, inhibition, orderly exit, restoration or an ordinary backend switch. Failed release preserves ownership and prevents subsequent writes; failed acquisition attempts restoration. No caller can supply an assertion type or identifier. The helper requires an existing numeric session and a system sleep observer before accepting discharge, and refuses removal of a registered sleep target during discharge. Pending recovery is retried at sleep entry; failed sleep policy application also attempts cleanup immediately. Lease, console and shutdown cleanup use the same owned backend. The advertisement describes the implemented request protocol, not observed power flow or physical support.

App control additionally requires `firmwarePlan:atomicSleepV1`. Each `firmwarePlan:allow|inhibit|discharge:<target>` request accepts only 15 or 20...100 and publishes the action and sleep target together on the root observer's serial queue. Initial protected actions first establish an inhibit/15 plan, then obtain the required sleep protection before starting charging or discharge. Healthy discharge heartbeats reuse the owned inflow assertion. The app separately reads root-owned session status before cached control transitions; matching register values cannot establish continued ownership, and a lost session stops control until cleanup and explicit re-enabling. Ordinary sleep/quit boolean settings do not override the numeric state projection; the UI marks them inapplicable for this channel. Quit uses the actual Exit phase and acknowledges its explicit target before relinquishing ownership. Ambiguous replies retain cleanup responsibility, and disable, cancelled exit, backup restoration and service removal share acknowledged restoration. Existing installed helpers without this extension are refused for the selected numeric models. Special multi-display sleep behavior and physical transitions still require validation.

The privileged factory requires a firmware recovery store. Ordinary and numeric charge sessions share a serialized coordinator because their fixed keys can overlap. Switching restores the old backend before acquiring new ownership. Startup restores the sole pending backend; if both charge journals exist, it preserves both and refuses automatic writes. Failed cleanup blocks new charge requests until explicit recovery succeeds. A rejected numeric profile preflight leaves a healthy ordinary session intact.

The finite helper commands accept only canonical decimal limits from 20 through 100, a separate inhibit operation, read-only status, bounded sleep targets (15 or 20 through 100), sleep-policy removal and an explicit orderly-exit target. The existing active-console peer checks, framing bounds and charge lease still apply. Status reads do not renew that lease. Numeric sleep uses its configured target without switching to the ordinary charge backend; wake renews the lease for the app to re-enter its policy. The app does not yet send these projections. Watchdog, console change and service shutdown restore owned originals; successful explicit exit commits its target and clears ownership, so later cleanup leaves that target alone.

Helper removal refuses to remove recovery service files while any ordinary charge, numeric firmware, LED or sleep record remains, including unexpected record paths. The new code was tested only with injected callbacks, fake registers and current-user files; no new helper was installed or restarted and no physical setter was invoked.


### Sleep-transition admission (development source)

A helper built from current development source rejects late charge-control and sleep-policy requests after its IOKit sleep callback begins. Queries, restore and explicit exit cleanup remain available. The updated client distinguishes the exact non-execution reply from an ambiguous transport failure, preserves existing ownership, and retries control after wake. This requires matching updated app/helper source; an older client may report the temporary rejection as a control failure. The validation machine still uses its previous read-only helper. This admission guard does not establish the remaining multi-display sleep-entry behavior or physical effects.


Current development app/helper source negotiates `chargeTransition:epochV1`. The helper changes its context at sleep, wake, recovery and console-owner changes and gives each process instance a distinct identity. One app policy round reuses one context for the fixed charge/protection requests, so a completed sleep/wake between requests also rejects the stale round. The app leaves coordinated sleep preparation to this helper instead of sending an independent ordinary sleep action. Older helpers retain the legacy path, and older clients do not gain the per-round context protection. Explicit recovery and exit cleanup remain available across transitions.


### Development multi-display sleep entry

Matching development app/helper builds advertise `dischargeSleep:displaySnapshotV1` with the independent event-context protocol. The app samples `NSScreen.screens` on its main actor and attaches one of two finite system/display variants to an ordinary force action or an atomic numeric discharge plan, only in the Discharging policy phase. Calibration discharge is excluded. The helper records the metadata only after that action succeeds, without a separate ownership or lease request. Old helpers receive existing commands.

At system sleep entry the helper requires a current discharge session, a snapshot at most 45 seconds old, a known physical adapter and closed lid, and no pending recovery. It then bypasses the usual sleep target for that entry: allowance uses the current exclusive charge backend, system/lid protection uses the existing recovery journal with the selected display preference, and a fixed local-user activity request follows the protection attempt even if it failed. Each result is recorded separately; any failure attempts existing charge/sleep restoration and keeps failed cleanup pending. Normal sleep acknowledgement is retained. Wake, recovery and console handoff clear selection and release owned protection/activity.

The display value is a bounded snapshot, not an instantaneous root-side `NSScreen` observation. Screen-parameter notifications request a new app policy round; the next accepted action atomically replaces or revokes selection. This implementation serializes independent attempts and does not reproduce or claim the completion order of asynchronous requests. User activity concerns display wake/idle behavior and does not establish a system-sleep veto. Native/model/OS and physical multi-display behavior remain unverified; the validation machine still runs the older read-only-tested helper.

## Legacy Apple silicon compatibility gap

The generic ordinary controller is not yet a platform-specific implementation of every legacy Apple silicon key layout. It prefers CHTE whenever present; otherwise it requires both CH0B and CH0C and inhibits both. A CH0C-selected path that leaves CH0B unchanged during inhibition is not integrated. This also leaves the case where CH0C and CHTE coexist, and a layout with CH0C but no CH0B, unresolved. Recognized keys and passing generic-controller fixtures do not establish equivalence for these cases. The compatibility investigation has not changed the controller or enabled hardware control.

## macOS charging features

Apple documents a separate system Charge Limit on Apple silicon with macOS Tahoe 26.4 or later. It offers limits from 80% to 100%, resumes after a drop of more than 5%, and can occasionally charge to 100% for battery-state estimation. These are system behaviors, not guarantees made by OpenCharge's policy engine. The app does not currently report the system's selected limit or override its calibration behavior. See [Apple's charging documentation](https://support.apple.com/en-us/102338).
