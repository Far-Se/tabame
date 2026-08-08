import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';

import '../platform_models.dart';

const String linuxPlatformChannelName = 'tabame/linux/core';
const String linuxEventChannelName = 'tabame/linux/events';

/// A native Linux capability probe. X11-only services are false when the
/// process is running in a Wayland session; a Wayland/XWayland display is not
/// treated as an X11 permission boundary.
class LinuxCapabilitySnapshot {
  const LinuxCapabilitySnapshot({
    required this.displayServer,
    required this.x11,
    required this.wayland,
    required this.windowEnumeration,
    required this.windowActivation,
    required this.monitorGeometry,
    required this.globalHotkeys,
    required this.clipboardMonitoring,
    required this.filesystemWatching,
    required this.notifications,
    required this.secretService,
    required this.desktopFileDiscovery,
    this.xwayland = false,
    this.inputInjection = false,
    this.screenCapture = false,
    this.screenRecording = false,
    this.waylandCompositor = 'unknown',
    this.portalDesktop = false,
    this.screenCastPortal = false,
    this.screenshotPortal = false,
    this.fileChooserPortal = false,
    this.globalShortcutsPortal = false,
    this.remoteDesktopPortal = false,
    this.pipeWire = false,
    this.reasons = const <String, String>{},
  });

  const LinuxCapabilitySnapshot.unknown()
      : displayServer = 'unknown',
        x11 = false,
        wayland = false,
        windowEnumeration = false,
        windowActivation = false,
        monitorGeometry = false,
        globalHotkeys = false,
        clipboardMonitoring = false,
        filesystemWatching = false,
        notifications = false,
        secretService = false,
        desktopFileDiscovery = false,
        xwayland = false,
        inputInjection = false,
        screenCapture = false,
        screenRecording = false,
        waylandCompositor = 'unknown',
        portalDesktop = false,
        screenCastPortal = false,
        screenshotPortal = false,
        fileChooserPortal = false,
        globalShortcutsPortal = false,
        remoteDesktopPortal = false,
        pipeWire = false,
        reasons = const <String, String>{};

  final String displayServer;
  final bool x11;
  final bool wayland;
  final bool windowEnumeration;
  final bool windowActivation;
  final bool monitorGeometry;
  final bool globalHotkeys;
  final bool clipboardMonitoring;
  final bool filesystemWatching;
  final bool notifications;
  final bool secretService;
  final bool desktopFileDiscovery;
  final bool xwayland;
  final bool inputInjection;
  final bool screenCapture;
  final bool screenRecording;
  final String waylandCompositor;
  final bool portalDesktop;
  final bool screenCastPortal;
  final bool screenshotPortal;
  final bool fileChooserPortal;
  final bool globalShortcutsPortal;
  final bool remoteDesktopPortal;
  final bool pipeWire;
  final Map<String, String> reasons;

  bool get isWaylandOnly => wayland && !x11;

  /// Portal/PipeWire presence is infrastructure information only. It does not
  /// mean that a capture permission was granted or that a capture adapter is
  /// installed.
  bool get hasCaptureInfrastructure => screenCastPortal && pipeWire;

  String reasonFor(String capability) => reasons[capability] ?? '';

  factory LinuxCapabilitySnapshot.fromValue(dynamic value) {
    if (value is! Map<dynamic, dynamic>) return const LinuxCapabilitySnapshot.unknown();
    final Map<String, dynamic> map = Map<String, dynamic>.from(value);
    final Map<String, String> reasons = <String, String>{};
    for (final MapEntry<String, dynamic> entry in map.entries) {
      if (!entry.key.endsWith('Reason') || entry.value is! String) continue;
      reasons[entry.key.substring(0, entry.key.length - 'Reason'.length)] = entry.value as String;
    }
    return LinuxCapabilitySnapshot(
      displayServer: (map['displayServer'] ?? 'unknown').toString(),
      x11: _asBool(map['x11']),
      wayland: _asBool(map['wayland']),
      windowEnumeration: _asBool(map['windowEnumeration']),
      windowActivation: _asBool(map['windowActivation']),
      monitorGeometry: _asBool(map['monitorGeometry']),
      globalHotkeys: _asBool(map['globalHotkeys']),
      clipboardMonitoring: _asBool(map['clipboardMonitoring']),
      filesystemWatching: _asBool(map['filesystemWatching']),
      notifications: _asBool(map['notifications']),
      secretService: _asBool(map['secretService']),
      desktopFileDiscovery: _asBool(map['desktopFileDiscovery']),
      xwayland: _asBool(map['xWayland']),
      inputInjection: _asBool(map['inputInjection']),
      screenCapture: _asBool(map['screenCapture']),
      screenRecording: _asBool(map['screenRecording']),
      waylandCompositor: (map['waylandCompositor'] ?? 'unknown').toString(),
      portalDesktop: _asBool(map['portalDesktop']),
      screenCastPortal: _asBool(map['screenCastPortal']),
      screenshotPortal: _asBool(map['screenshotPortal']),
      fileChooserPortal: _asBool(map['fileChooserPortal']),
      globalShortcutsPortal: _asBool(map['globalShortcutsPortal']),
      remoteDesktopPortal: _asBool(map['remoteDesktopPortal']),
      pipeWire: _asBool(map['pipeWire']),
      reasons: Map<String, String>.unmodifiable(reasons),
    );
  }

  static bool _asBool(dynamic value) => value == true || value == 1 || value == 'true';
}

/// The only Linux native boundary used by the X11 and reduced Wayland adapters.
class LinuxPlatformChannel {
  LinuxPlatformChannel({
    MethodChannel? methodChannel,
    EventChannel? eventChannel,
    bool? available,
    LinuxCapabilitySnapshot? initialCapabilities,
  })  : methodChannel = methodChannel ?? const MethodChannel(linuxPlatformChannelName),
        eventChannel = eventChannel ?? const EventChannel(linuxEventChannelName),
        _available = available ?? Platform.isLinux,
        _capabilities = initialCapabilities ?? const LinuxCapabilitySnapshot.unknown();

  static final LinuxPlatformChannel instance = LinuxPlatformChannel();

  final MethodChannel methodChannel;
  final EventChannel eventChannel;
  final bool _available;
  LinuxCapabilitySnapshot _capabilities;
  late final Stream<Map<String, dynamic>> _events = eventChannel
      .receiveBroadcastStream()
      .where((dynamic value) => value is Map<dynamic, dynamic>)
      .map((dynamic value) => Map<String, dynamic>.from(value as Map<dynamic, dynamic>));

  bool get isAvailable => _available;
  LinuxCapabilitySnapshot get cachedCapabilities => _capabilities;
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
      // A missing display server, D-Bus service, or desktop permission is a
      // capability change, not a reason to abort the launcher startup.
      return null;
    }
  }

  Future<LinuxCapabilitySnapshot> refreshCapabilities() async {
    final dynamic value = await _invoke('capabilities');
    // Do not retain permissions or services from an earlier display/session
    // after a failed refresh. Unknown is safer than stale availability.
    _capabilities = value == null ? const LinuxCapabilitySnapshot.unknown() : LinuxCapabilitySnapshot.fromValue(value);
    return _capabilities;
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

  Future<HotkeyRegistrationResult> registerGlobalHotkey({
    required String key,
    required List<String> modifiers,
    String name = 'summon',
  }) async {
    final dynamic value = await _invoke('registerGlobalHotkey', <String, dynamic>{
      'key': key,
      'modifiers': modifiers,
      'name': name,
    });
    if (value is! Map<dynamic, dynamic>) {
      return const HotkeyRegistrationResult(
        registered: false,
        permissionRequired: true,
        reason: 'The Linux global hotkey service is unavailable. Use the visible Tabame window instead.',
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

  Future<bool> showNotification({required String title, required String body}) async {
    return await _invoke('showNotification', <String, dynamic>{'title': title, 'body': body}) == true;
  }

  /// Returns a base64-encoded random key held by the freedesktop Secret
  /// Service, or null when the service is absent, locked, or inaccessible.
  Future<String?> ensureSecretServiceKey() async {
    final dynamic value = await _invoke('ensureSecretServiceKey');
    return value is String && value.isNotEmpty ? value : null;
  }
}
