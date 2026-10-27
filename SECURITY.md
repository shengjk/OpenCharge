# Security and privacy

OpenCharge can control battery charging through an optional root service. New installations without recovery records only monitor; a replacement helper first attempts to release its same-boot recorded charge/LED writes. Hardware control, scheduled system actions and LED policies require explicit choices.

## Boundaries

| Area | Protection and limits |
| --- | --- |
| Local IPC | Console-user socket permissions, authenticated root peer, bounded newline messages and fixed commands |
| Privileged actions | No caller-selected SMC keys, byte payloads, executables or shell commands |
| Sleep control | Fixed root-helper actions, dynamic SPI detection, journal-before-write, non-retained lease and independent cleanup; lid control uses a shared kernel flag and cannot isolate concurrent powerd/app writers |
| Recovery | Readback and compare-and-restore for owned values; separate boot-scoped charge/LED write-ahead journals and awake-time watchdogs; physical crash recovery is unverified |
| Configuration import | Bounded schema; imported hardware/system actions and schedules disabled |
| Diagnostics | Allowlisted projection; no raw registry, serials, user paths, task dates or history |
| Software updates | Anonymous opt-in/manual GitHub requests; pinned repository and HTTPS redirect hosts, bounded transfers, SHA-256 verification and quarantine; no automatic execution or app/helper replacement |
| Energy applications | Names and identifiers stay in memory; optional private interface may fail or change |

Another process with the same user account can access that user's configuration and issue allowed local requests. Root compromise and external controller interference are outside these guarantees. Firmware writes are not atomic. Sleep setting and lid operations are also non-atomic. A captured missing custom SleepDisabled value is restored as the logical false default, which may leave an explicit false preference. SleepDisabled persistence is distinct from the boot-scoped lid flag. A local signature is not notarization or an independent security audit. Release checksums and API digests validate consistency with the same GitHub publisher; they are not independent publisher authentication. GitHub and the network receive normal connection metadata such as the source IP when a check or download is requested.

## Reporting

Use the repository's private vulnerability reporting option if enabled: [OpenCharge security](https://github.com/shengjk/OpenCharge/security). Do not post exploit details or personal diagnostics publicly. If private reporting is unavailable, open a minimal issue asking the maintainer for a private channel without including the vulnerability details.

Native legacy file removal is a separate fixed operation: a blessed helper at its installed path requires a matching Apple-issued client signature selected by a kernel audit token and an existing administrator authorization right. It restores owned hardware state, refuses all pending recovery paths and validates descriptor-relative fixed files before unlinking. No path, executable or hardware payload is accepted from the request. Partial removal blocks new control operations and retains process-local retry state; this is not durable crash recovery. Ad-hoc/development installations do not expose this native deletion path.
