import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';

class ClaudeUsageRecord {
  final double fiveHour;
  final double sevenDay;
  final String? fiveResetAt;
  final String? sevenResetAt;
  final DateTime fetchedAt;

  const ClaudeUsageRecord({
    required this.fiveHour,
    required this.sevenDay,
    this.fiveResetAt,
    this.sevenResetAt,
    required this.fetchedAt,
  });

  factory ClaudeUsageRecord.fromCache(Map<String, dynamic> json) {
    return ClaudeUsageRecord(
      fiveHour: (json['five_hour'] as num).toDouble(),
      sevenDay: (json['seven_day'] as num).toDouble(),
      fiveResetAt: json['five_reset_at'] as String?,
      sevenResetAt: json['seven_reset_at'] as String?,
      fetchedAt: DateTime.parse(json['fetched_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'five_hour': fiveHour,
        'seven_day': sevenDay,
        'five_reset_at': fiveResetAt,
        'seven_reset_at': sevenResetAt,
        'fetched_at': fetchedAt.toIso8601String(),
      };
}

/// Polls Claude's OAuth usage endpoint. Fetches from the API at most every
/// [_apiCacheTtl]; the UI refresh timer runs every [_uiPollInterval].
/// Automatically starts/stops based on listener count.
///
/// Works without Claude Code running (same approach as Claude-Code-Usage-Monitor):
/// Claude Code only refreshes its OAuth token while it runs, so an expired
/// token is refreshed by running the CLI headlessly once
/// (`claude -p . --no-session-persistence`) and re-reading `.credentials.json`.
/// When the usage endpoint is unavailable for an account, the rate-limit
/// headers of a 1-token Messages API probe are used instead.
class ClaudeUsageService {
  ClaudeUsageService._();
  static final ClaudeUsageService instance = ClaudeUsageService._();

  static const Duration _apiCacheTtl = Duration(minutes: 4);
  static const Duration _uiPollInterval = Duration(minutes: 4);
  static const Duration _cliRefreshCooldown = Duration(minutes: 10);
  static const String _usageUrl = 'https://api.anthropic.com/api/oauth/usage';
  static const String _messagesUrl = 'https://api.anthropic.com/v1/messages';
  static const String _oauthBeta = 'oauth-2025-04-20';
  // Header probes stay on the cheapest tier.
  static const String _probeModel = 'claude-haiku-4-5';

  ClaudeUsageRecord? _record;
  Timer? _timer;
  bool _fetching = false;
  DateTime? _lastAttempt;
  DateTime? _lastCliRefresh;
  String? _lastError;
  String? _failure;
  final List<void Function(ClaudeUsageRecord?)> _listeners = <void Function(ClaudeUsageRecord?)>[];

  ClaudeUsageRecord? get latest => _record;
  String? get lastError => _lastError;

  void addListener(void Function(ClaudeUsageRecord?) listener) {
    _listeners.add(listener);
    if (_listeners.length == 1) _start();
  }

  void removeListener(void Function(ClaudeUsageRecord?) listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) _stop();
  }

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_uiPollInterval, (_) => _tick(force: true));
    _tick();
  }

  Future<void> refresh() => _tick(force: true);

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _notify() {
    for (final void Function(ClaudeUsageRecord?) fn in List<void Function(ClaudeUsageRecord?)>.from(_listeners)) {
      fn(_record);
    }
  }

  Future<void> _tick({bool force = false}) async {
    if (_fetching) return;
    final DateTime now = DateTime.now();
    if (_lastAttempt != null && now.difference(_lastAttempt!) < const Duration(minutes: 1)) {
      _notify();
      return;
    }

    // If in-memory cache is fresh, just notify UI without hitting the API.
    if (!force && _record != null && DateTime.now().difference(_record!.fetchedAt) < _apiCacheTtl) {
      _notify();
      return;
    }

    _fetching = true;
    try {
      // Warm up from disk cache on first run.
      if (_record == null) {
        final ClaudeUsageRecord? disk = await _readDiskCache();
        if (disk != null) {
          _record = disk;
          _notify();
          if (!force && DateTime.now().difference(disk.fetchedAt) < _apiCacheTtl) {
            return;
          }
        }
      }

      _lastAttempt = DateTime.now();
      _failure = null;
      final ClaudeUsageRecord? fresh = await _fetchFromApi();
      _lastError = fresh == null ? (_failure ?? 'Could not refresh Claude usage.') : null;
      if (fresh != null) {
        _record = fresh;
        await _writeDiskCache(fresh);
      }
      _notify();
    } finally {
      _fetching = false;
    }
  }

  Future<ClaudeUsageRecord?> _fetchFromApi() async {
    _ClaudeCredentials? creds = _readCredentials();
    if (creds == null) {
      _failure = 'Sign in to Claude Code to make usage available.';
      return null;
    }

    if (creds.isExpired) {
      await _refreshTokenViaCli(creds.configDir);
      creds = _readCredentials();
      if (creds == null || creds.isExpired) {
        _failure = 'Claude token expired and could not be refreshed. Run `claude` once to sign in again.';
        return null;
      }
    }

    _UsageResult result = await _fetchUsage(creds.accessToken);
    if (result.isAuthError) {
      // The token can be revoked before its recorded expiry.
      await _refreshTokenViaCli(creds.configDir);
      final _ClaudeCredentials? retry = _readCredentials();
      if (retry != null && retry.accessToken != creds.accessToken) {
        creds = retry;
        result = await _fetchUsage(retry.accessToken);
      }
    }

    final ClaudeUsageRecord? record = result.record;
    if (record != null) {
      if (record.fiveResetAt != null && record.sevenResetAt != null) return record;
      // Fill missing reset timers from the rate-limit headers.
      final ClaudeUsageRecord? probe = await _fetchViaMessages(creds.accessToken);
      if (probe == null) return record;
      return ClaudeUsageRecord(
        fiveHour: record.fiveHour,
        sevenDay: record.sevenDay,
        fiveResetAt: record.fiveResetAt ?? probe.fiveResetAt,
        sevenResetAt: record.sevenResetAt ?? probe.sevenResetAt,
        fetchedAt: record.fetchedAt,
      );
    }

    if (result.isAuthError) {
      _failure = 'Claude rejected the sign-in. Run `claude` once to sign in again.';
      return null;
    }
    final int? status = result.status;
    // Rate limits, server faults and network errors are transient; keep the cached value.
    if (status == null || status == 429 || status >= 500) {
      _failure = status == null
          ? 'Could not reach the Claude usage endpoint.'
          : 'Claude usage is temporarily unavailable (HTTP $status).';
      return null;
    }

    // Usage endpoint unsupported for this account: fall back to the Messages API headers.
    final ClaudeUsageRecord? probe = await _fetchViaMessages(creds.accessToken);
    if (probe == null) _failure = 'Could not refresh Claude usage (HTTP $status).';
    return probe;
  }

  Future<_UsageResult> _fetchUsage(String token) async {
    try {
      final http.Response response = await http.get(
        Uri.parse(_usageUrl),
        headers: <String, String>{
          'Authorization': 'Bearer $token',
          'anthropic-beta': _oauthBeta,
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) return _UsageResult(status: response.statusCode);

      final Map<String, dynamic> json = jsonDecode(response.body) as Map<String, dynamic>;
      final Map<String, dynamic>? five = json['five_hour'] as Map<String, dynamic>?;
      final Map<String, dynamic>? seven = json['seven_day'] as Map<String, dynamic>?;
      // A body without either window is treated like an unsupported endpoint.
      if (five == null && seven == null) return const _UsageResult(status: 404);
      return _UsageResult(
        status: 200,
        record: ClaudeUsageRecord(
          fiveHour: (five?['utilization'] as num?)?.toDouble() ?? 0,
          sevenDay: (seven?['utilization'] as num?)?.toDouble() ?? 0,
          fiveResetAt: five?['resets_at'] as String?,
          sevenResetAt: seven?['resets_at'] as String?,
          fetchedAt: DateTime.now(),
        ),
      );
    } catch (_) {
      return const _UsageResult();
    }
  }

  Future<ClaudeUsageRecord?> _fetchViaMessages(String token) async {
    try {
      // A 429 still carries the usage and reset headers this probe needs.
      final http.Response response = await http
          .post(
            Uri.parse(_messagesUrl),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'anthropic-version': '2023-06-01',
              'anthropic-beta': _oauthBeta,
              'content-type': 'application/json',
            },
            body: jsonEncode(<String, dynamic>{
              'model': _probeModel,
              'max_tokens': 1,
              'messages': <Map<String, String>>[
                <String, String>{'role': 'user', 'content': '.'},
              ],
            }),
          )
          .timeout(const Duration(seconds: 15));

      final Map<String, String> headers = response.headers;
      final double? five = double.tryParse(headers['anthropic-ratelimit-unified-5h-utilization'] ?? '');
      final double? seven = double.tryParse(headers['anthropic-ratelimit-unified-7d-utilization'] ?? '');
      if (five == null && seven == null) return null;

      String? reset(String name) {
        final int? seconds = int.tryParse(headers[name] ?? '');
        if (seconds == null) return null;
        return DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true).toIso8601String();
      }

      return ClaudeUsageRecord(
        fiveHour: (five ?? 0) * 100,
        sevenDay: (seven ?? 0) * 100,
        fiveResetAt: reset('anthropic-ratelimit-unified-5h-reset'),
        sevenResetAt: reset('anthropic-ratelimit-unified-7d-reset'),
        fetchedAt: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  static String get _home => Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';

  _ClaudeCredentials? _readCredentials() {
    try {
      final String? envDir = Platform.environment['CLAUDE_CONFIG_DIR'];
      final String configDir = envDir != null && envDir.isNotEmpty ? envDir : '$_home\\.claude';
      final File credFile = File('$configDir\\.credentials.json');
      if (!credFile.existsSync()) return null;
      final Map<String, dynamic> creds = jsonDecode(credFile.readAsStringSync()) as Map<String, dynamic>;
      final Map<String, dynamic>? oauth = creds['claudeAiOauth'] as Map<String, dynamic>?;
      final String token = (oauth?['accessToken'] as String? ?? '').trim();
      if (token.isEmpty) return null;
      return _ClaudeCredentials(
        accessToken: token,
        expiresAt: (oauth?['expiresAt'] as num?)?.toInt(),
        configDir: configDir,
      );
    } catch (_) {
      return null;
    }
  }

  /// Runs a minimal headless Claude Code prompt so the CLI refreshes and
  /// persists its OAuth token. Session persistence is disabled so it leaves no
  /// conversation behind.
  Future<void> _refreshTokenViaCli(String configDir) async {
    final DateTime now = DateTime.now();
    if (_lastCliRefresh != null && now.difference(_lastCliRefresh!) < _cliRefreshCooldown) return;
    _lastCliRefresh = now;

    final String? claude = await _resolveClaudeExecutable();
    if (claude == null) return;

    final bool isCmd = claude.toLowerCase().endsWith('.cmd');
    final Map<String, String> environment = Map<String, String>.from(Platform.environment)
      ..remove('CLAUDECODE')
      ..remove('CLAUDE_CODE_ENTRYPOINT')
      ..['CLAUDE_CONFIG_DIR'] = configDir;
    try {
      final Process process = await Process.start(
        isCmd ? 'cmd.exe' : claude,
        <String>[
          if (isCmd) ...<String>['/d', '/c', claude],
          '-p',
          '.',
          '--no-session-persistence',
        ],
        environment: environment,
        includeParentEnvironment: false,
        workingDirectory: Directory.systemTemp.path,
      );
      unawaited(process.stdout.drain<void>());
      unawaited(process.stderr.drain<void>());
      unawaited(process.stdin.close());
      await process.exitCode.timeout(const Duration(seconds: 30), onTimeout: () {
        process.kill();
        return -1;
      });
    } catch (_) {}
  }

  Future<String?> _resolveClaudeExecutable() async {
    for (final String name in <String>['claude.exe', 'claude.cmd']) {
      try {
        final ProcessResult result = await Process.run('where.exe', <String>[name]);
        if (result.exitCode != 0) continue;
        final String path = result.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
        if (path.isNotEmpty) return path;
      } catch (_) {}
    }

    final File native = File('$_home\\.local\\bin\\claude.exe');
    if (native.existsSync()) return native.path;

    // The Claude desktop app bundles `claude-code\<version>\claude.exe`.
    final String? appData = Platform.environment['APPDATA'];
    final String? localAppData = Platform.environment['LOCALAPPDATA'];
    final List<String> roots = <String>[
      if (localAppData != null) ..._childDirectories('$localAppData\\Claude-Data', prefix: 'claude_'),
      if (appData != null) '$appData\\Claude',
    ];

    String? best;
    List<int> bestVersion = <int>[];
    for (final String root in roots) {
      for (final String versionDir in _childDirectories('$root\\claude-code')) {
        final File exe = File('$versionDir\\claude.exe');
        if (!exe.existsSync()) continue;
        final List<int>? version = _parseVersion(_baseName(versionDir));
        if (version == null) continue;
        if (best == null || _compareVersions(version, bestVersion) > 0) {
          best = exe.path;
          bestVersion = version;
        }
      }
    }
    return best;
  }

  static List<String> _childDirectories(String path, {String prefix = ''}) {
    try {
      final Directory dir = Directory(path);
      if (!dir.existsSync()) return const <String>[];
      return dir
          .listSync()
          .whereType<Directory>()
          .map((Directory d) => d.path)
          .where((String p) => _baseName(p).startsWith(prefix))
          .toList();
    } catch (_) {
      return const <String>[];
    }
  }

  static String _baseName(String path) => path.split(RegExp(r'[\\/]')).lastWhere((String s) => s.isNotEmpty);

  static List<int>? _parseVersion(String text) {
    final List<int> parts = <int>[];
    for (final String part in text.split('.')) {
      final int? value = int.tryParse(part);
      if (value == null) return null;
      parts.add(value);
    }
    return parts;
  }

  static int _compareVersions(List<int> a, List<int> b) {
    for (int i = 0; i < a.length && i < b.length; i++) {
      if (a[i] != b[i]) return a[i].compareTo(b[i]);
    }
    return a.length.compareTo(b.length);
  }

  Future<ClaudeUsageRecord?> _readDiskCache() async {
    try {
      final File file = await _cacheFile();
      if (!file.existsSync()) return null;
      return ClaudeUsageRecord.fromCache(jsonDecode(file.readAsStringSync()) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Future<void> _writeDiskCache(ClaudeUsageRecord record) async {
    try {
      final File file = await _cacheFile();
      file.writeAsStringSync(jsonEncode(record.toJson()));
    } catch (_) {}
  }

  Future<File> _cacheFile() async {
    final Directory dir = await getApplicationSupportDirectory();
    return File('${dir.path}/claude_usage_cache.json');
  }
}

class _ClaudeCredentials {
  const _ClaudeCredentials({required this.accessToken, required this.expiresAt, required this.configDir});

  final String accessToken;
  final int? expiresAt;
  final String configDir;

  bool get isExpired => expiresAt != null && DateTime.now().millisecondsSinceEpoch >= expiresAt!;
}

class _UsageResult {
  const _UsageResult({this.status, this.record});

  final int? status;
  final ClaudeUsageRecord? record;

  bool get isAuthError => status == 401 || status == 403;
}
