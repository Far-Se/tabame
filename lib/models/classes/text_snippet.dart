// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:tabamewin32/tabamewin32.dart';

import 'boxes.dart';

/// A single text-expansion rule. When the user types [trigger] and fires the
/// insert-snippet hotkey, the trigger is replaced by [text].
class TextSnippet {
  String trigger;
  String text;
  bool enabled;

  TextSnippet({
    required this.trigger,
    required this.text,
    this.enabled = true,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'trigger': trigger,
        'text': text,
        'enabled': enabled,
      };

  String toJson() => jsonEncode(toMap());

  factory TextSnippet.fromMap(Map<String, dynamic> map) => TextSnippet(
        trigger: (map['trigger'] as String?) ?? '',
        text: (map['text'] as String?) ?? '',
        enabled: (map['enabled'] as bool?) ?? true,
      );

  factory TextSnippet.fromJson(String source) =>
      TextSnippet.fromMap(jsonDecode(source) as Map<String, dynamic>);

  TextSnippet copyWith({String? trigger, String? text, bool? enabled}) => TextSnippet(
        trigger: trigger ?? this.trigger,
        text: text ?? this.text,
        enabled: enabled ?? this.enabled,
      );
}

/// Persistence + native sync for [TextSnippet]s. The list lives in settings
/// under [settingsKey]; the enabled rules are mirrored to the native buffer via
/// [TextSnippets.setSnippets] so expansion can happen synchronously in the hook.
class TextSnippetsManager {
  static const String settingsKey = "textSnippets";

  static List<TextSnippet> load() =>
      Boxes.getSavedMap<TextSnippet>(TextSnippet.fromJson, settingsKey);

  static Future<void> save(List<TextSnippet> snippets) async {
    await Boxes.updateSettings(settingsKey, jsonEncode(snippets));
    await pushToNative(snippets);
  }

  /// Push the enabled snippets to the native matcher. Safe to call repeatedly;
  /// the native side simply replaces its list.
  static Future<void> pushToNative([List<TextSnippet>? snippets]) async {
    final List<TextSnippet> list = snippets ?? load();
    await TextSnippets.setSnippets(
      list
          .where((TextSnippet s) => s.enabled && s.trigger.isNotEmpty)
          .map((TextSnippet s) => <String, String>{'trigger': s.trigger, 'text': s.text})
          .toList(),
    );
  }

  /// Invoked from the `ExpandSnippet` hotkey function.
  static Future<bool> expand() => TextSnippets.expand();
}
