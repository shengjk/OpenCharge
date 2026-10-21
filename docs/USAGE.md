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

## Top Up and temperature

A fresh configuration keeps Top Up separate from the ordinary charging-temperature pause. To apply that pause while charging to full, enable **充至满电期间也启用温控（可选增强）** in Charge Control. The main thermal-protection switch must also be on. Calibration uses its own independent option.

Older saved policies keep the previous Top Up temperature behavior; the new checkbox shows the effective preference, and an explicit change is saved. Backup and restore preserve that choice. These are application policy rules, not a guarantee of physical charging under any temperature or hardware condition.

The dashboard Top Up button and the popover Top Up/Discharge buttons toggle their active operation. While active, the label changes to **Stop Top Up** or **Stop Discharging** (localized in the app). Clicking Stop enters persistent Pause and preserves the daily limit; it does not set the limit to the current percentage. Use Automatic or explicitly choose another mode to resume. An automatic discharge also exposes Stop Discharging. The dedicated Pause Charging Shortcut retains its separate current-percentage behavior.

Scheduled **Pause Charging** is conditional. Charging, Top Up, Discharging and active Calibration accept it; Heat Protection accepts it only when the daily limit is 100%. It sets the daily limit to the current selected control percentage (20–100%) and enters current-limit Pause. Ordinary control resumes when the reading drops into a lower whole-percentage bin. Sailing, existing Pause and other unsuitable phases leave the policy unchanged. Missing or invalid selected hardware telemetry never falls back to macOS percentage. An interrupted calibration remains pending.

A skipped Pause still consumes that occurrence and records its reason. Same-refresh tasks follow their list order and see earlier strategy changes. An accepted Pause ends the old active calibration before a later calibration task starts a fresh run. History describes accepted strategy changes, including changes overwritten by later tasks; it does not confirm a hardware effect. Dashboard Pause and the generic paused mode remain indefinite.
