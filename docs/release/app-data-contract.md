# Tabame app-data contract

- **Phase:** 2 — App-data model and migration
- **Status:** Implemented for the `portable` and selected `storeInstaller` routes
- **Canonical `storeInstaller` root:** `%LOCALAPPDATA%\\Tabame`
- **Canonical `storeMsix` roots:** `ApplicationData.Current.LocalFolder`,
  `LocalCacheFolder`, and `TemporaryFolder`
- **Migration marker:** `.tabame-data-migration.json`, version `1`

## Provider rules

All app-owned paths are selected through `AppPaths`. Callers may resolve a path
for reading, which can temporarily fall back to the legacy Windows root, or
resolve a path for writing, which always selects the canonical provider root.
Database paths are always canonical because SQLite writes WAL/SHM sidecars beside
the database.

The first Store route is `storeInstaller`, so it deliberately retains the
existing `%LOCALAPPDATA%\\Tabame` root. The installer owns binaries and lifecycle;
`InstallLifecycleService` exposes that ownership to the app without allowing
Store profiles to mutate installed files. Tabame owns data below that root.
Uninstall must preserve the root unless the user explicitly chooses **Delete all
Tabame data** in the maintenance UI.

For a future `storeMsix` build, the Windows native bridge resolves the three
package-managed folders through `Windows.Storage.ApplicationData`. The physical
package-family path is never constructed in Dart. A missing provider is a hard
initialization error for `storeMsix`, rather than silently writing to an
unmanaged location.

## Classification

| Location or data                                                                                    | Classification                         | Provider path                                  | Retention/handling                                                                       |
| --------------------------------------------------------------------------------------------------- | -------------------------------------- | ---------------------------------------------- | ---------------------------------------------------------------------------------------- |
| `settings/settings.json`, `.bk`, `reload.signal`                                                    | Settings                               | `AppPaths.settingsPath()`                      | Durable; writes use canonical root; backup is last-known-good recovery data              |
| `views.json`, capture/draw/recording JSON, music server/preferences JSON, authenticator/vault files | Durable app data / secrets             | `AppPaths.settingsPath()`                      | Durable; secret stores use DPAPI or an explicit password/re-entry path                   |
| `file_index.db`, `music_library.db`, `-wal`, `-shm`                                                 | Durable app data                       | `AppPaths.databasePath()`                      | Durable; migrate the database and sidecars together; never rename SQLite DLLs at runtime |
| `cache/**`, clipboard history/images, icon/artwork/backdrop caches, usage cache                     | Cache                                  | `AppPaths.cachePath()`                         | Disposable; **Clear cache** removes only this class                                      |
| Temporary capture, update, plugin staging, image-processing files                                   | Temporary                              | `AppPaths.temporaryPath()`                     | Disposable; host/provider temporary folder; never used as durable settings storage       |
| `plugins/**`, `.tabame-store.json`, dependency folders                                              | Plugin/extension data                  | `AppPaths.pluginsPath()`                       | Portable may retain/use it; first Store release does not execute executable plugins      |
| `errors.log`, debug/CPP/FFmpeg logs                                                                 | Log                                    | `AppPaths.currentPath()`                       | Durable until cleared; new writes and reads redact common credential forms               |
| `fancyshot/**`, `rewindly/**`, `trktivity/**`, project/script outputs                               | User-created output / durable app data | `AppPaths.currentPath()` or explicit user path | Preserve on installer uninstall; do not remove during cache clearing                     |
| Browser bridge configuration                                                                        | Secret / durable app data              | `AppPaths.currentPath('browser-bridge.json')`  | Pairing token is not included in exports or diagnostics                                  |
| DPAPI/Credential Manager entries                                                                    | Secret                                 | Windows secret-store boundary                  | Machine/user-bound; never plaintext-exported; re-entry required when unavailable         |

External paths such as Start Menu, Startup, Desktop, Downloads, Pictures,
`%APPDATA%`, and user-selected capture/plugin folders are not app-owned roots.
They remain explicit user/system locations and are not deleted by Tabame data
cleanup.

## Migration contract

Migration from the legacy root is non-destructive and versioned:

1. If source and canonical roots are equal, no migration is required.
2. If a version-1 complete marker exists, migration is skipped as already done.
3. Missing files are copied into a disposable staging directory first; existing
   canonical files are never overwritten.
4. SQLite database files and their `-wal`/`-shm` siblings are copied as ordinary
   files and retain their relative names.
5. Staged files are moved into canonical locations only after each copy exists.
6. A complete marker is written only after all source files are processed.
7. A copy failure records an `incomplete` marker, preserves both source and
   canonical data, discards staging on the next retry, and retries on startup.
8. The legacy root is never deleted automatically.

The migration intentionally treats canonical data as authoritative when a
legacy/canonical conflict exists. This makes upgrades repeatable and avoids
replacing newer user data with an older copy.

## Export, logs, cache, and deletion

- **Open data folder** opens `AppPaths.root`, not a reconstructed Windows path.
- **Export settings** writes a `tabame-settings-export` JSON document containing
  preferences after redacting password, token, API-key, authorization,
  credential, secret, and embedded JSON credential fields. Authenticator, vault,
  DPAPI, Credential Manager, and browser pairing files are not exported.
- **Logs** redact the same common credential forms when written and when read.
  Existing raw logs are redacted at read time; clearing removes both legacy and
  canonical error logs.
- **Clear cache** removes only the provider cache root and recreates it.
- **Delete all Tabame data** is a separate explicit action. It removes the
  app-owned root and provider cache, but it is not invoked by installer
  uninstall automatically.

## Focused evidence

`test/app_paths_test.dart` covers:

- clean installation with no legacy data;
- existing settings, database, and WAL/SHM sidecars;
- versioned migration completion;
- partial migration failure and retry;
- canonical-versus-legacy upgrade conflicts;
- injected MSIX provider locations on Windows;
- legacy read fallback versus canonical write paths;
- deliberate plugin-folder moves.

The export and redaction tests cover secret-key removal, embedded JSON values,
Bearer headers, OTP secrets, and safe settings export. Packaging checks require
`sqlite3.dll` beside `tabame.exe`; runtime code performs no DLL rename or write.
