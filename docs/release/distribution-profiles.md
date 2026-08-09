# Distribution profile build contract

- **Phase:** 1 — Distribution profile foundation
- **Status:** Foundation plus elevation/lifecycle boundaries implemented; packaging and publication unchanged
- **Default:** `portable`
- **Define:** `TABAME_DISTRIBUTION_PROFILE`

The profile is compile-time configuration. An unknown value fails during startup;
no value selects the safe `portable` profile. Runtime package identity is checked
on Windows and logged as a diagnostic when it does not match the selected
profile. A mismatch does not crash the portable development process. Normal
startup is non-elevated for every profile; explicit elevation is governed by the
Phase 4 elevation service and the `allowElevation` capability.

## Profiles

| Profile          | Intended artifact                               | Package identity | Update/lifecycle policy                                                                                                            |
| ---------------- | ----------------------------------------------- | ---------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| `portable`       | Existing ZIP/GitHub build                       | Unpackaged       | Existing ZIP self-update and custom lifecycle remain available; elevation is explicit                                              |
| `storeInstaller` | Future signed EXE/MSI listed in Microsoft Store | Unpackaged       | Installer owns lifecycle; self-update, custom install, and custom uninstall disabled; explicit UAC is available                    |
| `storeMsix`      | Future Store-hosted MSIX                        | Required         | Store owns updates/uninstall; package app-data and StartupTask are required; elevation is disabled until `allowElevation` approval |

`storeInstaller` is the selected first Store route. The current CI still
publishes the portable ZIP; this phase does not change release publication or
create an installer/MSIX artifact.

## Local commands

From the project root, after dependencies are available:

```text
# Safe default; equivalent to omitting the define.
flutter build windows --release

# Explicit portable profile.
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=portable

# Validate the future installer-listed Store behavior without packaging it.
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
pass a distribution define and publishes a ZIP. When profile builds are added in
a later packaging phase, CI must pass the define explicitly rather than relying
on `kReleaseMode` or executable paths:

```text
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=portable
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=storeInstaller
flutter build windows --release --dart-define=TABAME_DISTRIBUTION_PROFILE=storeMsix
```

The `storeInstaller` command is only a profile build until signing, immutable
hosting, installer packaging, and Store listing work is completed. The
`storeMsix` command is only a capability-policy build until manifest, restricted
capability, signing, package, WACK, and Store validation work is approved.

## Policy boundaries

- Do not use `kReleaseMode` as a distribution-channel selector.
- Do not infer Store behavior from package identity alone; the compile-time
  profile is authoritative and identity is a diagnostic cross-check.
- The profile foundation does not approve restricted MSIX elevation. `allowElevation`
  remains false for `storeMsix` until Microsoft approval is recorded.
- `UpdateService` and `InstallLifecycleService` own runtime lifecycle policy;
  packaging, signing, installer artifact production, and Store publication remain
  later release work.
- `ExtensionPolicy` owns executable plugin provenance, gallery/dependency gates,
  imported-plugin configuration gates, and user-authored command/PowerShell
  policy. See [`extension-policy-contract.md`](extension-policy-contract.md).
