// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/foundation.dart';

class Hotkeys {
  String key;
  List<String> modifiers;
  List<KeyMap> keymaps;
  List<String> prohibited;
  bool noopScreenBusy;

  Hotkeys({
    required this.key,
    required this.modifiers,
    required this.keymaps,
    required this.prohibited,
    required this.noopScreenBusy,
  });

  String get hotkey {
    if (modifiers.isNotEmpty) return '${modifiers.join('+')}+$key';
    if (key.isNotEmpty) return key;
    return "NoKey";
  }

  Hotkeys copyWith({
    String? key,
    List<String>? modifiers,
    List<KeyMap>? keymaps,
    List<String>? prohibited,
    bool? noopScreenBusy,
  }) {
    return Hotkeys(
      key: key ?? this.key,
      modifiers: modifiers ?? this.modifiers,
      keymaps: keymaps ?? this.keymaps,
      prohibited: prohibited ?? this.prohibited,
      noopScreenBusy: noopScreenBusy ?? this.noopScreenBusy,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'key': key,
      'modifiers': modifiers,
      'keymaps': keymaps.map((KeyMap x) => x.toMap()).toList(),
      'prohibited': prohibited,
      'noopScreenBusy': noopScreenBusy,
    };
  }

  factory Hotkeys.fromMap(Map<String, dynamic> map) {
    return Hotkeys(
      key: (map['key'] ?? '') as String,
      modifiers: List<String>.from(map['modifiers'] ?? const <String>[]),
      keymaps: List<KeyMap>.from(
        (map['keymaps'] as List<dynamic>).map<KeyMap>(
          (dynamic x) => KeyMap.fromMap(x as Map<String, dynamic>),
        ),
      ),
      prohibited: List<String>.from(map['prohibited'] ?? const <String>[]),
      noopScreenBusy: (map['noopScreenBusy'] ?? false) as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory Hotkeys.fromJson(String source) => Hotkeys.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'Hotkeys(key: $key, modifiers: $modifiers, keymaps: $keymaps, prohibited: $prohibited, noopScreenBusy: $noopScreenBusy)';
  }

  @override
  bool operator ==(covariant Hotkeys other) {
    if (identical(this, other)) return true;

    return other.key == key &&
        listEquals(other.modifiers, modifiers) &&
        listEquals(other.keymaps, keymaps) &&
        listEquals(other.prohibited, prohibited) &&
        other.noopScreenBusy == noopScreenBusy;
  }

  @override
  int get hashCode {
    return key.hashCode ^ modifiers.hashCode ^ keymaps.hashCode ^ prohibited.hashCode ^ noopScreenBusy.hashCode;
  }
}

enum TriggerType {
  press,
  doublePress,
  movement,
  duration,
}

class KeyMap {
  bool enabled;
  bool windowUnderMouse;
  String name;

  /// [0] - title, exe, class, [1] - searchFor
  List<String> windowsInfo;
  bool boundToRegion;
  Region region;
  // enum
  TriggerType triggerType;

  /// press: [0] - has double press,
  /// Movemenet: [0] - direction , [1] - distanceMin, [2] - Distance max
  /// Duration: [0] - min miliseconds, [1] - max miliseconds
  List<int> triggerInfo;
  List<KeyAction> actions;
  List<String> variableCheck;

  KeyMap({
    required this.enabled,
    required this.windowUnderMouse,
    required this.name,
    required this.windowsInfo,
    required this.boundToRegion,
    required this.region,
    required this.triggerType,
    required this.triggerInfo,
    required this.actions,
    required this.variableCheck,
  }) {
    if (windowsInfo.length != 2) windowsInfo = <String>["any", ""];
    if (triggerInfo.length != 3) {
      while (triggerInfo.length != 3) {
        triggerInfo.add(0);
      }
    }
    if (variableCheck.length != 2) variableCheck = <String>["", ""];
  }

  KeyMap copyWith({
    bool? enabled,
    bool? windowUnderMouse,
    String? name,
    List<String>? windowsInfo,
    bool? boundToRegion,
    Region? region,
    TriggerType? triggerType,
    List<int>? triggerInfo,
    List<KeyAction>? actions,
    List<String>? variableCheck,
  }) {
    return KeyMap(
      enabled: enabled ?? this.enabled,
      windowUnderMouse: windowUnderMouse ?? this.windowUnderMouse,
      name: name ?? this.name,
      windowsInfo: windowsInfo ?? this.windowsInfo,
      boundToRegion: boundToRegion ?? this.boundToRegion,
      region: region ?? this.region,
      triggerType: triggerType ?? this.triggerType,
      triggerInfo: triggerInfo ?? this.triggerInfo,
      actions: actions ?? this.actions,
      variableCheck: variableCheck ?? this.variableCheck,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'enabled': enabled,
      'windowUnderMouse': windowUnderMouse,
      'name': name,
      'windowsInfo': windowsInfo,
      'boundToRegion': boundToRegion,
      'region': region.toMap(),
      'triggerType': triggerType.index,
      'triggerInfo': triggerInfo,
      'actions': actions.map((KeyAction x) => x.toMap()).toList(),
      'variableCheck': variableCheck,
    };
  }

  factory KeyMap.fromMap(Map<String, dynamic> map) {
    return KeyMap(
      enabled: (map['enabled'] ?? false) as bool,
      windowUnderMouse: (map['windowUnderMouse'] ?? false) as bool,
      name: (map['name'] ?? '') as String,
      windowsInfo: List<String>.from(map['windowsInfo'] ?? const <String>[]),
      boundToRegion: (map['boundToRegion'] ?? false) as bool,
      region: Region.fromMap(map['region'] as Map<String, dynamic>),
      triggerType: TriggerType.values[(map['triggerType'] ?? 0) as int],
      triggerInfo: List<int>.from(map['triggerInfo'] ?? const <int>[]),
      actions: List<KeyAction>.from(
        (map['actions'] as List<dynamic>).map<KeyAction>(
          (dynamic x) => KeyAction.fromMap(x as Map<String, dynamic>),
        ),
      ),
      variableCheck: List<String>.from(map['variableCheck'] ?? const <String>[]),
    );
  }

  String toJson() => json.encode(toMap());

  factory KeyMap.fromJson(String source) => KeyMap.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'KeyMap(enabled: $enabled, windowUnderMouse: $windowUnderMouse, name: $name, windowsInfo: $windowsInfo, boundToRegion: $boundToRegion, region: $region, triggerType: $triggerType, triggerInfo: $triggerInfo, actions: $actions, variableCheck: $variableCheck)';
  }

  @override
  bool operator ==(covariant KeyMap other) {
    if (identical(this, other)) return true;

    return other.enabled == enabled &&
        other.windowUnderMouse == windowUnderMouse &&
        other.name == name &&
        listEquals(other.windowsInfo, windowsInfo) &&
        other.boundToRegion == boundToRegion &&
        other.region == region &&
        other.triggerType == triggerType &&
        listEquals(other.triggerInfo, triggerInfo) &&
        listEquals(other.actions, actions) &&
        listEquals(other.variableCheck, variableCheck);
  }

  @override
  int get hashCode {
    return enabled.hashCode ^
        windowUnderMouse.hashCode ^
        name.hashCode ^
        windowsInfo.hashCode ^
        boundToRegion.hashCode ^
        region.hashCode ^
        triggerType.hashCode ^
        triggerInfo.hashCode ^
        actions.hashCode ^
        variableCheck.hashCode;
  }
}

enum ActionType {
  sendKeys,
  hotkey,
  tabameFunction,
  setVar,
  sendClick,
}

class HotKeyInfo {
  static const List<String> windowInfo = <String>["any", "exe", "class", "title"];
  static const Map<String, String> windowInfoNames = <String, String>{
    "any": "Any Window",
    "exe": "Exe Contains",
    "class": "Class Contains",
    "title": "Title Contains",
  };
  static const List<String> triggers = <String>["Press", "Double Press", "Mouse Movement", "Hold Duration"];
  static const List<String> mouseDirections = <String>["Left", "Right", "Up", "Down"];
  static const List<String> tabameFunctions = <String>[
    "ToggleTaskbar",
    "ToggleQuickMenu",
    "ToggleQuickRun",
    "OpenAudioSettings",
    "PlayPauseSpotify",
    "SwitchDesktop",
    "SwitchAudioOutput",
    "SwitchMicrophoneInput",
    "ToggleMicrophone",
    "SwitchDesktopToRight",
    "SwitchDesktopToLeft",
  ];
}

class KeyAction {
  //enum
  ActionType type;
  String value;
  KeyAction({
    required this.type,
    required this.value,
  });

  KeyAction copyWith({
    ActionType? type,
    String? value,
  }) {
    return KeyAction(
      type: type ?? this.type,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'type': type.index,
      'value': value,
    };
  }

  factory KeyAction.fromMap(Map<String, dynamic> map) {
    return KeyAction(
      type: ActionType.values[(map['type'] ?? 0) as int],
      value: (map['value'] ?? '') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory KeyAction.fromJson(String source) => KeyAction.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'KeyAction(type: $type, value: $value)';

  @override
  bool operator ==(covariant KeyAction other) {
    if (identical(this, other)) return true;

    return other.type == type && other.value == value;
  }

  @override
  int get hashCode => type.hashCode ^ value.hashCode;
}

class ClickAction {
  int x;
  int y;
  bool percentage;
  bool currentWindow;
  // enum
  AnchorType anchorType;
  ClickAction({
    required this.x,
    required this.y,
    required this.percentage,
    required this.currentWindow,
    required this.anchorType,
  });

  ClickAction copyWith({
    int? x,
    int? y,
    bool? percentage,
    bool? currentWindow,
    AnchorType? anchorType,
  }) {
    return ClickAction(
      x: x ?? this.x,
      y: y ?? this.y,
      percentage: percentage ?? this.percentage,
      currentWindow: currentWindow ?? this.currentWindow,
      anchorType: anchorType ?? this.anchorType,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'x': x,
      'y': y,
      'percentage': percentage,
      'currentWindow': currentWindow,
      'anchorType': anchorType.index,
    };
  }

  factory ClickAction.fromMap(Map<String, dynamic> map) {
    return ClickAction(
      x: (map['x'] ?? 0) as int,
      y: (map['y'] ?? 0) as int,
      percentage: (map['percentage'] ?? false) as bool,
      currentWindow: (map['currentWindow'] ?? false) as bool,
      anchorType: AnchorType.values[(map['anchorType'] ?? 0) as int],
    );
  }

  String toJson() => json.encode(toMap());

  factory ClickAction.fromJson(String source) => ClickAction.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'ClickAction(x: $x, y: $y, percentage: $percentage, currentWindow: $currentWindow, anchorType: $anchorType)';
  }

  @override
  bool operator ==(covariant ClickAction other) {
    if (identical(this, other)) return true;

    return other.x == x && other.y == y && other.percentage == percentage && other.currentWindow == currentWindow && other.anchorType == anchorType;
  }

  @override
  int get hashCode {
    return x.hashCode ^ y.hashCode ^ percentage.hashCode ^ currentWindow.hashCode ^ anchorType.hashCode;
  }
}

enum AnchorType {
  topLeft,
  topRight,
  topCenter,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

class Region {
  int x1;
  int y1;
  int x2;
  int y2;
  bool asPercentage;
  // enum
  AnchorType anchorType;
  Region({
    this.x1 = 0,
    this.y1 = 0,
    this.x2 = 0,
    this.y2 = 0,
    this.asPercentage = false,
    this.anchorType = AnchorType.topLeft,
  });
  int get sum => x1.abs() + x2.abs() + y1.abs() + y1.abs();
  int get area => (x2 - x1) * (y2 - y1);
  Region copyWith({
    int? x1,
    int? y1,
    int? x2,
    int? y2,
    bool? asPercentage,
    AnchorType? anchorType,
  }) {
    return Region(
      x1: x1 ?? this.x1,
      y1: y1 ?? this.y1,
      x2: x2 ?? this.x2,
      y2: y2 ?? this.y2,
      asPercentage: asPercentage ?? this.asPercentage,
      anchorType: anchorType ?? this.anchorType,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'x1': x1,
      'y1': y1,
      'x2': x2,
      'y2': y2,
      'asPercentage': asPercentage,
      'anchorType': anchorType.index,
    };
  }

  factory Region.fromMap(Map<String, dynamic> map) {
    return Region(
      x1: (map['x1'] ?? 0) as int,
      y1: (map['y1'] ?? 0) as int,
      x2: (map['x2'] ?? 0) as int,
      y2: (map['y2'] ?? 0) as int,
      asPercentage: (map['asPercentage'] ?? false) as bool,
      anchorType: AnchorType.values[(map['anchorType'] ?? 0) as int],
    );
  }

  String toJson() => json.encode(toMap());

  factory Region.fromJson(String source) => Region.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'Region(x1: $x1, y1: $y1, x2: $x2, y2: $y2, asPercentage: $asPercentage, anchorType: $anchorType)';
  }

  @override
  bool operator ==(covariant Region other) {
    if (identical(this, other)) return true;

    return other.x1 == x1 && other.y1 == y1 && other.x2 == x2 && other.y2 == y2 && other.asPercentage == asPercentage && other.anchorType == anchorType;
  }

  @override
  int get hashCode {
    return x1.hashCode ^ y1.hashCode ^ x2.hashCode ^ y2.hashCode ^ asPercentage.hashCode ^ anchorType.hashCode;
  }
}
