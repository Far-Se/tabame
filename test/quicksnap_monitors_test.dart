import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/pages/quicksnap_portable.dart';
import 'package:tabame/platform/macos/macos_monitor_service.dart';
import 'package:tabame/platform/macos/macos_platform_channel.dart';
import 'package:tabame/platform/macos/macos_quick_snap_service.dart';

import 'package:tabame/platform/platform_capabilities.dart';
import 'package:tabame/platform/platform_models.dart';
import 'package:tabame/platform/quick_snap_service.dart';
import 'package:tabame/platform/windows/windows_monitor_service.dart';
import 'package:tabame/platform/windows/windows_quick_snap_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('shared geometry selects a monitor and resolves symmetric gaps', () {
    const PlatformWindow window = PlatformWindow(
      nativeId: 'opaque-window',
      title: 'Editor',
      applicationName: 'Editor',
      bundleIdentifier: 'com.example.editor',
      processId: 42,
      x: 2100,
      y: 100,
      width: 800,
      height: 600,
    );
    const List<PlatformMonitor> monitors = <PlatformMonitor>[
      PlatformMonitor(
        nativeId: 'left',
        x: -1920,
        y: 0,
        width: 1920,
        height: 1080,
        visibleX: -1920,
        visibleY: 0,
        visibleWidth: 1920,
        visibleHeight: 1040,
        scaleFactor: 1,
        isPrimary: false,
      ),
      PlatformMonitor(
        nativeId: 'primary',
        x: 0,
        y: 0,
        width: 2560,
        height: 1440,
        visibleX: 0,
        visibleY: 0,
        visibleWidth: 2560,
        visibleHeight: 1400,
        scaleFactor: 1.5,
        isPrimary: true,
      ),
    ];

    final PlatformMonitor? selected = QuickSnapGeometry.monitorForWindow(window, monitors);
    expect(selected?.identity, 'primary');

    final PlatformRect rect = QuickSnapGeometry.zoneRect(
      monitors.last,
      const PlatformSnapZone(left: 0, top: 0, right: 0.5, bottom: 1),
      gap: 20,
    );
    expect(rect.left, 10);
    expect(rect.top, 10);
    expect(rect.right, 1270);
    expect(rect.bottom, 1430);
  });

  test('Windows monitor adapter exposes neutral geometry and cursor placement', () async {
    final _FakeMonitorBridge bridge = _FakeMonitorBridge(
      monitors: const <PlatformMonitor>[
        PlatformMonitor(
          nativeId: 'monitor-a',
          x: 0,
          y: 0,
          width: 1920,
          height: 1080,
          visibleX: 0,
          visibleY: 0,
          visibleWidth: 1920,
          visibleHeight: 1040,
          scaleFactor: 1,
          isPrimary: true,
        ),
      ],
      cursor: const PlatformPoint(x: 1600, y: 700),
    );
    final WindowsMonitorService service = WindowsMonitorService(bridge: bridge);

    expect(service.isAvailable, isTrue);
    expect((await service.cursorMonitor())?.identity, 'monitor-a');
    final PlatformPopupPlacement? placement = await service.placePopup(width: 400, height: 200);
    expect(placement?.monitorId, 'monitor-a');
    expect(placement?.x, 760);
    expect(placement?.y, 420);
  });

  test('Windows QuickSnap adapter keeps neutral windows and zones at the seam', () async {
    const PlatformWindow window = PlatformWindow(
      nativeId: 'opaque-window',
      title: 'Editor',
      applicationName: 'Editor',
      bundleIdentifier: 'editor',
      processId: 42,
      x: 10,
      y: 10,
      width: 800,
      height: 600,
    );
    const PlatformMonitor monitor = PlatformMonitor(
      nativeId: 'opaque-monitor',
      x: 0,
      y: 0,
      width: 1920,
      height: 1080,
      visibleX: 0,
      visibleY: 0,
      visibleWidth: 1920,
      visibleHeight: 1040,
      scaleFactor: 1,
      isPrimary: true,
    );
    final _FakeQuickSnapBridge bridge = _FakeQuickSnapBridge(window: window);
    final WindowsQuickSnapService service = WindowsQuickSnapService(bridge: bridge);

    final bool snapped = await service.snap(
      window: window,
      monitor: monitor,
      zone: const PlatformSnapZone(left: 0, top: 0, right: 0.5, bottom: 1),
      gap: 12,
    );

    expect(snapped, isTrue);
    expect(bridge.lastWindow?.identity, 'opaque-window');
    expect(bridge.lastZone?.right, 0.5);
    expect(bridge.lastGap, 12);
  });

  test('macOS monitor and manual snap adapters translate method-channel payloads', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/macos/quicksnap');
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async {
        calls.add(call);
        switch (call.method) {
          case 'listMonitors':
            return <dynamic>[
              <String, dynamic>{
                'nativeId': 'display:1',
                'x': 0,
                'y': 0,
                'width': 1440,
                'height': 900,
                'visibleX': 0,
                'visibleY': 24,
                'visibleWidth': 1440,
                'visibleHeight': 876,
                'scaleFactor': 2,
                'isPrimary': true,
              },
            ];
          case 'cursorMonitor':
            return <String, dynamic>{
              'nativeId': 'display:1',
              'x': 0,
              'y': 0,
              'width': 1440,
              'height': 900,
              'visibleX': 0,
              'visibleY': 24,
              'visibleWidth': 1440,
              'visibleHeight': 876,
              'scaleFactor': 2,
              'isPrimary': true,
            };
          case 'cursorPosition':
            return <String, dynamic>{'x': 240, 'y': 180};
          case 'snapWindow':
          case 'restoreWindow':
            return true;
          default:
            return null;
        }
      },
    );
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, null);
    });

    final MacOSPlatformChannel channel = MacOSPlatformChannel(
      methodChannel: methodChannel,
      eventChannel: const EventChannel('tabame/test/macos/quicksnap-events'),
      available: true,
    );
    final MacOSMonitorService monitors = MacOSMonitorService(channel: channel);
    final MacOSQuickSnapService service = MacOSQuickSnapService(channel: channel, available: true);
    final PlatformMonitor monitor = (await monitors.enumerate()).single;

    expect((await monitors.cursorPosition())?.x, 240);
    expect(
      await service.snap(
        window: const PlatformWindow(
          nativeId: '123:456',
          title: 'Document',
          applicationName: 'Editor',
          bundleIdentifier: 'com.example.editor',
          processId: 123,
          x: 10,
          y: 20,
          width: 800,
          height: 600,
        ),
        monitor: monitor,
        zone: const PlatformSnapZone(left: 0, top: 0, right: 0.5, bottom: 1),
        gap: 8,
      ),
      isTrue,
    );
    expect(calls.map((MethodCall call) => call.method), contains('snapWindow'));
    expect(
        await service.restore(const PlatformWindow(
          nativeId: '123:456',
          title: 'Document',
          applicationName: 'Editor',
          bundleIdentifier: 'com.example.editor',
          processId: 123,
          x: 10,
          y: 20,
          width: 800,
          height: 600,
        )),
        isTrue);
  });

  testWidgets('portable QuickSnap surface explains a deferred capability', (WidgetTester tester) async {
    final PlatformCapabilities previousCapabilities = PlatformCapabilities.current;
    final QuickSnapService previousService = QuickSnapService.instance;
    PlatformCapabilities.register(const PlatformCapabilities());
    QuickSnapService.register(const UnavailableQuickSnapService());
    addTearDown(() {
      PlatformCapabilities.register(previousCapabilities);
      QuickSnapService.register(previousService);
    });

    await tester.pumpWidget(const MaterialApp(home: PortableQuickSnapPanel()));

    expect(find.textContaining('unavailable'), findsOneWidget);
  });
}

class _FakeMonitorBridge implements WindowsMonitorBridge {
  _FakeMonitorBridge({required this.monitors, required this.cursor});

  final List<PlatformMonitor> monitors;
  final PlatformPoint cursor;

  @override
  bool get isAvailable => true;

  @override
  Future<List<PlatformMonitor>> enumerate() async => monitors;

  @override
  Future<PlatformPoint?> cursorPosition() async => cursor;
}

class _FakeQuickSnapBridge extends WindowsQuickSnapBridge {
  _FakeQuickSnapBridge({required this.window});

  final PlatformWindow window;
  final StreamController<WindowsQuickSnapEvent> controller = StreamController<WindowsQuickSnapEvent>.broadcast();
  PlatformWindow? lastWindow;
  PlatformSnapZone? lastZone;
  double lastGap = 0;

  @override
  bool get isAvailable => true;

  @override
  Stream<WindowsQuickSnapEvent> get events => controller.stream;

  @override
  Future<PlatformWindow?> resolveWindow(int handle) async => window;

  @override
  Future<bool> snap({
    required PlatformWindow window,
    required PlatformMonitor monitor,
    required PlatformSnapZone zone,
    double gap = 0,
    double topInset = 0,
  }) async {
    lastWindow = window;
    lastZone = zone;
    lastGap = gap;
    return true;
  }
}
