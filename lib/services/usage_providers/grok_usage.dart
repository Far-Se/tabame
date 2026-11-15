import 'dart:convert';
import 'dart:io';

import '../provider_usage_service.dart';

/// Grok Build credit pool, ported from Claude-Code-Usage-Monitor.
///
/// Uses the session the Grok CLI stores in `~/.grok/auth.json` (or
/// `$GROK_HOME`) and asks the same billing endpoint the CLI's `/usage` panel
/// reads. An expired token is refreshed by `grok models`, which needs a valid
/// token but spends no allowance.
class GrokUsageFetcher extends ProviderUsageFetcher {
  static const String _billingUrl = 'https://cli-chat-proxy.grok.com/v1/billing?format=credits';
  static const String _defaultClientVersion = '1.0.0';

  String? _cliPath;
  String? _clientVersion;
  DateTime? _lastCliRefresh;

  @override
  Future<ProviderUsageRecord> fetch() async {
    final File? authFile = _authFile;
    final _GrokSession? session = authFile == null ? null : _readSession(authFile);
    if (authFile == null || session == null) {
      throw const UsageFetchException("Run 'grok login' to make Grok usage available.");
    }

    UsageHttpResult result = await _fetchBilling(session);
    if (result.isAuthError) {
      // Without a refresh token the CLI would open a browser sign-in; never do that from the background.
      if (!session.canRefresh) throw const UsageFetchException("Grok session expired. Run 'grok login' again.");
      await _refreshViaCli();
      final _GrokSession? refreshed = _readSession(authFile);
      if (refreshed == null || refreshed.accessToken == session.accessToken) {
        throw const UsageFetchException("Grok session expired. Run 'grok login' again.");
      }
      result = await _fetchBilling(refreshed);
    }

    if (!result.ok) {
      if (result.isAuthError) throw const UsageFetchException("Grok rejected the sign-in. Run 'grok login' again.");
      throw UsageFetchException(result.status == null
          ? 'Could not reach Grok.'
          : 'Grok usage is temporarily unavailable (HTTP ${result.status}).');
    }
    final ProviderUsageRecord? record = _fromBilling(result.body);
    if (record == null) throw const UsageFetchException('Grok returned no credit usage.');
    return record;
  }

  Future<UsageHttpResult> _fetchBilling(_GrokSession session) async {
    return usageJsonRequest('GET', _billingUrl, headers: <String, String>{
      'Authorization': 'Bearer ${session.accessToken}',
      'X-XAI-Token-Auth': 'xai-grok-cli',
      'x-grok-client-mode': 'cli',
      'x-grok-client-version': await _version(),
      if (session.userId.isNotEmpty) 'x-userid': session.userId,
    });
  }

  ProviderUsageRecord? _fromBilling(dynamic body) {
    if (body is! Map || body['config'] is! Map) return null;
    final Map<dynamic, dynamic> config = body['config'] as Map<dynamic, dynamic>;
    final dynamic period = config['currentPeriod'];
    final DateTime? reset = period is Map ? parseUsageDate(period['end']) : null;
    // Protobuf JSON omits zeros: a fresh period arrives without creditUsagePercent.
    final double? used = parseUsageDouble(config['creditUsagePercent']) ?? (reset != null ? 0 : null);
    if (used == null) return null;

    final String periodType =
        period is Map ? (period['type'] ?? period['periodType'] ?? '').toString().toLowerCase() : '';
    final String poolLabel = periodType.contains('monthly') ? 'Monthly credits' : 'Weekly credits';

    final List<ProviderUsageWindow> windows = <ProviderUsageWindow>[
      ProviderUsageWindow(label: poolLabel, usedPercent: used.clamp(0, 100).toDouble(), resetAt: reset),
    ];
    // Per-product split of the one shared pool.
    final dynamic products = config['productUsage'];
    if (products is List) {
      for (final dynamic product in products) {
        if (product is! Map) continue;
        final String name = (product['product'] ?? '').toString().trim();
        final double? percent = parseUsageDouble(product['usagePercent']);
        if (name.isEmpty || percent == null) continue;
        windows.add(ProviderUsageWindow(label: _prettyProduct(name), usedPercent: percent.clamp(0, 100).toDouble()));
      }
    }

    final dynamic tier = body['subscriptionTier'];
    return ProviderUsageRecord(windows: windows, fetchedAt: DateTime.now(), plan: tier is String ? tier : null);
  }

  static String _prettyProduct(String name) {
    final String cleaned = name
        .replaceFirst(RegExp('^PRODUCT_', caseSensitive: false), '')
        .replaceAll('_', ' ')
        // Split camelCase ("GrokChat" -> "Grok Chat").
        .replaceAllMapped(RegExp(r'([a-z])([A-Z])'), (Match m) => '${m[1]} ${m[2]}');
    final bool shouting = cleaned == cleaned.toUpperCase();
    return cleaned
        .split(' ')
        .where((String w) => w.isNotEmpty)
        .map((String w) => '${w[0].toUpperCase()}${shouting ? w.substring(1).toLowerCase() : w.substring(1)}')
        .join(' ');
  }

  // ── Auth / CLI ───────────────────────────────────────────────────────────

  File? get _authFile {
    final String? grokHome = nonEmptyEnvironment('GROK_HOME');
    if (grokHome != null) return File('$grokHome\\auth.json');
    final String home = usageHomeDirectory;
    return home.isEmpty ? null : File('$home\\.grok\\auth.json');
  }

  /// `auth.json` may also hold corporate OIDC tokens and API keys; only xAI
  /// sign-in scopes belong at the billing endpoint. Prefer the latest-expiring.
  _GrokSession? _readSession(File file) {
    try {
      if (!file.existsSync()) return null;
      final dynamic entries = jsonDecode(file.readAsStringSync());
      if (entries is! Map) return null;
      _GrokSession? best;
      DateTime bestExpiry = DateTime.fromMillisecondsSinceEpoch(0);
      for (final MapEntry<dynamic, dynamic> entry in entries.entries) {
        final String scope = entry.key.toString();
        final bool xai = scope == 'https://accounts.x.ai/sign-in' ||
            (scope.startsWith('https://auth.x.ai::') && scope.length > 'https://auth.x.ai::'.length);
        if (!xai || entry.value is! Map) continue;
        final Map<dynamic, dynamic> value = entry.value as Map<dynamic, dynamic>;
        final String key = (value['key'] ?? '').toString().trim();
        if (key.isEmpty) continue;
        final DateTime expiry = parseUsageDate(value['expires_at']) ?? DateTime.fromMillisecondsSinceEpoch(0);
        if (best != null && !expiry.isAfter(bestExpiry)) continue;
        bestExpiry = expiry;
        best = _GrokSession(
          accessToken: key,
          userId: (value['user_id'] ?? '').toString().trim(),
          canRefresh: (value['refresh_token'] ?? '').toString().trim().isNotEmpty,
        );
      }
      return best;
    } on Object {
      return null;
    }
  }

  Future<String?> _grokPath() async {
    if (_cliPath != null) return _cliPath;
    final String home = usageHomeDirectory;
    _cliPath = await resolveCliExecutable(
      <String>['grok.exe', 'grok.cmd', 'grok.ps1', 'grok'],
      extraPaths: <String>[if (home.isNotEmpty) '$home\\.grok\\bin\\grok.exe'],
    );
    return _cliPath;
  }

  Future<String> _version() async {
    if (_clientVersion != null) return _clientVersion!;
    final String? fromEnv = nonEmptyEnvironment('GROK_CLIENT_VERSION');
    if (fromEnv != null) return _clientVersion = fromEnv;
    final String? path = await _grokPath();
    if (path != null) {
      final String? output = await runCliQuietly(path, <String>['version'], timeout: const Duration(seconds: 5));
      final RegExpMatch? match = output == null ? null : RegExp(r'\d+\.\d+\.\d+').firstMatch(output);
      if (match != null) return _clientVersion = match.group(0)!;
    }
    return _defaultClientVersion;
  }

  Future<void> _refreshViaCli() async {
    final DateTime now = DateTime.now();
    if (_lastCliRefresh != null && now.difference(_lastCliRefresh!) < const Duration(minutes: 10)) return;
    _lastCliRefresh = now;
    final String? path = await _grokPath();
    if (path != null) await runCliQuietly(path, <String>['models']);
  }
}

class _GrokSession {
  const _GrokSession({required this.accessToken, required this.userId, required this.canRefresh});

  final String accessToken;
  final String userId;
  final bool canRefresh;
}
