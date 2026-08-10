# Distribution profile build contract

- **Phase:** 1 — Distribution profile foundation
- **Status:** Store installer candidate packaging/signing path implemented; portable publication remains unchanged
- **Default:** `portable`
- **Define:** `TABAME_DISTRIBUTION_PROFILE`

The profile is compile-time configuration. An unknown value fails during startup;
no value selects the safe `portable` profile. Runtime package identity is checked
on Windows and logged as a diagnostic when it does not match the selected
profile. A mismatch does not crash the portable development process, and
automatic elevation fails closed when package identity is mismatched or unavailable.
Normal startup is non-elevated by default; the portable and storeInstaller profiles
also support the explicit, persisted Elevated Permission preference. Startup
elevation is governed by the Phase 4 elevation service and the
`allowElevation`/`automaticElevation` capabilities.

## Profiles

| Profile          | Intended artifact                                                  | Package identity | Update/lifecycle policy                                                                                                             |
| ---------------- | ------------------------------------------------------------------ | ---------------- | ----------------------------------------------------------------------------------------------------------------------------------- |
| `portable`       | Existing ZIP/GitHub build                                          | Unpackaged       | Existing ZIP self-update and custom lifecycle remain available; explicit and opt-in startup UAC are available                       |
| `storeInstaller` | Signed per-user Inno Setup EXE candidate listed in Microsoft Store | Unpackaged       | Installer owns lifecycle; self-update, custom install, and custom uninstall disabled; explicit and opt-in startup UAC are available |
| `storeMsix`      | Future Store-hosted MSIX                                           | Required         | Store owns updates/uninstall; package app-data and StartupTask are required; elevation is disabled until `allowElevation` approval  |

`storeInstaller` is the selected first Store route. The existing Windows workflow
still publishes the portable ZIP unchanged. The separate
`.github/workflows/release-packaging-windows-store.yml` creates a signed installer
candidate only when its protected signing environment is explicitly used.

## Local commands

From the project root, after dependencies are available:

```text
# Safe default; equivalent to omitting the define.
flutter build windows --release

# Explicit portable profile.
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=portable

# Build the installer-listed Store profile; package it with the separate CI script.
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=storeInstaller

# Validate the future MSIX capability policy without producing an MSIX.
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=storeMsix
```

Focused profile tests can be run with:

```text
flutter test test/distribution_profile_test.dart
```

The test suite exercises all three profiles through the pure profile/capability
model. It does not require a package identity; runtime identity checks accept
injected probe results so packaged and unpackaged cases are deterministic.

## CI contract

The existing Windows workflow remains the portable profile because it does not
pass a distribution define and publishes a ZIP. The separate Store candidate
workflow passes its profile define explicitly rather than relying on
`kReleaseMode` or executable paths:

```text
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=portable
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=storeInstaller
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=storeMsix
```

The `storeInstaller` command is wired to the separate signed EXE candidate path,
but submission still requires protected signing, immutable hosting, metadata
approval, and certification gates. The `storeMsix` command remains only a
capability-policy build until its separate manifest, restricted-capability,
signing, package, WACK, and Store validation work is approved.

## Policy boundaries

- Do not use `kReleaseMode` as a distribution-channel selector.
- Do not infer Store behavior from package identity alone; the compile-time
  profile is authoritative and identity is a diagnostic cross-check.
- The profile foundation does not approve restricted MSIX elevation. `allowElevation`
  remains false for `storeMsix` until Microsoft approval is recorded.
- `UpdateService` and `InstallLifecycleService` own runtime lifecycle policy;
  the Store installer package/signing scripts own candidate production, while
  immutable hosting and Store publication remain release-owner work.
- `ExtensionPolicy` owns executable plugin provenance, gallery/dependency gates,
  imported-plugin configuration gates, and user-authored command/PowerShell
  policy. See [`extension-policy-contract.md`](extension-policy-contract.md).
