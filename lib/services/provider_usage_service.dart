import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'usage_providers/antigravity_usage.dart';
import 'usage_providers/cursor_usage.dart';
import 'usage_providers/grok_usage.dart';
import 'usage_providers/opencode_usage.dart';

/// One quota window of a provider, e.g. "5-hour limit" or "Weekly limit".
class ProviderUsageWindow {
  const ProviderUsageWindow({required this.label, required this.usedPercent, this.resetAt});

  final String label;
  final double usedPercent;
  final DateTime? resetAt;

  double get remainingPercent => (100 - usedPercent).clamp(0, 100).toDouble();
}

class ProviderUsageRecord {
  const ProviderUsageRecord({required this.windows, required this.fetchedAt, this.plan});

  /// The first window drives the QuickMenu ring and the reset alert.
  final List<ProviderUsageWindow> windows;
  final DateTime fetchedAt;
  final String? plan;

  ProviderUsageWindow? get primary => windows.isEmpty ? null : windows.first;
}

/// Raised by a fetcher with a user-facing reason.
class UsageFetchException implements Exception {
  const UsageFetchException(this.message);

  final String message;

  @override
  String toString() => message;
}

abstract class ProviderUsageFetcher {
  Future<ProviderUsageRecord> fetch();
}

/// Generic poller for the providers ported from Claude-Code-Usage-Monitor
/// (Antigravity, Cursor, Grok, OpenCode Go). Same contract as the Claude and
/// Codex services: polling starts with the first listener and stops with the last.
class ProviderUsageService {
  ProviderUsageService._(this.id, this.name, this._fetcher);

  static final ProviderUsageService antigravity =
      ProviderUsageService._('antigravity', 'Antigravity', AntigravityUsageFetcher());
  static final ProviderUsageService cursor = ProviderUsageService._('cursor', 'Cursor', CursorUsageFetcher());
  static final ProviderUsageService grok = ProviderUsageService._('grok', 'Grok', GrokUsageFetcher());
  static final ProviderUsageService opencode =
      ProviderUsageService._('opencode', 'OpenCode Go', OpenCodeUsageFetcher());

  static final Map<String, ProviderUsageService> all = <String, ProviderUsageService>{
    for (final ProviderUsageService service in <ProviderUsageService>[antigravity, cursor, grok, opencode])
      service.id: service,
  };

  static const Duration _cacheTtl = Duration(minutes: 4);
  static const Duration _pollInterval = Duration(minutes: 4);

  final String id;
  final String name;
  final ProviderUsageFetcher _fetcher;

  ProviderUsageRecord? _record;
  Timer? _timer;
  bool _fetching = false;
  DateTime? _lastAttempt;
  String? _lastError;
  final List<void Function(ProviderUsageRecord?)> _listeners = <void Function(ProviderUsageRecord?)>[];

  ProviderUsageRecord? get latest => _record;
  String? get lastError => _lastError;

  void addListener(void Function(ProviderUsageRecord?) listener) {
    _listeners.add(listener);
    if (_listeners.length == 1) _start();
  }

  void removeListener(void Function(ProviderUsageRecord?) listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) _stop();
  }

  Future<void> refresh({bool force = false}) => _tick(force: force);

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_tick(force: true)));
    unawaited(_tick());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _notify() {
    for (final void Function(ProviderUsageRecord?) listener
        in List<void Function(ProviderUsageRecord?)>.from(_listeners)) {
      listener(_record);
    }
  }

  Future<void> _tick({bool force = false}) async {
    if (_fetching) return;
    final DateTime now = DateTime.now();
    if (_lastAttempt != null && now.difference(_lastAttempt!) < const Duration(minutes: 1)) {
      _notify();
      return;
    }
    if (!force && _record != null && now.difference(_record!.fetchedAt) < _cacheTtl) {
      _notify();
      return;
    }

    _fetching = true;
    _lastAttempt = now;
    try {
      _record = await _fetcher.fetch();
      _lastError = null;
    } on UsageFetchException catch (error) {
      _lastError = error.message;
    } on Object catch (error) {
      _lastError = 'Could not refresh $name usage ($error).';
    } finally {
      _fetching = false;
    }
    _notify();
  }
}

// ── Shared helpers for fetchers ────────────────────────────────────────────

String get usageHomeDirectory => Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';

String? nonEmptyEnvironment(String name) {
  final String? value = Platform.environment[name]?.trim();
  return value == null || value.isEmpty ? null : value;
}

/// Accepts ISO-8601 strings and epoch seconds/milliseconds (number or string).
DateTime? parseUsageDate(dynamic value) {
  if (value is num) {
    final double raw = value.toDouble();
    if (raw <= 0) return null;
    final double millis = raw > 100000000000 ? raw : raw * 1000;
    return DateTime.fromMillisecondsSinceEpoch(millis.round()).toLocal();
  }
  if (value is String) {
    final String text = value.trim();
    if (text.isEmpty) return null;
    final num? numeric = num.tryParse(text);
    if (numeric != null) return parseUsageDate(numeric);
    return DateTime.tryParse(text)?.toLocal();
  }
  return null;
}

double? parseUsageDouble(dynamic value) {
  if (value is num) return value.toDouble().isFinite ? value.toDouble() : null;
  if (value is String) return double.tryParse(value.trim());
  return null;
}

class UsageHttpResult {
  const UsageHttpResult(this.status, this.body);

  final int? status;
  final dynamic body;

  bool get ok => status != null && status! >= 200 && status! < 300;
  bool get isAuthError => status == 401 || status == 403;
}

/// JSON request that never throws; network failures return a null status.
Future<UsageHttpResult> usageJsonRequest(
  String method,
  String url, {
  Map<String, String> headers = const <String, String>{},
  Object? jsonBody,
  Map<String, String>? formBody,
}) async {
  try {
    final Uri uri = Uri.parse(url);
    final Map<String, String> allHeaders = <String, String>{
      'Accept': 'application/json',
      if (jsonBody != null) 'Content-Type': 'application/json',
      ...headers,
    };
    final http.Response response = await (method == 'POST'
            ? http.post(uri, headers: allHeaders, body: jsonBody != null ? jsonEncode(jsonBody) : formBody)
            : http.get(uri, headers: allHeaders))
        .timeout(const Duration(seconds: 15));
    dynamic body;
    try {
      body = response.body.isEmpty ? null : jsonDecode(response.body);
    } on FormatException {
      body = null;
    }
    return UsageHttpResult(response.statusCode, body);
  } on Object {
    return const UsageHttpResult(null, null);
  }
}

/// Finds a CLI on PATH (`where.exe`), trying each name in order.
Future<String?> resolveCliExecutable(List<String> names, {List<String> extraPaths = const <String>[]}) async {
  for (final String name in names) {
    try {
      final ProcessResult result = await Process.run('where.exe', <String>[name]);
      if (result.exitCode != 0) continue;
      final String path = result.stdout.toString().split(RegExp(r'\r?\n')).first.trim();
      if (path.isNotEmpty) return path;
    } on Object {
      // Try the next candidate.
    }
  }
  for (final String path in extraPaths) {
    if (File(path).existsSync()) return path;
  }
  return null;
}

/// Runs a CLI headlessly with a timeout; returns stdout, or null on failure.
Future<String?> runCliQuietly(
  String executable,
  List<String> args, {
  Duration timeout = const Duration(seconds: 30),
  Map<String, String>? environment,
}) async {
  final String lower = executable.toLowerCase();
  final bool viaCmd = lower.endsWith('.cmd') || lower.endsWith('.bat');
  final bool viaPowerShell = lower.endsWith('.ps1');
  try {
    final Process process = await Process.start(
      viaCmd
          ? 'cmd.exe'
          : viaPowerShell
              ? 'powershell.exe'
              : executable,
      <String>[
        if (viaCmd) ...<String>['/d', '/c', executable],
        if (viaPowerShell) ...<String>['-NoProfile', '-NonInteractive', '-ExecutionPolicy', 'Bypass', '-File', executable],
        ...args,
      ],
      environment: environment,
      workingDirectory: Directory.systemTemp.path,
    );
    unawaited(process.stdin.close());
    unawaited(process.stderr.drain<void>());
    final Future<String> stdout = process.stdout.transform(const Utf8Decoder(allowMalformed: true)).join();
    final int code = await process.exitCode.timeout(timeout, onTimeout: () {
      process.kill();
      return -1;
    });
    if (code != 0) return null;
    return await stdout.timeout(const Duration(seconds: 2), onTimeout: () => '');
  } on Object {
    return null;
  }
}
