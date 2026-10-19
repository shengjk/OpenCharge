# Dashboard

Eight sections support visibility and ordering with accessible up/down buttons. Nine specification fields can be selected individually. Empty layouts have an explicit state; reset restores defaults.

The native dashboard window is reused when reopened. Startup visibility and Dock visibility are preferences. By default the dashboard opens at launch and display updates pause when unfocused. Background updates are optional.

The display uses an independent snapshot. Policy evaluation, schedules, menu-bar battery state and history continue while the dashboard is paused. Focus immediately captures the latest state. Hidden/inactive energy consumers stop querying, and animation follows actual window focus and Reduce Motion.

`Scripts/test-dashboard.sh` exercises the production model with isolated storage, proving due schedules continue while display snapshots freeze. Layout and focus policy have core coverage. UI checks covered hiding/reordering, specification selection, reset, persistence and window reopening. Complete login/session behavior remains to verify.
