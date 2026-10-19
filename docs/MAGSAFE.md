# MagSafe LED control

OpenCharge supports fixed off/green/orange requests, captured-state restoration and optional automatic indication, discharge blinking and sleep suppression. The [MIT battery project](https://github.com/actuallymentor/battery/blob/main/battery.sh) documents ACLC values 01/03/04. OpenCharge preserves captured opaque values rather than guessing a reset byte.

The capability is independent of charge control. One-byte ACLC values must be in 0...4; a readable key is not proof of a physical adapter or LED effect. The root service accepts only fixed actions. LED ownership has a separate 45-awake-second lease; external changes relinquish ownership and failed restore remains retryable. The helper supplies a separate boot-scoped LED write-ahead journal; physical crash/reboot recovery remains unverified.

Automatic indication distinguishes charging, Sailing hold and thermal pause. Sleep suppression overrides manual colors, which override automatic mode. Discharge blink uses a monotonic one-second on/off phase. The native intent saves desired settings; it does not claim a physical change.

`Scripts/test-magsafe.sh` uses injected access for format, ownership, readback, rollback, retry and session policy checks. Physical colors, sleep behavior and generation-specific protocols remain unverified. The local validation machine has no MagSafe port.

## Same-boot LED recovery — 0.3.8

The helper stores captured ACLC ownership in `magsafe-recovery.json`, alongside the independent charge record under `/var/db/org.opencharge.charged/`. Both stores share one root-private directory descriptor and lifetime lock; filenames are fixed and cannot be supplied by IPC. The same bounded read, owner/permission/link checks and synchronized atomic replacement apply.

The LED schema permits one captured byte in 0...4, fixed color targets (1/3/4), a bounded previous value and a valid boot UUID. Same-boot startup restoration attempts the captured value before new LED control; no blinking pattern is resumed automatically. Different-boot records are cleared without hardware writes. Corrupt records and failed recovery block LED changes; failed runtime blink/sleep/wake updates enter restoration instead of continuing to toggle.

Every new ownership/state pair is persisted before the write. Once the disk record covers both alternating blink values, later alternations reuse it. A 1000-tick fixture checks that an initial captured value of 2 requires only two record saves before restoration. Changing ownership or introducing a new color requires a new record. External values outside the owned expected/previous states are preserved. Missing registers, readback and record-removal failures remain retryable.

Tests terminate subprocesses using file-backed fake ACLC values, including after a cached blink transition. These are not physical LED, SIGKILL or reboot tests. No installed helper is updated or restarted by the tests.
