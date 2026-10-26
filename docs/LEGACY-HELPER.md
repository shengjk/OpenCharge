# Older privileged-helper package

This is the packaging prerequisite for the older macOS privileged-helper route. The application still supports macOS 13 and later. Its pre-13 authorization, job ownership and removal backend is not yet implemented or enabled. No administrator authorization or system installation is performed by the build or tests below.

The app contains two separate helper executables:

- `Contents/MacOS/charged` remains the macOS 13 SMAppService helper. The explicit development installer also uses its separately packaged `bin/charged` copy.
- `Contents/Library/LaunchServices/org.opencharge.charged` is compiled from the same daemon source with a macOS 11 target. It embeds `__TEXT,__info_plist` and `__TEXT,__launchd_plist` for the older installation API. It is not installed by the current app.

The embedded Info contains the helper identifier, numeric app build version, `SMAuthorizedClients` and an `OpenChargeInstallRoute` marker. Its launchd dictionary uses the fixed label, RunAtLoad, KeepAlive, bounded restart interval and Interactive process type. It does not supply a Program path or custom arguments; the installation API supplies the fixed installed location.

`Scripts/legacy-helper-package.py prepare` reads the already-signed normal helper's actual Apple-issued signing team. It creates the app's `SMPrivilegedExecutables` requirement and the helper's reverse client requirement using fixed identifiers, Apple anchoring and the same team. No team is invented or supplied through an unchecked environment override. If the signature has no verified Apple-issued team, both requirements are `never`, so the local package cannot authorize the older installation route.

The builder compiles optimized static core/hardware modules for each macOS 11 architecture, with content/compiler/SDK fingerprints, then links the common daemon with its metadata sections. It does not reuse macOS 13 object code for this older target. Helper linking always uses the current app build number. Preparation updates staging files before runtime-path normalization and final signing. The legacy helper has an explicit signing identifier matching its job label, and the outer app has its app identifier.

```sh
# Normally called by build-app.sh and build-universal.sh after provisional helper signing.
python3 Scripts/legacy-helper-package.py prepare path/to/OpenCharge.app
# Run runtime preparation and final helper/app signing before verification.
python3 Scripts/legacy-helper-package.py verify path/to/OpenCharge.app
bash Scripts/test-legacy-helper-package.sh
```

Verification reads the exact plist section bounds in every architecture. It checks typed metadata, version agreement, identifiers, macOS 11 deployment, signatures and reciprocal requirements. The tests use ad-hoc packages and pure signing-policy fixtures; they do not create or import certificates. They re-sign malformed helper slices to check metadata rejection beyond simple corruption, including a nonhost slice. Read-only verification must leave package bytes unchanged.

An actual certificate-signed positive installation, administrator prompt, launchd lifecycle, upgrade from the script-installed service, recovery before removal and physical hardware behavior remain unverified. The package marker is metadata for future ownership checks, not proof that a service was installed by a particular route. The app now inspects fixed system service files before allowing modern registration or removal. It distinguishes absent files, the development layout, older native metadata with verified signing ownership, and unrecognized or incomplete files. This read-only snapshot is separate from launchd registration and connection status.

References: Apple's [SMJobBless requirements](https://developer.apple.com/documentation/servicemanagement/smjobbless%28_%3A_%3A_%3A_%3A%29), [authorized clients](https://developer.apple.com/documentation/bundleresources/information-property-list/smauthorizedclients), and the local ServiceManagement.h contract.

The inspector checks bounded regular files, expected UID and mode bits, link count, fixed launch arguments and typed plist fields. It validates each declared supported Mach-O slice before reading its signed metadata. Older native ownership requires matching Apple-anchored signing teams and exact reciprocal client/helper requirements. An ad-hoc signature cannot establish this ownership. Development layout matching does not establish which installer wrote the files.

Opened file descriptors and a final inode/metadata comparison detect changes during inspection. This is a best-effort filesystem snapshot: it does not evaluate ACLs, establish launchd liveness or grant permission for privileged changes. Existing, partial or unrecognized root-installed files block app registration and removal before recovery or backend calls. The pre-13 installation/removal backend remains unavailable.
