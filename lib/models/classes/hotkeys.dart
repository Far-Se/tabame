// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../keys.dart';
import '../win32/win32.dart';

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
    if (modifiers.isNotEmpty) return '${modifiers.join('+')}+$key'.toUpperCase();
    if (key.isNotEmpty) return key.toUpperCase();
    return "NoKey";
  }

  bool get hasDuration => keymaps.any((KeyMap km) => km.triggerType == TriggerType.duration && km.enabled);
  bool get hasDoublePress => keymaps.any((KeyMap km) => km.triggerType == TriggerType.doublePress && km.enabled);
  bool get hasMouseMovement => keymaps.any((KeyMap km) => km.triggerType == TriggerType.movement && km.enabled);
  bool get hasMouseMovementTriggers => keymaps.any((KeyMap km) => km.triggerType == TriggerType.movement && km.triggerInfo[2] == -1 && km.enabled);

  List<KeyMap> get getPress => keymaps.where((KeyMap km) => km.triggerType == TriggerType.press && km.enabled).toList();
  List<KeyMap> get getDurationKeys => keymaps.where((KeyMap km) => km.triggerType == TriggerType.duration && km.enabled).toList();
  List<KeyMap> get getDoublePress => keymaps.where((KeyMap km) => km.triggerType == TriggerType.doublePress && km.enabled).toList();
  List<KeyMap> get getHotkeysWithMovement => keymaps.where((KeyMap km) => km.triggerType == TriggerType.movement && km.triggerInfo[2] != -1 && km.enabled).toList();
  List<KeyMap> get getHotkeysWithMovementTriggers =>
      keymaps.where((KeyMap km) => km.triggerType == TriggerType.movement && km.triggerInfo[2] == -1 && km.enabled).toList();

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
  bool regionOnScreen = false;
  Region region;
  // enum
  TriggerType triggerType;
  bool get isMouseInRegion {
    if (!boundToRegion) return true;
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final Pointer<RECT> lpRect = calloc<RECT>();
    int hwnd = GetForegroundWindow();
    if (!windowUnderMouse) {
      hwnd = GetDesktopWindow();
      GetWindowRect(hwnd, lpRect);
      while (lpPoint.ref.x >= lpRect.ref.right) {
        lpPoint.ref.x = lpPoint.ref.x - lpRect.ref.right;
      }
      while (lpPoint.ref.y >= lpRect.ref.bottom) {
        lpPoint.ref.y = lpPoint.ref.y - lpRect.ref.right;
      }
    } else {
      if (windowUnderMouse) {
        hwnd = WindowFromPoint(lpPoint.ref);
        hwnd = GetAncestor(hwnd, 2);
      }
      GetWindowRect(hwnd, lpRect);
    }

    int x = 0, y = 0;
    int yTop = lpPoint.ref.y - lpRect.ref.top;
    int yBottom = lpPoint.ref.y - lpRect.ref.bottom;
    int xLeft = lpPoint.ref.x - lpRect.ref.left;
    int xRight = lpPoint.ref.x - lpRect.ref.right;
    int width = lpRect.ref.right - lpRect.ref.left;
    int height = lpRect.ref.bottom - lpRect.ref.top;
    free(lpRect);
    free(lpPoint);

    if (region.anchorType == AnchorType.topLeft) {
      x = xLeft;
      y = yTop;
    } else if (region.anchorType == AnchorType.topRight) {
      x = xRight;
      y = yTop;
    } else if (region.anchorType == AnchorType.bottomLeft) {
      x = xLeft;
      y = yBottom;
    } else if (region.anchorType == AnchorType.bottomRight) {
      x = xRight;
      y = yBottom;
    }
    x = x.abs();
    y = y.abs();
    int percentageX = ((x / width) * 100).ceil();
    int percentageY = ((y / height) * 100).ceil();
    if (region.asPercentage) {
      x = percentageX;
      y = percentageY;
    }

    if (x >= region.x1 && x <= region.x2 && y >= region.y1 && y <= region.y2) {
      return true;
    }
    return false;
  }

  /// Press:
  ///
  ///  [0] - has double press,
  ///
  /// Movement:
  ///
  ///  [0] - direction , [1] - distanceMin, [2] - Distance max
  ///
  /// MovementSteps:
  ///
  ///  [0] - direction, [1] - distance, [2] - hasSteps = -1
  ///
  /// Duration:
  ///
  ///  [0] - min miliseconds, [1] - max miliseconds
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
    if (boundToRegion && windowsInfo[0] == "any") {
      regionOnScreen = true;
    }
  }
  void applyActions() {
    int delayed = 1;
    if (windowUnderMouse) {
      print("Activating window under cursor");
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      int hWnd = WindowFromPoint(lpPoint.ref);
      hWnd = GetAncestor(hWnd, 2);
      free(lpPoint);
      if (GetForegroundWindow() != hWnd) {
        delayed = 150;
        SetForegroundWindow(hWnd);
        SetFocus(hWnd);
        SetActiveWindow(hWnd);
        SendMessage(hWnd, WM_UPDATEUISTATE, 2 & 0x2, 0);
      }
      // Win32.activeWindowUnderCursor();
    }
    Future<void>.delayed(Duration(milliseconds: delayed), () {
      for (KeyAction action in actions) {
        if (action.type == ActionType.hotkey) {
          final List<String> keys = action.value.split('+');
          String sendKey = "";
          for (String key in keys) {
            if (key.length > 1) {
              sendKey += "{#$key}";
            } else {
              sendKey += "$key";
            }
          }
          print(sendKey);
          WinKeys.send(sendKey);

          //
        } else if (action.type == ActionType.sendKeys) {
          WinKeys.send(action.value);
        } else if (action.type == ActionType.sendClick) {
          final ClickAction click = ClickAction.fromJson(action.value);
        } else if (action.type == ActionType.tabameFunction) {
          if (HotKeyInfo.tabameFunctionsMap.containsKey(action.value)) {
            HotKeyInfo.tabameFunctionsMap[action.value]!();
          }
          //
        } else if (action.type == ActionType.setVar) {
          //
        }
      }
    });
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
  static Map<String, Function> tabameFunctionsMap = <String, Function>{
    "ToggleTaskbar": () => WinUtils.toggleTaskbar(),
    "ToggleQuickMenu": () {},
    "ToggleQuickRun": () {},
    "ShowLastActiveWindow": () {},
    "OpenAudioSettings": () {},
    "PlayPauseSpotify": () {},
    "SwitchAudioOutput": () => Audio.switchDefaultDevice(AudioDeviceType.output),
    "ToggleHiddenFiles": () => WinUtils.toggleHiddenFiles(),
    "ToggleDesktopFiles": () => WinUtils.toggleDesktopFiles(),
    "SwitchMicrophoneInput": () => Audio.switchDefaultDevice(AudioDeviceType.input),
    "ToggleMicrophone": () => Audio.getMuteAudioDevice(AudioDeviceType.input).then((bool value) => Audio.setMuteAudioDevice(!value, AudioDeviceType.input)),
    "SwitchDesktop": () => moveDesktopMethod(DesktopDirection.right),
    "SwitchDesktopToRight": () => WinUtils.moveDesktop(DesktopDirection.right),
    "SwitchDesktopToLeft": () => WinUtils.moveDesktop(DesktopDirection.left),
  };
  static List<String> tabameFunctions = tabameFunctionsMap.keys.toList();
  //keymap.keymaps[index].actions[0].type
  static const Map<ActionType, IconData> actionTypeIcons = <ActionType, IconData>{
    ActionType.hotkey: Icons.tag,
    ActionType.sendClick: Icons.mouse,
    ActionType.sendKeys: Icons.keyboard,
    ActionType.setVar: Icons.tune,
    ActionType.tabameFunction: Icons.functions,
  };
  static const Map<TriggerType, IconData> triggerTypeIcons = <TriggerType, IconData>{
    TriggerType.press: Icons.touch_app,
    TriggerType.doublePress: Icons.ads_click,
    TriggerType.duration: Icons.schedule,
    TriggerType.movement: Icons.gps_fixed,
  };
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
  bottomLeft,
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
