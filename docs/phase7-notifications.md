# Phase 7 notifications migration

Status: implemented for Windows and Linux/X11

This phase migrates the desktop-notification delivery family only. Reminder
scheduling, quick timers, activity budgets, and launcher plugin commands keep
their existing trigger logic, but they now send a neutral
`NotificationRequest` through `NotificationCoordinator` instead of calling the
Windows utility directly.

## Contract and orchestration

`lib/platform/notification_service.dart` owns the platform-neutral contract:

- `NotificationRequest` contains only a title, body, and optional Dart click
  callback.
- `NotificationService` reports availability, click support, initialization,
  and best-effort delivery.
- `NotificationCoordinator` is the shared orchestration edge used by timers,
  reminders, activity budgets, plugin hosts, and the portable shell. Delivery
  failures become `false` rather than escaping from a timer or background
  plugin callback.

No notification request contains an `HWND`, `CGWindowID`, X11 ID, D-Bus object,
or native notification DTO.

## Platform behavior

| Behavior | Windows | Linux/X11 |
| --- | --- | --- |
| Delivery | `local_notifier` through `WindowsNotificationService` | `org.freedesktop.Notifications` over the session D-Bus through `LinuxNotificationService` |
| Capability | Advertised by the Windows adapter registration | Advertised only when the native capability probe finds a notification daemon |
| Click actions | Supported by the existing Windows toast backend | Intentionally unsupported in this phase; the request is fire-and-forget |
| Setup | Lazy and idempotent; the existing `ShortcutPolicy.requireCreate` behavior is preserved | Capability probing and delivery return an unavailable result when the session bus or daemon is missing |
| UI fallback | Existing Windows notification behavior remains available | The portable notification action and visual reminder option are disabled with the adapter reason; voice reminders remain available |

Linux notifications use the freedesktop notification service rather than an
X11 window ID or an X11-specific notification API. This is the intentional
Linux/X11 backend boundary for the supported Phase 6 X11 matrix. This phase
does not add or change Wayland policy.

The existing macOS notification adapter is not the target backend for this
migration and was not changed beyond consuming the extended neutral request
shape. macOS permission behavior remains documented in
[`macos-permissions.md`](macos-permissions.md).

Awake Guard's existing `Notify` automation remains a Windows message-box
fallback rather than being silently changed into a desktop toast; it is outside
the delivery call sites migrated here. Voice reminder speech likewise remains
its existing platform-specific implementation.

## Capability-gated UI

- The portable shell only enables **Test desktop notification** when both the
  service and `PlatformCapabilities.systemNotifications` are available.
- The reminder editor disables **Visual** reminders when the same capability is
  unavailable and leaves **Voice** reminders selectable.
- Linux capability changes refresh the portable shell so a daemon discovered
  after the first frame can enable the action without restarting the app.

## Focused regression coverage

`test/notification_service_test.dart` covers:

- neutral coordinator payload forwarding and failure containment;
- Windows adapter delegation, click support, and backend failure handling;
- Linux/X11 capability-gated delivery through a mocked platform channel;
- the explicit missing-notification-daemon reason.

The Linux native D-Bus call remains an integration boundary and is not required
for ordinary unit tests.
