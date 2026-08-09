import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/platform/macos/macos_platform_channel.dart';
import 'package:tabame/platform/macos/macos_secret_store.dart';
import 'package:tabame/platform/macos/macos_window_service.dart';
import 'package:tabame/platform/platform_capabilities.dart';
import 'package:tabame/platform/platform_models.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('parses macOS permission and neutral geometry payloads', () {
    final MacOSPermissionSnapshot snapshot = MacOSPermissionSnapshot.fromValue(<dynamic>[
      <String, dynamic>{'permission': 'accessibility', 'status': 'granted'},
      <String, dynamic>{'permission': 'screenRecording', 'status': 'denied'},
    ]);

    expect(snapshot.stateFor(MacOSPermission.accessibility).isGranted, isTrue);
    expect(snapshot.stateFor(MacOSPermission.screenRecording).status, MacOSPermissionStatus.denied);
    expect(snapshot.stateFor(MacOSPermission.notifications).status, MacOSPermissionStatus.unknown);

    final PlatformWindow window = PlatformWindow.fromMap(<String, dynamic>{
      'nativeId': '123:456',
      'title': 'Document',
      'applicationName': 'Editor',
      'bundleIdentifier': 'com.example.editor',
      'processId': 123,
      'x': 10,
      'y': 20,
      'width': 800,
      'height': 600,
      'icon': 'cached-icon.ico',
    });
    expect(window.nativeId, '123:456');
    expect(window.width, 800);
    expect(window.icon, 'cached-icon.ico');
  });

  test('macOS window service gates and delegates neutral enumeration', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/macos/window-service');
    final PlatformCapabilities previous = PlatformCapabilities.current;
    PlatformCapabilities.register(
      previous.copyWith(windowEnumeration: true, windowActivation: true),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async {
        switch (call.method) {
          case 'listWindows':
            return <dynamic>[
              <String, dynamic>{
                'nativeId': 'opaque-window',
                'title': 'Document',
                'applicationName': 'Editor',
                'bundleIdentifier': 'com.example.editor',
                'processId': 42,
                'x': 10,
                'y': 20,
                'width': 800,
                'height': 600,
                'isOnScreen': true,
              },
            ];
          case 'activateWindow':
            return true;
          default:
            return null;
        }
      },
    );
    addTearDown(() {
      PlatformCapabilities.register(previous);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, null);
    });

    final MacOSPlatformChannel channel = MacOSPlatformChannel(
      methodChannel: methodChannel,
      eventChannel: const EventChannel('tabame/test/macos/window-events'),
      available: true,
    );
    final MacOSWindowService service = MacOSWindowService(channel: channel);

    PlatformCapabilities.register(previous.copyWith(windowEnumeration: false, windowActivation: false));
    expect(service.isAvailable, isFalse);
    expect(service.unavailableReason, contains('Screen Recording'));

    PlatformCapabilities.register(previous.copyWith(windowEnumeration: true, windowActivation: true));
    expect(service.isAvailable, isTrue);
    final List<PlatformWindow> windows = await service.enumerate();
    expect(windows.single.identity, 'opaque-window');
    expect(await service.activate(windows.single), isTrue);
  });

  test('macOS Keychain probing can retry after a transient failure', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/macos/retry');
    final Uint8List key = Uint8List.fromList(List<int>.generate(32, (int index) => index));
    int calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async {
        calls++;
        return calls == 1 ? null : base64Encode(key);
      },
    );
    addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(methodChannel, null));

    final MacOSSecretStore store = MacOSSecretStore(
      channel: MacOSPlatformChannel(
        methodChannel: methodChannel,
        eventChannel: const EventChannel('tabame/test/macos/retry-events'),
        available: true,
      ),
    );

    expect(await store.initialize(), isFalse);
    expect(await store.initialize(), isTrue);
    expect(calls, 2);
  });

  test('Keychain-backed store keeps the synchronous contract over a native key', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/macos/core');
    final Uint8List key = Uint8List.fromList(List<int>.generate(32, (int index) => index));
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async {
        expect(call.method, 'ensureKeychainKey');
        return base64Encode(key);
      },
    );

    final MacOSPlatformChannel channel = MacOSPlatformChannel(
      methodChannel: methodChannel,
      eventChannel: const EventChannel('tabame/test/macos/events'),
      available: true,
    );
    final MacOSSecretStore store = MacOSSecretStore(channel: channel);

    expect(await store.initialize(), isTrue);
    final Map<String, dynamic> envelope = store.sealWithMachineKey('secret text');
    expect(envelope['kdf'], 'keychain-aes-gcm');
    expect(store.openWithMachineKey(envelope), 'secret text');

    final String protectedValue = store.protectField('field secret');
    expect(protectedValue, startsWith('keychain:v1:'));
    expect(store.unprotectField(protectedValue), 'field secret');
  });
}
