# Elevation and privileged-action contract

- **Phase:** 4 — Elevation and privileged-action redesign
- **Status:** Implemented; desktop UAC validation remains outstanding
- **Selected first Store route:** `storeInstaller`
- **MSIX restricted capability:** `allowElevation` is not approved and remains disabled

## Integrity baseline

Tabame starts at normal user integrity on every distribution profile. A login
startup shortcut or future MSIX `StartupTask` launches the same non-elevated
process. There is no startup relaunch, `runas` retry, `-tryadmin` handshake, or
persistent administrator-mode preference.

The old `runAsAdministrator` setting is no longer read or written. Existing
stored values are ignored deliberately; they cannot cause a future login UAC
prompt. Users who need a privileged session must invoke the explicit action in
**Settings → Advanced & Security → Elevation**.

## Capability model

`ElevationService` is the UI-facing boundary. It reports both the profile
capability and the current token state:

| Profile          | Explicit elevation | `allowElevation` | Behavior                                                                       |
| ---------------- | ------------------ | ---------------- | ------------------------------------------------------------------------------ |
| `portable`       | available          | true             | Preserve the existing Win32 UAC mechanism, but only after a user action        |
| `storeInstaller` | available          | true             | Allow a clearly labeled current-session restart and selected-app UAC actions   |
| `storeMsix`      | disabled           | false            | Keep medium-integrity reduced mode; hide or reject elevation-dependent actions |

`allowElevation` is a policy input, not a runtime inference from package
identity. It must not be enabled for MSIX without a reviewed Microsoft approval.
No privileged helper or general-purpose elevated command runner was introduced.

## Privilege states

The Windows adapter distinguishes:

- **standard user:** not an administrator account and not elevated;
- **administrator account / medium integrity:** administrator-group membership is
  present, but the current token is not elevated and still requires UAC;
- **elevated:** the current process token is elevated;
- **unavailable:** privilege probing failed or Windows is not available.

Administrator-group membership is not used as a proxy for process elevation.
This prevents medium-integrity administrator sessions from being treated as
already privileged.

## Audited actions

| Action                                                 | Actual requirement                                                                            | Result in standard/medium session                                                        | MSIX behavior                              |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ------------------------------------------ |
| Start with Windows                                     | Per-user shortcut or `StartupTask`; no elevation                                              | Works without UAC                                                                        | Uses the manifest `StartupTask` only       |
| Restart Tabame elevated                                | Needed only when the user wants one elevated Tabame session                                   | Explicit UAC; accepted launch closes the old process, cancellation leaves it running     | Blocked with an explanation                |
| Launch selected file/app as Administrator              | A user-invoked ShellExecute `runas` action, not a Tabame startup requirement                  | Explicit UAC; cancellation/error is shown and the launcher remains usable                | Action is hidden/rejected                  |
| Context Menu Cleaner registry write                    | Some merged or machine-scope keys may reject medium-integrity writes                          | Attempt remains explicit; access errors explain that an elevated session may be required | Elevation restart is unavailable           |
| Focus/close/taskbar actions involving elevated windows | Many ordinary window operations work at medium integrity; protected targets may reject access | Keep existing fallback/reduced behavior; do not relaunch automatically                   | Keep medium-integrity fallback             |
| Task Manager focus                                     | Ordinary focus can work, while protected Task Manager windows may require a fallback hotkey   | Use the existing Ctrl+Shift+Esc fallback when needed                                     | Same reduced behavior                      |
| QuickSnap and screen overlays                          | No administrator requirement was established; these are ordinary window/capture actions       | Start the child process at the current non-elevated integrity                            | Available in medium-integrity reduced mode |

The launcher elevation path accepts an executable path and optional arguments for
that selected application. It does not accept shell snippets, PowerShell, `cmd`,
or arbitrary privileged commands.

## Failure and cancellation behavior

- A denied or cancelled UAC request returns an explicit `cancelled` result.
- The current Tabame process is not closed after cancellation or launch failure.
- Profile-blocked actions return a `blocked` result with the capability reason.
- Native launch failures return a `failed` result with a Windows error/code
  message suitable for the UI.
- No retry loop or silent fallback to automatic elevation is permitted.

## Tests

`test/elevation_service_test.dart` covers:

- standard-user explicit restart;
- administrator account at medium integrity;
- already elevated session;
- cancelled UAC without closing the current process;
- MSIX rejection while `allowElevation` is false.

Desktop validation is still required on the supported Windows baseline for
normal launch, opted-in shortcut startup, accepted UAC, cancelled UAC, denied
registry writes, and elevated-window reduced behavior.
