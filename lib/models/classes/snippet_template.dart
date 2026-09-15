import 'dart:convert';

import 'package:characters/characters.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:intl/intl.dart';
import 'package:math_parser/math_parser.dart';
import 'package:uuid/uuid.dart';

class SnippetArgument {
  const SnippetArgument(this.name, {this.defaultValue, this.options = const <String>[]});

  final String name;
  final String? defaultValue;
  final List<String> options;
}

class SnippetTemplateSource {
  const SnippetTemplateSource(this.text, {this.allowShell = false});

  final String text;
  final bool allowShell;
}

class SnippetExpansion {
  const SnippetExpansion(this.text, {this.cursorOffset, this.html = ''});

  final String text;
  final int? cursorOffset;
  final String html;
  int get cursorLeft => cursorOffset == null ? -1 : text.substring(cursorOffset!).characters.length;
  int get characterCount => text.characters.length;
}

/// Shared parser for previews, the library, and native keyword expansion.
/// Clipboard/argument/shell values are never parsed again as template code.
class SnippetTemplate {
  SnippetTemplate(
    String source, {
    Map<String, SnippetTemplateSource> snippets = const <String, SnippetTemplateSource>{},
    bool allowShell = false,
  }) {
    _parts = _parse(source, snippets, <String>[], allowShell);
    if (_cursorCount > 1) throw const FormatException('Use only one {cursor}, including referenced snippets.');
  }

  static const int maxLength = 262144;
  static const String _cursor = '\uE000tabame-cursor\uE001';
  static final RegExp _identifier = RegExp(r'^[A-Za-z_][\w-]*');
  static final RegExp _attribute = RegExp(r'''^([\w-]+)\s*=\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^\s]+))''');
  static const Set<String> _builtins = <String>{
    'clipboard',
    'cursor',
    'date',
    'time',
    'datetime',
    'day',
    'uuid',
    'argument',
    'snippet',
    'shell',
    'calculator',
  };
  static const Set<String> _modifiers = <String>{
    'uppercase',
    'lowercase',
    'trim',
    'percent-encode',
    'json-stringify',
    'raw',
  };
  late final List<_SnippetPart> _parts;
  final Map<String, SnippetArgument> _arguments = <String, SnippetArgument>{};
  int _unnamedArguments = 0;
  int _cursorCount = 0;
  int _sourceBudget = 0;
  bool hasShell = false;
  final Set<int> clipboardOffsets = <int>{};

  List<SnippetArgument> get arguments => _arguments.values.toList();
  bool get needsInput => arguments.any((SnippetArgument a) => a.defaultValue == null);
  bool get isDynamic => _parts.any((_SnippetPart part) => part.kind.isNotEmpty);

  List<_SnippetPart> _parse(
      String source, Map<String, SnippetTemplateSource> snippets, List<String> stack, bool allowShell) {
    _sourceBudget += source.length;
    if (_sourceBudget > maxLength || stack.length > 8) {
      throw const FormatException('Snippet references are too large or nested more than 8 levels.');
    }
    if (source.contains(_cursor)) throw const FormatException('Snippet contains a reserved cursor marker.');
    final List<_SnippetPart> parts = <_SnippetPart>[];
    final StringBuffer literal = StringBuffer();
    void flush() {
      if (literal.isNotEmpty) {
        parts.add(_SnippetPart(literal: literal.toString()));
        literal.clear();
      }
    }

    for (int i = 0; i < source.length;) {
      if (source[i] == '\\' && i + 1 < source.length && (source[i + 1] == '{' || source[i + 1] == '}')) {
        literal.write(source[i + 1]);
        i += 2;
        continue;
      }
      if (source[i] != '{' || !_identifier.hasMatch(source.substring(i + 1))) {
        literal.write(source[i++]);
        continue;
      }
      int end = i + 1;
      String quote = '';
      for (; end < source.length; end++) {
        final String ch = source[end];
        if (ch == '\\' && quote.isNotEmpty) {
          end++;
          continue;
        }
        if (quote.isNotEmpty) {
          if (ch == quote) quote = '';
        } else if (ch == '"' || ch == "'") {
          quote = ch;
        } else if (ch == '}' || ch == '{' || ch == '\n') {
          break;
        }
      }
      if (end >= source.length || source[end] != '}') {
        literal.write(source[i++]);
        continue;
      }
      final String body = source.substring(i + 1, end);
      final String name = _identifier.firstMatch(body)!.group(0)!;
      String rest = body.substring(name.length).trim();
      // Ordinary JSON, CSS, and code blocks remain literal.
      if (rest.isNotEmpty && !RegExp(r'^[\w-]+\s*=|^\|').hasMatch(rest)) {
        literal.write(source.substring(i, end + 1));
        i = end + 1;
        continue;
      }
      if (!_builtins.contains(name) && rest.isNotEmpty && !rest.startsWith('|')) {
        throw FormatException('Unknown placeholder: $name. Escape a literal brace with \\{.');
      }
      final Map<String, String> attrs = <String, String>{};
      while (rest.isNotEmpty && !rest.startsWith('|')) {
        final RegExpMatch? match = _attribute.firstMatch(rest);
        if (match == null) throw FormatException('Invalid attributes in {$body}.');
        final String key = match.group(1)!;
        if (attrs.containsKey(key)) throw FormatException('Repeated attribute "$key" in {$body}.');
        attrs[key] = (match.group(2) ?? match.group(3) ?? match.group(4)!)
            .replaceAllMapped(RegExp(r'''\\([\\"'])'''), (Match m) => m.group(1)!);
        rest = rest.substring(match.end).trim();
      }
      final List<String> modifiers =
          rest.isEmpty ? <String>[] : rest.substring(1).split('|').map((String s) => s.trim()).toList();
      for (final String modifier in modifiers) {
        if (!_modifiers.contains(modifier)) throw FormatException('Unknown modifier: $modifier.');
      }
      final String kind = _builtins.contains(name) ? name : 'argument';
      if (kind == 'argument') {
        final String key = attrs['name'] ?? (kind == name ? 'Argument ${++_unnamedArguments}' : name);
        if (key.trim().isEmpty) throw const FormatException('Argument names cannot be empty.');
        attrs['name'] = key;
        final List<String> options = attrs['options']
                ?.split(',')
                .map((String s) => s.trim())
                .where((String s) => s.isNotEmpty)
                .toSet()
                .toList() ??
            <String>[];
        final SnippetArgument? previous = _arguments[key];
        final SnippetArgument arg = SnippetArgument(key,
            defaultValue: attrs['default'] ?? previous?.defaultValue,
            options: options.isEmpty ? previous?.options ?? <String>[] : options);
        if (arg.defaultValue != null && arg.options.isNotEmpty && !arg.options.contains(arg.defaultValue)) {
          throw FormatException('The default for "$key" must be one of its options.');
        }
        if (previous != null &&
            ((previous.defaultValue != null &&
                    attrs.containsKey('default') &&
                    previous.defaultValue != arg.defaultValue) ||
                (previous.options.isNotEmpty &&
                    options.isNotEmpty &&
                    previous.options.join('\n') != options.join('\n')))) {
          throw FormatException('Repeated argument "$key" must use the same default and options.');
        }
        _arguments[key] = arg;
      }
      if (kind == 'cursor') _cursorCount++;
      if (kind == 'shell') {
        hasShell = true;
        if ((attrs['code'] ?? '').isEmpty) throw const FormatException('Shell placeholders need code="...".');
      }
      if (kind == 'clipboard') {
        final int? offset = int.tryParse(attrs['offset'] ?? '0');
        if (offset == null || offset < 0 || offset > 100)
          throw const FormatException('Clipboard offset must be between 0 and 100.');
        clipboardOffsets.add(offset);
      }
      if (kind == 'calculator' && !attrs.containsKey('expression')) clipboardOffsets.add(0);
      if (<String>{'date', 'time', 'datetime', 'day'}.contains(kind)) {
        if (attrs.containsKey('locale') && attrs.containsKey('format')) {
          throw const FormatException('Use either a date format or a locale, not both.');
        }
        _offsetDate(DateTime(2024, 1, 31), attrs['offset'] ?? '');
      }
      final Set<String> allowed = switch (kind) {
        'argument' => <String>{'name', 'default', 'options'},
        'snippet' => <String>{'name'},
        'shell' => <String>{'code'},
        'calculator' => <String>{'expression'},
        'clipboard' => <String>{'offset'},
        'date' || 'time' || 'datetime' || 'day' => <String>{'format', 'locale', 'offset'},
        _ => <String>{},
      };
      for (final String key in attrs.keys) {
        if (!allowed.contains(key)) throw FormatException('Unknown attribute "$key" for {$kind}.');
      }
      List<_SnippetPart>? children;
      if (kind == 'snippet') {
        final String reference = attrs['name'] ?? '';
        final SnippetTemplateSource? target = snippets[reference];
        if (target == null) throw FormatException('Referenced snippet "$reference" was not found.');
        if (stack.contains(reference))
          throw FormatException('Circular snippet reference: ${<String>[...stack, reference].join(' → ')}.');
        children = _parse(target.text, snippets, <String>[...stack, reference], target.allowShell);
      }
      flush();
      parts.add(_SnippetPart(
          kind: kind, attributes: attrs, modifiers: modifiers, children: children, allowShell: allowShell));
      i = end + 1;
    }
    flush();
    return parts;
  }

  Future<SnippetExpansion> render({
    Map<String, String> values = const <String, String>{},
    Map<int, String> clipboard = const <int, String>{},
    DateTime? now,
    bool preview = false,
    Future<String> Function(String code)? runShell,
  }) async {
    final DateTime timestamp = now ?? DateTime.now();
    final String cursorMarker = '$_cursor:${const Uuid().v4()}';
    final Map<String, String> args = <String, String>{};
    for (final SnippetArgument argument in arguments) {
      final String? value = values[argument.name] ?? argument.defaultValue;
      if (!preview && (value == null || (value.isEmpty && argument.defaultValue == null))) {
        throw FormatException('Enter ${argument.name}.');
      }
      if (!preview && argument.options.isNotEmpty && !argument.options.contains(value)) {
        throw FormatException('Choose a value for ${argument.name}.');
      }
      args[argument.name] = value ?? '‹${argument.name}›';
    }
    final List<_SnippetPart> shellParts = <_SnippetPart>[];
    void collectShells(List<_SnippetPart> parts) {
      for (final _SnippetPart part in parts) {
        if (part.kind == 'shell') shellParts.add(part);
        if (part.children != null) collectShells(part.children!);
      }
    }

    collectShells(_parts);
    final Map<_SnippetPart, String> shellOutput = <_SnippetPart, String>{};
    if (!preview && shellParts.isNotEmpty) {
      if (runShell == null || shellParts.any((_SnippetPart part) => !part.allowShell)) {
        throw const FormatException('Enable shell commands in each referenced snippet before using it.');
      }
      if (shellParts.length > 16) throw const FormatException('Use at most 16 shell placeholders in one expansion.');
      final List<String> outputs =
          await Future.wait(shellParts.map((_SnippetPart part) => runShell(part.attributes['code']!)));
      for (int i = 0; i < shellParts.length; i++) {
        shellOutput[shellParts[i]] = outputs[i];
      }
    }
    Future<String> renderParts(List<_SnippetPart> parts) async {
      final StringBuffer output = StringBuffer();
      for (final _SnippetPart part in parts) {
        String value;
        if (part.kind.isEmpty) {
          value = part.literal;
        } else {
          final Map<String, String> a = part.attributes;
          switch (part.kind) {
            case 'cursor':
              value = cursorMarker;
            case 'argument':
              value = args[a['name']]!;
            case 'clipboard':
              value = clipboard[int.parse(a['offset'] ?? '0')] ?? '';
            case 'uuid':
              value = const Uuid().v4();
            case 'snippet':
              value = await renderParts(part.children!);
            case 'shell':
              if (preview) {
                value = '‹shell output · runs on use›';
              } else {
                value = shellOutput[part]!;
              }
            case 'calculator':
              final String expression = a['expression'] ?? clipboard[0] ?? '';
              try {
                final num result =
                    MathNodeExpression.fromString(expression).calc(const MathVariableValues(<String, num>{}));
                if (!result.isFinite) throw const FormatException('Result is not finite.');
                value = result.abs() <= 9007199254740991 && result == result.roundToDouble()
                    ? result.toInt().toString()
                    : result.toString();
              } catch (_) {
                throw FormatException('Invalid calculator expression: $expression.');
              }
            default:
              final DateTime date = _offsetDate(timestamp, a['offset'] ?? '');
              final String? localeTag = a['locale'];
              final bool use24Hour =
                  localeTag?.endsWith('-u-hc-h23') == true || localeTag?.endsWith('-u-hc-h24') == true;
              final String? locale = localeTag?.split('-u-').first.replaceAll('-', '_');
              if (locale != null) {
                await initializeDateFormatting(locale);
                if (!DateFormat.localeExists(locale)) throw FormatException('Unsupported date locale: ${a['locale']}.');
              }
              final String? format = a['format'];
              final DateFormat formatter = format != null
                  ? DateFormat(format)
                  : switch (part.kind) {
                      'time' => use24Hour ? DateFormat.Hm(locale) : DateFormat.jm(locale),
                      'datetime' => use24Hour ? DateFormat.yMMMd(locale).add_Hm() : DateFormat.yMMMd(locale).add_jm(),
                      'day' => DateFormat.EEEE(locale),
                      _ => DateFormat.yMMMd(locale),
                    };
              value = formatter.format(date);
          }
          for (final String modifier in part.modifiers) {
            if (value.contains(cursorMarker) && modifier != 'raw')
              throw const FormatException('Modifiers cannot transform a cursor position.');
            value = switch (modifier) {
              'uppercase' => value.toUpperCase(),
              'lowercase' => value.toLowerCase(),
              'trim' => value.trim(),
              'percent-encode' => Uri.encodeComponent(value),
              'json-stringify' => jsonEncode(value),
              _ => value,
            };
          }
        }
        if (output.length + value.length > maxLength)
          throw const FormatException('Expanded snippet exceeds 256K characters.');
        output.write(value);
      }
      return output.toString();
    }

    final String expanded = (await renderParts(_parts)).replaceAll('\r\n', '\n').replaceAll('\r', '\n');
    final int cursor = expanded.indexOf(cursorMarker);
    return SnippetExpansion(expanded.replaceAll(cursorMarker, ''), cursorOffset: cursor < 0 ? null : cursor);
  }

  static DateTime _offsetDate(DateTime date, String offset) {
    if (offset.trim().isEmpty) return date;
    for (final String token in offset.trim().split(RegExp(r'\s+'))) {
      final RegExpMatch? match = RegExp(r'^([+-]\d+)([mhdMwy])$').firstMatch(token);
      if (match == null) throw FormatException('Invalid date offset: $token. Use +2d, -3h, +1M, or +1y.');
      final int count = int.parse(match.group(1)!);
      if (count.abs() > 100000) throw const FormatException('Date offset is too large.');
      switch (match.group(2)) {
        case 'm':
          date = date.add(Duration(minutes: count));
        case 'h':
          date = date.add(Duration(hours: count));
        case 'd':
          date = DateTime(date.year, date.month, date.day + count, date.hour, date.minute, date.second,
              date.millisecond, date.microsecond);
        case 'w':
          date = DateTime(date.year, date.month, date.day + count * 7, date.hour, date.minute, date.second,
              date.millisecond, date.microsecond);
        default:
          final int month = date.month + (match.group(2) == 'y' ? count * 12 : count);
          final DateTime first = DateTime(date.year, month);
          final int lastDay = DateTime(first.year, first.month + 1, 0).day;
          date = DateTime(first.year, first.month, date.day > lastDay ? lastDay : date.day, date.hour, date.minute,
              date.second, date.millisecond, date.microsecond);
      }
    }
    return date;
  }
}

class _SnippetPart {
  const _SnippetPart(
      {this.literal = '',
      this.kind = '',
      this.attributes = const <String, String>{},
      this.modifiers = const <String>[],
      this.children,
      this.allowShell = false});
  final String literal;
  final String kind;
  final Map<String, String> attributes;
  final List<String> modifiers;
  final List<_SnippetPart>? children;
  final bool allowShell;
}
