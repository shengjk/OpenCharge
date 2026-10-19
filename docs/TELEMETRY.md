# Telemetry units and evidence

The first implementation incorrectly treated the IORegistry `Temperature` property as raw Smart Battery tenths of Kelvin. Version0.2 corrects it to centi-Celsius (`3077` →30.77°C), as used by primary implementations [beltex/SystemKit](https://github.com/beltex/SystemKit/blob/master/SystemKit/Battery.swift) and [exelban/stats](https://github.com/exelban/stats/blob/master/Modules/Battery/readers.swift). This is a data-format fact, not copied GPL implementation code. Missing or implausible values remain unknown.

macOS percentage uses IOPowerSources; hardware percentage uses AppleRawCurrentCapacity / AppleRawMaxCapacity. The user can select which percentage reference drives the policy. Full capacity prefers valid AppleRawMaxCapacity, then NominalChargeCapacity or legacy mAh values; nominal capacity is also reported separately. A pinned percentage is never treated as mAh. Health ratio is full/design, not necessarily Apple's displayed Battery Health assessment.

AdapterDetails voltage/current/watts are negotiated/rated specifications. They are never used as actual power consumption. PowerTelemetryData SystemLoad and SystemPowerIn are OS telemetry in mW; displayed W divides by1000. On the local M1 Mac, SystemPowerIn can be cross-checked against SystemVoltageIn × SystemCurrentIn /1000. These fields are undocumented and can be stale or absent; they are not calibrated wall-power meter readings.

The system load average integrates sample-and-hold readings over actual elapsed time, caps each reading's validity at120seconds, breaks coverage at unknown samples, and displays coverage percentage. No interpolation across sleep gaps. Remaining-energy math requires an explicitly supplied nominal battery voltage; the UI uses OS time-to-empty/full when available instead of guessing nominal pack voltage.

`Scripts/test-telemetry.sh` tests irregular weighting, stale gaps, unknown/invalid values, equal timestamps, temperature units, energy units and idle-assertion ownership with a fake backend. It does not create real sleep assertions or exercise hardware. Real CLI telemetry separately returned macOS80% / raw about77%, adapter60W rating and lower measured input, demonstrating why the values must remain distinct.

Adapter inhibition caveat: cutting adapter input can make ExternalConnected report false, as independently documented by battery-limiter. The policy prefers AppleRawExternalConnected when available and otherwise distinguishes an acknowledged own adapter-cut action from an unplug event. Raw physical presence under an actual forced-discharge test is still unverified; this fallback prevents immediate on/off oscillation but does not prove physical-cable detection.


## Read-only sensor selection — 0.3.3

The app, CLI and App Intents share BatteryTelemetryReader. It prefers the fixed SMC TB0T battery sensor when its known format decodes into a finite plausible value. Signed sp78 uses big-endian 8.8 fixed point; the supported flt payload uses little-endian IEEE Float. Unknown formats, missing keys, access failures and invalid values preserve the IORegistry Temperature fallback and identify it explicitly. This does not request root access or perform any write. Registry Temperature and VirtualTemperature are retained separately; the virtual reading never silently substitutes for a missing physical reading.

JSON telemetry includes temperatureSource, registryTemperature, virtualTemperature, nominalCapacityMAH and healthCondition. The macOS BatteryHealth assessment is primary for condition, while BatteryHealthCondition is a separate maintenance hint. Capacity health uses the selected full/design ratio, not Apple's assessment. These fields are optional so old telemetry and history decode without invented source metadata. New history/CSV records the selected temperature source; old entries keep it unknown.

Scripts/test-telemetry-reader.sh exercises production decoding and injected read selection with no hardware access: distinct sensor/capacity/health fields, failures, unavailable data, exact binary layouts, invalid values and legacy JSON. The production dashboard fixture also verifies history provenance round-trip and legacy decoding.
