import 'dart:async';
import 'dart:convert';
import 'dart:io';

class CodexUsageRecord {
  const CodexUsageRecord({
    required this.fiveHourRemaining,
    required this.weeklyRemaining,
    required this.fiveHourResetAt,
    required this.weeklyResetAt,
    required this.plan,
    required this.fetchedAt,
  });

  final double? fiveHourRemaining;
  final double? weeklyRemaining;
  final String? fiveHourResetAt;
  final String? weeklyResetAt;
  final String plan;
  final DateTime fetchedAt;
}

/// Reads the local Codex usage source used by the standalone usage widget.
///
/// The CLI is preferred because it can refresh the data from Codex. The local
/// usage-limits cache is kept as a fallback so the panel still has useful data
/// when the CLI is not available on PATH.
class CodexUsageService {
  CodexUsageService._();

  static final CodexUsageService instance = CodexUsageService._();

  static const Duration _cacheTtl = Duration(minutes: 5);
  static const Duration _pollInterval = Duration(minutes: 5);
  static const String _usageCommand = 'codex-cli-usage';

  CodexUsageRecord? _record;
  Timer? _timer;
  bool _fetching = false;
  String? _lastError;
  final List<void Function(CodexUsageRecord?)> _listeners = <void Function(CodexUsageRecord?)>[];

  CodexUsageRecord? get latest => _record;
  String? get lastError => _lastError;

  void addListener(void Function(CodexUsageRecord?) listener) {
    _listeners.add(listener);
    if (_listeners.length == 1) _start();
  }

  void removeListener(void Function(CodexUsageRecord?) listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) _stop();
  }

  Future<void> refresh({bool force = false}) => _tick(force: force);

  void _start() {
    _timer?.cancel();
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_tick()));
    unawaited(_tick());
  }

  void _stop() {
    _timer?.cancel();
    _timer = null;
  }

  void _notify() {
    for (final void Function(CodexUsageRecord?) listener in List<void Function(CodexUsageRecord?)>.from(_listeners)) {
      listener(_record);
    }
  }

  Future<void> _tick({bool force = false}) async {
    if (_fetching) return;
    if (!force && _record != null && DateTime.now().difference(_record!.fetchedAt) < _cacheTtl) {
      _notify();
      return;
    }

    _fetching = true;
    try {
      final CodexUsageRecord? fresh = await _loadUsage();
      if (fresh == null) {
        _lastError = 'No Codex usage data was found.';
      } else {
        _record = fresh;
        _lastError = null;
      }
      _notify();
    } finally {
      _fetching = false;
    }
  }

  Future<CodexUsageRecord?> _loadUsage() async {
    for (final String command in _commandCandidates()) {
      try {
        final ProcessResult result = await Process.run(
          command,
          <String>['json'],
          runInShell: command == _usageCommand,
        ).timeout(const Duration(seconds: 30));
        if (result.exitCode != 0) continue;

        final dynamic data = jsonDecode(result.stdout.toString());
        final CodexUsageRecord? record = _normalizeUsage(data);
        if (record != null) return record;
      } on Object {
        // Try the next command candidate and then the on-disk fallback.
      }
    }

    final String home = _homeDirectory;
    if (home.isEmpty) return null;

    try {
      final File cacheFile = File('$home/.codex/usage-limits.json');
      if (!cacheFile.existsSync()) return null;
      final dynamic data = jsonDecode(await cacheFile.readAsString());
      return _normalizeUsage(data);
    } on Object {
      return null;
    }
  }

  List<String> _commandCandidates() {
    final Set<String> commands = <String>{_usageCommand};
    final String home = _homeDirectory;
    if (home.isNotEmpty) {
      commands.add('$home/.local/bin/codex-cli-usage.exe');
      commands.add('$home/.local/bin/codex-cli-usage');
    }
    return commands.toList();
  }

  String get _homeDirectory {
    return Platform.environment['USERPROFILE'] ?? Platform.environment['HOME'] ?? '';
  }

  static CodexUsageRecord? _normalizeUsage(dynamic data) {
    if (data is! Map) return null;

    final _CodexWindow session = _readWindow(
      data,
      const <String>['primary_window', 'primary', 'session', 'five_hour', '5h'],
      const <String>['5h', '5-hour', 'session', 'primary'],
    );
    final _CodexWindow weekly = _readWindow(
      data,
      const <String>['secondary_window', 'secondary', 'weekly', 'week', '7d'],
      const <String>['7d', '7-day', 'week', 'weekly', 'secondary'],
    );

    if (session.percent == null && weekly.percent == null && session.resetAt == null && weekly.resetAt == null) {
      return null;
    }

    final dynamic planValue = data['plan'] ?? data['account_plan'] ?? data['subscription'];
    final String plan = planValue == null ? '' : _titleCase(planValue.toString().trim());

    return CodexUsageRecord(
      fiveHourRemaining: session.percent,
      weeklyRemaining: weekly.percent,
      fiveHourResetAt: session.resetAt,
      weeklyResetAt: weekly.resetAt,
      plan: plan,
      fetchedAt: DateTime.now(),
    );
  }

  static _CodexWindow _readWindow(Map<dynamic, dynamic> data, List<String> keys, List<String> labels) {
    for (final String key in keys) {
      if (!data.containsKey(key)) continue;
      final dynamic value = data[key];
      return _CodexWindow(
        percent: _clampPercent(_findPercent(value)),
        resetAt: _formatReset(value),
      );
    }

    return _pickWindow(data, labels);
  }

  static _CodexWindow _pickWindow(dynamic data, List<String> labels) {
    int bestScore = 0;
    _CodexWindow? best;

    for (final dynamic candidate in _walk(data)) {
      if (candidate is! Map) continue;
      final int score = _scoreWindow(candidate, labels);
      if (score <= bestScore) continue;

      final double? percent = _findPercent(candidate);
      if (percent == null) continue;
      bestScore = score;
      best = _CodexWindow(
        percent: _clampPercent(percent),
        resetAt: _formatReset(candidate),
      );
    }

    return best ?? const _CodexWindow();
  }

  static Iterable<dynamic> _walk(dynamic value) sync* {
    yield value;
    if (value is Map) {
      for (final dynamic child in value.values) {
        yield* _walk(child);
      }
    } else if (value is List) {
      for (final dynamic child in value) {
        yield* _walk(child);
      }
    }
  }

  static int _scoreWindow(Map<dynamic, dynamic> value, List<String> labels) {
    final String keys = value.keys.map((dynamic key) => key.toString().toLowerCase()).join(' ');
    final String scalarValues = value.values
        .where((dynamic item) => item is String || item is num)
        .map((dynamic item) => item.toString().toLowerCase())
        .join(' ');
    final String haystack = '$keys $scalarValues';
    return labels.where((String label) => haystack.contains(label)).length;
  }

  static double? _findPercent(dynamic value) {
    if (value == null) return null;
    if (value is num) {
      final double raw = value.toDouble();
      return raw >= 0 && raw <= 1 ? raw * 100 : raw;
    }
    if (value is String) {
      final double? parsed = double.tryParse(value.trim().replaceAll('%', ''));
      return parsed;
    }
    if (value is! Map) return null;

    final double? pct = _findPercent(value['pct']);
    if (pct != null) return _clampPercent(100 - pct);

    for (final String key in <String>[
      'percent_remaining',
      'remaining_percent',
      'remaining_pct',
      'percent_available',
      'available_percent',
      'remaining',
      'available',
    ]) {
      final double? remaining = _findPercent(value[key]);
      if (remaining != null) return _clampPercent(remaining);
    }

    final double? used = _findPercent(value['used_percent']) ?? _findPercent(value['usage_percent']);
    if (used != null) return _clampPercent(100 - used);
    return null;
  }

  static String? _formatReset(dynamic value) {
    if (value is num) {
      final double raw = value.toDouble();
      final double seconds = raw > 10000000000 ? raw / 1000 : raw;
      try {
        return _formatResetDate(DateTime.fromMillisecondsSinceEpoch((seconds * 1000).round()).toLocal());
      } on Object {
        return null;
      }
    }

    if (value is String) {
      final String text = value.trim();
      if (text.isEmpty) return null;
      try {
        return _formatResetDate(DateTime.parse(text).toLocal());
      } on FormatException {
        // Some Codex usage sources already return a display-ready label.
      }
      for (final String prefix in <String>['resets ', 'reset ']) {
        if (text.toLowerCase().startsWith(prefix)) return text.substring(prefix.length);
      }
      return text;
    }

    if (value is Map) {
      for (final String key in <String>['reset_at', 'resets_at', 'reset_time', 'reset', 'resets', 'window_reset']) {
        if (!value.containsKey(key)) continue;
        final String? reset = _formatReset(value[key]);
        if (reset != null) return reset;
      }
    }
    return null;
  }

  static String _formatResetDate(DateTime reset) {
    final DateTime now = DateTime.now();
    if (reset.year == now.year && reset.month == now.month && reset.day == now.day) {
      final int hour = reset.hour % 12 == 0 ? 12 : reset.hour % 12;
      final String minute = reset.minute.toString().padLeft(2, '0');
      return '$hour:$minute ${reset.hour >= 12 ? 'PM' : 'AM'}';
    }
    const List<String> months = <String>[
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec'
    ];
    return '${months[reset.month - 1]} ${reset.day}';
  }

  static double? _clampPercent(double? value) {
    if (value == null) return null;
    return value.clamp(0.0, 100.0).toDouble();
  }

  static String _titleCase(String value) {
    if (value.isEmpty) return value;
    return value
        .split(RegExp(r'\s+'))
        .where((String word) => word.isNotEmpty)
        .map((String word) => '${word[0].toUpperCase()}${word.substring(1).toLowerCase()}')
        .join(' ');
  }
}

class _CodexWindow {
  const _CodexWindow({this.percent, this.resetAt});

  final double? percent;
  final String? resetAt;
}
