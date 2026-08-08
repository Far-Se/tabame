import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:tabame/models/util/secret_crypto.dart';
import 'package:tabame/platform/app_paths.dart';
import 'package:tabame/platform/linux/linux_clipboard_service.dart';
import 'package:tabame/platform/linux/linux_file_watcher.dart';
import 'package:tabame/platform/linux/linux_bootstrap.dart';
import 'package:tabame/platform/linux/linux_hotkey_service.dart';
import 'package:tabame/platform/linux/linux_monitor_service.dart';
import 'package:tabame/platform/linux/linux_platform_channel.dart';
import 'package:tabame/platform/linux/linux_secret_store.dart';
import 'package:tabame/platform/linux/linux_window_service.dart';
import 'package:tabame/platform/platform_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Wayland detection falls back to a live socket when session type is unset', () {
    expect(
      LinuxBootstrap.sessionLooksWaylandFromEnvironment(<String, String>{'WAYLAND_DISPLAY': 'wayland-0'}),
      isTrue,
    );
    expect(
      LinuxBootstrap.sessionLooksWaylandFromEnvironment(<String, String>{'WAYLAND_DISPLAY': ''}),
      isFalse,
    );
    expect(
      LinuxBootstrap.sessionLooksWaylandFromEnvironment(
          <String, String>{'XDG_SESSION_TYPE': 'x11', 'WAYLAND_DISPLAY': 'wayland-0'}),
      isFalse,
    );
  });

  test('Linux capability probe keeps Wayland separate from X11', () {
    final LinuxCapabilitySnapshot snapshot = LinuxCapabilitySnapshot.fromValue(<String, dynamic>{
      'displayServer': 'wayland',
      'waylandCompositor': 'mutter',
      'wayland': true,
      'x11': false,
      'windowEnumeration': false,
      'windowEnumerationReason': 'Window enumeration is restricted.',
      'desktopFileDiscovery': true,
    });

    expect(snapshot.isWaylandOnly, isTrue);
    expect(snapshot.waylandCompositor, 'mutter');
    expect(snapshot.xwayland, isFalse);
    expect(snapshot.windowEnumeration, isFalse);
    expect(snapshot.reasonFor('windowEnumeration'), 'Window enumeration is restricted.');
    expect(snapshot.desktopFileDiscovery, isTrue);
  });

  test('Wayland infrastructure is reported without enabling restricted features', () {
    final LinuxCapabilitySnapshot snapshot = LinuxCapabilitySnapshot.fromValue(<String, dynamic>{
      'displayServer': 'wayland',
      'waylandCompositor': 'mutter',
      'wayland': true,
      'x11': false,
      'xWayland': true,
      'screenCastPortal': true,
      'screenshotPortal': true,
      'globalShortcutsPortal': true,
      'remoteDesktopPortal': true,
      'pipeWire': true,
      'screenCapture': false,
      'globalHotkeys': false,
      'globalHotkeysReason': 'The portal is present but not registered.',
    });

    expect(snapshot.isWaylandOnly, isTrue);
    expect(snapshot.xwayland, isTrue);
    expect(snapshot.hasCaptureInfrastructure, isTrue);
    expect(snapshot.screenCastPortal, isTrue);
    expect(snapshot.screenCapture, isFalse);
    expect(snapshot.screenRecording, isFalse);
    expect(snapshot.globalShortcutsPortal, isTrue);
    expect(snapshot.globalHotkeys, isFalse);
    expect(snapshot.reasonFor('globalHotkeys'), 'The portal is present but not registered.');
  });

  test('failed capability refresh clears stale availability', () async {
    final LinuxCapabilitySnapshot initial = LinuxCapabilitySnapshot.fromValue(<String, dynamic>{
      'displayServer': 'x11',
      'x11': true,
      'windowEnumeration': true,
    });
    final LinuxPlatformChannel channel = LinuxPlatformChannel(
      methodChannel: const MethodChannel('tabame/test/linux/missing'),
      eventChannel: const EventChannel('tabame/test/linux/missing-events'),
      available: true,
      initialCapabilities: initial,
    );

    final LinuxCapabilitySnapshot refreshed = await channel.refreshCapabilities();

    expect(refreshed.displayServer, 'unknown');
    expect(refreshed.x11, isFalse);
    expect(refreshed.windowEnumeration, isFalse);
  });

  test('Linux adapters expose native Wayland restriction reasons', () {
    final LinuxPlatformChannel channel = LinuxPlatformChannel(
      available: true,
      initialCapabilities: LinuxCapabilitySnapshot.fromValue(<String, dynamic>{
        'displayServer': 'wayland',
        'wayland': true,
        'x11': false,
        'windowEnumerationReason': 'Window listing is compositor-controlled.',
        'monitorGeometryReason': 'Popup placement is compositor-controlled.',
        'globalHotkeysReason': 'Use the visible launcher.',
      }),
    );

    expect(
      LinuxWindowService(channel: channel).unavailableReason,
      'Window listing is compositor-controlled.',
    );
    expect(
      LinuxMonitorService(channel: channel).unavailableReason,
      'Popup placement is compositor-controlled.',
    );
    expect(
      LinuxHotkeyService(channel: channel).unavailableReason,
      'Use the visible launcher.',
    );
  });

  test('Linux channel converts neutral window and monitor payloads', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/linux/core');
    final LinuxPlatformChannel channel = LinuxPlatformChannel(
      methodChannel: methodChannel,
      eventChannel: const EventChannel('tabame/test/linux/events'),
      available: true,
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async {
        switch (call.method) {
          case 'capabilities':
            return <String, dynamic>{
              'displayServer': 'x11',
              'x11': true,
              'windowEnumeration': true,
              'windowActivation': true,
              'monitorGeometry': true,
              'globalHotkeys': true,
              'clipboardMonitoring': true,
              'filesystemWatching': true,
              'notifications': false,
              'secretService': false,
              'desktopFileDiscovery': true,
            };
          case 'listWindows':
            return <dynamic>[
              <String, dynamic>{
                'nativeId': '66',
                'title': 'Editor',
                'applicationName': 'Editor',
                'bundleIdentifier': 'linux:Editor',
                'processId': 42,
                'x': 1,
                'y': 2,
                'width': 800,
                'height': 600,
              }
            ];
          case 'activateWindow':
            return true;
          case 'listMonitors':
            return <dynamic>[
              <String, dynamic>{
                'nativeId': 'monitor:0',
                'x': 0,
                'y': 0,
                'width': 1920,
                'height': 1080,
                'visibleX': 0,
                'visibleY': 0,
                'visibleWidth': 1920,
                'visibleHeight': 1040,
                'scaleFactor': 1,
                'isPrimary': true,
              }
            ];
          default:
            return null;
        }
      },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null));

    final LinuxCapabilitySnapshot capabilities = await channel.refreshCapabilities();
    final List<PlatformWindow> windows = await channel.listWindows();
    final List<PlatformMonitor> monitors = await channel.listMonitors();

    expect(capabilities.x11, isTrue);
    expect(await channel.activateWindow(windows.single.nativeId), isTrue);
    expect(windows.single.nativeId, '66');
    expect(windows.single.processId, 42);
    expect(monitors.single.visibleHeight, 1040);
  });

  test('Linux X11 clipboard adapter forwards text and maps change events', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/linux/clipboard');
    final StreamController<Map<String, dynamic>> events = StreamController<Map<String, dynamic>>.broadcast();
    final LinuxCapabilitySnapshot snapshot = LinuxCapabilitySnapshot.fromValue(<String, dynamic>{
      'displayServer': 'x11',
      'x11': true,
      'clipboardMonitoring': true,
    });
    final LinuxPlatformChannel channel = LinuxPlatformChannel(
      methodChannel: methodChannel,
      eventChannel: const EventChannel('tabame/test/linux/clipboard-events'),
      available: true,
      initialCapabilities: snapshot,
    );
    final List<String> calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async {
        calls.add(call.method);
        switch (call.method) {
          case 'startClipboardMonitoring':
            return true;
          case 'readClipboardText':
            return 'read text';
          case 'writeClipboardText':
            return true;
          case 'stopClipboardMonitoring':
            return null;
          default:
            return null;
        }
      },
    );
    addTearDown(() async {
      await events.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, null);
    });

    final LinuxClipboardService service = LinuxClipboardService(channel: channel, events: events.stream);
    expect(service.isAvailable, isTrue);
    expect(await service.start(), isTrue);
    expect(await service.start(), isTrue);

    final Future<PlatformClipboardText> change = service.changes.first;
    events.add(<String, dynamic>{'type': 'clipboardChanged', 'text': 'changed', 'changeCount': 7});
    expect((await change).text, 'changed');
    expect((await service.readText()), 'read text');
    expect(await service.writeText('written'), isTrue);
    expect(calls, containsAll(<String>['startClipboardMonitoring', 'readClipboardText', 'writeClipboardText']));

    await service.stop();
    expect(service.isMonitoringAvailable, isFalse);
  });

  test('Linux Wayland-only clipboard capability stays explicitly unavailable', () async {
    final LinuxPlatformChannel channel = LinuxPlatformChannel(
      available: true,
      initialCapabilities: LinuxCapabilitySnapshot.fromValue(<String, dynamic>{
        'displayServer': 'wayland',
        'wayland': true,
        'x11': false,
        'clipboardMonitoring': false,
      }),
    );
    final LinuxClipboardService service =
        LinuxClipboardService(channel: channel, events: const Stream<Map<String, dynamic>>.empty());

    expect(service.isAvailable, isFalse);
    expect(await service.start(), isFalse);
    expect(service.unavailableReason, contains('Wayland'));
  });

  test('Linux SecretStore keeps its key in the Secret Service boundary', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/linux/secret');
    final Uint8List key = Uint8List.fromList(List<int>.generate(32, (int index) => index));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async => call.method == 'ensureSecretServiceKey' ? base64Encode(key) : null,
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null));

    final LinuxPlatformChannel channel = LinuxPlatformChannel(
      methodChannel: methodChannel,
      eventChannel: const EventChannel('tabame/test/linux/secret-events'),
      available: true,
    );
    final LinuxSecretStore store = LinuxSecretStore(channel: channel);
    expect(await store.initialize(), isTrue);

    final Map<String, dynamic> envelope = store.sealWithMachineKey('secret text');
    expect(envelope['kdf'], SecretCrypto.secretServiceKdf);
    expect(store.openWithMachineKey(envelope), 'secret text');

    final String protectedValue = store.protectField('field secret');
    expect(protectedValue, startsWith(SecretCrypto.secretServiceFieldPrefix));
    expect(store.unprotectField(protectedValue), 'field secret');
  });

  test('Linux file watcher exposes a safe unavailable result', () {
    final LinuxFileWatcher watcher = LinuxFileWatcher(available: false);
    expect(watcher.isAvailable, isFalse);
    expect(watcher.watch(Directory.current.path, (_) {}), isNull);
  });

  test('Linux SecretStore writes plugin ciphertext below AppPaths', () async {
    final Directory workspace = await Directory.systemTemp.createTemp('tabame_linux_secret_test_');
    try {
      AppPaths.resetForTesting();
      await AppPaths.initialize(
        applicationSupportDirectory: () async => Directory(p.join(workspace.path, 'support')),
        applicationCacheDirectory: () async => Directory(p.join(workspace.path, 'cache')),
        temporaryDirectory: () async => Directory(p.join(workspace.path, 'temp')),
        rootOverride: p.join(workspace.path, 'support', 'Tabame'),
        legacyRootOverride: p.join(workspace.path, 'legacy', 'Tabame'),
        migrateLegacyData: false,
      );
      const MethodChannel methodChannel = MethodChannel('tabame/test/linux/plugin-secret');
      final Uint8List key = Uint8List.fromList(List<int>.filled(32, 7));
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
        methodChannel,
        (MethodCall call) async => base64Encode(key),
      );
      final LinuxSecretStore store = LinuxSecretStore(
        channel: LinuxPlatformChannel(
          methodChannel: methodChannel,
          eventChannel: const EventChannel('tabame/test/linux/plugin-secret-events'),
          available: true,
        ),
      );
      expect(await store.initialize(), isTrue);
      store.writePluginSecret('demo', 'token', 'value');
      expect(store.readPluginSecret('demo', 'token'), 'value');
      expect(File(AppPaths.settingsPath('linux_plugin_secrets.json')).existsSync(), isTrue);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, null);
    } finally {
      AppPaths.resetForTesting();
      if (workspace.existsSync()) await workspace.delete(recursive: true);
    }
  });
}
