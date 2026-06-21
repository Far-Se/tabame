// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:math';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../pages/color_picker/win32_helper.dart';
import '../../pages/screen_capture.dart';
import '../globals.dart';
import '../settings.dart';
import '../win32/keys.dart';
import '../win32/mixed.dart';
import '../win32/win32.dart';
import '../win32/win_utils.dart';
import '../window_watcher.dart';
import 'boxes.dart';

class Hotkeys {
  static const List<String> modifierOrder = <String>["CTRL", "ALT", "SHIFT", "WIN"];
  static const String mouseButton4Key = "MouseButton4";
  static const String mouseButton5Key = "MouseButton5";
  static const String doubleAltKey = "DoubleAlt";
  static const String rightAltKey = "RightAlt";
  static const String rightControlKey = "RightControl";
  static const List<String> specialBindingKeys = <String>[
    mouseButton4Key,
    mouseButton5Key,
    doubleAltKey,
    rightAltKey,
    rightControlKey,
  ];
  static const Map<String, String> specialBindingLabels = <String, String>{
    mouseButton4Key: "Mouse Button 4",
    mouseButton5Key: "Mouse Button 5",
    doubleAltKey: "Double Alt",
    rightAltKey: "Right Alt",
    rightControlKey: "Right Control",
  };
  static const Map<String, String> namedKeyAliases = <String, String>{
    // Existing
    ' ': 'SPACE',
    'SPACEBAR': 'SPACE',

    'ESC': 'ESCAPE',
    'ENTER': 'RETURN',
    'BACKSPACE': 'BACK',
    'DEL': 'DELETE',

    'PAGEUP': 'PRIOR',
    'PAGEDOWN': 'NEXT',

    'LEFT ARROW': 'LEFT',
    'RIGHT ARROW': 'RIGHT',
    'UP ARROW': 'UP',
    'DOWN ARROW': 'DOWN',

    // Extra common navigation aliases
    'INS': 'INSERT',
    'PGUP': 'PRIOR',
    'PGDN': 'NEXT',

    // Modifier keys
    'CTRL': 'CONTROL',
    'LEFT CTRL': 'LCONTROL',
    'RIGHT CTRL': 'RCONTROL',

    'LEFT CONTROL': 'LCONTROL',
    'RIGHT CONTROL': 'RCONTROL',

    'ALT': 'MENU',
    'LEFT ALT': 'LMENU',
    'RIGHT ALT': 'RMENU',

    'SHIFT': 'SHIFT',
    'LEFT SHIFT': 'LSHIFT',
    'RIGHT SHIFT': 'RSHIFT',

    'WIN': 'LWIN',
    'LEFT WIN': 'LWIN',
    'RIGHT WIN': 'RWIN',

    'CMD': 'LWIN',
    'COMMAND': 'LWIN',

    // Locks
    'CAPSLOCK': 'CAPITAL',
    'NUMLOCK': 'NUMLOCK',
    'SCROLLLOCK': 'SCROLL',

    // Print/system
    'PRINTSCREEN': 'SNAPSHOT',
    'PRTSC': 'SNAPSHOT',
    'PRTSCN': 'SNAPSHOT',

    // Numpad operators
    'NUM *': 'NUMPADMULTIPLY',
    'NUM +': 'NUMPADADD',
    'NUM -': 'NUMPADSUBTRACT',
    'NUM /': 'NUMPADDIVIDE',
    'NUM .': 'NUMPADDECIMAL',

    'NUMPAD *': 'NUMPADMULTIPLY',
    'NUMPAD +': 'NUMPADADD',
    'NUMPAD -': 'NUMPADSUBTRACT',
    'NUMPAD /': 'NUMPADDIVIDE',
    'NUMPAD .': 'NUMPADDECIMAL',

    // Numpad digits
    'NUM 0': 'NUMPAD0',
    'NUM 1': 'NUMPAD1',
    'NUM 2': 'NUMPAD2',
    'NUM 3': 'NUMPAD3',
    'NUM 4': 'NUMPAD4',
    'NUM 5': 'NUMPAD5',
    'NUM 6': 'NUMPAD6',
    'NUM 7': 'NUMPAD7',
    'NUM 8': 'NUMPAD8',
    'NUM 9': 'NUMPAD9',

    'NUMPAD 0': 'NUMPAD0',
    'NUMPAD 1': 'NUMPAD1',
    'NUMPAD 2': 'NUMPAD2',
    'NUMPAD 3': 'NUMPAD3',
    'NUMPAD 4': 'NUMPAD4',
    'NUMPAD 5': 'NUMPAD5',
    'NUMPAD 6': 'NUMPAD6',
    'NUMPAD 7': 'NUMPAD7',
    'NUMPAD 8': 'NUMPAD8',
    'NUMPAD 9': 'NUMPAD9',
  };
  static const Map<String, String> namedKeyDisplayLabels = <String, String>{
    'SPACE': 'Space',
    'ESCAPE': 'Escape',
    'RETURN': 'Enter',
    'BACK': 'Backspace',
    'PRIOR': 'Page Up',
    'NEXT': 'Page Down',
    'LEFT': 'Left',
    'RIGHT': 'Right',
    'UP': 'Up',
    'DOWN': 'Down',
    'INSERT': 'Insert',
    'DELETE': 'Delete',
    'HOME': 'Home',
    'END': 'End',
    'TAB': 'Tab',
    'NUMPAD0': 'Numpad 0',
    'NUMPAD1': 'Numpad 1',
    'NUMPAD2': 'Numpad 2',
    'NUMPAD3': 'Numpad 3',
    'NUMPAD4': 'Numpad 4',
    'NUMPAD5': 'Numpad 5',
    'NUMPAD6': 'Numpad 6',
    'NUMPAD7': 'Numpad 7',
    'NUMPAD8': 'Numpad 8',
    'NUMPAD9': 'Numpad 9',
    'NUMPADADD': 'Numpad +',
    'NUMPADSUBTRACT': 'Numpad -',
    'NUMPADMULTIPLY': 'Numpad *',
    'NUMPADDIVIDE': 'Numpad /',
    'NUMPADDECIMAL': 'Numpad .',
    'NUMPADSEPARATOR': 'Numpad Separator',
  };

  String key;
  List<String> modifiers;
  List<KeyMap> keymaps;
  List<String> prohibited;
  bool noopScreenBusy;
  bool waitForDoublePress;

  Hotkeys({
    required this.key,
    required this.modifiers,
    required this.keymaps,
    required this.prohibited,
    required this.noopScreenBusy,
    required this.waitForDoublePress,
  });

  // --------------------------------------------------------------------------
  // Group: Modifier formatting helpers
  // Purpose: Normalize modifier order and build display-friendly hotkey labels.
  // --------------------------------------------------------------------------

  static List<String> normalizeModifiers(Iterable<String> modifiers) {
    final Set<String> normalizedModifiers = modifiers.map((String modifier) => modifier.toUpperCase()).toSet();
    final List<String> orderedModifiers = <String>[];

    for (final String modifier in modifierOrder) {
      if (normalizedModifiers.remove(modifier)) orderedModifiers.add(modifier);
    }

    if (normalizedModifiers.isNotEmpty) {
      final List<String> extraModifiers = normalizedModifiers.toList()..sort();
      orderedModifiers.addAll(extraModifiers);
    }

    return orderedModifiers;
  }

  static String normalizeKeyName(String key) {
    if (key.isEmpty) return '';
    final String trimmed = key.trim();
    if (key == ' ' || trimmed.isEmpty) return 'SPACE';

    final String normalized = trimmed.toUpperCase();
    return namedKeyAliases[normalized] ?? normalized;
  }

  static String keyFromLogicalKey(LogicalKeyboardKey logicalKey) {
    if (logicalKey == LogicalKeyboardKey.space) return 'SPACE';
    if (logicalKey == LogicalKeyboardKey.enter || logicalKey == LogicalKeyboardKey.numpadEnter) return 'RETURN';
    if (logicalKey == LogicalKeyboardKey.escape) return 'ESCAPE';
    if (logicalKey == LogicalKeyboardKey.backspace) return 'BACK';
    if (logicalKey == LogicalKeyboardKey.delete) return 'DELETE';
    if (logicalKey == LogicalKeyboardKey.insert) return 'INSERT';
    if (logicalKey == LogicalKeyboardKey.home) return 'HOME';
    if (logicalKey == LogicalKeyboardKey.end) return 'END';
    if (logicalKey == LogicalKeyboardKey.pageUp) return 'PRIOR';
    if (logicalKey == LogicalKeyboardKey.pageDown) return 'NEXT';
    if (logicalKey == LogicalKeyboardKey.arrowLeft) return 'LEFT';
    if (logicalKey == LogicalKeyboardKey.arrowRight) return 'RIGHT';
    if (logicalKey == LogicalKeyboardKey.arrowUp) return 'UP';
    if (logicalKey == LogicalKeyboardKey.arrowDown) return 'DOWN';
    if (logicalKey == LogicalKeyboardKey.tab) return 'TAB';
    if (logicalKey == LogicalKeyboardKey.numpad0) return 'NUMPAD0';
    if (logicalKey == LogicalKeyboardKey.numpad1) return 'NUMPAD1';
    if (logicalKey == LogicalKeyboardKey.numpad2) return 'NUMPAD2';
    if (logicalKey == LogicalKeyboardKey.numpad3) return 'NUMPAD3';
    if (logicalKey == LogicalKeyboardKey.numpad4) return 'NUMPAD4';
    if (logicalKey == LogicalKeyboardKey.numpad5) return 'NUMPAD5';
    if (logicalKey == LogicalKeyboardKey.numpad6) return 'NUMPAD6';
    if (logicalKey == LogicalKeyboardKey.numpad7) return 'NUMPAD7';
    if (logicalKey == LogicalKeyboardKey.numpad8) return 'NUMPAD8';
    if (logicalKey == LogicalKeyboardKey.numpad9) return 'NUMPAD9';
    if (logicalKey == LogicalKeyboardKey.numpadAdd) return 'NUMPADADD';
    if (logicalKey == LogicalKeyboardKey.numpadSubtract) return 'NUMPADSUBTRACT';
    if (logicalKey == LogicalKeyboardKey.numpadMultiply) return 'NUMPADMULTIPLY';
    if (logicalKey == LogicalKeyboardKey.numpadDivide) return 'NUMPADDIVIDE';
    if (logicalKey == LogicalKeyboardKey.numpadDecimal) return 'NUMPADDECIMAL';
    if (logicalKey == LogicalKeyboardKey.numpadComma) return 'NUMPADSEPARATOR';
    return normalizeKeyName(logicalKey.keyLabel);
  }

  static int? keyToVirtualKey(String key) {
    final String normalized = normalizeKeyName(key);
    return keyMap['VK_$normalized'];
  }

  static String formatHotkey({required String key, Iterable<String> modifiers = const <String>[]}) {
    final List<String> normalizedModifiers = normalizeModifiers(modifiers);
    final String normalizedKey = normalizeKeyName(key);

    if (normalizedModifiers.isNotEmpty) return '${normalizedModifiers.join('+')}+$normalizedKey';
    if (normalizedKey.isNotEmpty) return normalizedKey;
    return "NoKey";
  }

  static bool isSpecialBindingKey(String key) => specialBindingKeys.contains(key);

  static String displayKey(String key) {
    if (specialBindingLabels.containsKey(key)) return specialBindingLabels[key]!;

    final String normalizedKey = normalizeKeyName(key);
    return namedKeyDisplayLabels[normalizedKey] ?? normalizedKey;
  }

  static String formatHotkeyLabel({required String key, Iterable<String> modifiers = const <String>[]}) {
    final List<String> normalizedModifiers = normalizeModifiers(modifiers);
    final String displayKeyLabel = displayKey(key);

    if (normalizedModifiers.isEmpty && isSpecialBindingKey(key)) return displayKeyLabel;
    if (normalizedModifiers.isNotEmpty) return '${normalizedModifiers.join('+')}+$displayKeyLabel';
    if (displayKeyLabel.isNotEmpty) return displayKeyLabel;
    return "NoKey";
  }

  // --------------------------------------------------------------------------
  // Group: Derived hotkey state
  // Purpose: Expose computed state and filtered keymap views for the current hotkey.
  // --------------------------------------------------------------------------

  String get hotkey {
    return formatHotkey(key: key, modifiers: modifiers);
  }

  String get displayHotkey {
    return formatHotkeyLabel(key: key, modifiers: modifiers);
  }

  bool get hasDuration => keymaps.any((KeyMap keyMap) => keyMap.triggerType == TriggerType.duration && keyMap.enabled);
  bool get hasDoublePress =>
      keymaps.any((KeyMap keyMap) => keyMap.triggerType == TriggerType.doublePress && keyMap.enabled);
  bool get hasMouseMovement =>
      keymaps.any((KeyMap keyMap) => keyMap.triggerType == TriggerType.movement && keyMap.enabled);
  bool get hasMouseMovementTriggers => keymaps.any(
      (KeyMap keyMap) => keyMap.triggerType == TriggerType.movement && keyMap.triggerInfo[2] == -1 && keyMap.enabled);

  List<KeyMap> get getPress =>
      keymaps.where((KeyMap keyMap) => keyMap.triggerType == TriggerType.press && keyMap.enabled).toList();
  List<KeyMap> get getDurationKeys =>
      keymaps.where((KeyMap keyMap) => keyMap.triggerType == TriggerType.duration && keyMap.enabled).toList();
  List<KeyMap> get getDoublePress =>
      keymaps.where((KeyMap keyMap) => keyMap.triggerType == TriggerType.doublePress && keyMap.enabled).toList();
  List<KeyMap> get getHotkeysWithMovement => keymaps
      .where((KeyMap keyMap) =>
          keyMap.triggerType == TriggerType.movement && keyMap.triggerInfo[2] != -1 && keyMap.enabled)
      .toList();
  List<KeyMap> get getHotkeysWithMovementTriggers => keymaps
      .where((KeyMap keyMap) =>
          keyMap.triggerType == TriggerType.movement && keyMap.triggerInfo[2] == -1 && keyMap.enabled)
      .toList();

  // --------------------------------------------------------------------------
  // Group: Copy and serialization
  // Purpose: Clone hotkey models and convert them to and from persisted data.
  // --------------------------------------------------------------------------

  Hotkeys copyWith({
    String? key,
    List<String>? modifiers,
    List<KeyMap>? keymaps,
    List<String>? prohibited,
    bool? noopScreenBusy,
    bool? waitForDoublePress,
  }) {
    return Hotkeys(
      key: key ?? this.key,
      modifiers: normalizeModifiers(modifiers ?? this.modifiers),
      keymaps: keymaps ?? this.keymaps.map((KeyMap km) => km.copyWith()).toList(),
      prohibited: prohibited ?? List<String>.from(this.prohibited),
      noopScreenBusy: noopScreenBusy ?? this.noopScreenBusy,
      waitForDoublePress: waitForDoublePress ?? this.waitForDoublePress,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'key': key,
      'modifiers': normalizeModifiers(modifiers),
      'keymaps': keymaps.map((KeyMap keyMap) => keyMap.toMap()).toList(),
      'prohibited': prohibited,
      'noopScreenBusy': noopScreenBusy,
      'waitForDoublePress': waitForDoublePress,
    };
  }

  factory Hotkeys.fromMap(Map<String, dynamic> map) {
    return Hotkeys(
      key: (map['key'] ?? '') as String,
      modifiers: normalizeModifiers(List<String>.from(map['modifiers'] ?? const <String>[])),
      keymaps: List<KeyMap>.from(
        (map['keymaps'] as List<dynamic>).map<KeyMap>(
          (dynamic keyMapEntry) => KeyMap.fromMap(keyMapEntry as Map<String, dynamic>),
        ),
      ),
      prohibited: List<String>.from(map['prohibited'] ?? const <String>[]),
      noopScreenBusy: (map['noopScreenBusy'] ?? false) as bool,
      waitForDoublePress: (map['waitForDoublePress'] ?? false) as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory Hotkeys.fromJson(String source) => Hotkeys.fromMap(json.decode(source) as Map<String, dynamic>);

  // --------------------------------------------------------------------------
  // Group: Diagnostics and equality
  // Purpose: Provide debug output and stable value comparison for hotkeys.
  // --------------------------------------------------------------------------

  @override
  String toString() {
    return 'Hotkeys(key: $key, modifiers: $modifiers, keymaps: $keymaps, prohibited: $prohibited, noopScreenBusy: $noopScreenBusy, waitForDoublePress: $waitForDoublePress)';
  }

  @override
  bool operator ==(covariant Hotkeys other) {
    if (identical(this, other)) return true;

    return other.key == key &&
        listEquals(other.modifiers, modifiers) &&
        listEquals(other.keymaps, keymaps) &&
        listEquals(other.prohibited, prohibited) &&
        other.noopScreenBusy == noopScreenBusy &&
        other.waitForDoublePress == waitForDoublePress;
  }

  @override
  int get hashCode {
    return key.hashCode ^
        modifiers.hashCode ^
        keymaps.hashCode ^
        prohibited.hashCode ^
        noopScreenBusy.hashCode ^
        waitForDoublePress.hashCode;
  }
}

enum TriggerType {
  press,
  doublePress,
  movement,
  duration,
}

class KeyMap with TabameListener {
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

  // --------------------------------------------------------------------------
  // Group: Trigger region helpers
  // Purpose: Evaluate whether a keymap should react for the current mouse position.
  // --------------------------------------------------------------------------

  bool get isMouseInRegion {
    if (!boundToRegion) return true;

    final Point<int> mousePoint = HotKeyInfo.getMouseBounds(windowUnderMouse, region.anchorType, region.asPercentage);
    if (mousePoint.x >= region.x1 &&
        mousePoint.x <= region.x2 &&
        mousePoint.y >= region.y1 &&
        mousePoint.y <= region.y2) {
      return true;
    }
    return false;
  }

  // --------------------------------------------------------------------------
  // Group: Action execution
  // Purpose: Validate runtime conditions and execute the configured keymap actions.
  // --------------------------------------------------------------------------

  Future<void> applyActions(TriggerType type) async {
    if (variableCheck.isNotEmpty && variableCheck[0].isNotEmpty) {
      final String storedVariableValue = Boxes.pref.getString("k_${variableCheck[0]}") ?? "";
      if (storedVariableValue.isNotEmpty) {
        if (storedVariableValue != variableCheck[1]) {
          return;
        }
      } else {
        Boxes.pref.setString("k_${variableCheck[0]}", variableCheck[1]);
      }
    }

    int targetWindowHandle = GetForegroundWindow();

    if (windowUnderMouse) {
      final Pointer<POINT> cursorPointPointer = calloc<POINT>();
      GetCursorPos(cursorPointPointer);
      targetWindowHandle = GetAncestor(WindowFromPoint(cursorPointPointer.ref), 3);
      free(cursorPointPointer);
    }

    // 1. Check if the target window matches the configured window type and criteria
    if (windowsInfo[0] != "any") {
      String valueToCheck = "";
      switch (windowsInfo[0].toLowerCase()) {
        case "exe":
          valueToCheck = Win32.getWindowExePath(targetWindowHandle);
          break;
        case "class":
          valueToCheck = Win32.getClass(targetWindowHandle);
          break;
        case "title":
          valueToCheck = Win32.getTitle(targetWindowHandle);
          break;
      }

      final RegExp matcher = RegExp(windowsInfo[1], caseSensitive: false);
      if (!matcher.hasMatch(valueToCheck)) {
        return;
      }
    }

    // 2. If the window is under mouse but not foreground, activate it before sending keys
    if (windowUnderMouse && GetForegroundWindow() != targetWindowHandle) {
      Win32.activateWindow(targetWindowHandle);

      int pollCount = 0;
      while (pollCount < 200 && GetForegroundWindow() != targetWindowHandle) {
        pollCount++;
        await Future<void>.delayed(const Duration(milliseconds: 2));
      }

      if (GetForegroundWindow() == targetWindowHandle) {
        await applyActionsForWindow(type);
      }
      return;
    }

    await applyActionsForWindow(type);
  }

  Future<void> applyActionsForWindow(TriggerType type) async {
    for (final KeyAction action in actions) {
      switch (action.type) {
        case ActionType.hotkey:
          _processHotkey(action.value);
          break;
        case ActionType.sendKeys:
          if (action.value == "{WIN}") {
            int trayWindowHandle = FindWindow(TEXT("Shell_TrayWnd"), nullptr);
            if (trayWindowHandle == 0) trayWindowHandle = GetDesktopWindow();
            SetForegroundWindow(trayWindowHandle);
          }
          WinKeys.safeSendHotkey(() => WinKeys.send(action.value));

          break;
        case ActionType.openQuickMenuPage:
          if (HotKeyInfo.quickMenuPopups.contains(action.value)) {
            if (action.value == "Interface" || action.value == "Launcher") {
              QuickMenuFunctions.toggleQuickMenu(type: QuickMenuPage.launcher, center: true);
            } else {
              QuickMenuFunctions.openQuickMenuWithAction(action.value, center: true);
            }
          }
          break;
        case ActionType.wait:
          await Future<void>.delayed(Duration(milliseconds: int.tryParse(action.value) ?? 0));
          break;
        case ActionType.sendClick:
          _processSendClick(action.value);
          break;
        case ActionType.tabameFunction:
          if (HotKeyInfo.tabameFunctionsMap.containsKey(action.value)) {
            HotKeyInfo.tabameFunctionsMap[action.value]!();
          }
          break;
        case ActionType.setVar:
          if (action.value.isNotEmpty) _processSetVar(action.value);
          break;
        case ActionType.openLauncherWithPrefix:
          if (action.value.isNotEmpty) {
            QuickMenuFunctions.openQuickMenuWithAction(action.value, center: true, useSlash: false);
          }
          break;
      }
    }
  }

  void _processHotkey(String value) {
    final String serialized = value.split('+').map((String p) => p.length > 1 ? "{#$p}" : p).join();

    WinKeys.safeSendHotkey(() => WinKeys.send(serialized));
    // WinKeys.send(serialized);
  }

  void _processSendClick(String value) {
    int targetWindowHandle = GetForegroundWindow();
    final Pointer<POINT> cursorPointPointer = calloc<POINT>();
    GetCursorPos(cursorPointPointer);

    if (windowUnderMouse) {
      targetWindowHandle = GetAncestor(WindowFromPoint(cursorPointPointer.ref), 2);
    }

    final int originalCursorX = cursorPointPointer.ref.x;
    final int originalCursorY = cursorPointPointer.ref.y;
    free(cursorPointPointer);

    final Pointer<RECT> windowRectPointer = calloc<RECT>();
    GetWindowRect(targetWindowHandle, windowRectPointer);

    final ClickAction clickAction = ClickAction.fromJson(value);
    int clickX = 0;
    int clickY = 0;

    switch (clickAction.anchorType) {
      case AnchorType.topLeft:
        clickX = windowRectPointer.ref.left + clickAction.x;
        clickY = windowRectPointer.ref.top + clickAction.y;
        break;
      case AnchorType.topRight:
        clickX = windowRectPointer.ref.right - clickAction.x;
        clickY = windowRectPointer.ref.top + clickAction.y;
        break;
      case AnchorType.bottomLeft:
        clickX = windowRectPointer.ref.left + clickAction.x;
        clickY = windowRectPointer.ref.bottom - clickAction.y;
        break;
      case AnchorType.bottomRight:
        clickX = windowRectPointer.ref.right - clickAction.x;
        clickY = windowRectPointer.ref.bottom - clickAction.y;
        break;
    }
    free(windowRectPointer);

    SetCursorPos(clickX, clickY);
    Future<void>.delayed(const Duration(milliseconds: 500), () {
      final Pointer<INPUT> inputPointer = calloc<INPUT>();
      inputPointer.ref.type = INPUT_MOUSE;
      inputPointer.ref.mi.dwFlags = (MOUSEEVENTF_ABSOLUTE | MOUSEEVENTF_LEFTDOWN | MOUSEEVENTF_LEFTUP);
      inputPointer.ref.mi.mouseData = 0;
      inputPointer.ref.mi.dwExtraInfo = NULL;
      inputPointer.ref.mi.time = 0;
      SendInput(1, inputPointer, sizeOf<INPUT>());
      SetCursorPos(originalCursorX, originalCursorY);
      free(inputPointer);
    });
  }

  void _processSetVar(String value) {
    try {
      final List<dynamic> variableAssignment = jsonDecode(value);
      if (variableAssignment.length == 2) {
        Boxes.pref.setString("k_${variableAssignment[0]}", variableAssignment[1].toString());
      }
    } catch (e) {
      Debug.add("Hotkey: Error setting variable $e");
    }
  }

  // --------------------------------------------------------------------------
  // Group: Copy and serialization
  // Purpose: Clone keymap models and convert them to and from persisted data.
  // --------------------------------------------------------------------------

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
      windowsInfo: windowsInfo ?? List<String>.from(this.windowsInfo),
      boundToRegion: boundToRegion ?? this.boundToRegion,
      region: region ?? this.region.copyWith(),
      triggerType: triggerType ?? this.triggerType,
      triggerInfo: triggerInfo ?? List<int>.from(this.triggerInfo),
      actions: actions ?? this.actions.map((KeyAction a) => a.copyWith()).toList(),
      variableCheck: variableCheck ?? List<String>.from(this.variableCheck),
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
      'actions': actions.map((KeyAction action) => action.toMap()).toList(),
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
          (dynamic actionEntry) => KeyAction.fromMap(actionEntry as Map<String, dynamic>),
        ),
      ),
      variableCheck: List<String>.from(map['variableCheck'] ?? const <String>[]),
    );
  }

  String toJson() => json.encode(toMap());

  factory KeyMap.fromJson(String source) => KeyMap.fromMap(json.decode(source) as Map<String, dynamic>);

  // --------------------------------------------------------------------------
  // Group: Diagnostics and equality
  // Purpose: Provide debug output and stable value comparison for keymaps.
  // --------------------------------------------------------------------------

  @override
  String toString() {
    return '\nKeyMap(enabled: $enabled, windowUnderMouse: $windowUnderMouse, name: $name, windowsInfo: $windowsInfo, boundToRegion: $boundToRegion, region: $region, triggerType: $triggerType, triggerInfo: $triggerInfo, actions: $actions, variableCheck: $variableCheck)';
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
  openQuickMenuPage,
  wait,
  openLauncherWithPrefix,
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
  static List<String> quickMenuPopups = <String>[
    "Apps",
    "Audio Control",
    "Authenticator",
    "Bookmarks",
    "Calculator",
    "Cli Book",
    "Block Keyboard",
    "Clipboard History",
    "Color Picker",
    "Countdown",
    "Currency Converter",
    "Custom Chars",
    "Disk Cleanup",
    "Memos",
    "Notion",
    "QR Scanner",
    "Quick Actions",
    "QuickMenu Design",
    "Interface",
    "Shutdown",
    "Time Zone",
    "Translator",
    "Vaults",
    "Wallpapers",
    "Weather",
    "Workspaces",
    "Timers",
  ];
  static Map<String, Function> tabameFunctionsMap = <String, Function>{
    "ToggleQuickMenu": () {
      if (QuickMenuFunctions.isQuickMenuVisible) {
        final Offset position = Win32.getPosition();
        if (position.dx < -99) return QuickMenuFunctions.toggleQuickMenu(visible: true);
        QuickMenuFunctions.hideQuickMenu();
        if (GetForegroundWindow() == Win32.hWnd) WindowWatcher.focusFirstWindow();
        return () => <dynamic, dynamic>{};
      }
      return QuickMenuFunctions.toggleQuickMenu();
    },
    "ShowQuickMenuInCenter": () => QuickMenuFunctions.toggleQuickMenu(center: true),
    "OpenLauncher": () {
      if (QuickMenuFunctions.isQuickMenuVisible) {
        if (Globals.quickMenuPage == QuickMenuPage.launcher) {
          QuickMenuFunctions.hideQuickMenu();

          Win32.activateWindow(Globals.lastFocusedWinHWND);
          return () => <dynamic, dynamic>{};
        }
      }
      return QuickMenuFunctions.toggleQuickMenu(type: QuickMenuPage.launcher, center: true, visible: true);
    },
    "ToggleTaskbar": () => WinUtils.toggleTaskbar(),
    "OpenColorPicker": () => WinUtils.startTabame(closeCurrent: false, arguments: "-colorPicker"),
    "OpenScreenDraw": () {
      final int windowHwnd = Win32.findWindow("Tabame Screen Draw");
      if (windowHwnd != 0) {
        Win32.closeWindow(windowHwnd);
        // Win32.activateWindow(windowHwnd);
      } else {
        WinUtils.startTabame(closeCurrent: false, arguments: "-screenDraw", admin: false);
      }
    },
    "OpenScreenRecording": () {
      final int windowHwnd = Win32.findWindow("Tabame Screen Recording");
      if (windowHwnd != 0) {
        Win32.closeWindow(windowHwnd);
      } else {
        WinUtils.startTabame(closeCurrent: false, arguments: "-screenRecording");
      }
    },
    "OpenSpotlight": () {
      final int windowHwnd = Win32.findWindow("Tabame Spotlight");
      if (windowHwnd != 0) {
        Win32.closeWindow(windowHwnd);
      } else {
        WinUtils.startTabame(closeCurrent: false, arguments: "-spotlight");
      }
    },
    "OpenLiveFancyShot": () async {
      // WinUtils.startTabame(closeCurrent: false, arguments: "-capture");
      if (QuickMenuFunctions.isQuickMenuVisible) {
        QuickMenuFunctions.hideQuickMenu();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      Globals.quickMenuPage = QuickMenuPage.fancyShotLive;
      QuickMenuFunctions.refreshQuickMenu();
    },
    "OpenFrozenFancyShot": () async {
      if (QuickMenuFunctions.isQuickMenuVisible) {
        await QuickMenuFunctions.hideQuickMenu();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      Globals.quickMenuPage = QuickMenuPage.fancyShotFreeze;
      await FancyShotCaptureWidget.captureScreenshots();
      QuickMenuFunctions.refreshQuickMenu();
    },
    "OpenColorPickerInstant": () async {
      if (QuickMenuFunctions.isQuickMenuVisible) {
        QuickMenuFunctions.hideQuickMenu();
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
      await Win32Helper.instantColorPicker();
    },
    "OpenEmojiPicker": () async {
      if (QuickMenuFunctions.isQuickMenuVisible) {
        QuickMenuFunctions.hideQuickMenu();
        await Future<void>.delayed(const Duration(milliseconds: 160));
      }

      Globals.focusedRect = await getFocusedElementCaretRect();
      await QuickMenuFunctions.toggleQuickMenu(
          visible: true, type: QuickMenuPage.emojiPicker, forcePop: true, forceReposition: false);
    },
    "OpenQuickClick": () async {
      if (Globals.quickMenuPage == QuickMenuPage.quickClick) {
        // Win32.setWindowInvisible(true);
        Win32.setPosition(const Offset(-99999, -99999));
        await QuickMenuFunctions.hideQuickMenu();
        // Win32.setWindowInvisible(false);
        return;
      }

      Win32.setWindowInvisible(true);
      if (QuickMenuFunctions.isQuickMenuVisible) {
        QuickMenuFunctions.hideQuickMenu();
        await Future<void>.delayed(const Duration(milliseconds: 160));
      }
      await QuickMenuFunctions.toggleQuickMenu(
          visible: true, type: QuickMenuPage.quickClick, forcePop: true, forceReposition: false);
    },
    "BlockKeyboard": () async {
      await QuickMenuFunctions.openQuickMenuWithAction("BlockKeyboard", center: true);

      await Future<void>.delayed(const Duration(milliseconds: 300), () {
        QuickMenuFunctions.triggerQuickAction("StartBlockingKeyboard");
      });
    },
    "ShowStartMenu": () {
      int trayWindowHandle = FindWindow(TEXT("Shell_TrayWnd"), nullptr);
      if (trayWindowHandle != 0) {
        final int monitorId = Monitor.getMonitorNumber(Monitor.getCursorMonitor());
        if (monitorId > 1) trayWindowHandle = FindWindow(TEXT("Shell_SecondaryTrayWnd"), nullptr);
        if (trayWindowHandle == 0) trayWindowHandle = FindWindow(TEXT("Shell_TrayWnd"), nullptr);

        final int startButtonHandle = FindWindowEx(trayWindowHandle, 0, TEXT("Start"), nullptr);
        if (startButtonHandle != 0) {
          SetForegroundWindow(startButtonHandle);
          WinKeys.send("{SPACE}");
        } else {
          SetForegroundWindow(trayWindowHandle);
          WinKeys.send("{#SHIFT}{TAB}{|}{#SHIFT}{TAB}{|}{SPACE}");
        }
      }
    },
    "ShowLastActiveWindow": () {
      QuickMenuFunctions.hideQuickMenu();
      WindowWatcher.focusSecondWindow();
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        QuickMenuFunctions.hideQuickMenu();
      });
    },
    "ShowSecondWindowUnderCursor": () {
      QuickMenuFunctions.hideQuickMenu();
      WindowWatcher.showSecondWindowUnderCursor();
      Future<void>.delayed(const Duration(milliseconds: 50), () {
        QuickMenuFunctions.hideQuickMenu();
      });
    },
    "ToggleHiddenFiles": () => WinUtils.toggleHiddenFiles(),
    "ToggleDesktopFiles": () => WinUtils.toggleDesktopFiles(),
    "SwitchAudioOutput": () => Audio.switchDefaultDevice(
          AudioDeviceType.output,
          console: user.audioConsole,
          multimedia: user.audioMultimedia,
          communications: user.audioCommunications,
        ),
    "SwitchMicrophoneInput": () => Audio.switchDefaultDevice(
          AudioDeviceType.input,
          console: user.audioConsole,
          multimedia: user.audioMultimedia,
          communications: user.audioCommunications,
        ),
    "ToggleMicrophone": () => Audio.getMuteAudioDevice(AudioDeviceType.input)
        .then((bool isMuted) => Audio.setMuteAudioDevice(!isMuted, AudioDeviceType.input)),
    "SwitchDesktopToRight": () => WinUtils.moveDesktop(DesktopDirection.right),
    "SwitchDesktopToLeft": () => WinUtils.moveDesktop(DesktopDirection.left),
    "ToggleWallpaper": () async {
      final DesktopBackgroundType currentBackgroundType = WinUtils.getDesktopBackgroundType();

      if (currentBackgroundType == DesktopBackgroundType.wallpaper) {
        await WinUtils.toggleDesktopWallpaper(false);
        // await setWallpaperColor(0x00000000);
        return;
      }

      await WinUtils.toggleDesktopWallpaper(true);
    },
  };

  static List<String> tabameFunctions = tabameFunctionsMap.keys.toList();

  //keymap.keymaps[index].actions[0].type
  static const Map<ActionType, IconData> actionTypeIcons = <ActionType, IconData>{
    ActionType.hotkey: Icons.tag,
    ActionType.sendClick: Icons.mouse,
    ActionType.sendKeys: Icons.keyboard,
    ActionType.setVar: Icons.tune,
    ActionType.tabameFunction: Icons.functions,
    ActionType.openQuickMenuPage: Icons.apps,
    ActionType.wait: Icons.timer_sharp,
    ActionType.openLauncherWithPrefix: Icons.menu_book,
  };
  static const Map<TriggerType, IconData> triggerTypeIcons = <TriggerType, IconData>{
    TriggerType.press: Icons.touch_app,
    TriggerType.doublePress: Icons.ads_click,
    TriggerType.duration: Icons.schedule,
    TriggerType.movement: Icons.gps_fixed,
  };

  // --------------------------------------------------------------------------
  // Group: Cursor and window coordinate helpers
  // Purpose: Resolve mouse position relative to the desktop or the active target window.
  // --------------------------------------------------------------------------

  static Point<int> getMouseBounds(bool windowUnderMouse, AnchorType anchorType, bool asPercentage) {
    final Pointer<POINT> cursorPtr = calloc<POINT>();
    GetCursorPos(cursorPtr);
    final int cursorX = cursorPtr.ref.x;
    final int cursorY = cursorPtr.ref.y;

    int refLeft = 0, refTop = 0, refRight = 0, refBottom = 0;

    if (!windowUnderMouse) {
      // ── Desktop / screen-relative mode ─────────────────────────────────────
      // Use the monitor that the cursor is currently on, not GetDesktopWindow(),
      // which only covers the primary monitor and breaks multi-monitor setups.
      final int monitorHandle = MonitorFromPoint(cursorPtr.ref, MONITOR_DEFAULTTONEAREST);
      free(cursorPtr);

      if (Monitor.monitorSizes.containsKey(monitorHandle)) {
        final Square sq = Monitor.monitorSizes[monitorHandle]!;
        refLeft = sq.x;
        refTop = sq.y;
        refRight = sq.x + sq.width;
        refBottom = sq.y + sq.height;
      } else {
        // Fallback: refresh monitor list and try again.
        Monitor.fetchMonitors();
        if (Monitor.monitorSizes.containsKey(monitorHandle)) {
          final Square sq = Monitor.monitorSizes[monitorHandle]!;
          refLeft = sq.x;
          refTop = sq.y;
          refRight = sq.x + sq.width;
          refBottom = sq.y + sq.height;
        }
      }
    } else {
      // ── Window-relative mode ────────────────────────────────────────────────
      final Pointer<RECT> rectPtr = calloc<RECT>();
      final int hWnd = GetAncestor(WindowFromPoint(cursorPtr.ref), 2);
      free(cursorPtr);
      GetWindowRect(hWnd, rectPtr);
      refLeft = rectPtr.ref.left;
      refTop = rectPtr.ref.top;
      refRight = rectPtr.ref.right;
      refBottom = rectPtr.ref.bottom;
      free(rectPtr);
    }

    final int refWidth = refRight - refLeft;
    final int refHeight = refBottom - refTop;

    // Compute distances from each edge.
    final int fromLeft = cursorX - refLeft;
    final int fromTop = cursorY - refTop;
    final int fromRight = cursorX - refRight;
    final int fromBottom = cursorY - refBottom;

    int resolvedX = 0;
    int resolvedY = 0;

    switch (anchorType) {
      case AnchorType.topLeft:
        resolvedX = fromLeft;
        resolvedY = fromTop;
        break;
      case AnchorType.topRight:
        resolvedX = fromRight;
        resolvedY = fromTop;
        break;
      case AnchorType.bottomLeft:
        resolvedX = fromLeft;
        resolvedY = fromBottom;
        break;
      case AnchorType.bottomRight:
        resolvedX = fromRight;
        resolvedY = fromBottom;
        break;
    }

    // Distances are always treated as non-negative magnitudes for region checks.
    resolvedX = resolvedX.abs();
    resolvedY = resolvedY.abs();

    if (asPercentage) {
      if (refWidth > 0) resolvedX = ((resolvedX / refWidth) * 100).ceil();
      if (refHeight > 0) resolvedY = ((resolvedY / refHeight) * 100).ceil();
    }

    return Point<int>(resolvedX, resolvedY);
  }
}

class KeyAction {
  //enum
  ActionType type;
  String value;

  KeyAction({
    required this.type,
    required this.value,
  });

  // --------------------------------------------------------------------------
  // Group: Copy and serialization
  // Purpose: Clone key actions and convert them to and from persisted data.
  // --------------------------------------------------------------------------

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

  // --------------------------------------------------------------------------
  // Group: Diagnostics and equality
  // Purpose: Provide debug output and stable value comparison for key actions.
  // --------------------------------------------------------------------------

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
  bool currentWindow;
  // enum
  AnchorType anchorType;

  ClickAction({
    required this.x,
    required this.y,
    required this.currentWindow,
    required this.anchorType,
  });

  // --------------------------------------------------------------------------
  // Group: Copy and serialization
  // Purpose: Clone click actions and convert them to and from persisted data.
  // --------------------------------------------------------------------------

  ClickAction copyWith({
    int? x,
    int? y,
    bool? currentWindow,
    AnchorType? anchorType,
  }) {
    return ClickAction(
      x: x ?? this.x,
      y: y ?? this.y,
      currentWindow: currentWindow ?? this.currentWindow,
      anchorType: anchorType ?? this.anchorType,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'x': x,
      'y': y,
      'currentWindow': currentWindow,
      'anchorType': anchorType.index,
    };
  }

  factory ClickAction.fromMap(Map<String, dynamic> map) {
    return ClickAction(
      x: (map['x'] ?? 0) as int,
      y: (map['y'] ?? 0) as int,
      currentWindow: (map['currentWindow'] ?? false) as bool,
      anchorType: AnchorType.values[(map['anchorType'] ?? 0) as int],
    );
  }

  String toJson() => json.encode(toMap());

  factory ClickAction.fromJson(String source) => ClickAction.fromMap(json.decode(source) as Map<String, dynamic>);

  // --------------------------------------------------------------------------
  // Group: Diagnostics and equality
  // Purpose: Provide debug output and stable value comparison for click actions.
  // --------------------------------------------------------------------------

  @override
  String toString() {
    return 'ClickAction(x: $x, y: $y, currentWindow: $currentWindow, anchorType: $anchorType)';
  }

  @override
  bool operator ==(covariant ClickAction other) {
    if (identical(this, other)) return true;

    return other.x == x && other.y == y && other.currentWindow == currentWindow && other.anchorType == anchorType;
  }

  @override
  int get hashCode {
    return x.hashCode ^ y.hashCode ^ currentWindow.hashCode ^ anchorType.hashCode;
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

  // --------------------------------------------------------------------------
  // Group: Derived region metrics
  // Purpose: Expose simple computed measurements for the current region.
  // --------------------------------------------------------------------------

  int get sum => x1.abs() + x2.abs() + y1.abs() + y1.abs();
  int get area => (x2 - x1) * (y2 - y1);

  // --------------------------------------------------------------------------
  // Group: Copy and serialization
  // Purpose: Clone regions and convert them to and from persisted data.
  // --------------------------------------------------------------------------

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

  // --------------------------------------------------------------------------
  // Group: Diagnostics and equality
  // Purpose: Provide debug output and stable value comparison for regions.
  // --------------------------------------------------------------------------

  @override
  String toString() {
    return 'Region(x1: $x1, y1: $y1, x2: $x2, y2: $y2, asPercentage: $asPercentage, anchorType: $anchorType)';
  }

  @override
  bool operator ==(covariant Region other) {
    if (identical(this, other)) return true;

    return other.x1 == x1 &&
        other.y1 == y1 &&
        other.x2 == x2 &&
        other.y2 == y2 &&
        other.asPercentage == asPercentage &&
        other.anchorType == anchorType;
  }

  @override
  int get hashCode {
    return x1.hashCode ^ y1.hashCode ^ x2.hashCode ^ y2.hashCode ^ asPercentage.hashCode ^ anchorType.hashCode;
  }
}
