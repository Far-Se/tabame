import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/settings.dart';
import '../../models/win32/keys.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/win_utils.dart';
import '../../models/win32/window.dart';
import '../../models/window_watcher.dart';

class TaskbarStats extends StatefulWidget {
  final bool withTopDivider;
  final bool withBottomDivider;
  const TaskbarStats({super.key, this.withTopDivider = true, this.withBottomDivider = true});

  @override
  State<TaskbarStats> createState() => _TaskbarStatsState();
}

class _TaskbarStatsState extends State<TaskbarStats> {
  static const Duration _kRefreshInterval = Duration(seconds: 1);
  static const List<String> _kMetricOrder = <String>['CPU', 'RAM', 'DISK', 'NET'];

  Timer? _statsTimer;
  String _stats = "";

  @override
  void initState() {
    super.initState();
    _stats = _buildStatsLabel(WindowWatcher.taskManagerStats);
    _statsTimer = Timer.periodic(_kRefreshInterval, (_) {
      if (!mounted || !QuickMenuFunctions.isQuickMenuVisible) return;
      final String nextStats = _buildStatsLabel(WindowWatcher.taskManagerStats);
      if (nextStats == _stats) return;
      setState(() => _stats = nextStats);
    });
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  String _buildStatsLabel(String rawStats) {
    final String trimmed = rawStats.trim();
    if (trimmed.isEmpty) return "";

    return trimmed.startsWith('CPU ') ? trimmed : 'CPU $trimmed';
  }

  List<({String label, String value})> _parseStats(String stats) {
    final List<({String label, String value})> metrics = <({String label, String value})>[];
    if (stats.isEmpty) return metrics;
    try {
      final RegExp metricPattern = RegExp(r'(CPU|RAM|DISK|NET)\s+([^\s]+)', caseSensitive: false);
      final Iterable<RegExpMatch> matches = metricPattern.allMatches(stats);
      final Map<String, String> parsed = <String, String>{};
      for (final RegExpMatch match in matches) {
        final String? label = match.group(1)?.toUpperCase();
        final String? value = match.group(2);
        if (label == null || value == null) continue;
        parsed[label] = value;
      }

      for (final String label in _kMetricOrder) {
        final String? value = parsed[label];
        if (value != null && value.isNotEmpty) {
          metrics.add((label: label, value: value));
        }
      }
    } catch (_) {}

    return metrics;
  }

  Future<void> _focusTaskManager() async {
    if (!WinUtils.isAdministrator()) {
      WinKeys.send("{#CTRL}{#SHIFT}{ESCAPE}");
      return;
    }
    Window? taskManagerWindow = WindowWatcher.list.cast<Window?>().firstWhere(
          (Window? window) => window?.process.exe == "Taskmgr.exe",
          orElse: () => null,
        );

    if (taskManagerWindow == null) {
      await WindowWatcher.fetchWindows();
      taskManagerWindow = WindowWatcher.list.cast<Window?>().firstWhere(
            (Window? window) => window?.process.exe == "Taskmgr.exe",
            orElse: () => null,
          );
    }

    if (taskManagerWindow == null) return;
    if (taskManagerWindow.process.exe == "Taskmgr.exe" && !WinUtils.isAdministrator()) return;
    Win32.activateWindow(taskManagerWindow.hWnd);
  }

  @override
  Widget build(BuildContext context) {
    if (WindowWatcher.taskManagerStats == "") return const SizedBox.shrink();
    final double height = globalSettings.expandedTaskbar ? 32 : 27;
    final Color onSurface = globalSettings.themeColors.textColor;
    final List<({String label, String value})> metrics = _parseStats(_stats);
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        if (widget.withTopDivider) Divider(thickness: 1, height: 1, color: onSurface.withValues(alpha: 0.08)),
        SizedBox(
          height: height,
          width: double.infinity,
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: metrics.isEmpty ? null : _focusTaskManager,
              borderRadius: BorderRadius.circular(10),
              hoverColor: globalSettings.themeColors.accentColor.withAlpha(10),
              splashColor: Colors.transparent,
              child: Padding(
                padding: !globalSettings.expandedTaskbar
                    ? const EdgeInsets.fromLTRB(7, 3, 3, 3)
                    : const EdgeInsets.symmetric(horizontal: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    if (metrics.isNotEmpty)
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: metrics.map((({String label, String value}) metric) {
                            return Container(
                              padding: EdgeInsets.symmetric(
                                horizontal: globalSettings.expandedTaskbar ? 8 : 6,
                                vertical: globalSettings.expandedTaskbar ? 4 : 3,
                              ),
                              child: RichText(
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                text: TextSpan(
                                  children: <InlineSpan>[
                                    TextSpan(
                                      text: '${metric.label} ',
                                      style: TextStyle(
                                        fontSize: globalSettings.expandedTaskbar ? 11.5 : 10.5,
                                        letterSpacing: 0.4,
                                        fontFamily: globalSettings.themeColors.uiFontFamily,
                                        fontStyle: globalSettings.themeColors.uiFontItalic
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                        fontWeight: FontWeight(globalSettings.themeColors.uiFontWeight),
                                        color: globalSettings.themeColors.textColor,
                                      ),
                                    ),
                                    TextSpan(
                                      text: metric.value,
                                      style: TextStyle(
                                        fontSize: globalSettings.expandedTaskbar ? 12.5 : 11.5,
                                        fontFamily: globalSettings.themeColors.entryFontFamily,
                                        fontStyle: globalSettings.themeColors.entryFontItalic
                                            ? FontStyle.italic
                                            : FontStyle.normal,
                                        color: globalSettings.themeColors.textColor,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(growable: false),
                        ),
                      ),
                    if (metrics.isEmpty)
                      Expanded(
                        child: Text(
                          "",
                          style: TextStyle(
                            fontSize: globalSettings.expandedTaskbar ? 12 : 11,
                            fontWeight: FontWeight.w700,
                            color: onSurface,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
        if (widget.withBottomDivider) Divider(thickness: 1, height: 1, color: onSurface.withValues(alpha: 0.08)),
      ],
    );
  }
}
