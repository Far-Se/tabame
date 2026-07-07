import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/classes/boxes/trktivity_box.dart';
import '../../../models/classes/boxes/trktivity_summary.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

/// Live "Today" glance built on the existing Trktivity log: total active time,
/// top apps, keystroke/mouse activity, an active-vs-idle focus ratio, per-app
/// time-budget progress, and a 15-day history chart. Navigate to previous days
/// with the arrows. Read-only summary + a compact rules editor.
class TrktivityTodayButton extends StatelessWidget {
  const TrktivityTodayButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Today's Trktivity",
      heightFactor: 0.9,
      icon: const Icon(Icons.insights_outlined),
      child: () => const _TrktivityTodayPanel(),
    );
  }
}

String _fmtDuration(int seconds) {
  if (seconds < 60) return "${seconds}s";
  final int h = seconds ~/ 3600;
  final int m = (seconds % 3600) ~/ 60;
  if (h > 0) return "${h}h ${m}m";
  return "${m}m";
}

const Map<TrktivityCategory, Color> _catColors = <TrktivityCategory, Color>{
  TrktivityCategory.productive: Color(0xFF66BB6A),
  TrktivityCategory.neutral: Color(0xFF90A4AE),
  TrktivityCategory.distracting: Color(0xFFEF5350),
};

/// A single day of rolled-up activity for the history chart.
class _DayStat {
  final DateTime date;
  final TrktivitySummary summary;
  const _DayStat(this.date, this.summary);
}

class _TrktivityTodayPanel extends StatefulWidget {
  const _TrktivityTodayPanel();

  @override
  State<_TrktivityTodayPanel> createState() => _TrktivityTodayPanelState();
}

class _TrktivityTodayPanelState extends State<_TrktivityTodayPanel> {
  TrktivitySummary _summary = TrktivitySummary.empty;
  List<_DayStat> _history = <_DayStat>[];
  final Map<String, TrktivitySummary> _cache = <String, TrktivitySummary>{};
  DateTime _date = _today();
  bool _loading = true;
  bool _editing = false;

  static DateTime _today() {
    final DateTime n = DateTime.now();
    return DateTime(n.year, n.month, n.day);
  }

  static String _dateStr(DateTime d) => DateFormat("yyyy-MM-dd").format(d);

  bool get _isToday => _dateStr(_date) == _dateStr(_today());

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final String todayStr = _dateStr(_today());
    final String dateStr = _dateStr(_date);
    TrktivitySummary selected = TrktivitySummary.empty;
    final List<_DayStat> history = <_DayStat>[];
    for (int i = 14; i >= 0; i--) {
      final DateTime d = _date.subtract(Duration(days: i));
      final String ds = _dateStr(d);
      TrktivitySummary s;
      if (ds != todayStr && _cache.containsKey(ds)) {
        s = _cache[ds]!;
      } else {
        s = await computeTrktivitySummary(ds);
        if (ds != todayStr) _cache[ds] = s;
      }
      if (ds == dateStr) selected = s;
      history.add(_DayStat(d, s));
    }
    if (!mounted) return;
    setState(() {
      _summary = selected;
      _history = history;
      _loading = false;
    });
  }

  void _shiftDay(int delta) {
    final DateTime next = _date.add(Duration(days: delta));
    if (next.isAfter(_today())) return;
    setState(() => _date = next);
    _load();
  }

  void _goToDay(DateTime day) {
    final DateTime d = DateTime(day.year, day.month, day.day);
    if (_dateStr(d) == _dateStr(_date)) return;
    setState(() => _date = d);
    _load();
  }

  TrktivityCategory _categoryOf(String exe) {
    for (final TrktivityAppRule r in Trktivity.instance.appRules) {
      if (r.exe.toLowerCase() == exe.toLowerCase()) return r.category;
    }
    return TrktivityCategory.neutral;
  }

  TrktivityAppRule? _ruleOf(String exe) {
    for (final TrktivityAppRule r in Trktivity.instance.appRules) {
      if (r.exe.toLowerCase() == exe.toLowerCase()) return r;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: "Trktivity",
          icon: Icons.insights_outlined,
          buttonIcon: _editing ? Icons.check_rounded : Icons.tune_rounded,
          buttonTooltip: _editing ? "Done" : "Budgets & categories",
          buttonPressed: () => setState(() => _editing = !_editing),
          extraActions: <Widget>[
            IconButton(
              iconSize: 18,
              tooltip: "Refresh",
              onPressed: _load,
              icon: const Icon(Icons.refresh_rounded),
            ),
          ],
        ),
        Expanded(
          child: WindowsScrollView(
            padding: const EdgeInsets.all(14),
            child: !user.trktivityEnabled
                ? _disabledHint(scheme)
                : _loading
                    ? const Padding(
                        padding: EdgeInsets.all(30),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _editing
                        ? _rulesEditor(scheme)
                        : _summaryView(scheme),
          ),
        ),
      ],
    );
  }

  Widget _disabledHint(ColorScheme scheme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text("Trktivity isn't enabled", style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
        const SizedBox(height: 6),
        Text(
          "Enable Trktivity in the Interface → Trktivity page to start tracking your active time, "
          "keystrokes and app usage. Then come back here for today's glance.",
          style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.65), fontWeight: FontWeight.w600),
        ),
      ],
    );
  }

  Widget _summaryView(ColorScheme scheme) {
    final int active = _summary.activeSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _dateNavigator(scheme),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            _stat("Active", _fmtDuration(active), Icons.timelapse_rounded, scheme),
            _stat("Idle", _fmtDuration(_summary.idleSeconds), Icons.bedtime_outlined, scheme),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            _stat("Keystrokes", NumberFormat.compact().format(_summary.totalKeys), Icons.keyboard_outlined, scheme),
            _stat("Mouse", NumberFormat.compact().format(_summary.totalMouse), Icons.mouse_outlined, scheme),
          ],
        ),
        const SizedBox(height: 16),
        _focusBar(active, scheme),
        const SizedBox(height: 16),
        _categoriesBar(active, scheme),
        const SizedBox(height: 16),
        Text("Top apps", style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
        const SizedBox(height: 6),
        if (_summary.appSeconds.isEmpty)
          Text("No activity recorded ${_isToday ? "yet today" : "this day"}.",
              style: TextStyle(color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600))
        else
          ..._summary.topApps(6).map((MapEntry<String, int> e) => _appRow(e.key, e.value, active, scheme)),
        const SizedBox(height: 18),
        Text("Last 15 days", style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
        const SizedBox(height: 8),
        _HistoryChart(
          history: _history,
          selected: _date,
          scheme: scheme,
          onTapDay: _goToDay,
        ),
      ],
    );
  }

  Widget _dateNavigator(ColorScheme scheme) {
    final String label = _isToday
        ? "Today"
        : _dateStr(_date) == _dateStr(_today().subtract(const Duration(days: 1)))
            ? "Yesterday"
            : DateFormat("EEE, d MMM yyyy").format(_date);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          IconButton(
            iconSize: 20,
            tooltip: "Previous day",
            onPressed: () => _shiftDay(-1),
            icon: const Icon(Icons.chevron_left_rounded),
          ),
          Expanded(
            child: Center(
              child: Text(label, style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
            ),
          ),
          IconButton(
            iconSize: 20,
            tooltip: "Next day",
            onPressed: _isToday ? null : () => _shiftDay(1),
            icon: const Icon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon, ColorScheme scheme) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: scheme.onSurface.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 18, color: scheme.primary),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(value, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700)),
                Text(label,
                    style: TextStyle(
                        fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Active-vs-idle focus ratio — always meaningful regardless of app rules.
  Widget _focusBar(int active, ColorScheme scheme) {
    final int idle = _summary.idleSeconds;
    final int total = active + idle;
    if (total == 0) return const SizedBox.shrink();
    final int pct = ((active / total) * 100).round();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text("Focus balance", style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
            const Spacer(),
            Text("$pct% active", style: TextStyle(fontWeight: FontWeight.w700, color: scheme.primary)),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: <Widget>[
              if (active > 0) Expanded(flex: active, child: Container(height: 8, color: scheme.primary)),
              if (idle > 0)
                Expanded(flex: idle, child: Container(height: 8, color: scheme.onSurface.withValues(alpha: 0.25))),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Text("${_fmtDuration(active)} active  ·  ${_fmtDuration(idle)} idle",
              style:
                  TextStyle(fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
        ),
      ],
    );
  }

  /// Productive / neutral / distracting split, driven by the per-app rules.
  Widget _categoriesBar(int active, ColorScheme scheme) {
    if (active == 0) return const SizedBox.shrink();
    final Map<TrktivityCategory, int> byCat = <TrktivityCategory, int>{
      TrktivityCategory.productive: 0,
      TrktivityCategory.neutral: 0,
      TrktivityCategory.distracting: 0,
    };
    _summary.appSeconds.forEach((String exe, int secs) {
      final TrktivityCategory cat = _categoryOf(exe);
      byCat[cat] = byCat[cat]! + secs;
    });
    final int prod = byCat[TrktivityCategory.productive]!;
    final int dist = byCat[TrktivityCategory.distracting]!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Row(
          children: <Widget>[
            Text("App categories", style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
            const Spacer(),
            Text("${((prod / active) * 100).round()}% productive",
                style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF66BB6A))),
          ],
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Row(
            children: <Widget>[
              for (final TrktivityCategory cat in TrktivityCategory.values)
                if (byCat[cat]! > 0)
                  Expanded(
                    flex: byCat[cat]!,
                    child: Container(height: 8, color: _catColors[cat]),
                  ),
            ],
          ),
        ),
        if (dist > 0)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text("${_fmtDuration(dist)} distracting",
                style: TextStyle(
                    fontSize: 11, color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600)),
          ),
      ],
    );
  }

  Widget _appRow(String exe, int secs, int active, ColorScheme scheme) {
    final double frac = active == 0 ? 0 : secs / active;
    final TrktivityAppRule? rule = _ruleOf(exe);
    final Color catColor = _catColors[_categoryOf(exe)]!;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(width: 8, height: 8, decoration: BoxDecoration(color: catColor, shape: BoxShape.circle)),
              const SizedBox(width: 8),
              Expanded(
                  child:
                      Text(exe, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600))),
              Text(_fmtDuration(secs), style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
            ],
          ),
          const SizedBox(height: 3),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: frac.clamp(0.0, 1.0),
              minHeight: 4,
              backgroundColor: scheme.onSurface.withValues(alpha: 0.08),
              valueColor: AlwaysStoppedAnimation<Color>(catColor.withValues(alpha: 0.8)),
            ),
          ),
          if (rule != null && rule.dailyMinutes > 0)
            Padding(
              padding: const EdgeInsets.only(top: 3),
              child: Text(
                "Budget ${_fmtDuration(secs)} / ${rule.dailyMinutes}m"
                "${secs >= rule.dailyMinutes * 60 ? "  ·  over" : ""}",
                style: TextStyle(
                  fontSize: 10.5,
                  fontWeight: FontWeight.w600,
                  color: secs >= rule.dailyMinutes * 60
                      ? const Color(0xFFEF5350)
                      : scheme.onSurface.withValues(alpha: 0.55),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---- Rules editor --------------------------------------------------------
  Widget _rulesEditor(ColorScheme scheme) {
    final List<TrktivityAppRule> rules = List<TrktivityAppRule>.of(Trktivity.instance.appRules);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text("Budgets & categories", style: TextStyle(fontWeight: FontWeight.w700, color: scheme.onSurface)),
        const SizedBox(height: 4),
        Text(
          "Match an app by its executable name (e.g. chrome.exe). Set a daily minute "
          "budget for a nudge, and a category for the focus balance.",
          style: TextStyle(fontSize: 11.5, color: scheme.onSurface.withValues(alpha: 0.6), fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 10),
        for (int i = 0; i < rules.length; i++) _ruleRow(rules, i, scheme),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: TextButton.icon(
            onPressed: () {
              rules.add(TrktivityAppRule(exe: ""));
              _saveRules(rules);
            },
            icon: const Icon(Icons.add_rounded, size: 18),
            label: const Text("Add app rule"),
          ),
        ),
      ],
    );
  }

  Widget _ruleRow(List<TrktivityAppRule> rules, int i, ColorScheme scheme) {
    final TrktivityAppRule rule = rules[i];
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: TextFormField(
              initialValue: rule.exe,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(isDense: true, hintText: "app.exe", border: OutlineInputBorder()),
              onChanged: (String v) {
                rule.exe = v.trim();
                _saveRules(rules, rebuild: false);
              },
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: TextFormField(
              initialValue: rule.dailyMinutes == 0 ? "" : rule.dailyMinutes.toString(),
              style: const TextStyle(fontSize: 13),
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true, hintText: "min", border: OutlineInputBorder()),
              onChanged: (String v) {
                rule.dailyMinutes = int.tryParse(v) ?? 0;
                _saveRules(rules, rebuild: false);
              },
            ),
          ),
          const SizedBox(width: 6),
          DropdownButton<TrktivityCategory>(
            value: rule.category,
            isDense: true,
            underline: const SizedBox.shrink(),
            items: TrktivityCategory.values
                .map((TrktivityCategory c) => DropdownMenuItem<TrktivityCategory>(
                      value: c,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Container(
                              width: 8,
                              height: 8,
                              decoration: BoxDecoration(color: _catColors[c], shape: BoxShape.circle)),
                          const SizedBox(width: 5),
                          Text(c.name, style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ))
                .toList(),
            onChanged: (TrktivityCategory? c) {
              if (c == null) return;
              rule.category = c;
              _saveRules(rules);
            },
          ),
          IconButton(
            iconSize: 18,
            tooltip: "Remove",
            onPressed: () {
              rules.removeAt(i);
              _saveRules(rules);
            },
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }

  void _saveRules(List<TrktivityAppRule> rules, {bool rebuild = true}) {
    Trktivity.instance.appRules = rules;
    if (rebuild && mounted) setState(() {});
  }
}

/// 15-day active/idle bar chart. Tap a bar to jump to that day.
class _HistoryChart extends StatelessWidget {
  final List<_DayStat> history;
  final DateTime selected;
  final ColorScheme scheme;
  final void Function(DateTime day) onTapDay;

  const _HistoryChart({
    required this.history,
    required this.selected,
    required this.scheme,
    required this.onTapDay,
  });

  static String _dateStr(DateTime d) => DateFormat("yyyy-MM-dd").format(d);

  @override
  Widget build(BuildContext context) {
    if (history.isEmpty) return const SizedBox.shrink();
    final Color activeColor = scheme.primary;
    final Color idleColor = scheme.onSurface.withValues(alpha: 0.22);
    final String selectedStr = _dateStr(selected);

    double maxY = 1;
    for (final _DayStat s in history) {
      final double total = (s.summary.activeSeconds + s.summary.idleSeconds).toDouble();
      if (total > maxY) maxY = total;
    }

    return SizedBox(
      height: 150,
      child: BarChart(
        BarChartData(
          maxY: maxY,
          alignment: BarChartAlignment.spaceAround,
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              getTooltipItem: (BarChartGroupData group, int groupIndex, BarChartRodData rod, int rodIndex) {
                final _DayStat s = history[group.x];
                return BarTooltipItem(
                  "${DateFormat("EEE, d MMM").format(s.date)}\n"
                  "${_fmtDuration(s.summary.activeSeconds)} active\n"
                  "${_fmtDuration(s.summary.idleSeconds)} idle",
                  Theme.of(context).textTheme.labelMedium!,
                );
              },
            ),
            touchCallback: (FlTouchEvent event, BarTouchResponse? response) {
              if (event is! FlTapUpEvent) return;
              final int? idx = response?.spot?.touchedBarGroupIndex;
              if (idx == null || idx < 0 || idx >= history.length) return;
              onTapDay(history[idx].date);
            },
          ),
          barGroups: List<BarChartGroupData>.generate(history.length, (int i) {
            final _DayStat s = history[i];
            final double active = s.summary.activeSeconds.toDouble();
            final double idle = s.summary.idleSeconds.toDouble();
            final bool isSel = _dateStr(s.date) == selectedStr;
            return BarChartGroupData(
              x: i,
              barRods: <BarChartRodData>[
                BarChartRodData(
                  toY: active + idle,
                  width: 9,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(2)),
                  rodStackItems: <BarChartRodStackItem>[
                    BarChartRodStackItem(0, active, activeColor),
                    BarChartRodStackItem(active, active + idle, idleColor),
                  ],
                  color: Colors.transparent,
                  borderSide:
                      isSel ? BorderSide(color: scheme.onSurface.withValues(alpha: 0.7), width: 1.5) : BorderSide.none,
                ),
              ],
            );
          }),
          titlesData: FlTitlesData(
            show: true,
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 22,
                getTitlesWidget: (double value, TitleMeta meta) {
                  final int i = value.toInt();
                  if (i < 0 || i >= history.length) return const SizedBox.shrink();
                  final bool isSel = _dateStr(history[i].date) == selectedStr;
                  return SideTitleWidget(
                    meta: meta,
                    space: 6,
                    child: Text(
                      history[i].date.day.toString(),
                      style: TextStyle(
                        fontSize: 10,
                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w600,
                        color: isSel ? scheme.primary : scheme.onSurface.withValues(alpha: 0.5),
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
        ),
      ),
    );
  }
}
