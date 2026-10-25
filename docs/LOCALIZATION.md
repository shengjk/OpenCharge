# App localization

Development source contains English (`en`), Simplified Chinese (`zh-Hans`) and Traditional Chinese (`zh-Hant`) translations. The packaged app declares English as its development language and uses macOS language selection, including per-app language preferences. Relaunch the app after changing its language preference. Traditional Chinese regional selections such as Taiwan and Hong Kong use the shared `zh-Hant` table. Other languages currently fall back to English; additional translations are still pending.

`Resources/<language>.lproj/Localizable.strings` contains 524 source keys for controls, menu labels, status text, error descriptions and policy explanations. `AppShortcuts.strings` contains five invocation phrases with the named `${applicationName}` token. English plural rules cover local sample counts and minute durations. These are independently authored translations of this project's interface.

SwiftUI, AppKit-facing strings and domain labels use native localization APIs. Interpolation remains inside the localized literal so typed arguments and literal percent signs retain their formatting. Page titles are localized separately from stored page identifiers. Charge mode, phase, command, configuration and schedule identifiers retain their existing values. Older history entries and raw replies from an older service can still contain their original language; this change does not rewrite saved history or localize the fixed IPC protocol. CLI help and wider language coverage remain separate work.

## Development checks

Run `bash Scripts/test-localization.sh` with the existing Swift tools and Python 3. The script compiles localization-key extraction for the app and its domain modules, checks complete coverage of annotated Chinese source keys in all three language tables, checks format placeholders and plural rules, and verifies named App Shortcut tokens against the source declarations.

It then builds a private, never-shown native bundle and runs its actual page/menu/domain labels, interpolated text, plural forms, error and policy explanation under English, Simplified Chinese, Traditional Chinese, Taiwan/Hong Kong language selections and an unsupported language. It requires identical encoded charge policy across all six runs. These checks do not launch the application, instantiate its runtime model, perform an intent, modify language preferences or call a hardware service. The full `Scripts/check.sh` includes this check.

`Scripts/build-app.sh` copies the language folders before metadata extraction and code signing. Universal packaging retains those resources. Native bundle lookup and compiler coverage do not prove every translated layout, VoiceOver label or live Shortcuts/Siri phrase. Those visual and system-integration checks remain unverified. Existing release packages and the installed app are not updated by a source-only change.

Apple references: [Preparing views for localization](https://developer.apple.com/documentation/swiftui/preparing-views-for-localization) and [Migrate custom intents to App Intents](https://developer.apple.com/videos/play/tech-talks/10168/) describe the native string and App Shortcut phrase mechanisms used here.
