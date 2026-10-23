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

Command-1 opens the dashboard, Command-2 opens a separate popup preview, Command-3 toggles the actual menu-bar popover, Command-4 opens the real popup directly in edit mode, and Command-comma opens settings. Closing windows keeps monitoring active; use Quit to stop the application.

## Menu-bar appearance

Settings → Appearance offers dynamic status, monochrome battery, colored battery and OpenCharge icon styles. Icon-only hides the percentage without changing style; numeric-only modes omit the icon. Optional yellow icon tint reads the system's actual Low Power Mode and never changes it. This option defaults off. Battery fill uses observed OS percentage, while unknown values remain unknown.

## Top Up and temperature

A fresh configuration keeps Top Up separate from the ordinary charging-temperature pause. To apply that pause while charging to full, enable **充至满电期间也启用温控（可选增强）** in Charge Control. The main thermal-protection switch must also be on. Calibration uses its own independent option.

Older saved policies keep the previous Top Up temperature behavior; the new checkbox shows the effective preference, and an explicit change is saved. Backup and restore preserve that choice. These are application policy rules, not a guarantee of physical charging under any temperature or hardware condition.

The dashboard Top Up button and the popover Top Up/Discharge buttons toggle their active operation. While active, the label changes to **Stop Top Up** or **Stop Discharging** (localized in the app). Clicking Stop enters persistent Pause and preserves the daily limit; it does not set the limit to the current percentage. Use Automatic or explicitly choose another mode to resume. An automatic discharge also exposes Stop Discharging. The dedicated Pause Charging Shortcut retains its separate current-percentage behavior.

Scheduled **Pause Charging** is conditional. Charging, Top Up, Discharging and active Calibration accept it; Heat Protection accepts it only when the daily limit is 100%. It sets the daily limit to the current selected control percentage (20–100%) and enters current-limit Pause. Ordinary control resumes when the reading drops into a lower whole-percentage bin. Sailing, existing Pause and other unsuitable phases leave the policy unchanged. Missing or invalid selected hardware telemetry never falls back to macOS percentage. An interrupted calibration remains pending.

A skipped Pause still consumes that occurrence and records its reason. Same-refresh tasks follow their list order and see earlier strategy changes. An accepted Pause ends the old active calibration before a later calibration task starts a fresh run. History describes accepted strategy changes, including changes overwritten by later tasks; it does not confirm a hardware effect. Dashboard Pause and the generic paused mode remain indefinite.

## Menu-bar right-click

Settings → Appearance offers four right-click actions: show/hide the popover (default), open Settings, toggle charging, and toggle Low Power Mode. Left click and Command-3 always show/hide the popover, regardless of this preference. Opening Settings closes an existing popover and selects the dashboard Settings page.

The charging toggle pauses at the selected current percentage when the policy is Charging or Top Up, or Heat Protection with a 100% daily limit, and the percentage is at least 20%. Otherwise it selects ordinary Automatic charging with a 100% daily target, distinct from temporary Top Up. It cancels a departure plan. Missing or invalid selected telemetry leaves the policy unchanged; interrupted calibration still requires a continuation or cancellation choice. Saving a policy does not enable hardware control.

The Low Power Mode shortcut requires the system-actions permission in Settings and a responding helper with at least one supported power source. It toggles the current system activity and applies the existing helper command to supported sources. Capability failures do not save a successful selection. The administrator charging-settings restriction described below affects the charging toggle and selected editors; it leaves this Low Power Mode shortcut available.

## Explicit mode selection

The Charge Control mode picker applies and saves an accepted selection immediately, using the same path as explicit dashboard mode buttons. Selecting Pause creates an indefinite pause and clears any earlier current-percentage Pause marker. Top Up and Calibration require a connected power source; Top Up also requires leaving calibration first. An interrupted calibration remains pending when Calibration is selected again: use Continue to resume or select another mode to cancel.

Selecting a different mode cancels the old calibration stage even if the following telemetry read fails. A later calibration begins a new run. Quick profiles select Automatic and clear any interrupted calibration/checkpoint. These requests preserve the hardware-control opt-in; applying a mode in monitoring does not enable physical control.

## Administrator charging-settings restriction

The Boolean `settingsLock` preference in the `org.opencharge.app` defaults domain defaults to false. When true, the app displays a lock notice and disables interactive edits to the daily limit, Sailing, temperature protection, control percentage, sleep/exit charging policy and the right-click charging toggle. OpenCharge also restricts its additional charging-policy options (thermal enhancements, departure plan and reserve), GUI quick profiles and GUI configuration restore. Backup export remains available. Both the visual controls and their setters check the restriction; old input drafts cannot submit protected changes after locking.

The preference is read-only inside the app; there is no in-app unlock or password workflow. Administrators manage it through their normal preference-management mechanism. Local development examples:

```sh
defaults write org.opencharge.app settingsLock -bool true
defaults delete org.opencharge.app settingsLock
```

Preference observation updates the UI; policy refresh also re-reads it, and protected setters always re-read before writing. The app never saves the lock into the portable configuration backup or clears it on import. Managed-profile deployment still needs its own environment validation.

This is a restriction on selected interactive charge settings. Temporary Top Up, explicit mode selection, calibration continuation/cancellation, Low Power Mode, MagSafe, appearance and read-only inspection keep their existing paths. Schedules, CLI, URLs, Shortcuts, checkpoints and recovery also retain their contracts; this preference does not replace macOS authorization or provide a system-wide security boundary.
