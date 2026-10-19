# Architecture

OpenCharge is one SwiftPM package with three executables. The GUI owns the recurring policy loop; the CLI changes configuration or requests explicit fixed operations, and the root daemon performs privileged actions.

```text
OpenCharge / chargectl
  ├── ChargeCore: policies, schedules, layout, persistence, IPC
  └── ChargeHardware: read-only telemetry and system adapters
                         │ restricted Unix socket
                      charged
                         └── fixed SMC / power-mode operations
```

`ChargeModel.swift` coordinates telemetry, policy evaluation, schedules, history and helper requests. `App.swift` manages app lifecycle and scene entry. Main navigation, shared components and individual pages are separate Swift files. Dashboard and popover preferences are independent; their display/energy consumers never own the control loop.

ChargeCore remains independent of UI and IOKit. Hardware planners accept injected transports/runners so failures, rollback and external writers can be tested without changing a machine. The daemon authenticates local clients and validates fixed requests; only it writes privileged settings.

Configuration and bounded history live in the application support directory. Presentation preferences live in UserDefaults. Configuration backup is versioned and disables imported actions; diagnostics use a narrow projection. Runtime state, local exports, build products and private analysis files are not repository inputs.

The app delegate owns MenuBarController, its native status item and anchored popover. Native visibility and preview visibility are tracked separately; settings use a standard SwiftUI settings scene and share the model.

The daemon alone supplies the charge planner with a private recovery-file store and kernel boot identity. Fixed charge entries are persisted before writes and compared/restored on same-boot restart. Recovery-directory lock/identity failures stop startup before socket replacement; malformed records block new charge actions. LED ownership and persistent power-mode preferences remain separate.
