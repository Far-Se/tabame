import 'package:flutter/services.dart';

/// A parsed plugin action shortcut (`"ctrl+shift+c"`, `"alt+enter"`, …).
///
/// Shortcuts must include Ctrl and/or Alt — a bare key or Shift+key would
/// collide with typing in the search field, so those parse as invalid and the
/// action stays reachable only through the Ctrl+K palette.
class PluginShortcut {
  const PluginShortcut._({
    required this.ctrl,
    required this.shift,
    required this.alt,
    required this.key,
    required this.keyLabel,
  });

  final bool ctrl;
  final bool shift;
  final bool alt;
  final LogicalKeyboardKey key;
  final String keyLabel;

  static final Map<String, PluginShortcut?> _cache = <String, PluginShortcut?>{};

  /// Named keys accepted besides single letters/digits and `f1`–`f12`.
  static final Map<String, LogicalKeyboardKey> _named = <String, LogicalKeyboardKey>{
    'enter': LogicalKeyboardKey.enter,
    'space': LogicalKeyboardKey.space,
    'backspace': LogicalKeyboardKey.backspace,
    'delete': LogicalKeyboardKey.delete,
    'del': LogicalKeyboardKey.delete,
    'up': LogicalKeyboardKey.arrowUp,
    'down': LogicalKeyboardKey.arrowDown,
    'left': LogicalKeyboardKey.arrowLeft,
    'right': LogicalKeyboardKey.arrowRight,
    'home': LogicalKeyboardKey.home,
    'end': LogicalKeyboardKey.end,
    'comma': LogicalKeyboardKey.comma,
    'period': LogicalKeyboardKey.period,
    'slash': LogicalKeyboardKey.slash,
    'minus': LogicalKeyboardKey.minus,
    'equal': LogicalKeyboardKey.equal,
  };

  /// Parses a lowercase `mod+mod+key` string; null when invalid or unsafe
  /// (missing a Ctrl/Alt modifier). Results are memoized — frames re-arrive on
  /// every keystroke.
  static PluginShortcut? parse(String? value) {
    if (value == null || value.isEmpty) return null;
    return _cache.putIfAbsent(value, () => _parse(value));
  }

  static PluginShortcut? _parse(String value) {
    bool ctrl = false, shift = false, alt = false;
    LogicalKeyboardKey? key;
    String keyLabel = '';
    for (final String part in value.split('+')) {
      final String token = part.trim();
      if (token == 'ctrl' || token == 'control') {
        ctrl = true;
      } else if (token == 'shift') {
        shift = true;
      } else if (token == 'alt') {
        alt = true;
      } else if (key != null) {
        return null; // Two non-modifier keys.
      } else if (token.length == 1) {
        final int code = token.codeUnitAt(0);
        final bool letter = code >= 0x61 && code <= 0x7A; // a-z
        final bool digit = code >= 0x30 && code <= 0x39; // 0-9
        if (!letter && !digit) return null;
        // Logical key ids for printable keys equal their lowercase code point.
        key = LogicalKeyboardKey(code);
        keyLabel = token.toUpperCase();
      } else if (token.startsWith('f') && int.tryParse(token.substring(1)) != null) {
        final int n = int.parse(token.substring(1));
        if (n < 1 || n > 12) return null;
        key = LogicalKeyboardKey(LogicalKeyboardKey.f1.keyId + (n - 1));
        keyLabel = token.toUpperCase();
      } else if (_named.containsKey(token)) {
        key = _named[token];
        keyLabel = '${token[0].toUpperCase()}${token.substring(1)}';
      } else {
        return null;
      }
    }
    if (key == null || (!ctrl && !alt)) return null;
    return PluginShortcut._(ctrl: ctrl, shift: shift, alt: alt, key: key, keyLabel: keyLabel);
  }

  bool matches(KeyEvent event) {
    if (event.logicalKey.keyId != key.keyId) return false;
    final HardwareKeyboard keyboard = HardwareKeyboard.instance;
    return keyboard.isControlPressed == ctrl && keyboard.isShiftPressed == shift && keyboard.isAltPressed == alt;
  }

  /// Human hint shown in the palette, e.g. `Ctrl+Shift+C`.
  String get label => <String>[
        if (ctrl) 'Ctrl',
        if (alt) 'Alt',
        if (shift) 'Shift',
        keyLabel,
      ].join('+');
}
