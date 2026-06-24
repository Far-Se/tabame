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

  factory ClaudeUsageRecord.fromApi(Map<String, dynamic> json) {
    return ClaudeUsageRecord(
      fiveHour: (json['five_hour']['utilization'] as num).toDouble(),
      sevenDay: (json['seven_day']['utilization'] as num).toDouble(),
      fiveResetAt: json['five_hour']['resets_at'] as String?,
      sevenResetAt: json['seven_day']['resets_at'] as String?,
      fetchedAt: DateTime.now(),
    );
  }

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
class ClaudeUsageService {
  ClaudeUsageService._();
  static final ClaudeUsageService instance = ClaudeUsageService._();

  static const Duration _apiCacheTtl = Duration(minutes: 5);
  static const Duration _uiPollInterval = Duration(minutes: 1);
  static const String _usageUrl = 'https://api.anthropic.com/api/oauth/usage';
  static const String _oauthBeta = 'oauth-2025-04-20';

  ClaudeUsageRecord? _record;
  Timer? _timer;
  bool _fetching = false;
  final List<void Function(ClaudeUsageRecord?)> _listeners = <void Function(ClaudeUsageRecord?)>[];

  ClaudeUsageRecord? get latest => _record;

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
    _timer = Timer.periodic(_uiPollInterval, (_) => _tick());
    _tick();
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _notify() {
    for (final void Function(ClaudeUsageRecord?) fn in List<void Function(ClaudeUsageRecord?)>.from(_listeners)) {
      fn(_record);
    }
  }

  Future<void> _tick() async {
    if (_fetching) return;

    // If in-memory cache is fresh, just notify UI without hitting the API.
    if (_record != null && DateTime.now().difference(_record!.fetchedAt) < _apiCacheTtl) {
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
          if (DateTime.now().difference(disk.fetchedAt) < _apiCacheTtl) {
            return;
          }
        }
      }

      final ClaudeUsageRecord? fresh = await _fetchFromApi();
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
    try {
      final String home = Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
      final String configDir = Platform.environment['CLAUDE_CONFIG_DIR'] ?? '$home/.claude';
      final File credFile = File('$configDir/.credentials.json');
      if (!credFile.existsSync()) return null;

      final Map<String, dynamic> creds = jsonDecode(credFile.readAsStringSync()) as Map<String, dynamic>;
      final String token = (creds['claudeAiOauth'] as Map<String, dynamic>)['accessToken'] as String;

      final http.Response response = await http
          .get(
            Uri.parse(_usageUrl),
            headers: <String, String>{
              'Authorization': 'Bearer $token',
              'anthropic-beta': _oauthBeta,
            },
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        return ClaudeUsageRecord.fromApi(jsonDecode(response.body) as Map<String, dynamic>);
      }
    } catch (_) {}
    return null;
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
