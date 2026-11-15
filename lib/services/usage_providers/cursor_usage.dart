import 'dart:convert';
import 'dart:io';

import 'package:sqlite3/sqlite3.dart';

import '../provider_usage_service.dart';

/// Cursor plan usage, ported from Claude-Code-Usage-Monitor.
///
/// The login comes from `CURSOR_SESSION_TOKEN` or the access token Cursor
/// stores in `%APPDATA%\Cursor\User\globalStorage\state.vscdb`. The internal
/// current-period service is preferred (it matches what Cursor shows); the
/// dashboard usage summary is the fallback.
class CursorUsageFetcher extends ProviderUsageFetcher {
  static const String _currentPeriodUrl = 'https://api2.cursor.sh/aiserver.v1.DashboardService/GetCurrentPeriodUsage';
  static const String _summaryUrl = 'https://cursor.com/api/usage-summary';
  static const String _accessTokenKey = 'cursorAuth/accessToken';

  @override
  Future<ProviderUsageRecord> fetch() async {
    final _CursorAuth? auth = _readAuth();
    if (auth == null) {
      throw const UsageFetchException('Sign in to Cursor (or set CURSOR_SESSION_TOKEN) to make usage available.');
    }

    final UsageHttpResult current = await usageJsonRequest(
      'POST',
      _currentPeriodUrl,
      headers: <String, String>{'Authorization': 'Bearer ${auth.accessToken}', 'User-Agent': 'Mozilla/5.0'},
      jsonBody: <String, dynamic>{},
    );
    if (current.ok) {
      final ProviderUsageRecord? record = _fromCurrentPeriod(current.body);
      if (record != null) return record;
    }

    final UsageHttpResult summary = await usageJsonRequest(
      'GET',
      _summaryUrl,
      headers: <String, String>{'Cookie': 'WorkosCursorSessionToken=${auth.cookie}', 'User-Agent': 'Mozilla/5.0'},
    );
    if (summary.ok) {
      final ProviderUsageRecord? record = _fromSummary(summary.body);
      if (record != null) return record;
      throw const UsageFetchException('Cursor returned no plan usage.');
    }
    if (summary.isAuthError) throw const UsageFetchException('Cursor sign-in expired. Open Cursor to sign in again.');
    throw UsageFetchException(summary.status == null
        ? 'Could not reach Cursor.'
        : 'Cursor usage is temporarily unavailable (HTTP ${summary.status}).');
  }

  ProviderUsageRecord? _fromCurrentPeriod(dynamic value) {
    if (value is! Map || value['enabled'] == false) return null;
    final dynamic individual = value['individualUsage'];
    final dynamic plan = value['planUsage'] ?? value['plan'] ?? (individual is Map ? individual['plan'] : null);
    final DateTime? start = parseUsageDate(value['billingCycleStart']);
    final DateTime? end = parseUsageDate(value['billingCycleEnd']);
    return _fromPlan(plan, end, _periodLabel(start, end));
  }

  ProviderUsageRecord? _fromSummary(dynamic value) {
    if (value is! Map) return null;
    final dynamic individual = value['individualUsage'];
    if (individual is! Map) return null;
    return _fromPlan(individual['plan'], parseUsageDate(value['billingCycleEnd']), null);
  }

  ProviderUsageRecord? _fromPlan(dynamic plan, DateTime? reset, String? period) {
    if (plan is! Map) return null;
    double? read(String camel, String snake) => parseUsageDouble(plan[camel] ?? plan[snake]);
    final double? auto = read('autoPercentUsed', 'auto_percent_used');
    final double? api = read('apiPercentUsed', 'api_percent_used');
    final double? total = read('totalPercentUsed', 'total_percent_used');
    final double? included = auto ?? total;
    if (included == null && api == null) return null;
    return ProviderUsageRecord(
      fetchedAt: DateTime.now(),
      windows: <ProviderUsageWindow>[
        if (included != null)
          ProviderUsageWindow(
            label: period == null ? 'Auto usage' : 'Auto usage ($period)',
            usedPercent: included.clamp(0, 100).toDouble(),
            resetAt: reset,
          ),
        if (api != null)
          ProviderUsageWindow(label: 'API usage', usedPercent: api.clamp(0, 100).toDouble(), resetAt: reset),
      ],
    );
  }

  static String? _periodLabel(DateTime? start, DateTime? end) {
    if (start == null || end == null) return null;
    final Duration length = end.difference(start);
    if (length.inDays >= 1) return '${length.inDays}d';
    if (length.inHours >= 1) return '${length.inHours}h';
    return null;
  }

  // ── Auth ─────────────────────────────────────────────────────────────────

  _CursorAuth? _readAuth() {
    final String? env = nonEmptyEnvironment('CURSOR_SESSION_TOKEN');
    if (env != null) return _authFromEnvironment(env);

    final String? token = _readAccessTokenFromStateDb();
    if (token == null) return null;
    final String? cookie = _cookieFromAccessToken(token);
    return cookie == null ? null : _CursorAuth(token, cookie);
  }

  /// Accepts a raw access token, a `WorkosCursorSessionToken` cookie value or
  /// the combined `user_id%3A%3Aaccess_token` form.
  _CursorAuth? _authFromEnvironment(String raw) {
    if (raw.contains('\n') || raw.contains('\r')) return null;
    String token = raw.trim();
    if (token.startsWith('WorkosCursorSessionToken=')) token = token.substring('WorkosCursorSessionToken='.length);
    token = token.trim();
    if (token.isEmpty) return null;

    final String cookie;
    if (token.contains('%3A%3A')) {
      cookie = token;
    } else if (token.contains('::')) {
      cookie = token.replaceAll('::', '%3A%3A');
    } else {
      cookie = _cookieFromAccessToken(token) ?? token;
    }
    final int separator = cookie.indexOf('%3A%3A');
    final String access = separator >= 0 ? cookie.substring(separator + 6) : cookie;
    return _CursorAuth(access.isEmpty ? cookie : access, cookie);
  }

  static String? _cookieFromAccessToken(String jwt) {
    try {
      final List<String> parts = jwt.split('.');
      if (parts.length < 2) return null;
      final dynamic payload = jsonDecode(utf8.decode(base64Url.decode(base64Url.normalize(parts[1]))));
      final dynamic subject = payload is Map ? payload['sub'] : null;
      if (subject is! String || subject.isEmpty) return null;
      final String userId = subject.contains('|') ? subject.substring(subject.lastIndexOf('|') + 1) : subject;
      return '$userId%3A%3A$jwt';
    } on Object {
      return null;
    }
  }

  static String? _stateDbPath() {
    final String? appData = Platform.environment['APPDATA'];
    if (appData == null) return null;
    final String path = '$appData\\Cursor\\User\\globalStorage\\state.vscdb';
    return File(path).existsSync() ? path : null;
  }

  static String? _readAccessTokenFromStateDb() {
    final String? path = _stateDbPath();
    if (path == null) return null;
    try {
      return _queryToken(path);
    } on Object {
      // Cursor may hold a lock; read a temporary copy instead.
      final File copy = File('${Directory.systemTemp.path}\\tabame-cursor-state-${DateTime.now().microsecondsSinceEpoch}.vscdb');
      try {
        File(path).copySync(copy.path);
        return _queryToken(copy.path);
      } on Object {
        return null;
      } finally {
        try {
          if (copy.existsSync()) copy.deleteSync();
        } on Object {
          // Best effort cleanup.
        }
      }
    }
  }

  static String? _queryToken(String path) {
    final Database db = sqlite3.open(path, mode: OpenMode.readOnly);
    try {
      final ResultSet rows = db.select('SELECT value FROM ItemTable WHERE key = ?', <Object?>[_accessTokenKey]);
      if (rows.isEmpty) return null;
      final Object? value = rows.first.columnAt(0);
      final String token = (value is List<int> ? utf8.decode(value) : value?.toString() ?? '').trim();
      return token.isEmpty ? null : token;
    } finally {
      db.close();
    }
  }
}

class _CursorAuth {
  const _CursorAuth(this.accessToken, this.cookie);

  final String accessToken;
  final String cookie;
}
