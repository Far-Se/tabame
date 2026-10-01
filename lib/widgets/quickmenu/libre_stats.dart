import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../platform/windows/tabamewin32_api.dart';
import '../../platform/windows/win32_api.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/tray_watcher.dart';
import '../../services/libre_stats_service.dart';

class LibreStats extends StatefulWidget {
  final bool withTopDivider;
  final bool withBottomDivider;
  const LibreStats({super.key, this.withTopDivider = true, this.withBottomDivider = true});

  @override
  State<LibreStats> createState() => _LibreStatsState();
}

class _LibreStatsState extends State<LibreStats> with QuickMenuTriggers {
  static const Duration _kRefreshInterval = Duration(seconds: 1);

  Timer? _statsTimer;
  Future<void>? _refreshInFlight;
  final LibreStatsService _stats = LibreStatsService.instance;

  late double wUsage;
  late double wTemp;
  late double wRam;

  final TextStyle labelStyle = GoogleFonts.getFont(
    Design.uiFontFamily,
    fontSize: user.expandedTaskbar ? 11.5 : 10.5,
    letterSpacing: 0.4,
    fontStyle: Design.uiFontItalic ? FontStyle.italic : FontStyle.normal,
    fontWeight: FontWeight(Design.uiFontWeight),
    color: Design.text,
  );

  final TextStyle valueStyle = GoogleFonts.getFont(
    Design.entryFontFamily,
    fontSize: user.expandedTaskbar ? 12.5 : 11.5,
    fontStyle: Design.entryFontItalic ? FontStyle.italic : FontStyle.normal,
    fontWeight: FontWeight(Design.entryFontWeight),
    color: Design.text,
  );

  @override
  void initState() {
    super.initState();
    wUsage = _maxWidth(const <String>['100%', '0%'], valueStyle);
    wTemp = _maxWidth(const <String>['100°', '0°'], valueStyle);
    wRam = _maxWidth(const <String>['100%', '0%'], valueStyle);
    QuickMenuFunctions.addListener(this);
    if (QuickMenuFunctions.isQuickMenuVisible) unawaited(_refreshStats());
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    _statsTimer?.cancel();
    if (visible && type == QuickMenuPage.quickMenu) unawaited(_refreshStats());
  }

  Future<void> _refreshStats() {
    // Opening prefetches and widget refreshes share the same network request.
    return _refreshInFlight ??= _stats.refresh().then((_) {
      if (mounted && QuickMenuFunctions.isQuickMenuVisible) setState(() {});
    }).whenComplete(() {
      _refreshInFlight = null;
      if (!mounted || !QuickMenuFunctions.isQuickMenuVisible || Globals.quickMenuPage != QuickMenuPage.quickMenu)
        return;
      _statsTimer?.cancel();
      _statsTimer = Timer(_kRefreshInterval, () => unawaited(_refreshStats()));
    });
  }

  Future<void> _focusTaskManager() async {
    await TrayWatcher.fetchTray();
    final TrayBarInfo? info = TrayWatcher.trayList
        .where((TrayBarInfo element) => element.processExe == "LibreHardwareMonitor.exe")
        .firstOrNull;
    if (info == null) return;
    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_MOUSEACTIVATE);
    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONDOWN);
    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONUP);
    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONDBLCLK);
    PostMessage(info.hWnd, info.uCallbackMessage, info.uID, WM_LBUTTONUP);
  }

  double _measureText(String text, TextStyle style) {
    final TextPainter painter = TextPainter(
      text: TextSpan(text: text, style: style),
      maxLines: 1,
      textDirection: TextDirection.ltr,
    )..layout();
    return painter.size.width;
  }

  double _maxWidth(List<String> candidates, TextStyle style) =>
      candidates.map((String s) => _measureText(s, style)).reduce((double a, double b) => a > b ? a : b);

  /// A single fixed-width text cell.
  Widget _fixedCell(String text, double width, TextStyle style) {
    return SizedBox(
      width: width,
      child: Text(text, maxLines: 1, overflow: TextOverflow.clip, style: style),
    );
  }

  @override
  Widget build(BuildContext context) {
    final double height = user.expandedTaskbar ? 32 : 27;
    final Color onSurface = Design.text;

    // Fixed widths per column – measured once against the widest possible value.
    final double wCpuLbl = _measureText('CPU ', labelStyle);
    final double wRamLbl = _measureText('RAM ', labelStyle);
    final double wGpuLbl = _measureText('GPU ', labelStyle);

    // Small gap between usage and temp inside one chip.
    const double innerGap = 3;
    // Spacer between the three chips.
    const double chipGap = 6;

    final HardwareData? hardwareData = _stats.cached;
    final String cpuUsage = hardwareData == null ? '—' : '${hardwareData.cpuUsage.toStringAsFixed(0)}%';
    final String cpuTemp = hardwareData == null ? '—' : '${hardwareData.cpuTemp.toStringAsFixed(0)}°';
    final String ramUsage = hardwareData == null ? '—' : '${hardwareData.ramUsage.toStringAsFixed(0)}%';
    final String gpuUsage = hardwareData == null ? '—' : '${hardwareData.gpuUsage.toStringAsFixed(0)}%';
    final String gpuTemp = hardwareData == null ? '—' : '${hardwareData.gpuTemp.toStringAsFixed(0)}°';

    // Each chip: [label][usage][gap][temp]  or  [label][usage]
    Widget cpuChip = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        _fixedCell('CPU ', wCpuLbl, labelStyle),
        _fixedCell(cpuUsage, wUsage, valueStyle),
        const SizedBox(width: innerGap),
        _fixedCell(cpuTemp, wTemp, valueStyle),
      ],
    );

    Widget ramChip = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        _fixedCell('RAM ', wRamLbl, labelStyle),
        _fixedCell(ramUsage, wRam, valueStyle),
      ],
    );

    Widget gpuChip = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: <Widget>[
        _fixedCell('GPU ', wGpuLbl, labelStyle),
        _fixedCell(gpuUsage, wUsage, valueStyle),
        const SizedBox(width: innerGap),
        _fixedCell(gpuTemp, wTemp, valueStyle),
      ],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 7.0),
      child: Column(
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
                onTap: _focusTaskManager,
                borderRadius: BorderRadius.circular(10),
                hoverColor: Design.accent.withAlpha(10),
                splashColor: Colors.transparent,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(5, 3, 5, 3),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      Expanded(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: <Widget>[
                            cpuChip,
                            const SizedBox(width: chipGap),
                            ramChip,
                            const SizedBox(width: chipGap),
                            gpuChip,
                          ],
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
      ),
    );
  }
}
