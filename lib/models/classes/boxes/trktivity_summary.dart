import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';

import 'trktivity_box.dart';

/// A lightweight per-day rollup of the Trktivity log, independent of the heavy
/// Interface dashboard. Computes active seconds per exe (excluding idle), plus
/// total keystrokes and mouse-activity units. Used by the live "Today" QuickMenu
/// panel and the budget/category views.
class TrktivitySummary {
  final Map<String, int> appSeconds;
  final int idleSeconds;
  final int totalKeys;
  final int totalMouse;

  const TrktivitySummary({
    required this.appSeconds,
    required this.idleSeconds,
    required this.totalKeys,
    required this.totalMouse,
  });

  static const TrktivitySummary empty = TrktivitySummary(
    appSeconds: <String, int>{},
    idleSeconds: 0,
    totalKeys: 0,
    totalMouse: 0,
  );

  int get activeSeconds => appSeconds.values.fold(0, (int a, int b) => a + b);

  /// Top [n] apps by active time, most first.
  List<MapEntry<String, int>> topApps(int n) {
    final List<MapEntry<String, int>> list = appSeconds.entries.toList()
      ..sort((MapEntry<String, int> a, MapEntry<String, int> b) => b.value.compareTo(a.value));
    return list.take(n).toList();
  }
}

/// Parses `{folder}/{date}.json` (date as `yyyy-MM-dd`) into a [TrktivitySummary].
/// For today, the not-yet-flushed in-memory buffer is folded in for freshness.
Future<TrktivitySummary> computeTrktivitySummary(String date) async {
  final Map<String, int> appSeconds = <String, int>{};
  int idle = 0;
  int keys = 0;
  int mouse = 0;
  String lastExe = "";
  int startWTime = 0;

  void process(int ts, String t, String d) {
    if (t == "k") {
      keys += int.tryParse(d) ?? 0;
      return;
    }
    if (t == "m") {
      mouse += int.tryParse(d) ?? 0;
      return;
    }
    if (t != "w") return;
    String exe = "";
    try {
      exe = (jsonDecode(d)["e"] ?? "") as String;
    } catch (_) {
      return;
    }
    if (lastExe.isEmpty) {
      lastExe = exe;
      startWTime = ts;
      return;
    }
    if (exe != lastExe) {
      final int secs = ((ts - startWTime) / 1000).round();
      if (secs > 0 && secs < 3600) {
        if (lastExe == "idle.exe") {
          idle += secs;
        } else {
          appSeconds[lastExe] = (appSeconds[lastExe] ?? 0) + secs;
        }
      }
      lastExe = exe;
      startWTime = ts;
    }
  }

  final File f = File("${Trktivity.instance.folder}\\$date.json");
  if (f.existsSync()) {
    final List<String> lines = await f.readAsLines();
    for (final String line in lines) {
      if (line.trim().isEmpty) continue;
      try {
        final Map<String, dynamic> info = jsonDecode(line) as Map<String, dynamic>;
        process(info["ts"] as int, info["t"] as String, info["d"].toString());
      } catch (_) {
        // Skip malformed lines.
      }
    }
  }

  final bool isToday = date == DateFormat("yyyy-MM-dd").format(DateTime.now());
  if (isToday) {
    for (final TrktivitySave s in Trktivity.instance.saved) {
      process(s.timestamp, s.type, s.data);
    }
  }

  return TrktivitySummary(appSeconds: appSeconds, idleSeconds: idle, totalKeys: keys, totalMouse: mouse);
}
