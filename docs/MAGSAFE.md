# MagSafe LED control

OpenCharge supports fixed off/green/orange requests, captured-state restoration and optional automatic indication, discharge blinking and sleep suppression. The [MIT battery project](https://github.com/actuallymentor/battery/blob/main/battery.sh) documents ACLC values 01/03/04. OpenCharge preserves captured opaque values rather than guessing a reset byte.

The capability is independent of charge control. One-byte ACLC values must be in 0...4; a readable key is not proof of a physical adapter or LED effect. The root service accepts only fixed actions. LED ownership has a separate 45-awake-second lease; external changes relinquish ownership and failed restore remains retryable. The journal is in memory and does not guarantee crash/reboot recovery.

Automatic indication distinguishes charging, Sailing hold and thermal pause. Sleep suppression overrides manual colors, which override automatic mode. Discharge blink uses a monotonic one-second on/off phase. The native intent saves desired settings; it does not claim a physical change.

`Scripts/test-magsafe.sh` uses injected access for format, ownership, readback, rollback, retry and session policy checks. Physical colors, sleep behavior and generation-specific protocols remain unverified. The local validation machine has no MagSafe port.
