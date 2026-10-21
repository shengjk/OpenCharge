# Shortcuts actions

The dedicated **Pause Charging** action reads the selected control percentage, sets that value as the new daily limit, and enters a current-limit pause. It rejects missing, nonfinite, below-20% or above-100% readings without changing configuration. Hardware-percentage selection requires a readable hardware value. Temporary departure/Top Up and calibration state are cancelled. At 100% this explicit pause inhibits charging rather than entering system-managed top-off. After the percentage falls below the target bin, ordinary Sailing/charging rules resume.

**Set Mode: Pause** remains a separate indefinite manual pause and does not replace the limit. Choosing it explicitly clears current-limit pause behavior.

**Set MagSafe LED** offers system restoration, off, green, orange, and orange blinking. It saves the requested setting; the application applies it only through fixed helper actions. Green and native blinking require the updated native-encoding service capability. A saved setting does not establish a physical LED change.

The current **Get Charge State** action returns observed power-flow strings (`charging`, `holding`, or `discharging`). Semantic application-state output remains incomplete. See [status](STATUS.md) for remaining integration and hardware verification.

Local intent checks inject percentage readings and use isolated configuration. They do not send charge, LED, sleep or power-mode commands to the installed service.
