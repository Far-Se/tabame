# macOS MVP permissions and signing

Tabame's macOS MVP targets **macOS 13 Ventura or newer** and is intended to
ship as both `arm64` and `x86_64` (preferably one universal app). Startup is
non-blocking: the launcher and settings shell remain usable when any TCC
permission is denied.

## Permission matrix

| Permission       | Used for                                                         | Detection/request                                                  | Reduced-mode fallback                                                                                        |
| ---------------- | ---------------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------ |
| Accessibility    | Activating/raising another app's window and future input actions | `AXIsProcessTrustedWithOptions` through the macOS platform channel | App launching and the visible Tabame window continue; window activation is disabled                          |
| Input Monitoring | Low-level input features and event-monitor based shortcuts       | `CGPreflightListenEventAccess` / `CGRequestListenEventAccess`      | The Phase 5 summon shortcut uses Carbon registration where possible; otherwise use the visible/manual window |
| Screen Recording | Complete cross-app window metadata and later capture features    | `CGPreflightScreenCaptureAccess` / `CGRequestScreenCaptureAccess`  | The app starts, but window titles/details may be incomplete and capture remains unavailable                  |
| Notifications    | Desktop notification delivery                                    | `UNUserNotificationCenter` settings/request API                    | In-app status text and no notification; the request is deferred until the first notification                 |

The in-app **macOS capabilities** panel explains each permission, reports its
current state, and opens the matching System Settings pane. It does not request
all permissions during startup. TCC state is user-controlled and can change
while Tabame is running; refresh the panel after changing a setting.

Clipboard monitoring is text-only in this phase. It polls the general pasteboard
for change-count updates and does not read rich formats or images. macOS may
show a pasteboard privacy prompt or return no text; that is treated as an
unavailable clipboard event, never as a startup error.

Window bounds and monitor/popup geometry are exposed as global logical points in
Cocoa's bottom-left coordinate space. Quartz window bounds are normalized by the
native adapter. Validate a permissioned build with Retina/non-Retina displays
and a second display positioned above and below the primary display; Screen
Recording denial is allowed to produce partial/empty window metadata.

## Keychain and migration behavior

The native runner creates one random 256-bit generic-password item in the
user's Keychain (`com.farse.tabame`, account `master-key-v1`). The Dart
`MacOSSecretStore` uses that key to encrypt machine-bound envelopes and plugin
secrets. The encrypted payload remains in Tabame's normal settings files so the
existing synchronous secret contracts remain compatible.

Windows DPAPI envelopes and `dpapi:v1:` fields cannot be decrypted by Keychain.
They are preserved and reported through `SecretStoreUnavailableException`; the
user must re-enter the value or perform an explicit password-based export. Do
not delete or overwrite those values automatically.

No Keychain access-group entitlement is required for the default app Keychain
item. Add `keychain-access-groups` only if a future helper/login item must share
the item, and keep the access group tied to the signed Team ID.

## Signing and entitlements

1. Keep the bundle identifier stable (`com.farse.tabame`) between builds. TCC
   grants are associated with the signed app identity and can be reset when the
   bundle identifier or signing identity changes.
2. Configure a real Apple Development identity for local permission testing and
   a **Developer ID Application** identity for outside-App-Store distribution.
   Replace the placeholder automatic-signing settings in Xcode with the team's
   signing team/profile before release.
3. The Runner target references `Runner/DebugProfile.entitlements` for debug
   and `Runner/Release.entitlements` for release. The checked-in profiles
   deliberately disable App Sandbox and enable network client/server access for
   the full utility backend: direct app-bundle discovery, cross-app window
   metadata/activation, plugin networking, and system-level integrations. The
   MVP therefore expects a signed Developer ID distribution rather than a Mac
   App Store sandbox. Accessibility, Input Monitoring, Screen Recording, and
   notification permissions are TCC grants; there is no entitlement that
   silently grants them.
4. For a hardened-runtime Developer ID build, enable hardened runtime in the
   release target and sign the final `.app` after Flutter embeds all frameworks.
   Inspect the result with:

   ```sh
   codesign --verify --deep --strict --verbose=2 build/macos/Build/Products/Release/tabame.app
   codesign -dvv --entitlements :- build/macos/Build/Products/Release/tabame.app
   spctl --assess --type execute --verbose build/macos/Build/Products/Release/tabame.app
   ```

5. Build both architectures (or a universal artifact) on macOS, then notarize
   the exact signed artifact. A typical outside-App-Store flow is:

   ```sh
   flutter build macos --release
   ditto -c -k --keepParent build/macos/Build/Products/Release/tabame.app tabame.zip
   xcrun notarytool submit tabame.zip --keychain-profile TABAME_NOTARY --wait
   xcrun stapler staple build/macos/Build/Products/Release/tabame.app
   ```

   The `TABAME_NOTARY` keychain profile must be created by the release owner;
   never commit Apple credentials or hard-code them in the repository.

6. If the app is later distributed through the Mac App Store, create a separate
   sandboxed entitlement profile and revalidate app-bundle discovery, icon
   reads, cross-app window metadata/activation, app launching, and Keychain
   access using security-scoped/LaunchServices APIs. Do not silently reuse the
   unsandboxed Developer ID profile for an App Store submission.

For a clean permission test, remove the old Tabame entry from each relevant
System Settings privacy list (or reset the app's TCC state), launch the newly
signed app, and grant only the rows being tested. Denial is a supported state,
not a failed installation.

## Phase 7 window watcher behavior

The launcher-facing window watcher uses the shared `WindowWatcherService` and
neutral `PlatformWindow` model. `PlatformWindow.nativeId` is an opaque token
owned by the adapter; shared code never parses it as a CGWindowID, HWND, or X11
ID. The Windows path is registered through `WindowsWindowService`; the macOS
path uses `MacOSWindowService`.

Screen Recording gates enumeration and Accessibility gates activation. If
Screen Recording is denied, the launcher hides the window-search shortcut and a
`.` query explains the missing capability. If Accessibility is denied, the
launcher keeps metadata actions but omits the focus action. macOS activation is
application-first and may not provide Windows-equivalent per-window behavior.

The shared watcher polls neutral snapshots because the current macOS channel has
no window-change event stream. Empty-title/off-screen entries are filtered and
opaque identities are deduplicated. Executable paths and icons remain optional
metadata; the legacy Windows taskbar/QuickSnap/workspace/layout surfaces retain
their Windows compatibility behavior until a later window-control pass. Linux
and Wayland files were not changed in this feature-family pass.
