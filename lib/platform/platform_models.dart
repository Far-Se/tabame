import 'dart:math';
import 'dart:typed_data';

/// Native-window data exposed to shared code without leaking OS handle types.
///
/// [nativeId] is an opaque adapter-owned token. Shared code may retain it as
/// the identity of a snapshot and pass the complete [PlatformWindow] back to
/// [WindowService], but it must not parse it or assume an OS representation.
/// Coordinates are global logical points; each adapter owns conversion from its
/// native coordinate system.
class PlatformWindow {
  const PlatformWindow({
    required this.nativeId,
    required this.title,
    required this.applicationName,
    required this.bundleIdentifier,
    required this.processId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    this.executable = '',
    this.executablePath = '',
    this.className = '',
    this.monitorId = '',
    this.helpText = '',
    this.icon,
    this.isPinned = false,
    this.isOnScreen = true,
    this.isMinimized = false,
    this.layer = 0,
  });

  /// Opaque identity owned by the platform adapter; never parse this value in
  /// shared code as an HWND, CGWindowID, X11 ID, or any other native handle.
  final String nativeId;
  final String title;
  final String applicationName;
  final String bundleIdentifier;
  final int processId;
  final double x;
  final double y;
  final double width;
  final double height;
  final String executable;
  final String executablePath;
  final String className;
  final String monitorId;
  final String helpText;
  final Object? icon;
  final bool isPinned;
  final bool isOnScreen;
  final bool isMinimized;
  final int layer;

  /// A stable key for one current enumeration snapshot. It has no native type.
  String get identity => nativeId;

  String get searchText => <String>[title, applicationName, executable, executablePath].join(' ').toLowerCase();

  factory PlatformWindow.fromMap(Map<String, dynamic> map) {
    return PlatformWindow(
      nativeId: '${map['nativeId'] ?? ''}',
      title: '${map['title'] ?? ''}',
      applicationName: '${map['applicationName'] ?? ''}',
      bundleIdentifier: '${map['bundleIdentifier'] ?? ''}',
      processId: _asInt(map['processId']),
      x: _asDouble(map['x']),
      y: _asDouble(map['y']),
      width: _asDouble(map['width']),
      height: _asDouble(map['height']),
      executable: '${map['executable'] ?? ''}',
      executablePath: '${map['executablePath'] ?? ''}',
      className: '${map['className'] ?? ''}',
      monitorId: '${map['monitorId'] ?? ''}',
      icon: map['icon'],
      helpText: '${map['helpText'] ?? ''}',
      isPinned: map['isPinned'] == true,
      isOnScreen: map['isOnScreen'] is bool ? map['isOnScreen'] as bool : true,
      isMinimized: map['isMinimized'] is bool ? map['isMinimized'] as bool : false,
      layer: _asInt(map['layer']),
    );
  }

  @override
  bool operator ==(Object other) => other is PlatformWindow && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

/// A display's bounds and usable work area in the adapter's coordinate system.
class PlatformMonitor {
  const PlatformMonitor({
    required this.nativeId,
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.visibleX,
    required this.visibleY,
    required this.visibleWidth,
    required this.visibleHeight,
    required this.scaleFactor,
    required this.isPrimary,
  });

  final String nativeId;
  final double x;
  final double y;
  final double width;
  final double height;
  final double visibleX;
  final double visibleY;
  final double visibleWidth;
  final double visibleHeight;
  final double scaleFactor;
  final bool isPrimary;

  /// A stable adapter-owned identity. Shared code must treat it as opaque.
  String get identity => nativeId;

  factory PlatformMonitor.fromMap(Map<String, dynamic> map) {
    return PlatformMonitor(
      nativeId: (map['nativeId'] ?? '') as String,
      x: _asDouble(map['x']),
      y: _asDouble(map['y']),
      width: _asDouble(map['width']),
      height: _asDouble(map['height']),
      visibleX: _asDouble(map['visibleX']),
      visibleY: _asDouble(map['visibleY']),
      visibleWidth: _asDouble(map['visibleWidth']),
      visibleHeight: _asDouble(map['visibleHeight']),
      scaleFactor: _asDouble(map['scaleFactor'], fallback: 1),
      isPrimary: (map['isPrimary'] ?? false) as bool,
    );
  }
}

class PlatformPoint {
  const PlatformPoint({required this.x, required this.y});

  final double x;
  final double y;

  factory PlatformPoint.fromMap(Map<String, dynamic> map) {
    return PlatformPoint(
      x: _asDouble(map['x']),
      y: _asDouble(map['y']),
    );
  }
}

class PlatformPopupPlacement {
  const PlatformPopupPlacement({
    required this.x,
    required this.y,
    required this.width,
    required this.height,
    required this.monitorId,
  });

  final double x;
  final double y;
  final double width;
  final double height;
  final String monitorId;

  factory PlatformPopupPlacement.fromMap(Map<String, dynamic> map) {
    return PlatformPopupPlacement(
      x: _asDouble(map['x']),
      y: _asDouble(map['y']),
      width: _asDouble(map['width']),
      height: _asDouble(map['height']),
      monitorId: (map['monitorId'] ?? '') as String,
    );
  }
}

enum PlatformHotkeyPhase {
  pressedKbd,
  releaseKbd,
  pressed,
  moved,
  released,
}

extension PlatformHotkeyPhaseWireName on PlatformHotkeyPhase {
  String get wireName => name;

  static PlatformHotkeyPhase fromWireName(String value) {
    return PlatformHotkeyPhase.values.firstWhere(
      (PlatformHotkeyPhase phase) => phase.wireName == value,
      orElse: () => PlatformHotkeyPhase.pressed,
    );
  }
}

class PlatformMouseTrace {
  const PlatformMouseTrace({this.start = const Point<int>(0, 0), this.end = const Point<int>(0, 0)});

  final Point<int> start;
  final Point<int> end;

  Point<int> get diff => end - start;
}

class PlatformHotkeyTiming {
  const PlatformHotkeyTiming({this.start = 0, this.end = 0});

  final int start;
  final int end;

  int get duration => end - start;
}

/// Neutral event emitted by a hotkey adapter. The action strings intentionally
/// match the existing persisted dispatcher phases so Windows behavior can be
/// moved behind an adapter without changing settings data.
class PlatformHotkeyEvent {
  const PlatformHotkeyEvent({
    required this.name,
    this.hotkey = '',
    this.action = 'pressed',
    this.key = '',
    this.modifiers = const <String>[],
    this.mouse = const PlatformMouseTrace(),
    this.time = const PlatformHotkeyTiming(),
    this.timestamp,
  });

  final String name;
  final String hotkey;
  final String action;
  final String key;
  final List<String> modifiers;
  final PlatformMouseTrace mouse;
  final PlatformHotkeyTiming time;
  final DateTime? timestamp;

  PlatformHotkeyPhase get phase => PlatformHotkeyPhaseWireName.fromWireName(action);

  PlatformHotkeyEvent copyWith({
    String? name,
    String? hotkey,
    String? action,
    String? key,
    List<String>? modifiers,
    PlatformMouseTrace? mouse,
    PlatformHotkeyTiming? time,
    DateTime? timestamp,
  }) {
    return PlatformHotkeyEvent(
      name: name ?? this.name,
      hotkey: hotkey ?? this.hotkey,
      action: action ?? this.action,
      key: key ?? this.key,
      modifiers: modifiers ?? this.modifiers,
      mouse: mouse ?? this.mouse,
      time: time ?? this.time,
      timestamp: timestamp ?? this.timestamp,
    );
  }

  factory PlatformHotkeyEvent.fromMap(Map<String, dynamic> map) {
    final dynamic rawTimestamp = map['timestamp'];
    final dynamic rawStart = map['mouseStart'];
    final dynamic rawEnd = map['mouseEnd'];
    final Point<int> start = rawStart is Map<dynamic, dynamic>
        ? Point<int>(_asInt(rawStart['x']), _asInt(rawStart['y']))
        : Point<int>(_asInt(map['sX']), _asInt(map['sY']));
    final Point<int> end = rawEnd is Map<dynamic, dynamic>
        ? Point<int>(_asInt(rawEnd['x']), _asInt(rawEnd['y']))
        : Point<int>(_asInt(map['eX']), _asInt(map['eY']));
    final dynamic rawModifiers = map['modifiers'];
    return PlatformHotkeyEvent(
      name: (map['name'] ?? '') as String,
      hotkey: (map['hotkey'] ?? '') as String,
      action: (map['action'] ?? map['phase'] ?? map['info'] ?? 'pressed') as String,
      key: (map['key'] ?? '') as String,
      modifiers: rawModifiers is List<dynamic> ? List<String>.from(rawModifiers) : const <String>[],
      mouse: PlatformMouseTrace(start: start, end: end),
      time: PlatformHotkeyTiming(
        start: _asInt(map['start']),
        end: _asInt(map['end']),
      ),
      timestamp: rawTimestamp is num ? DateTime.fromMillisecondsSinceEpoch(rawTimestamp.toInt()) : null,
    );
  }
}

/// A registration request made entirely from logical key names and neutral
/// trigger metadata. Native adapters translate it into their own key format.
class PlatformHotkeyBinding {
  const PlatformHotkeyBinding({
    required this.name,
    required this.key,
    required this.modifiers,
    this.hotkey = '',
    this.listensToMovement = false,
    this.matchWindowBy = '',
    this.matchWindowText = '',
    this.activateWindowUnderCursor = false,
    this.noopScreenBusy = false,
    this.prohibitedWindows = const <String>[],
    this.region = const PlatformHotkeyRegion(),
  });

  final String name;
  final String key;
  final List<String> modifiers;
  final String hotkey;
  final bool listensToMovement;
  final String matchWindowBy;
  final String matchWindowText;
  final bool activateWindowUnderCursor;
  final bool noopScreenBusy;
  final List<String> prohibitedWindows;
  final PlatformHotkeyRegion region;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'key': key,
      'hotkey': hotkey,
      'modifiers': List<String>.from(modifiers),
      'listensToMovement': listensToMovement,
      'matchWindowBy': matchWindowBy,
      'matchWindowText': matchWindowText,
      'activateWindowUnderCursor': activateWindowUnderCursor,
      'noopScreenBusy': noopScreenBusy,
      'prohibitedWindows': List<String>.from(prohibitedWindows),
      'region': region.toMap(),
    };
  }
}

class PlatformHotkeyRegion {
  const PlatformHotkeyRegion({
    this.asPercentage = false,
    this.onScreen = false,
    this.x1 = 0,
    this.x2 = 0,
    this.y1 = 0,
    this.y2 = 0,
    this.anchorType = 0,
  });

  final bool asPercentage;
  final bool onScreen;
  final int x1;
  final int x2;
  final int y1;
  final int y2;
  final int anchorType;

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'asPercentage': asPercentage,
      'onScreen': onScreen,
      'x1': x1,
      'x2': x2,
      'y1': y1,
      'y2': y2,
      'anchorType': anchorType,
    };
  }
}

enum PlatformMouseButton {
  left,
  right,
  middle,
  button4,
  button5,
}

enum PlatformInputEventType {
  keyDown,
  keyUp,
  mouseDown,
  mouseUp,
  mouseMove,
  gesture,
}

class PlatformInputEvent {
  const PlatformInputEvent({
    required this.type,
    this.key = '',
    this.button,
    this.position = const Point<int>(0, 0),
    this.gesture = '',
    this.timestamp,
  });

  final PlatformInputEventType type;
  final String key;
  final PlatformMouseButton? button;
  final Point<int> position;
  final String gesture;
  final DateTime? timestamp;
}

class HotkeyRegistrationResult {
  const HotkeyRegistrationResult({
    required this.registered,
    this.permissionRequired = false,
    this.reason = '',
  });

  final bool registered;
  final bool permissionRequired;
  final String reason;
}

class PlatformClipboardText {
  const PlatformClipboardText({required this.text, this.changeCount});

  final String text;
  final int? changeCount;
}

/// Clipboard payload shared by the history orchestrator and platform adapters.
///
/// The platform boundary deliberately models formats instead of exposing
/// native clipboard handles or format constants. Linux/X11 and macOS currently
/// populate text only; Windows may populate HTML or image bytes.
class PlatformClipboardContent {
  const PlatformClipboardContent({
    this.text = '',
    this.html = '',
    this.imageBytes,
  });

  final String text;
  final String html;
  final Uint8List? imageBytes;

  bool get hasText => text.isNotEmpty;
  bool get hasRichText => html.isNotEmpty;
  bool get hasImage => imageBytes != null && imageBytes!.isNotEmpty;
}

/// Metadata for an image captured by an adapter directly to a file.
class PlatformClipboardImageInfo {
  const PlatformClipboardImageInfo({
    required this.path,
    required this.byteLength,
    this.hash = '',
  });

  final String path;
  final int byteLength;
  final String hash;
}

int _asInt(dynamic value) => value is num ? value.toInt() : int.tryParse('$value') ?? 0;

double _asDouble(dynamic value, {double fallback = 0}) =>
    value is num ? value.toDouble() : double.tryParse('$value') ?? fallback;
