# Shortcuts actions

The dedicated **Pause Charging** action reads the selected control percentage, sets that value as the new daily limit, and enters a current-limit pause. It rejects missing, nonfinite, below-20% or above-100% readings without changing configuration. Hardware-percentage selection requires a readable hardware value. Temporary departure/Top Up and calibration state are cancelled. At 100% this explicit pause inhibits charging rather than entering system-managed top-off. After the percentage falls below the target bin, ordinary Sailing/charging rules resume.

**Set Mode: Pause** remains a separate indefinite manual pause and does not replace the limit. Choosing it explicitly clears current-limit pause behavior.

**Set MagSafe LED** offers system restoration, off, green, orange, and orange blinking. It saves the requested setting; the application applies it only through fixed helper actions. Green and native blinking require the updated native-encoding service capability. A saved setting does not establish a physical LED change.

**Get Charge State** preserves its existing observed power-flow strings (`charging`, `holding`, or `discharging`). **Get Application State** separately reads the running application’s latest evaluated policy phase: `Charging`, `Pause`, `Sailing`, `Discharging`, `Topup`, `HeatProtect`, `Calibration`, or `Exit`. `IntelMode` is reserved for a backend that implements it and is not produced by the current engine. Policy state describes the application’s policy, including monitoring mode; it does not prove a physical charging effect.

The application normally evaluates policy every ten seconds and on relevant events. Reading application state does not force a sample, rerun policy, change settings or send a helper command. An unavailable or ended policy instance produces an error instead of a cached or guessed result. Interrupted calibration remains `Calibration`; quit preparation reports `Exit` while the process is still available. Full transition and hardware coverage remain subject to [status](STATUS.md).

Local intent checks inject percentage readings and use isolated configuration. They do not send charge, LED, sleep or power-mode commands to the installed service.
