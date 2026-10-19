# Menu-bar popover

Specifications, compact power flow and significant-energy apps are independently selectable from the main dashboard. Percentage and specification field choices persist in UserDefaults. Flow and energy are enabled by default.

Edit Components or long press enters the editor. Dedicated native drag handles and row destinations, plus accessible up/down buttons, reorder components. Empty layouts retain charge actions and console/quit controls. Command-2 opens a preview using the same component view.

Window key/close observation supplements appearance events. The energy reader runs if either visible consumer needs it; the popup never unfreezes the dashboard snapshot. Flow animation follows its native consumer and Reduce Motion.

Core and production-model fixtures cover layout, persistence and consumer coordination. Native preview checks covered add/remove, accessible ordering, reset and compact layout. Preview long press, upward/downward drag onto row text, invalid drops and persisted ordering have been observed. Real status-item opening/closing and energy pause are covered below; preview verification alone does not establish native behavior.


## Native drag handling — 0.3.4

Each edit row hosts its controls inside a registered AppKit destination, with a dedicated native drag handle. The destination accepts only a source from the same preferences instance, a matching fixed component payload and currently visible source/target components. External drags are refused. The order changes only on an accepted drop; entering a row or dropping outside rows does not persist a partial move. The drag session permits movement only within the application. Up/down buttons remain available to keyboard and accessibility users.

The footer says Done Editing because changes persist immediately; leaving edit mode does not claim to undo them. Preview verification is separate from native menu-bar lifecycle verification.


## Native status item — 0.3.5

The app directly owns one NSStatusItem and one transient NSPopover. Command-3 dispatches the real status button action; Command-2 remains a separate preview. Native show/close notifications own the status consumer, while the preview tracks its own window. Closing either consumer cannot erase the other. A direct settings window is available through Command-comma and shows whether energy reads are paused. Closing application windows keeps the status item and policy loop alive.

Real anchored popover opening, button-toggle closure, Escape dismissal, adaptive content height and idle energy pause have been observed. Preview drag validation remains valid. Automated coordinate drags did not establish a valid row-to-row drop. On 2026-10-18, the user manually confirmed normal sorting in the real popup on the current Mac. This is user-reported runtime evidence, distinct from the automated preview checks. Drag sessions prevent automatic popover dismissal while active; invalid destinations still do not modify layout.

Appearance and Reduce Motion preferences apply to the native presentation. Label projection preserves status/icon/OS-percentage/hardware-percentage modes and identifies missing values without fabrication. Multi-display placement, status-item overflow/autohide and every login/session path remain unverified.


## Direct editor and animation — 0.3.6

Settings and Command-4 open the actual status popover directly in edit mode, including when it is already visible. Editing sessions belong separately to preview and status presentation, and close clears only that presentation's editor. The saved component order and metric selections remain intact. Editing mode is never persisted across app launches.

The popup animation preference persists independently of layout. The native controller evaluates it on opening; system Reduce Motion disables animation regardless of the app preference. Reset Popup restores the default enabled preference along with the default layout and percentage display.

Native runtime checks on 2026-10-18 confirmed both direct entry paths, switching an already visible popup into editing, and normal display mode after closing/reopening. Current component and specification selections were preserved. Animation UI presence was inspected; animation timing and changing the system accessibility preference were not measured.


## Menu-bar icon appearance — 0.3.9

Settings offer dynamic status, monochrome battery, colored battery and an independent OpenCharge symbol. Icon-only display hides text while preserving the selected style; OS/raw numeric-only displays remain icon-free. Existing display preferences remain intact and the new low-power tint defaults off. Battery fill uses valid observed OS percentage, not the policy limit or hardware reference. Missing/invalid values produce an unknown outline/glyph and em dash rather than a fabricated fill.

Charging follows the OS charging flag. Plugged discharge requires a physical adapter connection and a finite negative current; a disconnected battery is not labeled as adapter discharge. Accessibility labels describe the observed state and Low Power Mode in every display mode. The optional yellow tint applies to icons only and follows `ProcessInfo.isLowPowerModeEnabled`, with power-state notifications for changes. It never sets a power mode. Native appearance changes refresh adaptive images; normal text retains system colors.

Independent vector battery outlines and system symbols avoid importing third-party artwork. Colored battery icons use green for charging and red at or below 20%; the explicit low-power yellow option takes precedence. Image/description fixtures and a light/dark contact sheet cover the projection and renderer. Multi-display, overflow and full native presentation remain separate runtime validation.

Native settings on the current Mac exposed all four styles, accepted colored battery selection and disabled style/tint controls in numeric-only mode. The previous dynamic-status display/style were restored. The system Low Power Mode was not toggled; its real notification-to-render transition remains unverified.

### Redraw stability — 0.3.10

The 0.3.9 preview was withdrawn after native profiling showed a status-button appearance/snapshot redraw loop despite passing image fixtures. Appearance observation now belongs to the application, with semantic old/new name filtering. A bounded render cache records label/appearance before assigning an image, so unchanged notifications cannot recreate status snapshots. Tooltip-only changes do not redraw the icon. The regression fixture sends 1000 identical presentations and still verifies updates for genuine appearance, display, telemetry and power-state changes. Actual CPU measurement is required alongside these fixtures.
