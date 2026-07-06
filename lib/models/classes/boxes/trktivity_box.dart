import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:intl/intl.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../settings.dart';
import '../../win32/win32.dart';
import '../../win32/win_utils.dart';
import '../boxes.dart';

// --------------------------------------------------------------------------
// Trktivity
// --------------------------------------------------------------------------

enum TrktivityType { mouse, keys, window, title, idle }

class TrkFilterInfo {
  String title;
  String exe;
  String result;
  bool hasFilters;

  TrkFilterInfo({
    required this.title,
    required this.exe,
    required this.result,
    required this.hasFilters,
  });
}

class TrktivitySave {
  int ts;
  String t;
  String d;

  int get timestamp => ts;
  String get type => t;
  String get data => d;
  set timestamp(int e) => ts = e;
  set type(String e) => t = e;
  set data(String e) => d = e;

  TrktivitySave({this.ts = 0, this.t = "", this.d = ""});

  TrktivitySave copyWith({int? ts, String? t, String? d}) {
    return TrktivitySave(ts: ts ?? this.ts, t: t ?? this.t, d: d ?? this.d);
  }

  Map<String, dynamic> toMap() => <String, dynamic>{'ts': ts, 't': t, 'd': d};

  factory TrktivitySave.fromMap(Map<String, dynamic> map) {
    return TrktivitySave(
      ts: (map['ts'] ?? 0) as int,
      t: (map['t'] ?? '') as String,
      d: (map['d'] ?? '') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory TrktivitySave.fromJson(String source) => TrktivitySave.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'TrktivitySave(ts: $ts, t: $t, d: $d)';

  @override
  bool operator ==(covariant TrktivitySave other) {
    if (identical(this, other)) return true;
    return other.ts == ts && other.t == t && other.d == d;
  }

  @override
  int get hashCode => ts.hashCode ^ t.hashCode ^ d.hashCode;
}

class TrktivityData {
  String t;
  String e;
  String tl;

  String get type => t;
  String get exe => e;
  String get title => tl;
  set type(String e) => t = e;
  set exe(String e) => e = e;
  set title(String e) => tl = e;

  TrktivityData({required this.t, required this.e, required this.tl});

  TrktivityData copyWith({String? t, String? e, String? tl}) {
    return TrktivityData(t: t ?? this.t, e: e ?? this.e, tl: tl ?? this.tl);
  }

  Map<String, dynamic> toMap() => <String, dynamic>{'t': t, 'e': e, 'tl': tl};

  factory TrktivityData.fromMap(Map<String, dynamic> map) {
    return TrktivityData(
      t: (map['t'] ?? '') as String,
      e: (map['e'] ?? '') as String,
      tl: (map['tl'] ?? '') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory TrktivityData.fromJson(String source) => TrktivityData.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'TrktivityData(t: $t, e: $e, tl: $tl)';

  @override
  bool operator ==(covariant TrktivityData other) {
    if (identical(this, other)) return true;
    return other.t == t && other.e == e && other.tl == tl;
  }

  @override
  int get hashCode => t.hashCode ^ e.hashCode ^ tl.hashCode;
}

class TrktivityFilter {
  String exe;
  String titleSearch;
  String titleReplace;

  TrktivityFilter({
    required this.exe,
    required this.titleSearch,
    required this.titleReplace,
  });

  TrktivityFilter copyWith({String? exe, String? titleSearch, String? titleReplace}) {
    return TrktivityFilter(
      exe: exe ?? this.exe,
      titleSearch: titleSearch ?? this.titleSearch,
      titleReplace: titleReplace ?? this.titleReplace,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'exe': exe,
      'titleSearch': titleSearch,
      'titleReplace': titleReplace,
    };
  }

  factory TrktivityFilter.fromMap(Map<String, dynamic> map) {
    return TrktivityFilter(
      exe: (map['exe'] ?? '') as String,
      titleSearch: (map['titleSearch'] ?? '') as String,
      titleReplace: (map['titleReplace'] ?? '') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory TrktivityFilter.fromJson(String source) =>
      TrktivityFilter.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'TrktivityFilter(exe: $exe, titleSearch: $titleSearch, titleReplace: $titleReplace)';

  @override
  bool operator ==(covariant TrktivityFilter other) {
    if (identical(this, other)) return true;
    return other.exe == exe && other.titleSearch == titleSearch && other.titleReplace == titleReplace;
  }

  @override
  int get hashCode => exe.hashCode ^ titleSearch.hashCode ^ titleReplace.hashCode;
}

/// How an app counts toward the daily "productive vs distracting" ratio.
enum TrktivityCategory { productive, neutral, distracting }

/// A per-app rule: an optional daily time budget (minutes, 0 = none) and a
/// productivity category. Matched against the tracked executable name (exe).
class TrktivityAppRule {
  String exe;
  int dailyMinutes;
  TrktivityCategory category;

  TrktivityAppRule({
    required this.exe,
    this.dailyMinutes = 0,
    this.category = TrktivityCategory.neutral,
  });

  Map<String, dynamic> toMap() => <String, dynamic>{
        'exe': exe,
        'dailyMinutes': dailyMinutes,
        'category': category.index,
      };

  factory TrktivityAppRule.fromMap(Map<String, dynamic> map) {
    return TrktivityAppRule(
      exe: (map['exe'] ?? '') as String,
      dailyMinutes: (map['dailyMinutes'] ?? 0) as int,
      category: TrktivityCategory.values[(map['category'] ?? 1) as int],
    );
  }

  String toJson() => json.encode(toMap());
  factory TrktivityAppRule.fromJson(String source) =>
      TrktivityAppRule.fromMap(json.decode(source) as Map<String, dynamic>);
}

class Trktivity {
  Trktivity._();
  static final Trktivity instance = Trktivity._();
  int lasthWnd = -1;
  TrktivityType lastTrkType = TrktivityType.window;
  String lastTitle = "emptytitlehere";
  List<TrktivityFilter> _filters = <TrktivityFilter>[];
  List<TrktivitySave> saved = <TrktivitySave>[];
  String folder = "${WinUtils.getTabameAppDataFolder()}\\trktivity";

  set filters(List<TrktivityFilter> list) => _filters = list;

  // ---- Per-app time budgets & categories (live, in-memory) ----------------
  List<TrktivityAppRule> _appRules = <TrktivityAppRule>[];
  bool _appRulesLoaded = false;
  List<TrktivityAppRule> get appRules {
    if (!_appRulesLoaded) {
      _appRules = Boxes.getSavedMap<TrktivityAppRule>(TrktivityAppRule.fromJson, "trktivityAppRules");
      _appRulesLoaded = true;
    }
    return _appRules;
  }

  set appRules(List<TrktivityAppRule> list) {
    _appRules = list;
    _appRulesLoaded = true;
    Boxes.updateSettings(
      "trktivityAppRules",
      jsonEncode(list.map((TrktivityAppRule e) => e.toJson()).toList()),
    );
  }

  /// Seconds spent in each exe today, accumulated as foreground segments close.
  /// Drives budget nudges; reset automatically when the day rolls over.
  final Map<String, int> todaySeconds = <String, int>{};
  final Set<String> _notifiedToday = <String>{};
  String _todayDate = "";
  String _liveExe = "";
  int _liveStart = 0;

  void _rolloverIfNeeded() {
    final String today = DateFormat("yyyy-MM-dd").format(DateTime.now());
    if (today != _todayDate) {
      _todayDate = today;
      todaySeconds.clear();
      _notifiedToday.clear();
      _liveExe = "";
      _liveStart = 0;
    }
  }

  /// Closes the running foreground segment and starts a new one for [newExe].
  void _recordLiveSegment(String newExe) {
    final int now = DateTime.now().millisecondsSinceEpoch;
    _rolloverIfNeeded();
    if (_liveExe.isNotEmpty && _liveStart != 0 && _liveExe != "idle.exe") {
      final int secs = ((now - _liveStart) / 1000).round();
      if (secs > 0 && secs < 3600) {
        todaySeconds[_liveExe] = (todaySeconds[_liveExe] ?? 0) + secs;
        _checkBudget(_liveExe);
      }
    }
    _liveExe = newExe;
    _liveStart = now;
  }

  void _checkBudget(String exe) {
    if (_notifiedToday.contains(exe)) return;
    for (final TrktivityAppRule rule in appRules) {
      if (rule.dailyMinutes <= 0) continue;
      if (rule.exe.toLowerCase() != exe.toLowerCase()) continue;
      if ((todaySeconds[exe] ?? 0) >= rule.dailyMinutes * 60) {
        _notifiedToday.add(exe);
        WinUtils.showWindowsNotification(
          title: "Tabame · Time budget reached",
          body: "You've spent ${rule.dailyMinutes} min in $exe today.",
          onClick: () {},
        );
      }
      break;
    }
  }

  void onTrktivityEvent(String action, String info) {
    if (trktivityIdleState == 2) {
      add(lastTrkType, lasthWnd.toString());
    }
    trktivityIdleState = 0;
    if (action == "Keys") {
      add(TrktivityType.keys, info);
    } else if (action == "Movement") {
      add(TrktivityType.mouse, info);
    }
  }

  void onWinEventReceived(int hWnd, WinEventType type) {
    if (type == WinEventType.nameChange) {
      final String title = Win32.getTitle(hWnd);
      if (title.replaceFirst(lastTitle, "").length < 3 || lastTitle.replaceFirst(title, "").length < 3) {
        lastTitle = title;
        return;
      }
      lastTitle = title;
      add(TrktivityType.title, hWnd.toString());
      lasthWnd = hWnd;
      lastTrkType = TrktivityType.title;
    } else if (type == WinEventType.foreground) {
      add(TrktivityType.window, hWnd.toString());
      lasthWnd = hWnd;
      lastTrkType = TrktivityType.window;
    }
  }

  Timer? _timer;
  int trktivityIdleState = 0;

  void startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 15), (Timer timer) {
      if (trktivityIdleState == 0) {
        trktivityIdleState = 1;
      } else if (trktivityIdleState == 1) {
        add(TrktivityType.idle, "");
        trktivityIdleState = 2;
      }
    });
  }

  void stopTimer() => _timer?.cancel();

  List<TrktivityFilter> get filters => _filters.isEmpty
      ? _filters = Boxes.getSavedMap<TrktivityFilter>(
          TrktivityFilter.fromJson,
          "trktivityFilter",
          def: <TrktivityFilter>[
            TrktivityFilter(
              exe: "code",
              titleSearch: r"([\w\. ]+\w)[\W ]+([\w ]+) [\W ]+Visual",
              titleReplace: r"$2 - $1",
            ),
          ],
        )
      : _filters;

  void add(TrktivityType type, String value) {
    if (!user.trktivityEnabled) return;

    if (type == TrktivityType.idle) {
      _recordLiveSegment("idle.exe");
      final String data = TrktivityData(e: "idle.exe", t: "w", tl: "Idle").toJson();
      saved.add(TrktivitySave(ts: DateTime.now().millisecondsSinceEpoch, t: "w", d: data));
    } else if (type == TrktivityType.title || type == TrktivityType.window) {
      final TrkFilterInfo filterInfo = fitlerTitle(int.tryParse(value) ?? 0);
      if (type == TrktivityType.window && filterInfo.exe.isNotEmpty) {
        _recordLiveSegment(filterInfo.exe);
      }
      String title = "";
      if (filterInfo.hasFilters) {
        title = filterInfo.result;
      } else if (user.trktivitySaveAllTitles) {
        title = filterInfo.title;
      } else if (type == TrktivityType.title) {
        return;
      }
      final String data = TrktivityData(
        e: filterInfo.exe,
        t: type == TrktivityType.window ? "w" : "t",
        tl: title,
      ).toJson();
      saved.add(TrktivitySave(ts: DateTime.now().millisecondsSinceEpoch, t: "w", d: data));
    } else if (type == TrktivityType.keys) {
      saved.add(TrktivitySave(ts: DateTime.now().millisecondsSinceEpoch, t: "k", d: value));
    } else if (type == TrktivityType.mouse) {
      if (saved.length > 2 && saved.last.type == "m") {
        saved.last.data = ((int.tryParse(saved.last.data) ?? 0) + 1).toString();
        return;
      }
      saved.add(TrktivitySave(ts: DateTime.now().millisecondsSinceEpoch, t: "m", d: "1"));
    }

    if (saved.length > 10) {
      WinUtils.getTabameAppDataFolder();
      final String date = DateFormat("yyyy-MM-dd").format(DateTime.now());
      String output = "";
      for (TrktivitySave tr in saved) {
        output += "${tr.toJson()}\n";
      }
      File("$folder\\$date.json").writeAsStringSync(output, mode: FileMode.append);
      saved.clear();
    }
  }

  TrkFilterInfo fitlerTitle(int hWnd) {
    if (!Win32.isWindowOnDesktop(hWnd) && Win32.getTitle(hWnd).isEmpty) {
      return TrkFilterInfo(exe: "", hasFilters: false, result: "", title: "");
    }

    final String title = Win32.getTitle(hWnd);
    final String exe = Win32.getExe(Win32.getWindowExePath(hWnd));
    String newtitle = title;
    bool hasFilters = false;

    for (TrktivityFilter filter in filters) {
      if (filter.titleReplace.isEmpty || filter.titleSearch.isEmpty) continue;
      if (!RegExp(filter.exe, caseSensitive: false).hasMatch(exe)) continue;
      final RegExpMatch? match = RegExp(filter.titleSearch, caseSensitive: false).firstMatch(title);
      if (match != null) {
        String newString = filter.titleReplace;
        for (int i = 1; i < match.groupCount + 1; i++) {
          newString = newString.replaceAll("\$$i", match[i]!);
        }
        newtitle = newString;
        hasFilters = true;
        break;
      }
    }

    return TrkFilterInfo(exe: exe, title: title, result: newtitle, hasFilters: hasFilters);
  }
}
