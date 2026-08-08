import 'dart:io';

import 'package:flutter/services.dart';

import '../platform_models.dart';

const String macOSPlatformChannelName = 'tabame/macos/core';
const String macOSEventChannelName = 'tabame/macos/events';

enum MacOSPermission {
  accessibility,
  inputMonitoring,
  screenRecording,
  notifications,
}

enum MacOSPermissionStatus {
  granted,
  denied,
  notDetermined,
  unavailable,
  unknown,
}

extension MacOSPermissionName on MacOSPermission {
  String get wireName {
    switch (this) {
      case MacOSPermission.accessibility:
        return 'accessibility';
      case MacOSPermission.inputMonitoring:
        return 'inputMonitoring';
      case MacOSPermission.screenRecording:
        return 'screenRecording';
      case MacOSPermission.notifications:
        return 'notifications';
    }
  }

  String get displayName {
    switch (this) {
      case MacOSPermission.accessibility:
        return 'Accessibility';
      case MacOSPermission.inputMonitoring:
        return 'Input Monitoring';
      case MacOSPermission.screenRecording:
        return 'Screen Recording';
      case MacOSPermission.notifications:
        return 'Notifications';
    }
  }
}

class MacOSPermissionState {
  const MacOSPermissionState({
    required this.permission,
    required this.status,
    this.reason = '',
  });

  final MacOSPermission permission;
  final MacOSPermissionStatus status;
  final String reason;

  bool get isGranted => status == MacOSPermissionStatus.granted;

  factory MacOSPermissionState.fromMap(Map<String, dynamic> map) {
    final String permissionName = (map['permission'] ?? '').toString();
    final MacOSPermission permission = MacOSPermission.values.firstWhere(
      (MacOSPermission value) => value.wireName == permissionName,
      orElse: () => MacOSPermission.accessibility,
    );
    final String statusName = (map['status'] ?? 'unknown').toString();
    final MacOSPermissionStatus status = MacOSPermissionStatus.values.firstWhere(
      (MacOSPermissionStatus value) => value.name == statusName,
      orElse: () => MacOSPermissionStatus.unknown,
    );
    return MacOSPermissionState(
      permission: permission,
      status: status,
      reason: (map['reason'] ?? '').toString(),
    );
  }
}

class MacOSPermissionSnapshot {
  const MacOSPermissionSnapshot(this.states);

  final Map<MacOSPermission, MacOSPermissionState> states;

  MacOSPermissionState stateFor(MacOSPermission permission) {
    return states[permission] ??
        MacOSPermissionState(
          permission: permission,
          status: MacOSPermissionStatus.unknown,
        );
  }

  bool get allGranted => states.values.every((MacOSPermissionState state) => state.isGranted);

  factory MacOSPermissionSnapshot.fromValue(dynamic value) {
    final Iterable<dynamic> rawStates = value is List<dynamic>
        ? value
        : value is Map<dynamic, dynamic>
            ? <dynamic>[value]
            : const <dynamic>[];
    final Map<MacOSPermission, MacOSPermissionState> states = <MacOSPermission, MacOSPermissionState>{};
    for (final dynamic raw in rawStates) {
      if (raw is! Map<dynamic, dynamic>) continue;
      final Map<String, dynamic> map = Map<String, dynamic>.from(raw);
      final String wireName = (map['permission'] ?? '').toString();
      if (!MacOSPermission.values.any((MacOSPermission permission) => permission.wireName == wireName)) continue;
      final MacOSPermissionState state = MacOSPermissionState.fromMap(map);
      states[state.permission] = state;
    }
    return MacOSPermissionSnapshot(states);
  }

  static MacOSPermissionSnapshot unknown() {
    return MacOSPermissionSnapshot(<MacOSPermission, MacOSPermissionState>{
      for (final MacOSPermission permission in MacOSPermission.values)
        permission: MacOSPermissionState(
          permission: permission,
          status: MacOSPermissionStatus.unknown,
        ),
    });
  }
}

/// The only native boundary used by the macOS Phase 5 adapter.
class MacOSPlatformChannel {
  MacOSPlatformChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    bool? available,
    Stream<Map<String, dynamic>>? events,
  })  : methodChannel = methodChannel ?? const MethodChannel(macOSPlatformChannelName),
        eventChannel = eventChannel ?? const EventChannel(macOSEventChannelName),
        _available = available ?? Platform.isMacOS,
        _providedEvents = events;

  static final MacOSPlatformChannel instance = MacOSPlatformChannel();

  final MethodChannel methodChannel;
  final EventChannel eventChannel;
  final bool _available;
  final Stream<Map<String, dynamic>>? _providedEvents;
  late final Stream<Map<String, dynamic>> _events = _providedEvents ??
      eventChannel
          .receiveBroadcastStream()
          .where((dynamic value) => value is Map<dynamic, dynamic>)
          .map((dynamic value) => Map<String, dynamic>.from(value as Map<dynamic, dynamic>));

  bool get isAvailable => _available;

  Stream<Map<String, dynamic>> get events => _events;

  Future<dynamic> _invoke(String method, [Object? arguments]) async {
    if (!isAvailable) return null;
    try {
      return await methodChannel.invokeMethod<dynamic>(method, arguments);
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    } catch (_) {
      // Permission failures and unavailable native services must not prevent
      // the portable shell from starting.
      return null;
    }
  }

  Future<MacOSPermissionSnapshot> permissionStates() async {
    final dynamic value = await _invoke('permissionStates');
    if (value == null) return MacOSPermissionSnapshot.unknown();
    return MacOSPermissionSnapshot.fromValue(value);
  }

  Future<MacOSPermissionState> requestPermission(MacOSPermission permission) async {
    final dynamic value = await _invoke('requestPermission', <String, dynamic>{'permission': permission.wireName});
    if (value is! Map<dynamic, dynamic>) return (await permissionStates()).stateFor(permission);
    return MacOSPermissionState.fromMap(Map<String, dynamic>.from(value));
  }

  Future<bool> openPermissionSettings(MacOSPermission permission) async {
    final dynamic value = await _invoke(
      'openPermissionSettings',
      <String, dynamic>{'permission': permission.wireName},
    );
    return value == true;
  }

  Future<List<PlatformWindow>> listWindows() async {
    final dynamic value = await _invoke('listWindows');
    if (value is! List<dynamic>) return const <PlatformWindow>[];
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> item) => PlatformWindow.fromMap(Map<String, dynamic>.from(item)))
        .where((PlatformWindow window) => window.nativeId.isNotEmpty)
        .toList(growable: false);
  }

  Future<bool> activateWindow(String nativeId) async {
    if (nativeId.trim().isEmpty) return false;
    return await _invoke('activateWindow', <String, dynamic>{'nativeId': nativeId}) == true;
  }

  Future<List<PlatformMonitor>> listMonitors() async {
    final dynamic value = await _invoke('listMonitors');
    if (value is! List<dynamic>) return const <PlatformMonitor>[];
    return value
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> item) => PlatformMonitor.fromMap(Map<String, dynamic>.from(item)))
        .where((PlatformMonitor monitor) => monitor.nativeId.isNotEmpty)
        .toList(growable: false);
  }

  Future<PlatformMonitor?> cursorMonitor() async {
    final dynamic value = await _invoke('cursorMonitor');
    if (value is! Map<dynamic, dynamic>) return null;
    return PlatformMonitor.fromMap(Map<String, dynamic>.from(value));
  }

  Future<PlatformPoint?> cursorPosition() async {
    final dynamic value = await _invoke('cursorPosition');
    if (value is! Map<dynamic, dynamic>) return null;
    return PlatformPoint.fromMap(Map<String, dynamic>.from(value));
  }

  Future<PlatformPopupPlacement?> placePopup({
    required double width,
    required double height,
    double margin = 8,
    String? monitorId,
  }) async {
    final dynamic value = await _invoke('placePopup', <String, dynamic>{
      'width': width,
      'height': height,
      'margin': margin,
      if (monitorId != null) 'monitorId': monitorId,
    });
    if (value is! Map<dynamic, dynamic>) return null;
    return PlatformPopupPlacement.fromMap(Map<String, dynamic>.from(value));
  }

  Future<String?> captureFocus() async {
    final dynamic value = await _invoke('captureFocus');
    return value is String && value.isNotEmpty ? value : null;
  }

  Future<bool> restoreFocus(String? token) async {
    return await _invoke('restoreFocus', <String, dynamic>{if (token != null) 'token': token}) == true;
  }

  Future<bool> snapWindow({
    required String nativeId,
    required double x,
    required double y,
    required double width,
    required double height,
  }) async {
    return await _invoke('snapWindow', <String, dynamic>{
          'nativeId': nativeId,
          'x': x,
          'y': y,
          'width': width,
          'height': height,
        }) ==
        true;
  }

  Future<bool> restoreWindow(String nativeId) async {
    return await _invoke('restoreWindow', <String, dynamic>{'nativeId': nativeId}) == true;
  }

  Future<HotkeyRegistrationResult> registerGlobalHotkey({
    required String key,
    required List<String> modifiers,
    String name = 'summon',
  }) async {
    final dynamic value = await _invoke('registerGlobalHotkey', <String, dynamic>{
      'key': key,
      'modifiers': modifiers,
      'name': name,
      'hotkey': <String>[...modifiers, key].join('+'),
    });
    if (value is! Map<dynamic, dynamic>) {
      return const HotkeyRegistrationResult(
        registered: false,
        permissionRequired: true,
        reason: 'The macOS hotkey service is unavailable.',
      );
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(value);
    return HotkeyRegistrationResult(
      registered: map['registered'] == true,
      permissionRequired: map['permissionRequired'] == true,
      reason: (map['reason'] ?? '').toString(),
    );
  }

  Future<HotkeyRegistrationResult> registerGlobalHotkeys(Iterable<PlatformHotkeyBinding> bindings) async {
    final List<PlatformHotkeyBinding> requested = bindings.toList(growable: false);
    final dynamic value = await _invoke('registerGlobalHotkeys', <String, dynamic>{
      'bindings': requested.map((PlatformHotkeyBinding binding) => binding.toMap()).toList(growable: false),
    });
    if (value is! Map<dynamic, dynamic>) {
      return const HotkeyRegistrationResult(
        registered: false,
        permissionRequired: true,
        reason: 'The macOS hotkey service is unavailable.',
      );
    }
    final Map<String, dynamic> map = Map<String, dynamic>.from(value);
    return HotkeyRegistrationResult(
      registered: map['registered'] == true,
      permissionRequired: map['permissionRequired'] == true,
      reason: (map['reason'] ?? '').toString(),
    );
  }

  Future<void> unregisterGlobalHotkey() async {
    await _invoke('unregisterGlobalHotkey');
  }

  Future<bool> startClipboardMonitoring() async {
    return await _invoke('startClipboardMonitoring') == true;
  }

  Future<void> stopClipboardMonitoring() async {
    await _invoke('stopClipboardMonitoring');
  }

  Future<String?> readClipboardText() async {
    final dynamic value = await _invoke('readClipboardText');
    return value is String ? value : null;
  }

  Future<bool> writeClipboardText(String text) async {
    return await _invoke('writeClipboardText', <String, dynamic>{'text': text}) == true;
  }

  Future<bool> launchApplication({String? bundleIdentifier, String? path}) async {
    final dynamic value = await _invoke('launchApplication', <String, dynamic>{
      if (bundleIdentifier != null && bundleIdentifier.trim().isNotEmpty) 'bundleIdentifier': bundleIdentifier,
      if (path != null && path.trim().isNotEmpty) 'path': path,
    });
    return value == true;
  }

  Future<bool> writeApplicationIcon({required String path, required String destinationPath}) async {
    final dynamic value = await _invoke('writeApplicationIcon', <String, dynamic>{
      'path': path,
      'destinationPath': destinationPath,
    });
    return value == true;
  }

  Future<String?> ensureKeychainKey() async {
    final dynamic value = await _invoke('ensureKeychainKey');
    return value is String && value.isNotEmpty ? value : null;
  }
}
