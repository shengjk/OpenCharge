# Power flow

The diagram uses measured adapter input/system load and battery current × voltage. Adapter ratings are specifications, not measured consumption. Positive battery power points toward the battery; negative power points toward the Mac. Absolute battery power below 0.1 W has no moving arrow. Unknown/non-finite readings remain unavailable.

Samples can arrive asynchronously, so channels are not forced into an artificial balance equation or used to invent conversion losses. Line width scales with magnitude with a readability cap. Active known flows use a two-second system-composited arrow cycle. Static labels and power-width paths update with telemetry rather than animation frames. Focus loss freezes the arrows; hiding or detaching the host stops its animations. Reduce Motion retains direction with stationary arrows. Policy evaluation is independent.

Core tests cover charging, discharging with a physically connected adapter, idle and invalid/missing input. Native compact and full-size layouts were inspected using read-only data. Physical transitions remain to verify.
