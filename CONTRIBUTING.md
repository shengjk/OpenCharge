# Contributing

## Development

Use macOS 13+ and Swift 5.9+. Build with `bash Scripts/build-app.sh`; run deterministic checks with `bash Scripts/check.sh`. With a full usable Xcode toolchain, also run `swift test` for XCTest coverage. See [TESTING.md](docs/TESTING.md) for optional read-only integration checks.

## Where changes belong

- Put policy and calendar logic in ChargeCore with deterministic boundary tests.
- Keep IOKit and system commands in ChargeHardware. Test writes with injected transports/runners; do not make CI change physical battery or power settings.
- Keep the app model separate from views. Display refresh must not stop schedules or policy evaluation.
- Update both READMEs for user-facing changes and add an entry to CHANGELOG.md.

## Before a pull request

Run the checks above. Describe the trigger, resulting behavior, validation and any unverified hardware effects. Exclude build outputs, local configuration/history, diagnostic exports and credentials. Preserve third-party notices. Never report a simulated backend as a physical hardware test.

Use [GitHub issues](https://github.com/shengjk/OpenCharge/issues) for bugs and feature requests. Include macOS version, architecture, non-unique model identifier and reproduction steps. Remove serial numbers, user paths and application identities from attachments. For security issues, follow [SECURITY.md](SECURITY.md).
