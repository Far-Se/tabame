import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../provider_usage_service.dart';

/// Google Antigravity quotas, ported from Claude-Code-Usage-Monitor.
///
/// Antigravity stores its Google OAuth token in the Windows Credential
/// Manager (`gemini:antigravity`). An expired token is refreshed against
/// Google with the OAuth client embedded in the installed Antigravity binary
/// (the refreshed token is kept in memory only; Antigravity's store is never
/// written). Quotas come from the Cloud Code `retrieveUserQuotaSummary` call,
/// with per-model quotas as a fallback.
class AntigravityUsageFetcher extends ProviderUsageFetcher {
  static const String _credentialTarget = 'gemini:antigravity';
  static const String _tokenUrl = 'https://oauth2.googleapis.com/token';
  // The quota summary includes every group only for the agy CLI form of the UA.
  static const String _userAgent = 'antigravity/cli/1.4.0';
  static const List<String> _endpoints = <String>[
    'https://daily-cloudcode-pa.googleapis.com',
    'https://cloudcode-pa.googleapis.com',
    'https://daily-cloudcode-pa.sandbox.googleapis.com',
  ];

  String? _refreshedToken;
  DateTime? _refreshedExpiry;
  List<(String, String)>? _oauthClients;

  @override
  Future<ProviderUsageRecord> fetch() async {
    final _AntigravityToken? creds = _readCredentials();
    if (creds == null) throw const UsageFetchException('Sign in to Antigravity to make usage available.');

    final DateTime soon = DateTime.now().add(const Duration(minutes: 1));
    String token = creds.accessToken;
    bool refreshed = false;
    if (token.isEmpty || (creds.expiry != null && !creds.expiry!.isAfter(soon))) {
      if (_refreshedToken != null && _refreshedExpiry != null && _refreshedExpiry!.isAfter(soon)) {
        token = _refreshedToken!;
      } else if (creds.refreshToken != null) {
        try {
          token = await _refresh(creds.refreshToken!);
        } on _AuthRequired {
          throw const UsageFetchException('Antigravity sign-in expired. Open Antigravity to sign in again.');
        }
        refreshed = true;
      }
    }
    if (token.isEmpty) throw const UsageFetchException('Antigravity sign-in expired. Open Antigravity to sign in again.');

    try {
      return await _fetchUsage(token);
    } on _AuthRequired {
      if (refreshed || creds.refreshToken == null) {
        throw const UsageFetchException('Antigravity sign-in expired. Open Antigravity to sign in again.');
      }
      try {
        return await _fetchUsage(await _refresh(creds.refreshToken!));
      } on _AuthRequired {
        throw const UsageFetchException('Antigravity rejected the sign-in. Open Antigravity to sign in again.');
      }
    }
  }

  Future<ProviderUsageRecord> _fetchUsage(String token) async {
    ProviderUsageRecord? modelFallback;
    bool authError = false;
    for (final String base in _endpoints) {
      final Map<String, String> headers = <String, String>{'Authorization': 'Bearer $token', 'User-Agent': _userAgent};

      final UsageHttpResult load = await usageJsonRequest('POST', '$base/v1internal:loadCodeAssist',
          headers: headers,
          jsonBody: <String, dynamic>{
            'metadata': <String, String>{'ideType': 'ANTIGRAVITY'},
          });
      if (load.isAuthError) {
        authError = true;
        continue;
      }
      if (!load.ok) continue;
      final dynamic project = load.body is Map ? (load.body as Map<dynamic, dynamic>)['cloudaicompanionProject'] : null;
      final String? projectId = project is String && project.isNotEmpty ? project : null;

      if (projectId != null) {
        final UsageHttpResult summary = await usageJsonRequest('POST', '$base/v1internal:retrieveUserQuotaSummary',
            headers: headers, jsonBody: <String, String>{'project': projectId});
        if (summary.isAuthError) {
          authError = true;
          continue;
        }
        if (summary.ok) {
          final ProviderUsageRecord? record = _fromSummary(summary.body);
          // A summary is authoritative; later endpoints are not consulted.
          if (record != null) return record;
        }
      }

      if (modelFallback != null) continue;
      final UsageHttpResult models = await usageJsonRequest('POST', '$base/v1internal:fetchAvailableModels',
          headers: headers, jsonBody: <String, String>{if (projectId != null) 'project': projectId});
      if (models.isAuthError) {
        authError = true;
        continue;
      }
      if (models.ok) modelFallback = _fromModels(models.body);
    }
    if (modelFallback != null) return modelFallback;
    if (authError) throw const _AuthRequired();
    throw const UsageFetchException('Could not refresh Antigravity usage.');
  }

  /// Groups named Gemini come first (the ring tracks the Gemini 5-hour pool),
  /// then Claude/GPT, then anything else such as "Gemini 4 Argon".
  ProviderUsageRecord? _fromSummary(dynamic body) {
    if (body is! Map || body['groups'] is! List) return null;
    final List<(int, List<ProviderUsageWindow>)> ranked = <(int, List<ProviderUsageWindow>)>[];
    for (final dynamic group in body['groups'] as List<dynamic>) {
      if (group is! Map) continue;
      final String name = (group['displayName'] ?? '').toString().trim();
      final String haystack = <dynamic>[
        name,
        group['description'],
        if (group['buckets'] is List)
          for (final dynamic b in group['buckets'] as List<dynamic>)
            if (b is Map) '${b['bucketId']} ${b['displayName']}',
      ].join(' ').toLowerCase();
      final int rank = haystack.contains('argon')
          ? 2
          : haystack.contains('gemini')
              ? 0
              : (haystack.contains('claude') || haystack.contains('gpt') || haystack.contains('external'))
                  ? 1
                  : 3;
      final List<ProviderUsageWindow> windows = <ProviderUsageWindow>[];
      for (final dynamic bucket in (group['buckets'] as List<dynamic>?) ?? const <dynamic>[]) {
        if (bucket is! Map) continue;
        final String window = (bucket['window'] ?? '').toString().toLowerCase();
        final double? remaining = parseUsageDouble(bucket['remainingFraction']);
        if (remaining == null || (window != '5h' && window != 'weekly')) continue;
        windows.add(ProviderUsageWindow(
          label: '${name.isEmpty ? 'Quota' : name} · ${window == '5h' ? '5-hour' : 'weekly'}',
          usedPercent: (1 - remaining.clamp(0, 1)) * 100,
          resetAt: parseUsageDate(bucket['resetTime']),
        ));
      }
      // 5-hour before weekly inside each group.
      windows.sort((ProviderUsageWindow a, ProviderUsageWindow b) =>
          (a.label.endsWith('weekly') ? 1 : 0).compareTo(b.label.endsWith('weekly') ? 1 : 0));
      if (windows.isNotEmpty) ranked.add((rank, windows));
    }
    if (ranked.isEmpty) return null;
    ranked.sort(((int, List<ProviderUsageWindow>) a, (int, List<ProviderUsageWindow>) b) => a.$1.compareTo(b.$1));
    return ProviderUsageRecord(
      windows: <ProviderUsageWindow>[for (final (int, List<ProviderUsageWindow>) group in ranked) ...group.$2],
      fetchedAt: DateTime.now(),
    );
  }

  /// Per-model quotas do not name their window; report the most-used Gemini model only.
  ProviderUsageRecord? _fromModels(dynamic body) {
    if (body is! Map || body['models'] is! Map) return null;
    ProviderUsageWindow? best;
    for (final MapEntry<dynamic, dynamic> entry in (body['models'] as Map<dynamic, dynamic>).entries) {
      if (!entry.key.toString().startsWith('gemini') || entry.value is! Map) continue;
      final dynamic quota = (entry.value as Map<dynamic, dynamic>)['quotaInfo'];
      if (quota is! Map) continue;
      final double? remaining = parseUsageDouble(quota['remainingFraction']);
      if (remaining == null) continue;
      final ProviderUsageWindow window = ProviderUsageWindow(
        label: 'Gemini quota',
        usedPercent: (1 - remaining.clamp(0, 1)) * 100,
        resetAt: parseUsageDate(quota['resetTime']),
      );
      if (best == null || window.usedPercent > best.usedPercent) best = window;
    }
    return best == null ? null : ProviderUsageRecord(windows: <ProviderUsageWindow>[best], fetchedAt: DateTime.now());
  }

  // ── OAuth refresh ────────────────────────────────────────────────────────

  Future<String> _refresh(String refreshToken) async {
    _oauthClients ??= await Isolate.run(_installedOauthClients);
    if (_oauthClients!.isEmpty) {
      throw const UsageFetchException('Antigravity token expired and its OAuth client was not found. Open Antigravity.');
    }
    for (final (String clientId, String clientSecret) in _oauthClients!) {
      final UsageHttpResult result = await usageJsonRequest('POST', _tokenUrl, formBody: <String, String>{
        'client_id': clientId,
        'client_secret': clientSecret,
        'refresh_token': refreshToken,
        'grant_type': 'refresh_token',
      });
      final dynamic body = result.body;
      if (result.ok && body is Map && (body['access_token'] ?? '').toString().isNotEmpty) {
        _refreshedToken = body['access_token'].toString();
        final int seconds = (body['expires_in'] as num?)?.toInt() ?? 3000;
        _refreshedExpiry = DateTime.now().add(Duration(seconds: seconds));
        return _refreshedToken!;
      }
      // A rejected pairing may simply not be the client that issued this token.
      final String error = body is Map ? (body['error'] ?? '').toString() : '';
      final bool rejected = result.isAuthError ||
          (result.status == 400 && <String>{'invalid_grant', 'invalid_client', 'unauthorized_client'}.contains(error));
      if (!rejected) throw UsageFetchException('Could not refresh the Antigravity token (HTTP ${result.status}).');
    }
    throw const _AuthRequired();
  }

  /// Extracts `<digits>-<hash>.apps.googleusercontent.com` client ids and
  /// `GOCSPX-` secrets from the installed Antigravity binaries.
  static List<(String, String)> _installedOauthClients() {
    final String? local = Platform.environment['LOCALAPPDATA'];
    final String? programFiles = Platform.environment['ProgramFiles'];
    final List<String> paths = <String>[
      if (local != null) '$local\\Programs\\Antigravity\\resources\\bin\\language_server.exe',
      if (local != null) '$local\\Programs\\Antigravity IDE\\resources\\bin\\language_server.exe',
      if (local != null) '$local\\agy\\bin\\agy.exe',
      if (programFiles != null) '$programFiles\\Antigravity\\resources\\bin\\language_server.exe',
    ];
    final RegExp idPattern = RegExp(r'\d{10,}-[A-Za-z0-9_-]{20,80}\.apps\.googleusercontent\.com');
    final RegExp secretPattern = RegExp(r'GOCSPX-[A-Za-z0-9_-]{28}');
    for (final String path in paths) {
      try {
        final File file = File(path);
        if (!file.existsSync()) continue;
        final String text = latin1.decode(file.readAsBytesSync());
        final List<String> ids = idPattern.allMatches(text).map((RegExpMatch m) => m.group(0)!).toSet().toList();
        final List<String> secrets = secretPattern.allMatches(text).map((RegExpMatch m) => m.group(0)!).toSet().toList();
        final List<(String, String)> clients = <(String, String)>[
          for (final String id in ids)
            for (final String secret in secrets) (id, secret),
        ];
        if (clients.isNotEmpty) return clients;
      } on Object {
        // Try the next install location.
      }
    }
    return const <(String, String)>[];
  }

  // ── Credential Manager ───────────────────────────────────────────────────

  _AntigravityToken? _readCredentials() {
    final String? content = _readGenericCredential(_credentialTarget);
    if (content == null) return null;
    try {
      final dynamic auth = jsonDecode(content);
      final dynamic token = auth is Map ? auth['token'] : null;
      if (token is! Map) return null;
      final String access = (token['access_token'] ?? '').toString();
      final String refresh = (token['refresh_token'] ?? '').toString();
      if (access.isEmpty && refresh.isEmpty) return null;
      return _AntigravityToken(
        accessToken: access,
        refreshToken: refresh.isEmpty ? null : refresh,
        expiry: parseUsageDate(token['expiry']),
      );
    } on Object {
      return null;
    }
  }

  static String? _readGenericCredential(String target) {
    final Pointer<Utf16> targetName = target.toNativeUtf16();
    final Pointer<Pointer<CREDENTIAL>> credential = calloc<Pointer<CREDENTIAL>>();
    try {
      if (CredRead(targetName, CRED_TYPE_GENERIC, 0, credential) == 0) return null;
      final CREDENTIAL value = credential.value.ref;
      try {
        if (value.CredentialBlobSize == 0 || value.CredentialBlob == nullptr) return null;
        final List<int> bytes = List<int>.of(value.CredentialBlob.asTypedList(value.CredentialBlobSize));
        // Some Node keyrings store UTF-16LE; ASCII in UTF-16 has a zero in every high byte.
        bool utf16 = bytes.length >= 2 && bytes.length.isEven;
        for (int i = 1; utf16 && i < bytes.length; i += 2) {
          if (bytes[i] != 0) utf16 = false;
        }
        if (utf16) {
          return String.fromCharCodes(<int>[for (int i = 0; i < bytes.length; i += 2) bytes[i] | (bytes[i + 1] << 8)]);
        }
        return utf8.decode(bytes, allowMalformed: true);
      } finally {
        CredFree(credential.value);
      }
    } on Object {
      return null;
    } finally {
      free(targetName);
      free(credential);
    }
  }
}

class _AntigravityToken {
  const _AntigravityToken({required this.accessToken, this.refreshToken, this.expiry});

  final String accessToken;
  final String? refreshToken;
  final DateTime? expiry;
}

class _AuthRequired implements Exception {
  const _AuthRequired();
}
