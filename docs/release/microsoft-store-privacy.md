# Tabame Microsoft Store privacy disclosure

**Status: release draft — product/legal review and a public URL are required
before Partner Center submission.**

- **Product:** Tabame
- **Distribution profile:** `storeInstaller`
- **Baseline:** Windows 10 22H2 (10.0.19045)+, x64
- **Canonical local data root:** `%LOCALAPPDATA%\Tabame`
- **Last repository review:** 2026-08-09

This document is the source for the Store privacy review. It describes the
implemented feature contracts, not a promise that Microsoft has pre-approved a
feature. The final listing must link to the approved public version of this
policy and must use the exact legal entity/contact selected by the owner.

## What Tabame stores or observes

Tabame is primarily a local Windows utility. The following table distinguishes
local observation from transmission. A feature is not started merely because
data exists in settings or an old portable installation.

| Surface | Data observed or stored | Default/consent | Transmission and retention |
| --- | --- | --- | --- |
| Settings and layout | Preferences, themes, hotkeys, window/layout choices, reminders, and local indexes | Required for the app; settings are created locally | Stored under `%LOCALAPPDATA%\Tabame` until changed or explicitly deleted; not sent by Tabame as analytics |
| Clipboard history | User-selected clipboard text and images, plus local history metadata | Off by default; the user enables, pauses, clears, or revokes it | Stored locally in the app-data/cache roots; no background collection while paused; the user must explicitly invoke any upload action |
| Screen capture, recording, and OCR | A selected screen region, an invoked capture, recording frames, or OCR input/output | Invoked by the user; background recording is not a Store startup default | Capture/recording output is local or user-selected; an upload is a separate action and the destination is shown by the feature |
| Activity/history features | Local activity records and usage caches created by enabled features | User enables the relevant feature | Retained locally until cleared or deleted; not a remote activity feed |
| Browser bridge | Pairing state and browser messages sent through a loopback connection | Off until the user enables and pairs it | Loopback only; pairing tokens are stored as secrets and excluded from exports/diagnostics; revoke stops the bridge and rotates pairing state |
| Vault/authenticator and music credentials | Passwords, OTP seeds, server credentials, and protected envelopes | User supplies the values to use the feature | Protected by the platform secret boundary/explicit password path; never included in plain-text exports or normal diagnostics |
| Logs | Error and native-service diagnostics | Created when needed for troubleshooting | Local `errors.log`; common token, authorization, credential, secret, and sensitive-value forms are redacted on write/read; user controls clearing/export |
| Plugins and extension data | Existing portable plugin folders/manifests may remain on disk | Executable plugins/gallery are disabled in the first Store release | Store build does not fetch, install, match, or execute executable plugin code; retained data is not automatically uploaded or deleted |
| File and window integration | File names, window metadata, taskbar/tray state, and process information needed for an invoked feature | Feature-specific consent or user invocation | Used locally to perform the requested action; not retained as a remote service dataset |

The app does not intentionally use a product analytics SDK in the reviewed
application surface. This statement is not a substitute for a dependency,
native-code, and release-build review; the security owner must re-check it for
every candidate.

## Optional network destinations

Some user-invoked features call external services. The user chooses the action
and should see the destination in the feature UI or its documentation. Examples
in the current product surface include weather data, currency conversion,
translation, music-server connections, sponsor content, browser integrations,
and image/screenshot upload services. These services may receive the request
content, query, image, or credentials necessary for the selected operation
according to their own policies. They are not required for the core launcher
shell.

The Store profile does not silently contact a plugin gallery, install a package
manager dependency, run an arbitrary downloaded script, or use a ZIP
self-update. Network failure leaves the core app in a reduced but usable mode.

## User controls and retention

- **Open data folder** opens the provider-selected data root.
- **Export settings** produces a redacted settings document; vault,
authenticator, DPAPI/Credential Manager values, browser pairing tokens, and
credential-shaped fields are excluded.
- **Clear cache** removes only cache and temporary data.
- **Delete all Tabame data** is an explicit destructive action and is separate
from installer uninstall.
- Installer uninstall removes managed binaries but preserves
  `%LOCALAPPDATA%\Tabame` unless the user separately deletes it.
- Users can disable startup, native integrations, clipboard history, browser
  bridge, and other consented features from the nearby settings/diagnostics
  controls.

## Store-edition limitations

The first installer-listed edition disables the plugin gallery, executable and
script plugin hosting, automatic npm/pip/bun dependency installation,
user-authored command templates, arbitrary PowerShell/cmd/Python/Node/Bun
execution, ZIP self-update, and custom in-app install/uninstall. Portable ZIP
behavior is not the Store privacy contract.

## Public policy and contact placeholders

These are proposed repository URLs until the product/legal owner approves the
final public policy and support host:

- Privacy URL: `https://github.com/Far-Se/tabame/blob/main/docs/release/microsoft-store-privacy.md`
- Support URL: `https://github.com/Far-Se/tabame/issues`
- License: `https://github.com/Far-Se/tabame/blob/main/LICENSE`

Before submission, confirm that the URLs are public, stable, reachable without
an account, and match the Partner Center listing. Add the legal entity, contact
method, retention jurisdiction, rights request process, and effective date to
the approved copy.
