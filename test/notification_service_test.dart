import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/linux/linux_notification_service.dart';
import 'package:tabame/platform/linux/linux_platform_channel.dart';
import 'package:tabame/platform/notification_service.dart';
import 'package:tabame/platform/windows/windows_notification_service.dart';
import 'package:tabame/services/notification_coordinator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('coordinator forwards a neutral request and contains delivery failures', () async {
    final NotificationService previous = NotificationService.instance;
    final _FakeNotificationService service = _FakeNotificationService();
    NotificationService.register(service);
    addTearDown(() => NotificationService.register(previous));

    expect(
      await NotificationCoordinator.instance.show(
        title: 'Title',
        body: 'Body',
      ),
      isTrue,
    );
    expect(service.requests.single.title, 'Title');
    expect(service.requests.single.body, 'Body');

    service.shouldThrow = true;
    expect(
      await NotificationCoordinator.instance.show(
        title: 'Failure',
        body: 'Is recoverable',
      ),
      isFalse,
    );
  });

  test('Windows adapter delegates neutral requests and exposes click support', () async {
    final _FakeWindowsNotificationBackend backend = _FakeWindowsNotificationBackend();
    final WindowsNotificationService service = WindowsNotificationService(backend: backend);
    final NotificationRequest request = NotificationRequest(
      title: 'Windows title',
      body: 'Windows body',
      onClick: () {},
    );

    expect(service.isAvailable, isTrue);
    expect(service.supportsClick, isTrue);
    expect(await service.initialize(), isTrue);
    expect(await service.show(request), isTrue);
    expect(backend.initializeCalls, 1);
    expect(backend.requests.single.title, 'Windows title');
    expect(backend.requests.single.body, 'Windows body');

    backend.shouldThrow = true;
    expect(await service.show(request), isFalse);
  });

  test('Linux X11 adapter forwards a freedesktop notification request', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/linux/notifications');
    final LinuxPlatformChannel channel = LinuxPlatformChannel(
      methodChannel: methodChannel,
      eventChannel: const EventChannel('tabame/test/linux/notification-events'),
      available: true,
    );
    final List<String> calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'capabilities':
            return <String, dynamic>{
              'displayServer': 'x11',
              'x11': true,
              'notifications': true,
            };
          case 'showNotification':
            expect(call.arguments, <String, dynamic>{'title': 'Linux title', 'body': 'Linux body'});
            return true;
          default:
            return null;
        }
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null),
    );

    final LinuxNotificationService service = LinuxNotificationService(channel: channel);
    expect(await service.show(const NotificationRequest(title: 'Linux title', body: 'Linux body')), isTrue);
    expect(service.isAvailable, isTrue);
    expect(service.supportsClick, isFalse);
    expect(calls, <String>['capabilities', 'showNotification']);
  });

  test('Linux adapter returns an explicit unavailable result without a daemon', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/linux/notifications-missing');
    final LinuxPlatformChannel channel = LinuxPlatformChannel(
      methodChannel: methodChannel,
      eventChannel: const EventChannel('tabame/test/linux/notification-missing-events'),
      available: true,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async {
        if (call.method == 'capabilities') {
          return <String, dynamic>{
            'displayServer': 'x11',
            'x11': true,
            'notifications': false,
            'notificationsReason': 'No notification daemon is running.',
          };
        }
        return null;
      },
    );
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(methodChannel, null),
    );

    final LinuxNotificationService service = LinuxNotificationService(channel: channel);
    expect(await service.show(const NotificationRequest(title: 'Title', body: 'Body')), isFalse);
    expect(service.unavailableReason, 'No notification daemon is running.');
  });
}

class _FakeNotificationService extends NotificationService {
  final List<NotificationRequest> requests = <NotificationRequest>[];
  bool shouldThrow = false;

  @override
  bool get isAvailable => true;

  @override
  bool get supportsClick => true;

  @override
  String get unavailableReason => '';

  @override
  Future<bool> initialize() async => true;

  @override
  Future<bool> show(NotificationRequest request) async {
    if (shouldThrow) throw StateError('delivery failed');
    requests.add(request);
    return true;
  }
}

class _FakeWindowsNotificationBackend implements WindowsNotificationBackend {
  final List<NotificationRequest> requests = <NotificationRequest>[];
  int initializeCalls = 0;
  bool shouldThrow = false;

  @override
  bool get isAvailable => true;

  @override
  bool get supportsClick => true;

  @override
  Future<bool> initialize() async {
    initializeCalls++;
    return !shouldThrow;
  }

  @override
  Future<bool> show(NotificationRequest request) async {
    if (shouldThrow) throw StateError('backend failed');
    requests.add(request);
    return true;
  }
}
