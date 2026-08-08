// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../platform/hotkey_action_service.dart';
import '../../platform/input_service.dart';
import '../../platform/platform_models.dart';

class Hotkeys {
  // Modifier tokens are ordered family-first so normalizeModifiers produces a
  // stable, human-readable order. Each family has an "either side" token plus
  // explicit Left/Right variants (matched natively against the physical key).
  static const List<String> modifierOrder = <String>[
    "CTRL", "LCTRL", "RCTRL", //
    "ALT", "LALT", "RALT", //
    "SHIFT", "LSHIFT", "RSHIFT", //
    "WIN", "LWIN", "RWIN", //
  ];

  /// Base modifier families exposed as tiles in the hotkey editor.
  static const List<String> modifierFamilies = <String>["CTRL", "ALT", "SHIFT", "WIN"];

  /// Modifier tokens per family. Index 0 = either side, 1 = Left, 2 = Right.
  static const Map<String, List<String>> modifierVariants = <String, List<String>>{
    "CTRL": <String>["CTRL", "LCTRL", "RCTRL"],
    "ALT": <String>["ALT", "LALT", "RALT"],
    "SHIFT": <String>["SHIFT", "LSHIFT", "RSHIFT"],
    "WIN": <String>["WIN", "LWIN", "RWIN"],
  };

  /// Families that offer Left/Right side selection in the UI.
  static const List<String> sidedModifierFamilies = <String>["CTRL", "ALT", "SHIFT", "WIN"];

  static const Map<String, String> modifierDisplayLabels = <String, String>{
    "CTRL": "Ctrl", "LCTRL": "L-Ctrl", "RCTRL": "R-Ctrl", //
    "ALT": "Alt", "LALT": "L-Alt", "RALT": "R-Alt", //
    "SHIFT": "Shift", "LSHIFT": "L-Shift", "RSHIFT": "R-Shift", //
    "WIN": "Win", "LWIN": "L-Win", "RWIN": "R-Win", //
  };

  static const String mouseButton4Key = "MouseButton4";
  static const String mouseButton5Key = "MouseButton5";
  static const String doubleAltKey = "DoubleAlt";
  static const String leftAltKey = "LeftAlt";
  static const String rightAltKey = "RightAlt";
  static const String leftControlKey = "LeftControl";
  static const String rightControlKey = "RightControl";
  static const String leftShiftKey = "LeftShift";
  static const String rightShiftKey = "RightShift";
  static const String leftWinKey = "LeftWin";
  static const String rightWinKey = "RightWin";
  static const List<String> specialBindingKeys = <String>[
    mouseButton4Key,
    mouseButton5Key,
    doubleAltKey,
    leftControlKey,
    rightControlKey,
    leftAltKey,
    rightAltKey,
    leftShiftKey,
    rightShiftKey,
    leftWinKey,
    rightWinKey,
  ];
  static const Map<String, String> specialBindingLabels = <String, String>{
    mouseButton4Key: "Mouse Button 4",
    mouseButton5Key: "Mouse Button 5",
    doubleAltKey: "Double Alt",
    leftControlKey: "Left Control",
    rightControlKey: "Right Control",
    leftAltKey: "Left Alt",
    rightAltKey: "Right Alt",
    leftShiftKey: "Left Shift",
    rightShiftKey: "Right Shift",
    leftWinKey: "Left Win",
    rightWinKey: "Right Win",
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

  /// Returns the base family ("CTRL"/"ALT"/"SHIFT"/"WIN") for any modifier token.
  static String modifierFamilyOf(String modifier) {
    final String upper = modifier.toUpperCase();
    for (final MapEntry<String, List<String>> entry in modifierVariants.entries) {
      if (entry.value.contains(upper)) return entry.key;
    }
    return upper;
  }

  /// Side of a modifier token: 0 = either side, 1 = Left, 2 = Right.
  static int modifierSideOf(String modifier) {
    final List<String>? variants = modifierVariants[modifierFamilyOf(modifier)];
    if (variants == null) return 0;
    final int index = variants.indexOf(modifier.toUpperCase());
    return index < 0 ? 0 : index;
  }

  /// Builds the modifier token for [family] with the given [side] (0/1/2).
  static String modifierWithSide(String family, int side) {
    final List<String>? variants = modifierVariants[family];
    if (variants == null || side <= 0 || side >= variants.length) return family;
    return variants[side];
  }

  /// The active modifier token for [family] within [modifiers], or null if the
  /// family is not present at all.
  static String? activeModifierForFamily(Iterable<String> modifiers, String family) {
    final List<String> variants = modifierVariants[family] ?? <String>[family];
    for (final String modifier in modifiers) {
      if (variants.contains(modifier.toUpperCase())) return modifier.toUpperCase();
    }
    return null;
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
    final List<String> displayModifiers =
        normalizedModifiers.map((String modifier) => modifierDisplayLabels[modifier] ?? modifier).toList();
    final String displayKeyLabel = displayKey(key);

    if (normalizedModifiers.isEmpty && isSpecialBindingKey(key)) return displayKeyLabel;
    if (displayModifiers.isNotEmpty) return '${displayModifiers.join('+')}+$displayKeyLabel';
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

  Future<bool> isMouseInRegion() {
    if (!boundToRegion) return Future<bool>.value(true);
    return InputService.instance.isPointerInRegion(
      windowUnderCursor: windowUnderMouse,
      region: PlatformHotkeyRegion(
        asPercentage: region.asPercentage,
        onScreen: regionOnScreen,
        x1: region.x1,
        x2: region.x2,
        y1: region.y1,
        y2: region.y2,
        anchorType: region.anchorType.index + 1,
      ),
    );
  }

  // --------------------------------------------------------------------------
  // Group: Action execution
  // Purpose: Validate runtime conditions and execute the configured keymap actions.
  // --------------------------------------------------------------------------

  Future<void> applyActions(TriggerType type) {
    return HotkeyActionService.instance.execute(
      PlatformHotkeyExecution(
        name: name,
        windowUnderCursor: windowUnderMouse,
        windowMatch: List<String>.from(windowsInfo),
        variableCheck: List<String>.from(variableCheck),
        trigger: type.name,
        actions: actions
            .map((KeyAction action) => PlatformHotkeyAction(type: action.type.name, value: action.value))
            .toList(growable: false),
      ),
    );
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
  static const List<String> windowInfo = <String>['any', 'exe', 'class', 'title'];
  static const Map<String, String> windowInfoNames = <String, String>{
    'any': 'Any Window',
    'exe': 'Exe Contains',
    'class': 'Class Contains',
    'title': 'Title Contains',
  };
  static const List<String> triggers = <String>['Press', 'Double Press', 'Mouse Movement', 'Hold Duration'];
  static const List<String> mouseDirections = <String>['Left', 'Right', 'Up', 'Down'];
  static const List<String> quickMenuPopups = <String>[
    'Apps',
    'Audio Control',
    'Authenticator',
    'Bookmarks',
    'Calculator',
    'Cli Book',
    'Block Keyboard',
    'Clipboard History',
    'Color Picker',
    'Countdown',
    'Currency Converter',
    'Custom Chars',
    'Disk Cleanup',
    'Memos',
    'Notion',
    'QR Scanner',
    'Quick Actions',
    'QuickMenu Design',
    'Interface',
    'Shutdown',
    'Time Zone',
    'Translator',
    'Vaults',
    'Wallpapers',
    'Weather',
    'Workspaces',
    'Timers',
  ];

  static Map<String, Function> get tabameFunctionsMap => HotkeyActionRegistry.functions;
  static List<String> get tabameFunctions => HotkeyActionRegistry.functionNames;

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
