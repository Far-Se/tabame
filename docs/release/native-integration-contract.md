# Native integration consent contract

- **Status:** Phase 7 implemented; Windows baseline and Store certification evidence remain outstanding
- **Route:** `storeInstaller`
- **Runtime owner:** [`NativeIntegrationCoordinator`](../../lib/services/native_integration_coordinator.dart)
- **Diagnostics page:** Interface → Capabilities

This contract makes consent and runtime capability state explicit without putting
native handles, clipboard content, browser tokens, or private paths into the
shared diagnostics payload. Portable builds keep their existing behavior unless
a caller explicitly requests consent; Store profiles require consent for the
high-risk integrations below.

## Lifecycle rules

1. Persistent integrations start only after the user has granted the named
   consent. A setting imported as `true` is not a Store consent grant.
2. One-shot actions use the action itself as the consent point and call
   `authorizeInvocation`; they do not start a background watcher.
3. Revocation closes the owned watcher/transport where the feature has one,
   clears or restores owned state where applicable, and leaves the launcher
   usable.
4. Native failures become `unavailable`, `blockedByPolicy`, or `error` status
   with a safe human-readable reason. Store browser-bridge failures do not
   enter an automatic retry loop.
5. A reduced mode is an intentional product state: manual summon, visible
   windows, ordinary taskbar behavior, and non-native launcher functions remain
   available when a native capability is denied.

## Integration matrix

| ID | Consent/disclosure | Reduced behavior | Revocation owner |
| --- | --- | --- | --- |
| `globalHooks` | System-wide hooks for configured shortcuts and input events | Visible/manual summon; configured hooks and mouse gestures remain stopped | Hotkey registration and gesture service |
| `windowAutomation` | Enumerates, activates, focuses, or previews other application windows | Launcher remains available without window list/activation | Window adapter |
| `inputInjection` | Synthesizes keyboard or pointer input | The named action is rejected; no helper retry | Input adapter |
| `shellIntegration` | Changes taskbar/Explorer presentation | Ordinary taskbar remains visible; failed changes do not update cached state | Taskbar controller and QuickMenu shutdown restore |
| `clipboardHistory` | Observes clipboard changes and retains selected formats locally | Panel remains visible with paused/unavailable state; no watcher starts | Clipboard history coordinator |
| `screenCapture` | Captures the selected screen region when invoked | Capture action returns no result without taking down the launcher | Windows capture adapter |
| `screenRecording` | Records screen pixels over time, including background Rewindly | Recording stays off when the backend fails or consent is revoked | Recording/Rewindly service |
| `ocr` | Processes a user-approved capture for text recognition | Capture/editor can remain usable without OCR | Windows OCR adapter |
| `contextMenu` | Reads or edits allow-listed Explorer context-menu registry entries | Existing context menu is left unchanged | Wizardly/context-menu UI |
| `processActions` | Enumerates or launches named process/system actions | Task Manager/shutdown and app enumeration are unavailable | Action-specific caller |
| `browserBridge` | Localhost browser pairing and requested browser actions | Transport is closed, token file is rotated on revoke, and Store failures stop retrying | Browser bridge service |
| `notifications` | Delivers user-requested desktop notifications | Existing in-app status/reminders remain best effort | Notification adapter |
| `quickSnap` | Observes supported window drags and moves selected windows | Manual snapping remains available when drag-trigger mode is denied | QuickSnap adapter |
| `audioControl` | Reads or changes selected audio endpoints | Audio controls report their adapter's unavailable state | Audio adapter |
| `backgroundCapture` | Stores activity history, including active-window metadata | Activity capture does not start; launcher remains usable | Trktivity caller |

## Diagnostics safety

`NativeIntegrationDiagnosticsSnapshot.toJson()` contains only profile, stable IDs,
labels, disclosure text, consent booleans, status, reduced-mode state, and
sanitized reasons. It deliberately excludes pairing tokens, clipboard values,
credentials, raw exception payloads, and absolute paths. Every newly added native
integration must use a stable ID and add its disclosure, reversible state, and
reduced behavior here before it is enabled in a Store profile.
