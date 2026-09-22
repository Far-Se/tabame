import 'dart:convert';

import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

class QuicklinkArgument {
  const QuicklinkArgument({required this.key, required this.name, this.defaultValue, this.options = const <String>[]});

  final String key;
  final String name;
  final String? defaultValue;
  final List<String> options;

  String? error(String value) {
    final String resolved = value.isEmpty ? defaultValue ?? '' : value;
    if (resolved.isEmpty && defaultValue == null) return 'Enter $name.';
    if (options.isNotEmpty && !options.contains(resolved)) return 'Choose one of: ${options.join(', ')}.';
    return null;
  }
}

class _Placeholder {
  const _Placeholder(this.match, this.kind, this.attributes, this.modifiers, this.argumentKey);
  final RegExpMatch match;
  final String kind;
  final Map<String, String> attributes;
  final List<String> modifiers;
  final String? argumentKey;
}

/// Reuses named arguments and encodes only substituted values. Local paths
/// retain spaces and separators; URLs percent-encode arguments by default.
class QuicklinkTemplate {
  QuicklinkTemplate(this.source) {
    _parse();
  }

  final String source;
  final List<QuicklinkArgument> arguments = <QuicklinkArgument>[];
  final List<_Placeholder> _placeholders = <_Placeholder>[];
  static final RegExp _placeholder = RegExp(r'''\{((?:[^{}"']|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*')*)\}''');
  static final RegExp _attribute =
      RegExp(r'''([a-zA-Z-]+)\s*=\s*(?:"((?:\\.|[^"\\])*)"|'((?:\\.|[^'\\])*)'|([^\s]+))''');
  static const Set<String> _kinds = <String>{'argument', 'clipboard', 'date', 'time', 'datetime', 'day', 'uuid'};
  static const Set<String> _modifiers = <String>{
    'raw',
    'uppercase',
    'lowercase',
    'trim',
    'percent-encode',
    'json-stringify'
  };

  static bool isLocalPath(String value) =>
      RegExp(r'^[a-zA-Z]:[\\/]').hasMatch(value) ||
      value.startsWith(r'\\') ||
      value.startsWith('/') ||
      value.startsWith('~/') ||
      value.startsWith('~\\');

  bool get usesClipboard => _placeholders.any((_Placeholder part) => part.kind == 'clipboard');

  static List<String> _splitModifiers(String body) {
    final List<String> parts = <String>[];
    String quote = '';
    int start = 0;
    for (int i = 0; i < body.length; i++) {
      final String char = body[i];
      if (quote.isNotEmpty) {
        if (char == '\\') {
          i++;
        } else if (char == quote) {
          quote = '';
        }
      } else if (char == '"' || char == "'") {
        quote = char;
      } else if (char == '|') {
        parts.add(body.substring(start, i).trim());
        start = i + 1;
      }
    }
    parts.add(body.substring(start).trim());
    return parts;
  }

  void _parse() {
    int unnamed = 0;
    for (final RegExpMatch match in _placeholder.allMatches(source)) {
      final List<String> segments = _splitModifiers(match.group(1)!);
      if (segments.first.isEmpty) throw const FormatException('Empty placeholder. Use {argument} for an input.');
      final String head = segments.first;
      final String kind = head.split(RegExp(r'\s+')).first;
      final Map<String, String> attributes = <String, String>{};
      final String tail = head.substring(kind.length).trim();
      int end = 0;
      for (final RegExpMatch attribute in _attribute.allMatches(tail)) {
        if (tail.substring(end, attribute.start).trim().isNotEmpty)
          throw FormatException('Invalid placeholder: ${match.group(0)}');
        final String key = attribute.group(1)!;
        if (attributes.containsKey(key)) throw FormatException('Repeated attribute "$key".');
        attributes[key] = (attribute.group(2) ?? attribute.group(3) ?? attribute.group(4)!)
            .replaceAllMapped(RegExp(r'''\\([\\"'])'''), (Match escaped) => escaped.group(1)!);
        end = attribute.end;
      }
      if (tail.substring(end).trim().isNotEmpty) throw FormatException('Invalid placeholder: ${match.group(0)}');
      final List<String> modifiers = segments.skip(1).toList();
      for (final String modifier in modifiers) {
        if (!_modifiers.contains(modifier)) throw FormatException('Unsupported modifier: $modifier.');
      }
      final bool shorthand = !_kinds.contains(kind);
      if (<String>{'selection', 'calculator', 'browser-tab', 'snippet', 'cursor', 'shell'}.contains(kind)) {
        throw FormatException('{$kind} is not supported in Tabame quicklinks.');
      }
      if (shorthand && (tail.isNotEmpty || kind.isEmpty)) throw FormatException('Unknown placeholder: $kind.');
      final String resolvedKind = shorthand ? 'argument' : kind;
      final Set<String> allowedAttributes = switch (resolvedKind) {
        'argument' => <String>{'name', 'default', 'options'},
        'date' || 'time' || 'datetime' || 'day' => <String>{'format', 'offset'},
        _ => <String>{},
      };
      for (final String attribute in attributes.keys) {
        if (!allowedAttributes.contains(attribute)) throw FormatException('$kind does not support "$attribute".');
      }
      String? argumentKey;
      if (resolvedKind == 'argument') {
        final String? name = shorthand ? kind : attributes['name'];
        if (name != null && name.trim().isEmpty) throw const FormatException('Argument names cannot be empty.');
        argumentKey = name == null ? 'unnamed:${unnamed++}' : 'named:$name';
        final List<String> options = (attributes['options'] ?? '')
            .split(',')
            .map((String option) => option.trim())
            .where((String option) => option.isNotEmpty)
            .toSet()
            .toList();
        QuicklinkArgument argument = QuicklinkArgument(
          key: argumentKey,
          name: name ?? (unnamed == 1 ? 'Query' : 'Argument $unnamed'),
          defaultValue: attributes['default'],
          options: options,
        );
        final int existing = arguments.indexWhere((QuicklinkArgument item) => item.key == argumentKey);
        if (existing < 0) {
          arguments.add(argument);
        } else {
          final QuicklinkArgument previous = arguments[existing];
          if ((previous.defaultValue != null &&
                  argument.defaultValue != null &&
                  previous.defaultValue != argument.defaultValue) ||
              (previous.options.isNotEmpty &&
                  options.isNotEmpty &&
                  previous.options.join('\u0000') != options.join('\u0000'))) {
            throw FormatException('Use the same default and options for every "$name" argument.');
          }
          argument = QuicklinkArgument(
              key: argumentKey,
              name: argument.name,
              defaultValue: previous.defaultValue ?? argument.defaultValue,
              options: previous.options.isEmpty ? options : previous.options);
          arguments[existing] = argument;
        }
        if (argument.defaultValue != null && argument.error('') != null) {
          throw FormatException('The default for "${argument.name}" must match one of its options.');
        }
      }
      _placeholders.add(_Placeholder(match, resolvedKind, attributes, modifiers, argumentKey));
    }
    final String literal = source.replaceAll(_placeholder, '');
    if (literal.contains('{') || literal.contains('}'))
      throw const FormatException('Close every placeholder with }. Encode literal braces as %7B and %7D in URLs.');
    if (arguments.length > 3) throw const FormatException('A quicklink can have up to three different arguments.');
  }

  void validate() {
    // Validate syntax without accessing the clipboard or opening anything.
    final Map<String, String> values = <String, String>{
      for (final QuicklinkArgument argument in arguments)
        argument.key: argument.options.isNotEmpty ? argument.options.first : 'example',
    };
    final String target = resolve(values: values, clipboard: 'https://example.com');
    // A raw argument can supply the entire destination; validate its actual
    // scheme at execution time instead of guessing what the user will enter.
    if (_placeholders.length == 1 &&
        _placeholders.first.match.group(0) == source &&
        _placeholders.first.modifiers.contains('raw')) return;
    validateTarget(target);
  }

  static void validateTarget(String target) {
    if (target.contains(RegExp(r'[\x00-\x1f]')))
      throw const FormatException('Links cannot contain line breaks or control characters.');
    if (isLocalPath(target)) return;
    final Uri? uri = Uri.tryParse(target);
    if (uri == null || !uri.hasScheme)
      throw const FormatException('Use a full URL (https://…), an absolute file path, or an app deeplink.');
    if (<String>{'http', 'https'}.contains(uri.scheme) && uri.host.isEmpty) {
      throw const FormatException('Enter a valid website address.');
    }
  }

  String resolve({Map<String, String> values = const <String, String>{}, String clipboard = '', DateTime? now}) {
    final DateTime current = now ?? DateTime.now();
    final StringBuffer output = StringBuffer();
    int end = 0;
    for (final _Placeholder part in _placeholders) {
      output.write(source.substring(end, part.match.start));
      String value;
      if (part.argumentKey != null) {
        final QuicklinkArgument argument =
            arguments.firstWhere((QuicklinkArgument item) => item.key == part.argumentKey);
        final String supplied = values[argument.key] ?? '';
        final String? error = argument.error(supplied);
        if (error != null) throw FormatException(error);
        value = supplied.isEmpty ? argument.defaultValue ?? '' : supplied;
      } else if (part.kind == 'clipboard') {
        value = clipboard;
      } else if (part.kind == 'uuid') {
        value = const Uuid().v4();
      } else {
        DateTime date = current;
        final String offset = part.attributes['offset'] ?? '';
        final RegExp offsetPattern = RegExp(r'([+-]\d+)([mhdMy])');
        if (offset.replaceAll(offsetPattern, '').trim().isNotEmpty)
          throw const FormatException('Use date offsets such as +2d or -1M.');
        for (final RegExpMatch change in offsetPattern.allMatches(offset)) {
          final int amount = int.parse(change.group(1)!);
          date = switch (change.group(2)) {
            'm' => date.add(Duration(minutes: amount)),
            'h' => date.add(Duration(hours: amount)),
            'd' => date.add(Duration(days: amount)),
            'M' => _offsetMonths(date, amount),
            'y' => _offsetMonths(date, amount * 12),
            _ => date,
          };
        }
        final String format = part.attributes['format'] ??
            switch (part.kind) {
              'time' => 'HH:mm',
              'datetime' => 'yyyy-MM-dd HH:mm',
              'day' => 'EEEE',
              _ => 'yyyy-MM-dd',
            };
        value = DateFormat(format).format(date);
      }
      bool encoded = false;
      for (final String modifier in part.modifiers) {
        switch (modifier) {
          case 'uppercase':
            value = value.toUpperCase();
          case 'lowercase':
            value = value.toLowerCase();
          case 'trim':
            value = value.trim();
          case 'json-stringify':
            value = jsonEncode(value);
          case 'percent-encode':
            value = Uri.encodeComponent(value);
            encoded = true;
        }
      }
      if (!isLocalPath(source) && !encoded && !part.modifiers.contains('raw')) value = Uri.encodeComponent(value);
      output.write(value);
      end = part.match.end;
    }
    output.write(source.substring(end));
    return output.toString();
  }

  static DateTime _offsetMonths(DateTime date, int months) {
    final DateTime month = DateTime(date.year, date.month + months);
    final int lastDay = DateTime(month.year, month.month + 1, 0).day;
    return DateTime(month.year, month.month, date.day.clamp(1, lastDay), date.hour, date.minute, date.second,
        date.millisecond, date.microsecond);
  }
}
