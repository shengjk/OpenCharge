# Swift runtime packaging

Both build scripts run `Scripts/prepare-swift-runtime.py` against their staging app and tool directory. Preparation changes Mach-O load commands, so it runs before executable and outer-app signing. Verification reads the resulting files without changing them.

```sh
python3 Scripts/prepare-swift-runtime.py prepare path/to/OpenCharge.app path/to/bin
# Sign the embedded helper, standalone tools and outer app after preparation.
python3 Scripts/prepare-swift-runtime.py verify path/to/OpenCharge.app path/to/bin
bash Scripts/test-runtime-package.sh
```

The app search order is `/usr/lib/swift`, then `@executable_path/../Frameworks`. Standalone tools, the modern helper and any packaged older helper retain only `/usr/lib/swift`. Developer-toolchain and build-directory RPATHs are removed from each architecture independently, including universal files whose host slice was already prepared. System libraries remain system dependencies.

An application slice targeting macOS before 12 that uses Swift concurrency requires a backdeployment runtime. The packager selects the active compiler's `lib/swift-5.5/macosx/libswift_Concurrency.dylib`, checks its macOS deployment commands and architecture coverage, and uses the matching `swift-stdlib-tool` to confirm and copy the dependency closure. It trims unused architectures, explicitly signs the copied library, and places it in `Contents/Frameworks`. Newer systems prefer their system runtime through the first RPATH. Current macOS 11-target app packages include this validated backdeployment library.

The verifier checks every executable slice, library install name, macOS minimum, runtime architecture and code signature. Mac Catalyst load-command versions in zippered SDK libraries are distinguished from macOS versions. Package executables must not require a newer macOS than the app declares. Runtime dependencies beyond the supported concurrency library and the system Swift core are rejected for explicit review. The packager does not provide a runtime installation layout for a standalone helper targeting an older OS; such a dependency fails before package publication.

Work on staging copies. Unexpected Frameworks content, symlinks, hardlinks and inconsistent architectures are rejected. A failed preparation can leave a partially prepared staging directory; rebuild that directory instead of publishing it. The native and universal builders keep the app and tools together in staging, complete signing and verification, and back up the previous generated output before publishing the new tree. The script never installs a service, modifies a system runtime or launches an app.

Tests run asynchronous fixture programs on the validation host and structurally check older-target packages. They do not establish a macOS 11 launch or exercise its runtime. Current packages declare macOS 11 as the minimum and include the validated backdeployment runtime. Actual macOS 11/12 launch, installation and runtime acceptance remain unverified.

References: Apple's [run-path dependent libraries](https://developer.apple.com/library/archive/documentation/DeveloperTools/Conceptual/DynamicLibraries/100-Articles/RunpathDependentLibraries.html), [bundle layout](https://developer.apple.com/documentation/bundleresources/placing-content-in-a-bundle), and [Xcode 13.2 concurrency backdeployment notes](https://developer.apple.com/documentation/Xcode-Release-Notes/xcode-13_2-release-notes).
