import 'dart:convert';

import 'hotkeys.dart';

enum ScreenDrawHotkeyAction {
  toggleDrawing,
  toggleVisibility,
  closeScreenDraw,
  spotlightEnable,
  spotlightSetActiveWindow,
  spotlightRaiseBlurSigma,
  spotlightDecreaseBlurSigma,
  spotlightRaiseDimOpacity,
  spotlightDecreaseDimOpacity,
  spotlightClose;

  String get id => name;

  String get label {
    switch (this) {
      case ScreenDrawHotkeyAction.toggleDrawing:
        return "Screen Drawing: Toggle Drawing";
      case ScreenDrawHotkeyAction.toggleVisibility:
        return "Screen Drawing: Toggle Visibility";
      case ScreenDrawHotkeyAction.closeScreenDraw:
        return "Screen Drawing: Close";
      case ScreenDrawHotkeyAction.spotlightEnable:
        return "Spotlight: Enable";
      case ScreenDrawHotkeyAction.spotlightSetActiveWindow:
        return "Spotlight: Set Active Window";
      case ScreenDrawHotkeyAction.spotlightRaiseBlurSigma:
        return "Spotlight: Increase Blur Sigma";
      case ScreenDrawHotkeyAction.spotlightDecreaseBlurSigma:
        return "Spotlight: Decrease Blur Sigma";
      case ScreenDrawHotkeyAction.spotlightRaiseDimOpacity:
        return "Spotlight: Increase Dim Opacity";
      case ScreenDrawHotkeyAction.spotlightDecreaseDimOpacity:
        return "Spotlight: Decrease Dim Opacity";
      case ScreenDrawHotkeyAction.spotlightClose:
        return "Spotlight: Close";
    }
  }

  static ScreenDrawHotkeyAction? fromId(String id) {
    for (final ScreenDrawHotkeyAction action in values) {
      if (action.id == id) return action;
    }
    return null;
  }
}

class ScreenDrawHotkeyBinding {
  final String actionId;
  String key;
  List<String> modifiers;
  bool enabled;

  ScreenDrawHotkeyBinding({
    required this.actionId,
    required this.key,
    required this.modifiers,
    this.enabled = true,
  });

  ScreenDrawHotkeyAction? get action => ScreenDrawHotkeyAction.fromId(actionId);

  bool get isSpotlight => actionId.startsWith('spotlight');

  bool get isScreenDraw => !isSpotlight;

  String get hotkey => Hotkeys.formatHotkey(key: key, modifiers: modifiers);

  String get displayHotkey => Hotkeys.formatHotkeyLabel(key: key, modifiers: modifiers);

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'actionId': actionId,
      'key': key,
      'modifiers': modifiers,
      'enabled': enabled,
    };
  }

  factory ScreenDrawHotkeyBinding.fromMap(Map<String, dynamic> map) {
    return ScreenDrawHotkeyBinding(
      actionId: (map['actionId'] ?? '') as String,
      key: (map['key'] ?? '') as String,
      modifiers: (map['modifiers'] as List<dynamic>? ?? <dynamic>[])
          .map((dynamic modifier) => modifier.toString())
          .toList(growable: false),
      enabled: (map['enabled'] ?? true) as bool,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ScreenDrawHotkeyBinding.fromJson(String source) =>
      ScreenDrawHotkeyBinding.fromMap(jsonDecode(source) as Map<String, dynamic>);

  static List<ScreenDrawHotkeyBinding> defaults() {
    return <ScreenDrawHotkeyBinding>[
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.toggleDrawing.id,
        key: 'D',
        modifiers: <String>['ALT', 'CTRL'],
      ),
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.toggleVisibility.id,
        key: 'V',
        modifiers: <String>['ALT', "CTRL"],
      ),
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.closeScreenDraw.id,
        key: 'X',
        modifiers: <String>['ALT', 'CTRL'],
      ),
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.spotlightEnable.id,
        key: 'Z',
        modifiers: <String>['ALT', 'CTRL'],
      ),
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.spotlightSetActiveWindow.id,
        key: 'V',
        modifiers: <String>['ALT', 'CTRL'],
      ),
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.spotlightRaiseBlurSigma.id,
        key: '.',
        modifiers: <String>['ALT', 'CTRL'],
      ),
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.spotlightDecreaseBlurSigma.id,
        key: ',',
        modifiers: <String>['ALT', 'CTRL'],
      ),
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.spotlightRaiseDimOpacity.id,
        key: ';',
        modifiers: <String>['ALT', 'CTRL'],
      ),
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.spotlightDecreaseDimOpacity.id,
        key: "'",
        modifiers: <String>['ALT', 'CTRL'],
      ),
      ScreenDrawHotkeyBinding(
        actionId: ScreenDrawHotkeyAction.spotlightClose.id,
        key: 'Q',
        modifiers: <String>['ALT', 'CTRL'],
      ),
    ];
  }

  static List<ScreenDrawHotkeyBinding> mergeWithDefaults(List<ScreenDrawHotkeyBinding> saved) {
    final Map<String, ScreenDrawHotkeyBinding> byActionId = <String, ScreenDrawHotkeyBinding>{
      for (final ScreenDrawHotkeyBinding binding in saved) binding.actionId: binding,
    };

    return <ScreenDrawHotkeyBinding>[
      for (final ScreenDrawHotkeyBinding defaultBinding in defaults())
        byActionId[defaultBinding.actionId] ?? defaultBinding,
      for (final ScreenDrawHotkeyBinding binding in saved)
        if (ScreenDrawHotkeyAction.fromId(binding.actionId) == null) binding,
    ];
  }
}
