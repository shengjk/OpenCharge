# Power flow

The diagram uses measured adapter input/system load and battery current × voltage. Adapter ratings are specifications, not measured consumption. Positive battery power points toward the battery; negative power points toward the Mac. Absolute battery power below 0.1 W has no moving arrow. Unknown/non-finite readings remain unavailable.

Samples can arrive asynchronously, so channels are not forced into an artificial balance equation or used to invent conversion losses. Line width scales with magnitude with a readability cap. Animation requests at most twenty updates per second only for an active consumer with known flow. Reduce Motion retains direction without animation. Policy evaluation is independent.

Core tests cover charging, discharging with a physically connected adapter, idle and invalid/missing input. Native compact and full-size layouts were inspected using read-only data. Physical transitions remain to verify.
