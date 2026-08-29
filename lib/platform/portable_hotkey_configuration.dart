import 'dart:convert';
import 'dart:io';

import '../models/classes/hotkeys.dart';
import 'app_paths.dart';
import 'hotkey_binding_factory.dart';
import 'platform_models.dart';

/// Loads the shared persisted hotkey format without importing the Windows
/// settings/box graph into the portable startup path.
class PortableHotkeyConfiguration {
  PortableHotkeyConfiguration._();

  static const Set<String> _supportedMacOSFunctions = <String>{
    'ToggleQuickMenu',
    'ShowQuickMenuInCenter',
    'OpenLauncher',
  };

  static Future<List<Hotkeys>> load() async {
    final File file = File(AppPaths.settingsPath('settings.json'));
    if (!file.existsSync()) return const <Hotkeys>[];

    try {
      final Object? decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<dynamic, dynamic>) return const <Hotkeys>[];

      dynamic encoded = decoded['flutter.remap'] ?? decoded['remap'];
      if (encoded is String) {
        if (encoded.trim().isEmpty) return const <Hotkeys>[];
        encoded = jsonDecode(encoded);
      }
      if (encoded is! List<dynamic>) return const <Hotkeys>[];

      final List<Hotkeys> result = <Hotkeys>[];
      for (final dynamic entry in encoded) {
        try {
          if (entry is String) {
            result.add(Hotkeys.fromJson(entry));
          } else if (entry is Map<dynamic, dynamic>) {
            result.add(Hotkeys.fromMap(Map<String, dynamic>.from(entry)));
          }
        } catch (_) {
          // One malformed legacy binding must not prevent the remaining
          // bindings or the default summon shortcut from starting.
        }
      }
      return result;
    } catch (_) {
      return const <Hotkeys>[];
    }
  }

  /// Returns only mappings that the macOS Carbon press-only adapter can execute.
  /// Movement, duration, region, window-targeted, and input-injection mappings
  /// stay out of both the registration set and the shared dispatcher.
  static List<Hotkeys> supportedMacOS(Iterable<Hotkeys> configured) {
    final List<Hotkeys> result = <Hotkeys>[];
    for (final Hotkeys group in configured) {
      final List<KeyMap> supportedKeymaps = group.keymaps.where(_supportsMacOSKeyMap).toList(growable: false);
      if (supportedKeymaps.isEmpty || Hotkeys.normalizeKeyName(group.key).isEmpty) continue;
      if (group.prohibited.isNotEmpty || group.noopScreenBusy) continue;
      result.add(group.copyWith(keymaps: supportedKeymaps));
    }
    return result;
  }

  static List<PlatformHotkeyBinding> macOSBindings(Iterable<Hotkeys> configured) {
    return HotkeyBindingFactory.fromModels(supportedMacOS(configured))
        .where(supportsMacOSBinding)
        .toList(growable: false);
  }

  /// Mirrors the Carbon adapter's accepted logical names so an unsupported
  /// persisted binding cannot prevent the default summon shortcut from being
  /// registered with the rest of the set.
  static bool supportsMacOSBinding(PlatformHotkeyBinding binding) {
    final String key = binding.key.toUpperCase();
    final int? functionNumber = key.startsWith('F') ? int.tryParse(key.substring(1)) : null;
    final bool functionKey = functionNumber != null && functionNumber >= 1 && functionNumber <= 20;
    final bool commonKey = RegExp(r'^[A-Z0-9]$').hasMatch(key) ||
        <String>{
          'MINUS',
          '-',
          'EQUAL',
          '=',
          'LEFTBRACKET',
          '[',
          'RIGHTBRACKET',
          ']',
          'BACKSLASH',
          '\\',
          'SEMICOLON',
          ';',
          'QUOTE',
          "'",
          'COMMA',
          ',',
          'PERIOD',
          '.',
          'SLASH',
          '/',
          'GRAVE',
          '`',
          'SPACE',
          'RETURN',
          'ENTER',
          'TAB',
          'ESCAPE',
          'ESC',
          'BACK',
          'BACKSPACE',
          'DELETE',
          'INSERT',
          'HOME',
          'END',
          'PRIOR',
          'PAGEUP',
          'NEXT',
          'PAGEDOWN',
          'LEFT',
          'RIGHT',
          'UP',
          'DOWN',
          'NUMPAD0',
          'NUMPAD1',
          'NUMPAD2',
          'NUMPAD3',
          'NUMPAD4',
          'NUMPAD5',
          'NUMPAD6',
          'NUMPAD7',
          'NUMPAD8',
          'NUMPAD9',
          'NUMPADADD',
          'NUMPADSUBTRACT',
          'NUMPADMULTIPLY',
          'NUMPADDIVIDE',
          'NUMPADDECIMAL',
        }.contains(key) ||
        functionKey;
    if (!commonKey) return false;

    const Set<String> acceptedModifiers = <String>{
      'CTRL',
      'ALT',
      'SHIFT',
      'WIN',
      'CMD',
      'COMMAND',
      'CONTROL',
      'OPTION'
    };
    return binding.modifiers.every((String modifier) => acceptedModifiers.contains(modifier.toUpperCase()));
  }

  static bool _supportsMacOSKeyMap(KeyMap keyMap) {
    if (!keyMap.enabled || keyMap.triggerType != TriggerType.press) return false;
    if (keyMap.name.trim().isEmpty) return false;
    if (keyMap.boundToRegion || keyMap.windowUnderMouse) return false;
    if (keyMap.windowsInfo.isNotEmpty && keyMap.windowsInfo[0].toLowerCase() != 'any') return false;
    if (keyMap.variableCheck.isNotEmpty && keyMap.variableCheck[0].trim().isNotEmpty) return false;
    if (keyMap.actions.isEmpty) return false;
    if (!keyMap.actions.any((KeyAction action) => action.type == ActionType.tabameFunction)) return false;
    return keyMap.actions.every(_supportsMacOSAction);
  }

  static bool _supportsMacOSAction(KeyAction action) {
    switch (action.type) {
      case ActionType.tabameFunction:
        return _supportedMacOSFunctions.contains(action.value);
      case ActionType.wait:
        return int.tryParse(action.value) != null && int.parse(action.value) >= 0;
      case ActionType.sendKeys:
      case ActionType.hotkey:
      case ActionType.setVar:
      case ActionType.sendClick:
      case ActionType.openQuickMenuPage:
      case ActionType.openLauncherWithPrefix:
      case ActionType.insertClipboardHistory:
        return false;
    }
  }
}
