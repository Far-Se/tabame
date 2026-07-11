import 'package:flutter/material.dart';

/// The markdown-lite subset allowed in plugin item titles/subtitles:
/// `**bold**` and `` `code` `` spans. Everything else is literal text.
final RegExp _inlineMarkupPattern = RegExp(r'\*\*(.+?)\*\*|`(.+?)`');

/// True when [text] contains any markup worth parsing — lets callers skip the
/// rich-text path entirely for plain strings.
bool hasInlineMarkup(String text) => _inlineMarkupPattern.hasMatch(text);

/// Parses [text] into a span tree styled relative to [base]: bold runs get
/// full opacity + w700, code runs get a monospace face tinted with [accent].
TextSpan launcherInlineMarkup(String text, TextStyle base, Color accent) {
  final List<InlineSpan> children = <InlineSpan>[];
  int cursor = 0;
  for (final RegExpMatch match in _inlineMarkupPattern.allMatches(text)) {
    if (match.start > cursor) {
      children.add(TextSpan(text: text.substring(cursor, match.start)));
    }
    final String? bold = match.group(1);
    if (bold != null) {
      children.add(TextSpan(
        text: bold,
        style: base.copyWith(fontWeight: FontWeight.w700, color: base.color?.withAlpha(255)),
      ));
    } else {
      children.add(TextSpan(
        text: match.group(2),
        style: base.copyWith(fontFamily: 'Consolas', color: accent),
      ));
    }
    cursor = match.end;
  }
  if (cursor < text.length) {
    children.add(TextSpan(text: text.substring(cursor)));
  }
  return TextSpan(style: base, children: children);
}
