import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/platform_models.dart';
import 'package:tabame/platform/window_service.dart';
import 'package:tabame/platform/window_watcher_service.dart';
import 'package:tabame/platform/windows/windows_window_bridge.dart';
import 'package:tabame/platform/windows/windows_window_service.dart';

void main() {
  test('normalizes neutral snapshots and emits only changed snapshots', () async {
    final _FakeWindowService service = _FakeWindowService(
      windows: <PlatformWindow>[
        _window('editor', title: 'Editor'),
        _window('editor', title: 'Duplicate'),
        _window('hidden', title: 'Hidden', isOnScreen: false),
        _window('untitled', title: ''),
      ],
    );
    final WindowWatcherService watcher = WindowWatcherService(service: service);
    final List<List<PlatformWindow>> events = <List<PlatformWindow>>[];
    final StreamSubscription<List<PlatformWindow>> subscription = watcher.changes.listen(events.add);
    addTearDown(subscription.cancel);

    expect(await watcher.refresh(), isTrue);
    expect(watcher.windows.map((PlatformWindow window) => window.title), <String>['Editor']);
    expect(events, hasLength(1));

    expect(await watcher.refresh(), isTrue);
    expect(events, hasLength(1));

    service.windows = <PlatformWindow>[_window('editor', title: 'Renamed')];
    expect(await watcher.refresh(), isTrue);
    expect(watcher.windows.single.title, 'Renamed');
    expect(events, hasLength(2));
  });

  test('unavailable enumeration and activation fail safely', () async {
    final _FakeWindowService service = _FakeWindowService(available: false);
    final WindowWatcherService watcher = WindowWatcherService(service: service);
    final PlatformWindow window = _window('editor', title: 'Editor');

    expect(await watcher.refresh(), isFalse);
    expect(watcher.windows, isEmpty);
    expect(await watcher.activate(window), isFalse);
    expect(watcher.unavailableReason, 'Window enumeration is unavailable.');
  });

  test('watcher start is idempotent and stop cancels polling', () async {
    final _FakeWindowService service = _FakeWindowService(windows: <PlatformWindow>[_window('editor')]);
    final WindowWatcherService watcher = WindowWatcherService(service: service);

    await watcher.start(interval: const Duration(seconds: 1));
    final int callsAfterFirstStart = service.enumerateCalls;
    await watcher.start(interval: const Duration(seconds: 1));
    expect(service.enumerateCalls, callsAfterFirstStart);

    await watcher.stop();
    expect(await watcher.refresh(), isTrue);
  });

  test('Windows adapter delegates neutral snapshots through its bridge', () async {
    final _FakeWindowsBridge bridge = _FakeWindowsBridge(windows: <PlatformWindow>[_window('windows-editor')]);
    final WindowsWindowService service = WindowsWindowService(bridge: bridge);

    expect(service.isAvailable, isTrue);
    expect((await service.enumerate()).single.identity, 'windows-editor');
    expect(await service.activate((await service.enumerate()).single), isTrue);
    expect(bridge.activateCalls, 1);
  });
}

PlatformWindow _window(
  String identity, {
  String title = 'Window',
  bool isOnScreen = true,
}) {
  return PlatformWindow(
    nativeId: identity,
    title: title,
    applicationName: 'Editor',
    bundleIdentifier: 'com.example.editor',
    processId: 42,
    x: 10,
    y: 20,
    width: 800,
    height: 600,
    executable: 'editor',
    isOnScreen: isOnScreen,
  );
}

class _FakeWindowService extends WindowService {
  _FakeWindowService({this.windows = const <PlatformWindow>[], this.available = true});

  List<PlatformWindow> windows;
  bool available;
  int enumerateCalls = 0;

  @override
  bool get isAvailable => available;

  @override
  String get unavailableReason => available ? '' : 'Window enumeration is unavailable.';

  @override
  bool get isActivationAvailable => available;

  @override
  Future<List<PlatformWindow>> enumerate() async {
    enumerateCalls++;
    return windows;
  }

  @override
  Future<bool> activate(PlatformWindow window) async => available;

  @override
  Future<String?> captureFocus() async => null;

  @override
  Future<bool> restoreFocus(String? token) async => false;
}

class _FakeWindowsBridge implements WindowsWindowBridge {
  _FakeWindowsBridge({required this.windows});

  final List<PlatformWindow> windows;
  int activateCalls = 0;

  @override
  bool get isAvailable => true;

  @override
  String get unavailableReason => '';

  @override
  Future<List<PlatformWindow>> enumerate() async => windows;

  @override
  Future<bool> activate(PlatformWindow window) async {
    activateCalls++;
    return true;
  }

  @override
  Future<String?> captureFocus() async => null;

  @override
  Future<bool> restoreFocus(String? token) async => false;
}
