# Usage

Open the app for monitoring. The GUI evaluates policies every ten seconds; only an explicitly enabled controller sends charging actions. A CLI configuration command alone does not start a persistent policy loop.

## Commands

```sh
./dist/bin/chargectl status --json
./dist/bin/chargectl limit 75
./dist/bin/chargectl mode topUp
./dist/bin/chargectl profile desk
./dist/bin/chargectl schedules
./dist/bin/chargectl schedule-history
./dist/bin/chargectl capabilities
open 'opencharge://limit?value=80'
```

Use the app to configure recurring tasks, departure estimates and calibration. Estimates are advisory. Interrupted calibration requires an explicit resume/cancel decision. Read-only helper commands report capability, not physical success. Hardware CLI actions require explicit confirmation; review [hardware documentation](HARDWARE.md) first.

## Data

Configuration and up to 10,080 history samples are stored in `~/Library/Application Support/OpenCharge/`. History can be disabled, exported or cleared. Configuration backup excludes history and disables imported control/actions/tasks. Dashboard and popup preferences are stored separately in UserDefaults. Diagnostics export only selected fields and do not upload them.

For isolated development, set `OPENCHARGE_DATA_DIR` to an absolute temporary directory. This keeps test configuration separate and suppresses notifications to the normal GUI.

## Window shortcuts

Command-1 opens the dashboard, Command-2 opens a separate popup preview, Command-3 activates the actual menu-bar status button, Command-4 opens the real popup directly in edit mode, and Command-comma opens settings. Closing windows keeps monitoring active; use Quit to stop the application.

## Menu-bar appearance

Settings → Appearance offers dynamic status, monochrome battery, colored battery and OpenCharge icon styles. Icon-only hides the percentage without changing style; numeric-only modes omit the icon. Optional yellow icon tint reads the system's actual Low Power Mode and never changes it. This option defaults off. Battery fill uses observed OS percentage, while unknown values remain unknown.
