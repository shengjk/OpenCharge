# MagSafe LED control

Fixed ACLC requests use off (1), green (2), orange (4), and native orange blinking (6). Values 0 and legacy 3 remain readable and recoverable; value 3 is not written by new green requests. Captured values are restored rather than guessing a reset byte. A readable key is not proof of a physical adapter or LED effect.

The root service accepts only fixed actions. Green and native-blink control require the exact `magSafeEncoding:aclcNativeV2` capability. The app and CLI share the check before any LED session setters for those requests; a legacy service receives only a capability read and a visible update-required result. The app does not install or restart a service automatically.

LED control is independent of charge control. Ownership has a separate 45-awake-second lease; external changes relinquish ownership and failed restore remains retryable. Automatic indication distinguishes charging, Sailing hold and temperature pause. Manual colors override automatic indication. Sleep-off selection takes priority; otherwise native blink is held at orange on sleep entry and restored on wake. Heartbeats do not alternate colors or restart the native pattern.

The native LED intent saves desired settings. Physical colors, blink cadence, sleep behavior and generation-specific support remain unverified. The local validation machine has no MagSafe port.

## Same-boot recovery

The helper stores captured ACLC ownership in `magsafe-recovery.json`, alongside the independent charge record under `/var/db/org.opencharge.charged/`. Both stores share one root-private directory descriptor and lifetime lock. Filenames are fixed and cannot be supplied by IPC; bounded reads, owner/permission/link checks and synchronized atomic replacement apply.

Schema 1 accepts captured/previous values 0, 1, 2, 3, 4 and 6. Owned expected targets accept 1, 2, 3, 4 and 6 so earlier journals containing target 3 remain recoverable. A valid boot UUID is required. Same-boot startup restoration attempts the captured value before new LED control; no pattern resumes automatically. Different-boot records are cleared without hardware writes. Corrupt records and failed recovery block new LED changes.

Ownership is persisted before each new write. Repeated native-blink heartbeats reuse the existing record; a 1000-tick fixture requires only one save before restoration. External values outside owned expected/previous states are preserved. Missing registers, readback and record-removal failures remain retryable.

`Scripts/test-magsafe.sh` uses fake ACLC values and file-backed terminated subprocesses, including native-pattern and legacy-journal recovery. These checks do not establish physical LED, real SIGKILL or reboot recovery. No installed helper is updated or restarted by the tests.
