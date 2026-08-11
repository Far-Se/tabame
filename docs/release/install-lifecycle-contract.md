# Install, update, and uninstall lifecycle contract

- **Phase:** 5 — Install, update, and uninstall lifecycle
- **Status:** Runtime lifecycle boundary implemented; installer/signing work remains
- **Selected first Store route:** `storeInstaller`
- **Portable route:** Existing ZIP/GitHub behavior retained through a dedicated adapter

## Ownership model

`InstallLifecycleService` and `UpdateService` are the application-facing lifecycle
boundaries. UI and startup code must not copy the executable directory, expand a
ZIP over the running binary, register an uninstall command, or delete installed
files directly.

| Profile          | Install/upgrade owner       | In-app update behavior                                                                                  | In-app uninstall behavior                                             | App-data behavior                                                         |
| ---------------- | --------------------------- | ------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------- |
| `portable`       | User/extracted ZIP          | Existing GitHub ZIP check and self-update adapter remain available                                      | Existing explicit portable custom uninstall adapter remains available | Existing portable behavior is preserved                                   |
| `storeInstaller` | Signed Store-listed EXE/MSI | No GitHub ZIP check or ZIP install; report “Updates are delivered by the signed Store-listed installer” | Hide custom uninstall; Windows installer owns removal                 | Installer uninstall preserves `%LOCALAPPDATA%\\Tabame`                    |
| `storeMsix`      | Microsoft Store/MSIX        | No GitHub check or binary replacement; Store owns updates                                               | Hide custom uninstall; Store owns removal                             | Package app-data follows MSIX rules; user-created exports remain separate |

The Store profiles never call the portable adapter. Profile capability is the
compile-time policy gate; package identity is not used to enable portable
lifecycle behavior.

## Update contract

`UpdateService` owns:

- release metadata retrieval for the portable profile;
- version comparison and downgrade rejection;
- selection of a ZIP asset for the portable adapter;
- profile-managed, blocked, failed, and started results;
- safe version-derived temporary filenames.

`VersionPolicy` compares up to four numeric components after an optional `v`
prefix. It rejects invalid versions and refuses downgrades. `Nightly` is treated
as the current development stream, matching the previous portable behavior.

The portable adapter retains the existing ZIP-over-install-directory behavior
for compatibility. This is intentionally not available to either Store profile.
The signed installer candidate path is implemented separately in Phase 8;
immutable hosting and Store publication remain release-owner gates.

## Uninstall contract

`InstallLifecycleService.uninstall()` is the only UI-facing uninstall operation.
It returns a result instead of silently doing nothing when the profile is managed
by an installer or Store. The native portable adapter is defensive-gated as
well, so a Store build cannot delete its own installation even if an old caller
reaches the native helper.

The Store settings page exposes data-folder access, export, cache clearing, and
explicit data deletion independently from uninstall. Installer-owned uninstall
must not invoke **Delete all Tabame data**.

First-run setup contains no copy-install implementation, uninstall registration,
or download-and-expand helper. It starts with settings setup and never changes
the application binaries or installation location. If the executable is under a
system temporary directory, it shows a warning and blocks advancing until the
user relaunches Tabame from a permanent folder.

## Focused evidence

`test/install_lifecycle_service_test.dart` covers:

- portable versus installer-managed versus Store-managed capabilities;
- Store profiles blocking custom uninstall without invoking the adapter;
- portable uninstall delegation;
- installer data-retention policy;
- upgrade, same-version, downgrade, and invalid-version decisions.

Desktop validation remains required for clean install, upgrade, repair if
supported, uninstall/data retention, and portable ZIP compatibility. Signed installer production, Authenticode verification, and CI are implemented
in the Phase 8 candidate path; immutable hosting and Partner Center submission
remain release gates.
