# OpenCharge

A local-first macOS battery manager with a native dashboard, menu-bar controls, CLI and Shortcuts actions.

[简体中文](README.zh-CN.md) · [Documentation](docs/README.md) · [Status](docs/STATUS.md) · [Contributing](CONTRIBUTING.md)

## Features

- Charge limits, Sailing hysteresis, timed thermal protection, Top Up, discharge and resumable calibration policies.
- Recurring schedules, departure estimates, presets, decision history and JSON configuration backups.
- Configurable dashboard and menu-bar components, measured power flow and optional significant-energy app readings.
- Eleven App Intents, four App Shortcuts, CLI and an `opencharge://` URL scheme.
- Local history and explicit diagnostic exports; no account, analytics or cloud service.

## Quick start

Requires macOS 13+, Swift 5.9+ and Apple's command-line developer tools. Native Shortcuts packaging also requires an installed App Intents metadata processor (normally supplied by Xcode).

```sh
git clone https://github.com/shengjk/OpenCharge.git
cd OpenCharge
bash Scripts/build-app.sh
open dist/OpenCharge.app
./dist/bin/chargectl status --json
```

New installations start in monitoring mode. Hardware control requires a separately installed privileged helper and explicit opt-in. Review the [setup guide](docs/HELPER-SETUP.md) before installing it. Keep only one charging controller active.

## What works and what remains

Version 0.3.7 is a development build. Policy tests and read-only telemetry have been exercised; real charging/discharging, MagSafe effects and sleep recovery still require hardware validation. Private macOS interfaces may be unavailable on another system. A universal binary does not establish support for every Intel or Apple Silicon firmware. See [status and limitations](docs/STATUS.md).

## Build and verify

```sh
bash Scripts/check.sh
bash Scripts/build-app.sh
# Optional arm64 + x86_64 package:
bash Scripts/build-universal.sh
```

The app, CLI and daemon are built together with SwiftPM. `dist/`, `dist-universal/` and build caches are ignored by Git. Local builds use ad-hoc signatures; they are not notarized releases. [Verification details](docs/TESTING.md).

## Repository layout

| Path | Purpose |
| --- | --- |
| `Sources/OpenCharge/` | Native application, model, views and system integrations |
| `Sources/ChargeCore/` | Pure policy, schedules, layouts, persistence and bounded IPC client |
| `Sources/ChargeHardware/` | Telemetry and fixed hardware operations |
| `Sources/ApplePowerConstants/` | Small C bridge to SDK constants |
| `Sources/chargectl/`, `Sources/charged/` | CLI and privileged service |
| `Tests/` | Core tests and isolated validation harnesses |
| `Scripts/` | Build, package, verification and explicit service installation |
| `docs/` | User guides, architecture, support status and license notices |

## Security and privacy

Data stays in `~/Library/Application Support/OpenCharge/`. The helper exposes fixed commands over a restricted local socket; it does not accept arbitrary SMC keys or shell commands. Charge recovery uses a bounded same-boot ownership journal and is best effort; physical crash recovery remains unverified, and LED ownership remains in memory. Read [SECURITY.md](SECURITY.md) for boundaries and reporting.

## License

MIT. Third-party notices and protocol references are retained in [docs/licenses/Hardware-MIT.txt](docs/licenses/Hardware-MIT.txt) and [hardware documentation](docs/HARDWARE.md).
