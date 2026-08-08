import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tabame/models/classes/hotkeys.dart';
import 'package:tabame/models/util/hotkey_handler.dart';
import 'package:tabame/platform/hotkey_action_service.dart';
import 'package:tabame/platform/hotkey_binding_factory.dart';
import 'package:tabame/platform/hotkey_coordinator.dart';
import 'package:tabame/platform/hotkey_service.dart';

import 'package:tabame/platform/macos/macos_hotkey_service.dart';
import 'package:tabame/platform/macos/macos_input_service.dart';
import 'package:tabame/platform/macos/macos_platform_channel.dart';
import 'package:tabame/platform/platform_models.dart';
import 'package:tabame/platform/portable_hotkey_configuration.dart';
import 'package:tabame/platform/windows/windows_hotkey_service.dart';

class _RecordingHotkeyActionService extends HotkeyActionService {
  final List<PlatformHotkeyExecution> executions = <PlatformHotkeyExecution>[];

  @override
  bool get isAvailable => true;

  @override
  String get unavailableReason => '';

  @override
  Future<void> execute(PlatformHotkeyExecution execution) async {
    executions.add(execution);
  }
}

class _FakeHotkeyService extends HotkeyService {
  final StreamController<PlatformHotkeyEvent> controller = StreamController<PlatformHotkeyEvent>.broadcast();
  List<PlatformHotkeyBinding>? registeredBindings;

  @override
  bool get isAvailable => true;

  @override
  bool get supportsConfiguredBindings => true;

  @override
  bool get supportsInputEvents => true;

  @override
  String get unavailableReason => '';

  @override
  Stream<PlatformHotkeyEvent> get events => controller.stream;

  @override
  Future<HotkeyRegistrationResult> registerGlobal({
    required String key,
    required List<String> modifiers,
    String name = 'summon',
  }) async {
    return const HotkeyRegistrationResult(registered: true);
  }

  @override
  Future<HotkeyRegistrationResult> registerBindings(Iterable<PlatformHotkeyBinding> bindings) async {
    registeredBindings = bindings.toList(growable: false);
    return const HotkeyRegistrationResult(registered: true);
  }

  @override
  Future<void> unregisterGlobal() async {}

  Future<void> dispose() => controller.close();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('neutral hotkey events preserve phase, timing, and pointer trace', () {
    final PlatformHotkeyEvent event = PlatformHotkeyEvent.fromMap(<String, dynamic>{
      'name': 'move-left',
      'hotkey': 'CTRL+ALT+X',
      'info': 'releaseKbd',
      'sX': 100,
      'sY': 200,
      'eX': 80,
      'eY': 205,
      'start': 1000,
      'end': 1250,
    });

    expect(event.name, 'move-left');
    expect(event.hotkey, 'CTRL+ALT+X');
    expect(event.phase, PlatformHotkeyPhase.releaseKbd);
    expect(event.time.duration, 250);
    expect(event.mouse.diff.x, -20);
    expect(event.mouse.diff.y, 5);
  });

  test('hotkey coordinator forwards adapter events to shared orchestration', () async {
    final _FakeHotkeyService service = _FakeHotkeyService();
    final List<PlatformHotkeyEvent> received = <PlatformHotkeyEvent>[];
    final HotkeyCoordinator coordinator = HotkeyCoordinator(
      service: service,
      onEvent: (PlatformHotkeyEvent event) => received.add(event),
    );

    await coordinator.start();
    service.controller.add(const PlatformHotkeyEvent(name: 'summon', hotkey: 'CTRL+SPACE'));
    await Future<void>.delayed(Duration.zero);

    expect(received.single.name, 'summon');
    expect(coordinator.isRunning, isTrue);
    await coordinator.stop();
    expect(coordinator.isRunning, isFalse);
    await service.dispose();
  });

  test('macOS adapter registers neutral binding sets and maps events', () async {
    const MethodChannel methodChannel = MethodChannel('tabame/test/hotkeys/core');
    final StreamController<Map<String, dynamic>> events = StreamController<Map<String, dynamic>>.broadcast();
    final List<MethodCall> calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      methodChannel,
      (MethodCall call) async {
        calls.add(call);
        expect(call.method, 'registerGlobalHotkeys');
        return <String, dynamic>{'registered': true};
      },
    );
    addTearDown(() async {
      await events.close();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(methodChannel, null);
    });

    final MacOSPlatformChannel channel = MacOSPlatformChannel(
      methodChannel: methodChannel,
      eventChannel: const EventChannel('tabame/test/hotkeys/events'),
      available: true,
      events: events.stream,
    );
    final MacOSHotkeyService service = MacOSHotkeyService(channel: channel);
    const PlatformHotkeyBinding binding = PlatformHotkeyBinding(
      name: 'summon',
      key: 'SPACE',
      modifiers: <String>['CTRL', 'ALT'],
      hotkey: 'CTRL+ALT+SPACE',
    );

    expect((await service.registerBindings(<PlatformHotkeyBinding>[binding])).registered, isTrue);
    expect(calls.single.arguments, containsPair('bindings', isA<List<dynamic>>()));

    final Future<PlatformHotkeyEvent> nextEvent = service.events.first;
    events.add(<String, dynamic>{
      'type': 'hotkey',
      'name': 'summon',
      'hotkey': 'CTRL+ALT+SPACE',
      'phase': 'pressed',
      'timestamp': 1234,
    });
    final PlatformHotkeyEvent event = await nextEvent;
    expect(event.name, 'summon');
    expect(event.hotkey, 'CTRL+ALT+SPACE');
    expect(event.phase, PlatformHotkeyPhase.released);
  });

  test('macOS low-level input remains an explicit unavailable capability', () {
    const MacOSInputService service = MacOSInputService();

    expect(service.isAvailable, isFalse);
    expect(service.supportsGlobalObservation, isFalse);
    expect(service.supportsKeyboardInjection, isFalse);
    expect(service.supportsMouseGestures, isFalse);
    expect(service.unavailableReason, contains('deferred'));
  });

  test('macOS filtering keeps only executable press mappings', () {
    final Hotkeys group = Hotkeys(
      key: 'x',
      modifiers: <String>['alt', 'ctrl'],
      prohibited: <String>[],
      noopScreenBusy: false,
      waitForDoublePress: false,
      keymaps: <KeyMap>[
        KeyMap(
          enabled: true,
          windowUnderMouse: false,
          name: 'Open launcher',
          windowsInfo: <String>['any', ''],
          boundToRegion: false,
          region: Region(),
          triggerType: TriggerType.press,
          triggerInfo: <int>[0, 0, 0],
          actions: <KeyAction>[
            KeyAction(type: ActionType.tabameFunction, value: 'OpenLauncher'),
          ],
          variableCheck: <String>['', ''],
        ),
      ],
    );

    final List<Hotkeys> supported = PortableHotkeyConfiguration.supportedMacOS(<Hotkeys>[group]);
    final List<PlatformHotkeyBinding> bindings = HotkeyBindingFactory.fromModels(supported);
    expect(bindings.single.hotkey, 'CTRL+ALT+X');
    expect(bindings.single.key, 'X');
    expect(bindings.single.modifiers, <String>['CTRL', 'ALT']);
    expect(bindings.single.region.anchorType, 0);
  });

  test('shared handler dispatches a macOS press-only event once', () async {
    final Hotkeys group = Hotkeys(
      key: 'X',
      modifiers: <String>['CTRL'],
      prohibited: <String>[],
      noopScreenBusy: false,
      waitForDoublePress: false,
      keymaps: <KeyMap>[
        KeyMap(
          enabled: true,
          windowUnderMouse: false,
          name: 'open-launcher',
          windowsInfo: <String>['any', ''],
          boundToRegion: false,
          region: Region(),
          triggerType: TriggerType.press,
          triggerInfo: <int>[0, 0, 0],
          actions: <KeyAction>[
            KeyAction(type: ActionType.tabameFunction, value: 'OpenLauncher'),
          ],
          variableCheck: <String>['', ''],
        ),
      ],
    );
    final _RecordingHotkeyActionService actionService = _RecordingHotkeyActionService();
    HotkeyActionService.register(actionService);
    addTearDown(() => HotkeyActionService.register(const UnavailableHotkeyActionService()));

    final HotkeyHandler handler = HotkeyHandler(hotkeys: () => <Hotkeys>[group]);
    await handler.handle(
      const PlatformHotkeyEvent(
        name: 'open-launcher',
        hotkey: 'CTRL+X',
        action: 'released',
      ),
    );

    expect(actionService.executions, hasLength(1));
    expect(actionService.executions.single.trigger, 'press');
    expect(actionService.executions.single.actions.single.value, 'OpenLauncher');
  });

  test('Windows native DTO encoding stays in the Windows adapter', () {
    expect(WindowsHotkeyService.keyToVirtualKey('A'), isNotNull);
    expect(WindowsHotkeyService.keyToVirtualKey('NOT_A_KEY'), isNull);

    final Map<String, dynamic> nativeBinding = WindowsHotkeyService.toNativeBinding(
      const PlatformHotkeyBinding(
        name: 'launch',
        key: 'A',
        modifiers: <String>['CTRL'],
        hotkey: 'CTRL+A',
      ),
    );
    expect(nativeBinding['hotkey'], 'CTRL+A');
    expect(nativeBinding['modifisers'], 'CTRL');
    expect(nativeBinding['keyVK'], isNot(-1));
  });
}
