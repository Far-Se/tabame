import 'dart:convert';

/// Redacts common credential fields before data leaves the app-data boundary.
class SensitiveDataRedactor {
  SensitiveDataRedactor._();

  static final RegExp _secretKey = RegExp(
    r'(password|passphrase|token|secret|api[_-]?key|access[_-]?key|client[_-]?secret|authorization|credential|private[_-]?key)',
    caseSensitive: false,
  );
  static final RegExp _bearer = RegExp(r'\bBearer\s+[A-Za-z0-9._~+/=-]+', caseSensitive: false);
  static final RegExp _otpauthSecret = RegExp(r'([?&]secret=)[^&\s]+', caseSensitive: false);
  static const String redacted = '[REDACTED]';

  static dynamic redactJson(Object? value) {
    if (value is Map) {
      return <String, dynamic>{
        for (final MapEntry<dynamic, dynamic> entry in value.entries)
          entry.key.toString(): _secretKey.hasMatch(entry.key.toString()) ? redacted : redactJson(entry.value),
      };
    }
    if (value is List) return value.map(redactJson).toList(growable: false);
    if (value is String) {
      final String? decoded = _redactEmbeddedJson(value);
      return decoded ?? redactText(value);
    }
    return value;
  }

  static String redactText(String value) {
    String result = value.replaceAllMapped(_bearer, (_) => 'Bearer $redacted');
    result = result.replaceAllMapped(_otpauthSecret, (Match match) => '${match.group(1)}$redacted');
    result = result.replaceAllMapped(
      RegExp(
        r'(password|passphrase|token|secret|api[_-]?key|access[_-]?key|client[_-]?secret|authorization|credential)'
        r'''(\s*[=:]\s*)("[^"]*"|'[^']*'|[^\s,;]+)''',
        caseSensitive: false,
      ),
      (Match match) => '${match.group(1)}${match.group(2)}$redacted',
    );
    return result;
  }

  static String? _redactEmbeddedJson(String value) {
    final String trimmed = value.trim();
    if (!(trimmed.startsWith('{') || trimmed.startsWith('['))) return null;
    try {
      final Object? decoded = jsonDecode(trimmed);
      return jsonEncode(redactJson(decoded));
    } catch (_) {
      return null;
    }
  }
}
