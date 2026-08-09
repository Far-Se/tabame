# Microsoft Store feature contract

- **Status:** Phase 7 native integration consent/reduced-mode implementation aligned; broader Store validation remains outstanding
- **Route:** `storeInstaller`
- **Baseline:** Windows 10 22H2 (10.0.19045)+, x64
- **First-release plugin decision:** all executable plugin sources and the plugin gallery are disabled
- **Related decision:** [`ADR 0001`](../decisions/0001-store-distribution-route.md)
- **Related extension policy:** [`extension-policy-contract.md`](extension-policy-contract.md)

This contract turns the current Windows feature surface into explicit Store
behavior. “Allowed” means the feature may ship in the installer-listed Store
edition only after its named test passes; it is not a claim that Microsoft has
pre-approved the feature. “Disabled” means it is not present or executable in
the first Store release. Portable ZIP behavior is not changed by this document.

## Contract rules

1. The main process starts at normal user integrity. No feature may silently
   relaunch it with `runas` at login.
2. Sensitive behavior is off by default where the current setting permits it and
   is enabled only from a clearly labeled user action or setting.
3. Consent must identify what system state or other applications are affected.
   Denial or policy failure leaves the launcher usable and reports a reduced
   capability rather than retrying silently.
4. Store binaries are treated as immutable. The Store edition must not overwrite
   its executable directory or remove itself with a custom script.
5. User data remains under `%LOCALAPPDATA%\\Tabame` for the installer route.
   Settings export, data-folder access, and deliberate cleanup are separate
   user actions; secrets are not included in plain-text exports or logs.
6. No feature is classified as “probably supported”. The table is the release
   contract; anything not listed is disabled or must be added by a reviewed
   contract amendment.

## Feature matrix

| Feature / current surface                        | Default state                                                                                                                                 | Consent point                                                                                                 | Store availability                                                                                                           | Reduced-mode behavior                                                                                                                                               | Required disclosure                                                                                                                    | Test case                                                                                                                     |
| ------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- |
| Start with Windows                               | Off by default; current implementation uses a per-user Startup `.lnk`                                                                         | User enables the setting; must be reversible                                                                  | **Allowed** via per-user Startup-folder shortcut or HKCU Run; never elevated                                                 | If registration is blocked, show unavailable/error state and link to Windows Startup settings                                                                       | “Starts Tabame when you sign in”; show enabled/disabled state                                                                          | `STORE-START-01`: opt in, sign out/in, disable, verify no UAC prompt and no duplicate entry                                   |
| Administrator-only actions / elevation           | No persistent admin mode; normal and login-startup launches are medium-integrity                                                              | User invokes **Restart elevated for this session** or a named selected-app action                             | **Allowed with redesign** for `storeInstaller`; explicit UAC only for the selected operation/session                         | Continue at standard integrity; disable or hide the individual action if elevation is denied; `storeMsix` remains disabled because `allowElevation` is not approved | Explain why elevation is needed, that it affects only the requested operation/session, and that cancellation leaves Tabame running     | `STORE-ELEV-01`: standard start, medium-integrity administrator account, accept/deny/cancel UAC, verify no automatic relaunch |
| Global keyboard and mouse hooks                  | Off until the named shortcut/gesture is configured and consented; no hook is constructed by adapter startup                                   | User enables the relevant hotkey/gesture/monitoring setting or grants first-run consent                       | **Allowed with consent and certification review**                                                                            | Use visible/manual summon and disable the affected shortcut/gesture when hooks fail                                                                                 | State that Tabame observes specified global input to provide the enabled action; never claim keystroke privacy beyond the actual scope | `STORE-HOOK-01`: enable/disable, deny/block via policy where possible, verify startup and manual fallback                     |
| Input suppression and injection                  | Block-keyboard and synthetic-input actions are user-invoked, not launcher startup behavior                                                    | User presses the named action and confirms any destructive/temporary mode                                     | **Allowed only as explicit actions**; no background injection                                                                | Hide/disable the action if the native API fails; never emulate with an unbounded helper                                                                             | Identify target scope, duration, and escape/cancel path                                                                                | `STORE-INPUT-01`: invoke block/injection, cancel, verify target-only behavior and recovery after failure                      |
| Taskbar controls and shell integration           | Taskbar hiding is off by default; taskbar-level placement, badges, tray, pinned-app and Explorer integration are exposed in the Windows UI    | User enables each setting/action; shell changes require confirmation                                          | **Allowed with explicit consent**; subject to certification and Windows-version validation                                   | Keep the normal taskbar visible and use an ordinary Tabame window if shell APIs are unavailable; restore the prior state on disable/exit                            | Explain that Tabame changes taskbar/Explorer presentation and may affect other windows                                                 | `STORE-SHELL-01`: toggle each supported shell action, restart Explorer/policy failure, verify restoration on exit             |
| Context-menu tools and registry edits            | Not a startup requirement; invoked from context-menu/settings tools                                                                           | User selects the exact registry/context-menu operation and confirms                                           | **Allowed only as opt-in, allow-listed operations**; no broad registry editor                                                | Hide the operation and leave the existing context menu unchanged if access is denied                                                                                | Identify affected registry scope and provide restore/undo behavior                                                                     | `STORE-CONTEXT-01`: apply, undo, deny standard-user access, restart Explorer, verify only selected entries change             |
| Plugin gallery and downloaded executable plugins | Current launcher supports user-installed script/executable plugin folders                                                                     | No consent is sufficient for first release; all executable extension sources are policy-disabled              | **Disabled in first Store release**                                                                                          | Hide gallery/install controls; built-in launcher remains available; no gallery network fetch or ZIP/file install                                                    | State that third-party executable extensions are unavailable in this edition                                                           | `STORE-PLUGIN-01`: clean install has no gallery/install path; gallery fetch/install cannot reach network or disk              |
| Existing local plugin data                       | Plugin storage exists under the app data root and may contain executable code                                                                 | No automatic execution or migration into the Store edition                                                    | **Disabled for executable hosting**; preserve data without running it                                                        | Keep manifests/folders for retention UX; imported `enabled: true` cannot enter keyword matching or start a process                                                  | Warn that portable plugins are not supported by the Store edition                                                                      | `STORE-PLUGIN-02`: pre-populate plugin folder, install Store build, verify no process starts, config is not executed/deleted  |
| ZIP self-update                                  | Auto-update setting exists and current updater expands a ZIP beside the executable                                                            | No automatic consent can make mutable self-update acceptable                                                  | **Disabled**; updates are delivered by the installer/Store listing                                                           | Hide or disable update/install controls; show current version and supported update path                                                                             | “Updates are delivered by the Store-listed installer”; do not offer unsigned ZIP replacement                                           | `STORE-UPDATE-01`: update check cannot overwrite install directory or launch an unsigned replacement                          |
| Custom install and uninstall                     | First-run and Win32 helpers copy/delete install files and manage registry entries                                                             | User starts installer lifecycle outside the app                                                               | **Disabled in app**; installer owns install/upgrade/uninstall                                                                | Remove/disable custom lifecycle UI; preserve `%LOCALAPPDATA%\\Tabame` unless user separately deletes it                                                             | Explain what uninstall removes and what user data is retained                                                                          | `STORE-LIFE-01`: install/upgrade/uninstall through installer, verify binaries/lifecycle and data retention                    |
| Screen capture and screen recording              | One-shot capture/record actions are off until invoked; background recording is off by default and never starts from a persisted Store setting | User invokes capture/record; upload requires a separate explicit action                                       | **Allowed with consent, privacy disclosure, and certification review**                                                       | Keep launcher usable; disable the capture/record action if the OS/API/policy blocks it; no Rewindly capture on denied startup                                       | Explain that selected screen contents and optional recordings are captured; disclose upload destination before upload                  | `STORE-CAPTURE-01`: capture selected region, cancel, record/stop, deny/block capability, verify no capture at startup         |
| OCR and screen-derived text                      | OCR is exposed from capture/quick actions                                                                                                     | User invokes OCR on a selected capture/region                                                                 | **Allowed with explicit invocation**; no background screen reading                                                           | Keep capture/editor available where possible; disable OCR if unavailable                                                                                            | Explain that the selected image/region is processed for text recognition                                                               | `STORE-CAPTURE-02`: OCR only selected region, verify no processing before invocation and graceful failure                     |
| Clipboard monitoring and history                 | Off by default; the coordinator starts only after the user enables history and can pause/revoke it                                            | User enables clipboard history/monitoring and can pause/clear it                                              | **Allowed with explicit opt-in and privacy disclosure**                                                                      | Launcher works without monitoring; keep the panel visible with a paused/unavailable state                                                                           | Explain what formats are retained, where they are stored, retention/clear controls, and that secrets may be copied by the user         | `STORE-CLIP-01`: opt in, copy text/image, pause, clear, restart, verify no capture while paused                               |
| Browser bridge                                   | Off by default; a persisted setting cannot start the loopback transport without a named consent grant                                         | User enables/connects the browser extension or bridge; pairing/token flow required                            | **Allowed as a local opt-in bridge**; no remote listener or silent browser collection                                        | Launcher works without bridge; show disconnected state, rotate pairing state on revoke, and stop accepting requests after disable                                   | Explain localhost communication, browser data exchanged, extension permissions, and token handling                                     | `STORE-BROWSER-01`: enable/pair, send one supported request, disable, verify port/token cleanup and no data without pairing   |
| External runtimes and system commands            | Current surface can launch `cmd.exe`, PowerShell, Task Manager, shutdown, and plugin runtimes; some helpers use external processes            | User invokes a named built-in action; arbitrary command/plugin execution is not consented by a generic prompt | **Built-in allow-listed actions only**; arbitrary PowerShell/cmd/Python/Node/Bun/npm/pip execution disabled in Store edition | Hide unavailable commands; reject imported custom command templates and script targets; never fall back to a general command runner                                 | Name the exact action, target, and system effect; disclose external process launch                                                     | `STORE-EXEC-01`: fixed actions work; imported Run Command/custom uploader/script target is rejected                           |

## Phase 7 implementation alignment

The implementation records native integration consent separately from ordinary
feature settings through [`native-integration-contract.md`](native-integration-contract.md).
The Interface → Capabilities page reports safe status, consent, disclosure, and
reduced-mode reasons for each native integration. Clipboard history, browser
loopback, global hooks, QuickSnap drag triggers, taskbar visibility, window
automation, process actions, context-menu tools, screen capture/OCR, and
background recording all fail closed or reduce to visible/manual behavior when
consent, Windows policy, or the native backend is unavailable.

The Store profile treats imported `true` settings as data, not as consent. A
user-invoked capture/action may record its own consent point, while persistent
watchers and background recording require an explicit grant and have a nearby
revoke path. Diagnostics exclude clipboard content, pairing tokens, credentials,
and raw absolute paths.

## Store edition exclusions at launch

The first Store edition must not expose or execute:

- the plugin gallery or any downloaded executable/script plugin hosting;
- automatic npm/pip/bun dependency installation for extensions;
- user-authored command templates, custom PowerShell uploaders, or implicit script execution;
- ZIP self-update or unsigned replacement of installed binaries;
- custom in-app install, uninstall, or deletion of the executable directory;
- automatic or silent administrator relaunch at startup;
- a general-purpose PowerShell, `cmd.exe`, Python, Node, Bun, npm, or pip
  command runner.

These exclusions are deliberate product behavior, not merely packaging notes.

The source classification, registry/host/gallery gates, imported-configuration
behavior, and user-command boundary are documented in the
[`extension-policy-contract.md`](extension-policy-contract.md).

## Validation and evidence requirements

Before submission, each `STORE-*` test must be run on the supported Windows
baseline and recorded against the signed installer/artifact hash. The release
matrix must additionally cover clean install, upgrade from an existing portable
`%LOCALAPPDATA%\\Tabame` root, uninstall/data retention, standard-user start,
UAC denial, Windows policy/Defender interference, multiple monitors, sleep/wake,
Explorer restart, and offline operation.

Certification, privacy, and security owners must review the disclosures for
hooks, input, shell changes, capture/recording, clipboard, browser bridge, and
external process actions. Passing a local test does not waive Microsoft Store
policy or certification review.

## Future amendments

A feature may move from **Disabled** or **Allowed with redesign** only through a
new reviewed contract entry that names its default, consent, data behavior,
reduced mode, disclosure, and test. A future `storeMsix` edition requires a
separate capability matrix because package identity, read-only files, startup,
elevation, app-data, and update semantics differ from this installer route.
