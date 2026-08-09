# Start-with-Windows registration contract

- **Phase:** 3 — Start-with-Windows service
- **Selected first Store route:** `storeInstaller`
- **Startup task ID for future MSIX:** `TabameStartupTask`
- **Default:** disabled until the user opts in

## Service boundary

`StartupRegistrationService` is the only UI-facing startup API. Settings and
first-run setup no longer call the Windows shortcut functions directly. The
service reports one of:

- `enabled`;
- `disabled`;
- `disabledByUser`;
- `disabledByPolicy`;
- `unavailable`;
- `error`.

A system-controlled state is not overwritten. The UI shows the state/message and
opens `ms-settings:startupapps` when Windows or policy owns the setting.

Startup registration has no administrator preference. Enabling or disabling
login startup never changes process integrity, and the startup action never
requests UAC. Explicit elevation is a separate Phase 4 action for the current
session only.

## Profile behavior

| Profile          | Registration mechanism                             | Arguments                       | Fallback                                                        |
| ---------------- | -------------------------------------------------- | ------------------------------- | --------------------------------------------------------------- |
| `portable`       | Existing per-user Startup-folder `.lnk`            | `-quickmenu`                    | Report unavailable/error; no silent alternate registration      |
| `storeInstaller` | Existing per-user Startup-folder `.lnk`            | `-quickmenu`                    | Report unavailable/error; link to Windows Startup Apps settings |
| `storeMsix`      | Manifest `StartupTask` with ID `TabameStartupTask` | Manifest-defined app entrypoint | No Startup-folder shortcut fallback                             |

The shortcut adapter verifies the expected shortcut after an enable/disable
operation. It uses the current executable basename, explicit working directory,
and explicit `-quickmenu` arguments. It does not target the interface/settings
process.

The source MSIX manifest template is
[`packaging/windows/store-msix/Package.appxmanifest`](../../packaging/windows/store-msix/Package.appxmanifest).
It is not wired into the current ZIP workflow and still requires the exact
Partner Center identity, publisher, version, assets, and approved capabilities
before packaging.

## Native MSIX bridge

The Windows plugin exposes three operations for the packaged profile:

- `getStartupTaskState`;
- `requestEnableStartupTask`;
- `disableStartupTask`.

They call `Windows.ApplicationModel.StartupTask` on a WinRT MTA thread. Errors
are surfaced as unavailable/error states. The Dart adapter never silently falls
back to a shortcut when the task is absent or blocked.

## Test contract

`test/startup_registration_service_test.dart` covers the fake-adapter service
boundary, explicit quick-menu arguments, non-elevated startup, and user/policy-
controlled states. Desktop validation still needs manual sign-in,
sign-out, Windows Settings ownership, policy denial, shortcut duplicate cleanup,
executable upgrade, and MSIX StartupTask checks against the signed artifacts.
