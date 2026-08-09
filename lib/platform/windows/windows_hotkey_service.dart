import 'dart:async';
import 'dart:io';

import '../../models/win32/keys.dart';
import '../hotkey_service.dart';
import '../platform_models.dart';
import 'tabamewin32_api.dart';

/// Windows adapter for the neutral hotkey contract.
///
/// NativeHooks remains the compatibility implementation for low-level
/// keyboard/mouse observation. This class owns the conversion at the boundary;
/// shared orchestration receives only [PlatformHotkeyEvent] values.
class WindowsHotkeyService extends HotkeyService implements TabameListener {
  WindowsHotkeyService();

  final StreamController<PlatformHotkeyEvent> _events = StreamController<PlatformHotkeyEvent>.broadcast();
  bool _listenerRegistered = false;

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  bool get supportsConfiguredBindings => isAvailable;

  @override
  bool get supportsInputEvents => isAvailable;

  @override
  String get unavailableReason =>
      isAvailable ? '' : 'The Windows native hotkey service is unavailable on this platform.';

  @override
  Stream<PlatformHotkeyEvent> get events => _events.stream;

  @override
  Future<HotkeyRegistrationResult> registerGlobal({
    required String key,
    required List<String> modifiers,
    String name = 'summon',
  }) {
    return registerBindings(<PlatformHotkeyBinding>[
      PlatformHotkeyBinding(
        name: name,
        key: key,
        modifiers: modifiers,
        hotkey: <String>[...modifiers, key].join('+'),
      ),
    ]);
  }

  @override
  Future<HotkeyRegistrationResult> registerBindings(Iterable<PlatformHotkeyBinding> bindings) async {
    if (!isAvailable) {
      return HotkeyRegistrationResult(
        registered: false,
        reason: unavailableReason,
      );
    }

    final List<Map<String, dynamic>> nativeBindings =
        bindings.map(WindowsHotkeyService.toNativeBinding).toList(growable: false);
    if (nativeBindings.isEmpty) {
      await unregisterBindings();
      return const HotkeyRegistrationResult(
        registered: false,
        reason: 'No enabled global hotkeys were configured; the native hook remains stopped.',
      );
    }

    try {
      if (!_listenerRegistered) {
        NativeHooks.registerCallHandler();
        NativeHooks.addListener(this);
        _listenerRegistered = true;
      }
      await NativeHooks.runHotkeys(nativeBindings);
      if (!NativeHooks.isRegistered) {
        return const HotkeyRegistrationResult(
          registered: false,
          permissionRequired: true,
          reason: 'Windows did not register the global hook; use the visible Tabame window instead.',
        );
      }
      return const HotkeyRegistrationResult(registered: true);
    } catch (error) {
      await unregisterBindings();
      return HotkeyRegistrationResult(
        registered: false,
        permissionRequired: true,
        reason: 'Windows rejected the global hook: $error',
      );
    }
  }

  @override
  Future<void> unregisterGlobal() => unregisterBindings();

  @override
  Future<void> unregisterBindings() async {
    if (!isAvailable) return;
    if (NativeHooks.isRegistered) await NativeHooks.unHook();
    await NativeHooks.resetHotkeys();
    if (_listenerRegistered) {
      NativeHooks.removeListener(this);
      _listenerRegistered = false;
    }
  }

  @override
  void onHotKeyEvent(HotkeyEvent event) {
    _events.add(
      PlatformHotkeyEvent(
        name: event.name,
        hotkey: event.hotkey,
        action: event.action,
        mouse: PlatformMouseTrace(start: event.mouse.start, end: event.mouse.end),
        time: PlatformHotkeyTiming(start: event.time.start, end: event.time.end),
      ),
    );
  }

  @override
  void onDisplayChange(MonitorEvent event) {}

  @override
  void onForegroundWindowChanged(int hWnd) {}

  @override
  void onTricktivityEvent(String action, String info) {}

  @override
  void onWinEventReceived(int hWnd, WinEventType type) {}

  @override
  void onViewsEvent(ViewsAction action, int hWnd) {}

  @override
  void onQuickClickEvent(String eventName, Map<String, String> params) {}

  @override
  void onKeyVizEvent(KeyVizEvent event) {}

  @override
  void onMouseGesture(String button, String pattern, int durationMs) {}

  static int? keyToVirtualKey(String key) {
    return keyMap['VK_${key.toUpperCase()}'];
  }

  static Map<String, dynamic> toNativeBinding(PlatformHotkeyBinding binding) {
    return <String, dynamic>{
      'name': binding.name,
      'hotkey': binding.hotkey.toUpperCase(),
      'keyVK': keyToVirtualKey(binding.key) ?? -1,
      // The native Windows DTO keeps this historical spelling for compatibility.
      'modifisers': binding.modifiers.isNotEmpty ? binding.modifiers.join('+').toUpperCase() : 'noModifiers',
      'listenToMovement': binding.listensToMovement,
      'matchWindowBy': binding.matchWindowBy,
      'matchWindowText': binding.matchWindowText,
      'activateWindowUnderCursor': binding.activateWindowUnderCursor,
      'noopScreenBusy': binding.noopScreenBusy,
      'prohibitedWindows': binding.prohibitedWindows.join(';'),
      'regionasPercentage': binding.region.asPercentage,
      'regionOnScreen': binding.region.onScreen,
      'regionX1': binding.region.x1,
      'regionX2': binding.region.x2,
      'regionY1': binding.region.y1,
      'regionY2': binding.region.y2,
      'anchorType': binding.region.anchorType,
    };
  }
}
