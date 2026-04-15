import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../win32/win32.dart';
import 'authenticator_entry.dart';

class AuthenticatorManager {
  static String get _filePath => "${WinUtils.getTabameAppDataFolder(settings: true)}\\authenticator.json";

  static Future<List<AuthenticatorEntry>> loadEntries() async {
    final File file = File(_filePath);
    if (!file.existsSync()) return <AuthenticatorEntry>[];

    try {
      final String content = await file.readAsString();
      if (content.trim().isEmpty) return <AuthenticatorEntry>[];

      final List<dynamic> decoded = jsonDecode(content) as List<dynamic>;
      final List<AuthenticatorEntry> entries = decoded
          .map((dynamic item) => AuthenticatorEntry.fromMap(item as Map<String, dynamic>))
          .where((AuthenticatorEntry item) => item.secret.trim().isNotEmpty)
          .toList();
      _sortEntries(entries);
      return entries;
    } catch (_) {
      return <AuthenticatorEntry>[];
    }
  }

  static Future<List<AuthenticatorEntry>> saveEntries(List<AuthenticatorEntry> entries) async {
    _sortEntries(entries);

    final File file = File(_filePath);
    if (!file.existsSync()) {
      await file.create(recursive: true);
    }

    await file.writeAsString(
      jsonEncode(entries.map((AuthenticatorEntry entry) => entry.toMap()).toList()),
    );
    return entries;
  }

  static Future<List<AuthenticatorEntry>> mergeEntries(Iterable<AuthenticatorEntry> newEntries) async {
    final List<AuthenticatorEntry> current = await loadEntries();
    final Set<String> fingerprints = current.map((AuthenticatorEntry entry) => entry.fingerprint).toSet();

    for (final AuthenticatorEntry entry in newEntries) {
      if (fingerprints.add(entry.fingerprint)) {
        current.add(entry);
      }
    }

    return saveEntries(current);
  }

  static Future<List<AuthenticatorEntry>> deleteEntry(String id) async {
    final List<AuthenticatorEntry> current = await loadEntries();
    current.removeWhere((AuthenticatorEntry entry) => entry.id == id);
    return saveEntries(current);
  }

  static AuthenticatorEntry parseOtpAuthUri(String rawUri) {
    final Uri uri = Uri.parse(rawUri.trim());
    if (uri.scheme.toLowerCase() != 'otpauth') {
      throw const FormatException('Expected an otpauth:// URI.');
    }
    if (uri.host.toLowerCase() != 'totp') {
      throw const FormatException('Only TOTP authenticators are supported.');
    }

    final String label = Uri.decodeComponent(
      uri.path.startsWith('/') ? uri.path.substring(1) : uri.path,
    ).trim();
    if (label.isEmpty) {
      throw const FormatException('The authenticator entry is missing a label.');
    }

    final Map<String, String> params = uri.queryParameters.map(
      (String key, String value) => MapEntry<String, String>(key.toLowerCase(), value.trim()),
    );

    final String secret = _normalizeSecret(params['secret'] ?? '');
    if (secret.isEmpty) {
      throw const FormatException('The authenticator entry is missing a secret.');
    }

    String issuerFromLabel = '';
    String accountName = label;
    final int labelSeparator = label.indexOf(':');
    if (labelSeparator >= 0) {
      issuerFromLabel = label.substring(0, labelSeparator).trim();
      accountName = label.substring(labelSeparator + 1).trim();
    }

    final String issuer = _decodeOtpComponent(params['issuer'] ?? issuerFromLabel);
    final String decodedAccountName = _decodeOtpComponent(accountName);
    final int digits = int.tryParse(params['digits'] ?? '') ?? 6;
    final int period = int.tryParse(params['period'] ?? '') ?? 30;
    final String algorithm = (params['algorithm'] ?? 'SHA1').toUpperCase();

    return AuthenticatorEntry(
      id: _buildEntryId(issuer: issuer, accountName: decodedAccountName, secret: secret),
      issuer: issuer,
      accountName: decodedAccountName,
      secret: secret,
      algorithm: algorithm,
      digits: digits < 4 ? 6 : digits,
      period: period <= 0 ? 30 : period,
    );
  }

  static String buildOtpAuthUri(AuthenticatorEntry entry) {
    final String label = entry.issuer.trim().isNotEmpty
        ? '${entry.issuer.trim()}:${entry.accountName.trim()}'
        : entry.accountName.trim().isNotEmpty
            ? entry.accountName.trim()
            : 'Authenticator';

    final Map<String, String> params = <String, String>{
      'secret': _normalizeSecret(entry.secret),
      if (entry.issuer.trim().isNotEmpty) 'issuer': entry.issuer.trim(),
      if (entry.algorithm.toUpperCase() != 'SHA1') 'algorithm': entry.algorithm.toUpperCase(),
      if (entry.digits != 6) 'digits': '${entry.digits}',
      if (entry.period != 30) 'period': '${entry.period}',
    };

    return Uri(
      scheme: 'otpauth',
      host: 'totp',
      path: '/$label',
      queryParameters: params,
    ).toString();
  }

  static List<String> extractOtpAuthUris(String raw) {
    final String normalized = raw.replaceAll('\uFEFF', '').trim();
    if (normalized.isEmpty) return <String>[];

    final Set<String> uris = <String>{};
    for (final String line in const LineSplitter().convert(normalized)) {
      final String trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (trimmed.toLowerCase().startsWith('otpauth://')) {
        uris.add(trimmed);
        continue;
      }
      if (trimmed.toLowerCase().startsWith('otpauth-migration://')) {
        uris.addAll(_expandMigrationUri(trimmed));
        continue;
      }

      for (final RegExpMatch match in RegExp("otpauth://[^\\s\"']+", caseSensitive: false).allMatches(trimmed)) {
        final String? value = match.group(0);
        if (value != null && value.isNotEmpty) {
          uris.add(value.trim());
        }
      }

      for (final RegExpMatch match
          in RegExp("otpauth-migration://[^\\s\"']+", caseSensitive: false).allMatches(trimmed)) {
        final String? value = match.group(0);
        if (value != null && value.isNotEmpty) {
          uris.addAll(_expandMigrationUri(value.trim()));
        }
      }
    }

    if (uris.isEmpty && normalized.toLowerCase().startsWith('otpauth://')) {
      uris.add(normalized);
    }
    if (uris.isEmpty && normalized.toLowerCase().startsWith('otpauth-migration://')) {
      uris.addAll(_expandMigrationUri(normalized));
    }
    return uris.toList(growable: false);
  }

  static String generateCode(AuthenticatorEntry entry, {DateTime? now}) {
    final Uint8List key = _decodeBase32(_normalizeSecret(entry.secret));
    if (key.isEmpty) {
      throw const FormatException('Invalid secret.');
    }

    final int timestamp = ((now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000);
    final int counter = timestamp ~/ entry.period;
    final ByteData counterBytes = ByteData(8)..setInt64(0, counter);
    final Hmac hmac = Hmac(_hashForAlgorithm(entry.algorithm), key);
    final List<int> digest = hmac.convert(counterBytes.buffer.asUint8List()).bytes;

    final int offset = digest.last & 0x0f;
    final int binary = ((digest[offset] & 0x7f) << 24) |
        ((digest[offset + 1] & 0xff) << 16) |
        ((digest[offset + 2] & 0xff) << 8) |
        (digest[offset + 3] & 0xff);
    final int code = binary % _pow10(entry.digits);
    return code.toString().padLeft(entry.digits, '0');
  }

  static int secondsRemaining(AuthenticatorEntry entry, {DateTime? now}) {
    final int timestamp = ((now ?? DateTime.now()).toUtc().millisecondsSinceEpoch ~/ 1000);
    final int remaining = entry.period - (timestamp % entry.period);
    return remaining == 0 ? entry.period : remaining;
  }

  static double progress(AuthenticatorEntry entry, {DateTime? now}) {
    final int remaining = secondsRemaining(entry, now: now);
    return 1 - (remaining / entry.period);
  }

  static void _sortEntries(List<AuthenticatorEntry> entries) {
    entries.sort((AuthenticatorEntry a, AuthenticatorEntry b) {
      final int issuerCompare = a.issuer.toLowerCase().compareTo(b.issuer.toLowerCase());
      if (issuerCompare != 0) return issuerCompare;
      return a.accountName.toLowerCase().compareTo(b.accountName.toLowerCase());
    });
  }

  static String _buildEntryId({
    required String issuer,
    required String accountName,
    required String secret,
  }) {
    final String base =
        '${issuer.trim()}|${accountName.trim()}|${secret.trim()}|${DateTime.now().microsecondsSinceEpoch}';
    return sha1.convert(utf8.encode(base)).toString();
  }

  static Hash _hashForAlgorithm(String algorithm) {
    switch (algorithm.toUpperCase()) {
      case 'SHA256':
        return sha256;
      case 'SHA512':
        return sha512;
      case 'SHA1':
      default:
        return sha1;
    }
  }

  static int _pow10(int digits) {
    int value = 1;
    for (int i = 0; i < digits; i++) {
      value *= 10;
    }
    return value;
  }

  static String _normalizeSecret(String secret) {
    return secret.replaceAll(RegExp(r'[\s-]+'), '').toUpperCase();
  }

  static String _decodeOtpComponent(String value) {
    return Uri.decodeComponent(value.replaceAll('+', '%20')).trim();
  }

  static Uint8List _decodeBase32(String input) {
    const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    int bits = 0;
    int value = 0;
    final List<int> output = <int>[];

    for (int i = 0; i < input.length; i++) {
      final int charIndex = alphabet.indexOf(input[i]);
      if (charIndex == -1) continue;

      value = (value << 5) | charIndex;
      bits += 5;

      if (bits >= 8) {
        output.add((value >> (bits - 8)) & 0xff);
        bits -= 8;
      }
    }

    return Uint8List.fromList(output);
  }

  static List<String> _expandMigrationUri(String rawUri) {
    try {
      final Uri uri = Uri.parse(rawUri.trim());
      if (uri.scheme.toLowerCase() != 'otpauth-migration') {
        return <String>[];
      }

      final String dataParam = uri.queryParameters['data']?.trim() ?? '';
      if (dataParam.isEmpty) return <String>[];

      final Uint8List bytes = _decodeMigrationData(dataParam);
      final _MigrationPayload payload = _parseMigrationPayload(bytes);
      return payload.entries
          .map((_MigrationOtpParameters entry) => _migrationEntryToOtpAuthUri(entry))
          .whereType<String>()
          .toList(growable: false);
    } catch (_) {
      return <String>[];
    }
  }

  static Uint8List _decodeMigrationData(String rawData) {
    final String decodedUrl = Uri.decodeComponent(rawData);
    final String normalized = decodedUrl.replaceAll('-', '+').replaceAll('_', '/');
    final int remainder = normalized.length % 4;
    final String padded = remainder == 0 ? normalized : '$normalized${'=' * (4 - remainder)}';
    return Uint8List.fromList(base64Decode(padded));
  }

  static _MigrationPayload _parseMigrationPayload(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);
    final List<_MigrationOtpParameters> entries = <_MigrationOtpParameters>[];

    while (!reader.isAtEnd) {
      final _ProtoField field = reader.readField();
      switch (field.number) {
        case 1:
          if (field.wireType != 2) continue;
          entries.add(_parseMigrationOtpParameters(field.bytesValue));
          break;
        default:
          break;
      }
    }

    return _MigrationPayload(entries: entries);
  }

  static _MigrationOtpParameters _parseMigrationOtpParameters(Uint8List bytes) {
    final _ProtoReader reader = _ProtoReader(bytes);
    final _MigrationOtpParameters entry = _MigrationOtpParameters();

    while (!reader.isAtEnd) {
      final _ProtoField field = reader.readField();
      switch (field.number) {
        case 1:
          if (field.wireType == 2) entry.secret = field.bytesValue;
          break;
        case 2:
          if (field.wireType == 2) entry.name = utf8.decode(field.bytesValue, allowMalformed: true);
          break;
        case 3:
          if (field.wireType == 2) entry.issuer = utf8.decode(field.bytesValue, allowMalformed: true);
          break;
        case 4:
          if (field.wireType == 0) entry.algorithm = field.intValue;
          break;
        case 5:
          if (field.wireType == 0) entry.digits = field.intValue;
          break;
        case 6:
          if (field.wireType == 0) entry.type = field.intValue;
          break;
        case 7:
          if (field.wireType == 0) entry.counter = field.intValue;
          break;
        default:
          break;
      }
    }

    return entry;
  }

  static String? _migrationEntryToOtpAuthUri(_MigrationOtpParameters entry) {
    if (entry.secret.isEmpty) return null;

    final String secret = _encodeBase32(entry.secret);
    if (secret.isEmpty) return null;

    final String accountName = entry.name.trim().isEmpty ? 'Imported account' : entry.name.trim();
    final String issuer = entry.issuer.trim();
    final String algorithm = _migrationAlgorithmName(entry.algorithm);
    final int digits = _migrationDigits(entry.digits);
    final bool isHotp = entry.type == 1;

    final String label = issuer.isEmpty ? accountName : '$issuer:$accountName';
    final Map<String, String> params = <String, String>{
      'secret': secret,
      if (issuer.isNotEmpty) 'issuer': issuer,
      if (algorithm != 'SHA1') 'algorithm': algorithm,
      if (digits != 6) 'digits': '$digits',
      if (isHotp) 'counter': '${entry.counter < 0 ? 0 : entry.counter}',
    };

    final String host = isHotp ? 'hotp' : 'totp';
    return Uri(
      scheme: 'otpauth',
      host: host,
      path: '/$label',
      queryParameters: params,
    ).toString();
  }

  static String _migrationAlgorithmName(int algorithm) {
    switch (algorithm) {
      case 2:
        return 'SHA256';
      case 3:
        return 'SHA512';
      case 4:
        return 'MD5';
      case 1:
      default:
        return 'SHA1';
    }
  }

  static int _migrationDigits(int digits) {
    switch (digits) {
      case 2:
        return 8;
      case 1:
      default:
        return 6;
    }
  }

  static String _encodeBase32(Uint8List input) {
    if (input.isEmpty) return '';

    const String alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';
    final StringBuffer output = StringBuffer();
    int value = 0;
    int bits = 0;

    for (final int byte in input) {
      value = (value << 8) | (byte & 0xff);
      bits += 8;

      while (bits >= 5) {
        output.write(alphabet[(value >> (bits - 5)) & 0x1f]);
        bits -= 5;
      }
    }

    if (bits > 0) {
      output.write(alphabet[(value << (5 - bits)) & 0x1f]);
    }

    return output.toString();
  }
}

class _MigrationPayload {
  const _MigrationPayload({
    required this.entries,
  });

  final List<_MigrationOtpParameters> entries;
}

class _MigrationOtpParameters {
  Uint8List secret = Uint8List(0);
  String name = '';
  String issuer = '';
  int algorithm = 1;
  int digits = 1;
  int type = 2;
  int counter = 0;
}

class _ProtoField {
  _ProtoField({
    required this.number,
    required this.wireType,
    this.intValue = 0,
    Uint8List? bytesValue,
  }) : bytesValue = bytesValue ?? Uint8List(0);

  final int number;
  final int wireType;
  final int intValue;
  final Uint8List bytesValue;
}

class _ProtoReader {
  _ProtoReader(this._bytes);

  final Uint8List _bytes;
  int _offset = 0;

  bool get isAtEnd => _offset >= _bytes.length;

  _ProtoField readField() {
    final int tag = _readVarint();
    final int fieldNumber = tag >> 3;
    final int wireType = tag & 0x07;

    switch (wireType) {
      case 0:
        return _ProtoField(
          number: fieldNumber,
          wireType: wireType,
          intValue: _readVarint(),
        );
      case 2:
        final int length = _readVarint();
        final Uint8List bytesValue = Uint8List.sublistView(_bytes, _offset, _offset + length);
        _offset += length;
        return _ProtoField(
          number: fieldNumber,
          wireType: wireType,
          bytesValue: bytesValue,
        );
      default:
        throw const FormatException('Unsupported protobuf wire type.');
    }
  }

  int _readVarint() {
    int shift = 0;
    int result = 0;

    while (true) {
      if (_offset >= _bytes.length) {
        throw const FormatException('Unexpected end of protobuf data.');
      }

      final int byte = _bytes[_offset++];
      result |= (byte & 0x7f) << shift;
      if ((byte & 0x80) == 0) {
        return result;
      }
      shift += 7;

      if (shift > 63) {
        throw const FormatException('Invalid protobuf varint.');
      }
    }
  }
}
