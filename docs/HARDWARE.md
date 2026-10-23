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


## Unreleased numeric firmware backend

An injected controller implements only the fixed CH0B/BCLM profile for a caller-established eligible host with an internal battery. It requires one-byte `ui8 ` metadata, accepts recognized current values, and exposes bounded limits from 20 through 100 plus a separate internal inhibit target of 15. Read-only status uses CH0B and BCLM, consulting BSIn bit 0 only when CH0B is zero and BCLM is 15; unavailable BSIn leaves that control state unknown. It does not substitute OS charging or measured power flow.

Transactions save owned original/expected/previous values before writes and validate readback and the final full profile. Crash recovery compares owned values before restoring originals. Orderly exit applies a separate explicit target and relinquishes ownership only after validation and successful journal removal; subsequent restore must preserve that target. Malformed recovery data and incomplete rollback block further mutation. The recovery schema is distinct from the production charge journal and has no production file path or IPC yet. Compare-and-restore remains subject to external-writer races and cannot identify an identical external value.

The backend mutation methods are not connected to production helper requests or GUI lifecycle. Read-only probing is described below; it does not enable firmware control. Process-crash fixtures establish recovery behavior for injected registers and local file operations only; real sleep, shutdown, charging effects, reboot and power-loss behavior remain unverified.


The production SMC client now shares metadata/payload decoding with raw 80-byte frame fixtures. Its read-only numeric probe selects only MacBookAir8,1, MacBookAir8,2 and MacBookAir9,1 in an x86_64 process with an internal battery, then validates CH0B/BCLM metadata and recognized values. These are the initial selected models, not an exhaustive hardware matrix. Model identity alone does not establish physical effects. Rosetta on an Apple Silicon model does not select this profile. `chargectl diagnose-smc` reports numeric read availability, limit and firmware charging-control state separately from ordinary charge capabilities; numeric writes remain unavailable.

A fixed numeric byte-write primitive rechecks metadata immediately before command 6, but it is not wired to production mutation requests. The backend's recovery-aware actions and orderly exit still require a separate helper protocol, journal path and lifecycle integration. On the current MacBookPro17,1, the new native read-only diagnostic preserves recognized CHTE/CHIE observation and reports numeric read/write unavailable. This is a refusal check on Apple Silicon, not an Intel firmware validation.
