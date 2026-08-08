# Phase 9 packaging and release runbook

Status: Phase 9 implementation

This is the release contract for the three supported desktop targets. The
packaging scripts are intentionally outside application feature code so a
release can be rebuilt from a clean checkout without changing runtime
behavior.

## Supported artifacts

| Target | Artifact | Baseline | Installation path | Upgrade path |
| --- | --- | --- | --- | --- |
| Windows | `tabame-nightly-windows.zip` for nightly builds; `tabame-v<version>-windows.zip` for official builds | Existing Windows workflow and Windows 10/11-era native integrations | Extract the ZIP and run `tabame.exe`; the existing `install.ps1` remains a local developer helper | Stop Tabame, extract the new ZIP over the existing install directory, and keep `%LOCALAPPDATA%\Tabame`; the existing workflow and tag semantics are unchanged |
| macOS Intel | `tabame-<version>-macos-x86_64.dmg` and matching ZIP | macOS 13 Ventura or newer, x86_64 | Open the DMG and copy `tabame.app` to `/Applications` | Replace the app bundle with the newer signed/notarized bundle; user data is outside the app bundle |
| macOS Apple Silicon | `tabame-<version>-macos-arm64.dmg` and matching ZIP | macOS 13 Ventura or newer, arm64 | Open the DMG and copy `tabame.app` to `/Applications` | Replace the app bundle with the newer signed/notarized bundle; user data is outside the app bundle |
| Linux | `tabame_<version>_<arch>.deb` for `amd64` and `arm64` | Ubuntu 22.04+ with GTK 3; X11 is the advanced integration target | `sudo apt install ./tabame_<version>_<arch>.deb` | Install the newer `.deb` with the same command; `dpkg` replaces `/opt/tabame` and preserves user data |

Linux AppImage and Flatpak are deliberately not release artifacts in Phase 9.
The `.deb` gives the MVP a package-manager-visible install, upgrade, and
uninstall lifecycle before another sandbox/runtime policy is added.

## Reproducible build recipe

All packaging starts from a clean checkout of the release commit. The CI uses
the stable Flutter channel, `pubspec.lock`, and the platform project files in
that checkout. `SOURCE_DATE_EPOCH` is set to the commit timestamp. The Linux
packager normalizes staged file timestamps and the CI rebuilds the `.deb` twice
with [`check-linux-reproducibility.sh`](../../tool/release/check-linux-reproducibility.sh)
and compares the bytes.

The Windows workflow passes the same commit timestamp to
[`package-windows.ps1`](../../tool/release/package-windows.ps1). It sorts ZIP
entries, assigns the fixed timestamp, and writes the existing ZIP/checksum
names. This changes only archive reproducibility; nightly/official release
selection, SQLite relocation, and publication behavior remain the same.

### Linux

```sh
flutter config --enable-linux-desktop
flutter pub get
flutter build linux --release -t lib/portable_main.dart
source_date_epoch="$(git log -1 --format=%ct)"
SOURCE_DATE_EPOCH="$source_date_epoch" \
  bash tool/release/package-linux-deb.sh \
    --bundle build/linux/x64/release/bundle \
    --version "$(awk '$1 == "version:" { print $2; exit }' pubspec.yaml)" \
    --arch amd64 \
    --source-date-epoch "$source_date_epoch"
```

The package installs the Flutter bundle under `/opt/tabame`, a launcher at
`/usr/bin/tabame`, the desktop entry at
`/usr/share/applications/tabame.desktop`, the icon in the hicolor icon tree,
and AppStream metadata. The package includes the native Flutter/SQLite assets
produced by the Linux build; it does not copy a developer machine's libraries.
The package declares the GTK/X11 runtime libraries that the current runner
requires.

Verify and smoke-test it without installing system-wide:

```sh
dpkg-deb --info dist/tabame_2.0.0_amd64.deb
bash tool/release/smoke-linux.sh \
  --package dist/tabame_2.0.0_amd64.deb \
  --no-launch

# On an X11-capable CI or desktop session, include the cold-start check:
xvfb-run -a dbus-run-session -- bash -c \
  'export XDG_SESSION_TYPE=x11; bash tool/release/smoke-linux.sh --package "$1"' \
  smoke dist/tabame_2.0.0_amd64.deb
```

### macOS

`macos/Runner/Release.entitlements` is the release entitlement profile and
`macos/Runner/Configs/Release.xcconfig` fixes the macOS 13 deployment target
and disables debug entitlement injection. Build one architecture on its
matching macOS runner, then package the completed app:

```sh
flutter config --enable-macos-desktop
flutter pub get
flutter build macos --release -t lib/portable_main.dart
bash tool/release/package-macos-dmg.sh \
  --app build/macos/Build/Products/Release/tabame.app \
  --version 2.0.0 \
  --arch arm64 \
  --output-dir dist
bash tool/release/smoke-macos.sh \
  --dmg dist/tabame-2.0.0-macos-arm64.dmg \
  --arch arm64
```

Unsigned DMGs are allowed for PR/build smoke jobs only. A tagged release must
provide all signing/notarization values to `.github/workflows/release-packaging-macos.yml`;
the job then imports the certificate, signs with hardened runtime, submits the
DMG to `xcrun notarytool`, staples the ticket, and runs the signed smoke check.
The required GitHub Actions secrets are:

| Secret | Purpose |
| --- | --- |
| `TABAME_APPLE_CERTIFICATE_P12_BASE64` | Base64 Developer ID Application certificate |
| `TABAME_APPLE_CERTIFICATE_PASSWORD` | Password for that P12 file |
| `TABAME_APPLE_KEYCHAIN_PASSWORD` | Temporary CI keychain password |
| `TABAME_MACOS_SIGNING_IDENTITY` | Exact `Developer ID Application: ...` identity name |
| `TABAME_APPLE_NOTARY_PRIVATE_KEY` | App Store Connect API `.p8` private key contents |
| `TABAME_APPLE_NOTARY_KEY_ID` | App Store Connect API key ID |
| `TABAME_APPLE_NOTARY_ISSUER_ID` | App Store Connect issuer ID |

The bundle identifier is `com.farse.tabame` and must remain stable. A signing
identity or bundle identifier change can invalidate existing TCC grants. Do
not commit certificates, API keys, provisioning profiles, or a populated
secret file. For local signing, import the certificate into a temporary
keychain and pass `--signing-identity`; use `--require-signed` to make a local
check fail instead of producing a smoke artifact.

## Windows release compatibility

`.github/workflows/windows-build.yml` remains the source of truth for Windows
release publication. Its behavior is preserved:

- `workflow_dispatch` still offers `nightly` and `official` release types.
- A `v*` tag still creates an official release named from that tag.
- A nightly build still moves the `Nightly` tag and uploads
  `tabame-nightly-windows.zip` plus its SHA-256 file.
- Official builds still upload `tabame-v<version>-windows.zip` plus its
  SHA-256 file.
- Existing MSIX/Store settings and the separate
  [`MICROSOFT_STORE_BUILD_GUIDE.md`](../../MICROSOFT_STORE_BUILD_GUIDE.md)
  remain unchanged.

Phase 9 only adds a package-layout/checksum smoke step using
[`verify-windows-package.ps1`](../../tool/release/verify-windows-package.ps1).
It does not replace the ZIP packaging, nightly tag movement, release naming,
or MSIX configuration.

## Logs and first-run diagnostics

Release-mode Dart and Flutter errors are appended to `errors.log` below the
platform-neutral `AppPaths` application root. The exact parent can vary with
the host's XDG/Apple known-folder policy, so support should use the paths shown
in the table as the normal locations and the in-app log export when available.

| Target | Normal log location | Permission/capability diagnostic |
| --- | --- | --- |
| Windows | `%LOCALAPPDATA%\Tabame\errors.log` | No OS permission grant is required for the portable shell. Windows-only actions may request elevation or depend on Explorer/Defender policy. |
| macOS | `~/Library/Application Support/<application-support-name>/Tabame/errors.log` | The portable shell shows **macOS capabilities** on first run when TCC grants are missing. Refreshing the panel re-probes Accessibility, Input Monitoring, Screen Recording, and Notifications and opens the matching System Settings pane. |
| Linux | `$XDG_DATA_HOME/tabame/Tabame/errors.log`, or `~/.local/share/tabame/Tabame/errors.log` when `XDG_DATA_HOME` is unset | The shell reports X11/Wayland mode and unavailable services. Missing session D-Bus, Secret Service, notifications, X11, or filesystem watches are reduced capabilities, not startup-fatal permissions. |

The log file can contain plugin and native-service details. Redact tokens,
paths, and plugin credentials before attaching it to a bug report. A log write
failure must never prevent startup.

### Required permissions and service dependencies

macOS permission states are user-controlled TCC grants:

- Accessibility: activating another app's window and future input actions.
- Input Monitoring: low-level event features and event-based shortcuts.
- Screen Recording: complete cross-app window metadata and future capture.
- Notifications: desktop notification delivery.

Tabame starts in reduced mode when any of these are denied. The permission
panel does not request every grant at startup. The macOS Keychain is used for
machine-bound secrets; Windows DPAPI data is not portable and must be re-entered
or explicitly exported through a password-based path.

Linux requires no privileged permission for the package or portable launcher.
The advanced window/hotkey/clipboard integration requires an X11 session. The
validated Wayland target is GNOME Shell/Mutter on Ubuntu 24.04 with a session
D-Bus; it deliberately disables X11-only capabilities and uses the visible
window as the summon fallback. Secret Service and notification availability is
reported at runtime and may depend on the user's desktop session.

Windows continues to use its existing native integrations and user data root.
The release ZIP is not an installer and does not silently request elevation;
the existing application behavior decides when administrator access is needed.

## Upgrade, migration, and uninstall checks

Run these checks for every release candidate. The application must be closed
before replacing an app bundle or package.

1. Start once from a clean user profile; confirm the launcher shell, settings,
   log creation, and the macOS/Linux capability diagnostic state.
2. Create a setting, a plugin value, a small file-index database, and a log.
   Upgrade using the target's documented path and confirm that all values remain.
3. Confirm SQLite `-wal`/`-shm` sidecars are retained or checkpointed before
   copying data. The path service never deletes the old root automatically.
4. On Windows, upgrade from `%LOCALAPPDATA%\Tabame` and confirm the existing
   ZIP install still reads settings and databases. The nightly and official
   workflows do not migrate or rename this directory.
5. On macOS and Linux, confirm the platform-native application-support/data
   root is retained across app replacement or `.deb` upgrade. Machine-bound
   DPAPI/Keychain/Secret Service values are not expected to decrypt on another
   OS; verify the explicit re-entry fallback instead.
6. Remove the application using the platform path: delete the extracted
   Windows directory, move the macOS app to Trash, or run `sudo apt remove
   tabame`. Uninstall must not delete the user data root unless the user
   explicitly chooses a separate data cleanup operation.
7. Reinstall the same artifact and repeat the cold-start, summon/hide, focus,
   monitor, sleep/wake, and log checks.

The focused migration checks already run in CI are
`test/app_paths_test.dart`, `test/secret_crypto_test.dart`, and the platform
contract tests selected by each release job. They complement, rather than
replace, the manual permission and desktop-session checks.

## Release smoke-test matrix

| Check | Windows | macOS | Linux X11 | Linux Wayland |
| --- | --- | --- | --- | --- |
| Artifact structure and checksum | `verify-windows-package.ps1` in `windows-build.yml` | `smoke-macos.sh`; `codesign` required on tags | `dpkg-deb`, AppStream, and `smoke-linux.sh` | Same package structure; portable bundle smoke under Weston |
| Cold start and clean shutdown | Package workflow layout check plus manual launch | DMG mount plus optional liveness launch | `xvfb-run` + session D-Bus liveness launch | `wayland-smoke.yml` runs the bundle under headless Weston |
| Summon/hide and focus restoration | Existing Windows workflow/manual desktop check | Manual permissioned desktop check; Carbon/manual fallback when denied | Manual X11 check with passive hotkey capability | Manual visible-window fallback; no global shortcut claim |
| Monitor changes and sleep/wake | Manual Windows desktop check | Manual Retina/non-Retina and above/below-display check | Manual multi-monitor X11 check | Compositor-managed placement only; restricted capability is expected |
| Settings migration and upgrade | `%LOCALAPPDATA%\Tabame` upgrade check | app replacement with support root retained | `.deb` upgrade with `/opt/tabame` replacement and data retained | Same reduced-mode data check |
| Permission/service denial | Elevation/Defender policy check | TCC denial and re-grant through diagnostics | missing D-Bus/Secret Service/notification check | X11 API denial/reduced-mode check |

The repeatable CI entry points are:

- `.github/workflows/windows-build.yml` for Windows nightly and official
  release paths.
- `.github/workflows/release-packaging-linux.yml` for native Linux amd64/arm64
  `.deb` builds, package checks, migration regression tests, and release asset
  upload.
- `.github/workflows/release-packaging-macos.yml` for macOS Intel/Apple Silicon
  DMG/ZIP builds, signing checks, and release asset upload.
- `.github/workflows/wayland-smoke.yml` for the reduced Wayland startup
  contract.

Desktop-session behavior that cannot be proven on a headless runner remains an
explicit manual release-candidate row. A release is not approved until those
rows are recorded against the artifact checksum in the release checklist.

## Known limitations

- Windows remains the only target with the full taskbar, foreign-tray, AppX,
  shell-context, capture/OCR, recording, and hardware-control integrations.
- macOS app/window activation and enumeration are permission-gated and
  application-first; they are not a Windows-equivalent taskbar model.
- Linux `.desktop` discovery, notifications, Secret Service, and X11 window or
  hotkey features depend on the user's desktop services. Wayland does not
  silently enable X11 behavior through XWayland.
- Linux release artifacts are currently architecture-specific; CI builds
  `amd64`. Additional architectures require a matching Flutter/CMake runner and
  a separate artifact smoke run.
- macOS signing/notarization cannot be completed without the release owner's
  Apple Developer ID certificate and App Store Connect credentials. Unsigned
  artifacts are for PR validation only.
- Signed/notarized Apple artifacts can contain Apple-generated signature and
  ticket timestamps. The recipe and inputs are fixed, while the Linux `.deb`
  has the stronger byte-for-byte reproducibility guarantee.
