# Elevation and privileged-action contract

- **Phase:** 4 — Elevation and privileged-action redesign
- **Status:** Implemented; desktop UAC validation remains outstanding
- **Selected first Store route:** `storeInstaller`
- **MSIX restricted capability:** `allowElevation` is not approved and remains disabled

## Integrity baseline

Tabame starts at normal user integrity by default. On profiles that allow
automatic elevation, users may enable **Settings → Advanced & Security →
Elevation → Elevated Permission**. The setting is persisted as
`runAsAdministrator`; on each primary Tabame launch it makes an explicit
`runas` request, then replaces the normal process with the elevated one while
preserving the requested page. UAC is still shown on every launch.

A cancelled or failed startup request leaves the current process running at
normal integrity. There is no retry loop or silent elevation. MSIX keeps
automatic and explicit elevation disabled until its restricted capability is
approved.

## Capability model

`ElevationService` is the UI-facing boundary. It reports both the profile
capability and the current token state:

| Profile          | Explicit elevation | `allowElevation` | Behavior                                                                       |
| ---------------- | ------------------ | ---------------- | ------------------------------------------------------------------------------ |
| `portable`       | available          | true             | Allow clearly labeled current-session actions and an opt-in elevated startup   |
| `storeInstaller` | available          | true             | Allow clearly labeled current-session actions and an opt-in elevated startup   |
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

| Action                                                 | Actual requirement                                                                            | Result in standard/medium session                                                        | MSIX behavior                                               |
| ------------------------------------------------------ | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------------------------------------- |
| Start with Windows                                     | Per-user shortcut or `StartupTask`; may use the separately opted-in elevation setting         | Starts normally by default; opted-in startup requests UAC                                | Uses the manifest `StartupTask`; elevation remains disabled |
| Restart Tabame elevated                                | Needed only when the user wants one elevated Tabame session                                   | Explicit UAC; accepted launch closes the old process, cancellation leaves it running     | Blocked with an explanation                                 |
| Launch selected file/app as Administrator              | A user-invoked ShellExecute `runas` action, not a Tabame startup requirement                  | Explicit UAC; cancellation/error is shown and the launcher remains usable                | Action is hidden/rejected                                   |
| Context Menu Cleaner registry write                    | Some merged or machine-scope keys may reject medium-integrity writes                          | Attempt remains explicit; access errors explain that an elevated session may be required | Elevation restart is unavailable                            |
| Focus/close/taskbar actions involving elevated windows | Many ordinary window operations work at medium integrity; protected targets may reject access | Keep existing fallback/reduced behavior; do not relaunch automatically                   | Keep medium-integrity fallback                              |
| Task Manager focus                                     | Ordinary focus can work, while protected Task Manager windows may require a fallback hotkey   | Use the existing Ctrl+Shift+Esc fallback when needed                                     | Same reduced behavior                                       |
| QuickSnap and screen overlays                          | No administrator requirement was established; these are ordinary window/capture actions       | Start the child process at the current non-elevated integrity                            | Available in medium-integrity reduced mode                  |

The launcher elevation path accepts an executable path and optional arguments for
that selected application. It does not accept shell snippets, PowerShell, `cmd`,
or arbitrary privileged commands.

## Failure and cancellation behavior

- A denied or cancelled UAC request returns an explicit `cancelled` result.
- The current Tabame process is not closed after cancellation or launch failure.
- A cancelled configured-startup request leaves the preference enabled for the
  next launch, while the current process continues normally.
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
- opt-in startup elevation capability by distribution profile;
- MSIX rejection while `allowElevation` is false.

Desktop validation is still required on the supported Windows baseline for
normal launch, opted-in shortcut startup, accepted UAC, cancelled UAC, denied
registry writes, and elevated-window reduced behavior.
