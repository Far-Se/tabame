# Windows automatic updates

Auto Update retains the existing `autoUpdate` preference. Users who already
enabled it get stable updates without another install prompt. Disabled users
can use **Check for Updates** to download and prepare a release explicitly.
The first release containing this updater must still be installed through the
old updater or installer; it cannot change code already shipped to users.

## User experience

- A running release build checks on startup, then every six hours. Failed
  network/download attempts retry after one hour. The schedule survives restarts.
- Downloads stream to a partial file. SHA-256, declared download size, GitHub's
  asset digest when supplied, archive paths, and packaged version are checked.
- A complete package waits on disk until the next normal Tabame launch.
  Opening Settings, the standalone launcher, recording, or another utility
  window does not trigger installation. There is no forced mid-session restart.
- Turning Auto Update off also prevents a previously staged automatic update
  from applying. A manually prepared update still applies on next launch.
- Other Tabame windows defer installation. The helper does not terminate an
  existing session or request administrator privileges. An app configured to
  run elevated follows its existing startup elevation flow first.
- The replacement app must render its first frame and initialize its window
  within two minutes. A handled replacement/startup failure restores backed-up
  app files and restarts the old version. That exact package is excluded from
  automatic retries; an explicit check can retry it, and a newer package can
  proceed automatically.

Portable ZIP and Inno installations use the same Windows ZIP payload, at the
existing executable path. Shortcuts, user settings, plugins, databases, and
installer/uninstaller files are preserved. Once a successful update records its
file inventory, later updates also remove obsolete files from that inventory.
Unknown files from older installations remain untouched.

## Publishing weekly releases

1. Increment `version` in `pubspec.yaml`, for example from `2.0.0` to `2.12.0`.
2. Publish an official release with the exactly matching tag, such as `v2.0.1`.
   Both Windows workflows reject mismatched tags. Do not reuse a stable version.
3. Let the existing workflow publish `tabame-v2.0.1-windows.zip` and its
   `.sha256` asset. Keep both assets on the release. The package verifier checks
   that the bundled version and replacement helper are included.
4. Mark the release as latest and keep it out of prerelease/draft status.
   Nightly builds do not enter this update channel. Windows assets can arrive
   after the release is created; clients retry incomplete publication later.

The client uses GitHub's [latest stable release endpoint](https://docs.github.com/en/rest/releases/releases#get-the-latest-release)
and exact Windows asset names. Version comparison is numeric, prevents
downgrades, and accepts the old `v2.0` notation as `2.0.0`. The bundled pubspec
provides the running version; there is no updater version string to bump by hand.

There is no external update backend or recurring installer interaction. Release
publication remains a maintainer action; this change does not schedule releases.

## State and recovery

State is isolated by installation path under
`%LOCALAPPDATA%\Tabame\updates\<installation-id>`:

| File                          | Purpose                                      |
| ----------------------------- | -------------------------------------------- |
| `schedule.json`               | Persistent network throttle                  |
| `package.part`, `package.zip` | Partial and verified payload                 |
| `pending.json`                | Versioned handoff descriptor (`schema: 1`)   |
| `update.lock`                 | Cross-process download/replacement exclusion |
| `journal.json`, `backup`      | File inventory and originals for rollback    |
| `installed-files.json`        | Last successfully managed application files  |
| `result.json`, `update.log`   | Installation outcome and helper diagnostics  |

Download errors go to the normal `errors.log`. All executable replacements
happen in the bundled Windows PowerShell helper, copied outside the managed payload
before handoff. Paths and arguments are passed as data. Its process launches use
[hidden windows](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.management/start-process),
and it rejects path traversal and reparse points before touching installation files.

A journal remaining after interruption is recovered on the next normal launch,
provided the application can still start. This is a file-copy transaction, not
an atomic directory swap: power loss or a concurrent external launch during
replacement can require reinstalling the release if Flutter cannot start at all.
Keep the journal and backup for diagnosis; installing the official setup over
the same directory restores the app without deleting its user data. Rollback
restores application files only, so release migrations must remain compatible
with the preceding version's user data.

SHA-256 detects damaged/mismatched downloads; it is not a publisher signature.
The trust boundary is the HTTPS GitHub repository and release permissions.
MSIX/Store installations use their platform updater. Debug builds do not replace
files. Linux and macOS automatic installation remain explicit platform stubs.

## Release acceptance checklist

Before rollout, exercise packaged release builds in a disposable Windows user
profile, for both a portable folder and an Inno installation:

- Enable Auto Update; publish a higher stable version; leave Tabame running and
  confirm the download completes without disrupting the session. Close all app
  windows and reopen: the new version appears without an update button.
- Disable the preference before download and after staging. Confirm no automatic
  application occurs. Explicitly prepare an update with it disabled and confirm
  that update applies on the next launch.
- Publish a nightly, a lower stable version, and an incomplete Windows release.
  Confirm there is no nightly installation, downgrade, or partial installation.
- Interrupt the network, corrupt the ZIP, fill the staging disk, and deny writes
  to the installation. Confirm the old installation is retained and errors are
  recorded without modal dialogs.
- Leave Settings or a recording window open and confirm replacement defers.
  Include spaces and apostrophes in the installation path and check startup with
  the existing administrator preference enabled.
- Fail the new app's startup before its acknowledgment. Confirm rollback,
  preservation of settings/plugins/databases, and suppression of automatic
  retries for the failed checksum.
- Remove a file from the next package and verify only previously managed files
  disappear. Verify installer uninstall still works after multiple updates.

These packaged acceptance checks are required before shipping; static analysis
alone cannot establish replacement, process-lifetime, or rollback behavior.
