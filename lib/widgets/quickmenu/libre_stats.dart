import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/tray_watcher.dart';

class LibreStats extends StatefulWidget {
  final bool withTopDivider;
  final bool withBottomDivider;
  const LibreStats({super.key, this.withTopDivider = true, this.withBottomDivider = true});

  @override
  State<LibreStats> createState() => _LibreStatsState();
}

class _LibreStatsState extends State<LibreStats> {
  static const Duration _kRefreshInterval = Duration(seconds: 1);

  Timer? _statsTimer;
  HardwareData hardwareData = const HardwareData(cpuTemp: 0, cpuUsage: 0, ramUsage: 0, gpuUsage: 0, gpuTemp: 0);

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

  String? baseUrl;
  @override
  void initState() {
    super.initState();
    baseUrl = Boxes.pref.getString('libreUrl');
    wUsage = _maxWidth(const <String>['100%', '0%'], valueStyle);
    wTemp = _maxWidth(const <String>['100°', '0°'], valueStyle);
    wRam = _maxWidth(const <String>['100%', '0%'], valueStyle);
    _fetchStats();
    _startTimer();
  }

  @override
  void dispose() {
    _statsTimer?.cancel();
    super.dispose();
  }

  void _startTimer() {
    _statsTimer = Timer.periodic(_kRefreshInterval, (_) async {
      if (!mounted || !QuickMenuFunctions.isQuickMenuVisible) return;
      await _fetchStats();
      if (mounted) setState(() {});
    });
  }

  double _extractByName(String body, String text, {String? type}) {
    final String typeClause = type != null ? '(?=(?:[^}]){0,350}"Type"\\s*:\\s*"${RegExp.escape(type)}")' : '';
    final RegExp re = RegExp(
      '"Text"\\s*:\\s*"${RegExp.escape(text)}"'
      '$typeClause'
      r'(?:[^}]{0,350}?)"Value"\s*:\s*"([\d.]+)',
      dotAll: true,
    );
    final Match? m = re.firstMatch(body);
    if (m == null) return 0;
    return double.tryParse(m.group(1)!) ?? 0;
  }

  // Hosts to try (on the same port as the configured baseUrl) when the
  // configured baseUrl stops responding.
  static const List<String> _fallbackHosts = <String>[
    '192.168.100.73',
    '169.254.83.107',
    '172.21.128.1',
    '0.0.0.0',
  ];

  /// Fetches the LibreHardwareMonitor JSON from [url], returning the body on
  /// success or `null` on any failure (non-200, timeout, network error).
  Future<String?> _fetchBody(String url) async {
    try {
      final Uri uri = Uri.parse('$url${url.endsWith('/') ? '' : '/'}data.json');
      final http.Response response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode != 200) return null;
      return response.body;
    } catch (_) {
      return null;
    }
  }

  /// Builds the candidate fallback URLs using the port from [baseUrl].
  List<String> _fallbackUrls(String url) {
    final Uri uri = Uri.tryParse(url) ?? Uri();
    final int port = uri.hasPort ? uri.port : 8085;
    return _fallbackHosts.map((String host) => 'http://$host:$port/').toList();
  }

  Future<void> _fetchStats() async {
    if (baseUrl == null) return;
    if (baseUrl == "") return;

    String? body = await _fetchBody(baseUrl!);

    // Configured URL failed — try the known fallback hosts on the same port.
    if (body == null) {
      for (final String candidate in _fallbackUrls(baseUrl!)) {
        if (candidate == baseUrl) continue;
        final String? fallbackBody = await _fetchBody(candidate);
        if (fallbackBody != null) {
          baseUrl = candidate; // Switch in-memory only (not Boxes settings).
          body = fallbackBody;
          break;
        }
      }
    }

    if (body == null) return; // Nothing reachable — keep last known values.

    // SensorId constants — adjust if your hardware uses different paths.
    final double gpuVideo = _extractByName(body, 'GPU Video Engine', type: 'Load');
    final double gpuCore = _extractByName(body, 'GPU Core', type: 'Load');
    hardwareData = HardwareData(
      cpuUsage: _extractByName(body, 'CPU Total', type: 'Load'),
      cpuTemp: _extractByName(body, 'CPU Package', type: 'Temperature'),
      ramUsage: _extractByName(body, 'Memory', type: 'Load'),
      gpuUsage: max(gpuCore, gpuVideo),
      gpuTemp: _extractByName(body, 'GPU Core', type: 'Temperature'),
    );
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

    // Fixed widths per column — measured once against the widest possible value.
    final double wCpuLbl = _measureText('CPU ', labelStyle);
    final double wRamLbl = _measureText('RAM ', labelStyle);
    final double wGpuLbl = _measureText('GPU ', labelStyle);

    // Small gap between usage and temp inside one chip.
    const double innerGap = 3;
    // Spacer between the three chips.
    const double chipGap = 6;

    final String cpuUsage = '${hardwareData.cpuUsage.toStringAsFixed(0)}%';
    final String cpuTemp = '${hardwareData.cpuTemp.toStringAsFixed(0)}°';
    final String ramUsage = '${hardwareData.ramUsage.toStringAsFixed(0)}%';
    final String gpuUsage = '${hardwareData.gpuUsage.toStringAsFixed(0)}%';
    final String gpuTemp = '${hardwareData.gpuTemp.toStringAsFixed(0)}°';

    // Each chip: [label][usage][gap][temp]  or  [label][usage]
    Widget cpuChip = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _fixedCell('CPU ', wCpuLbl, labelStyle),
        _fixedCell(cpuUsage, wUsage, valueStyle),
        const SizedBox(width: innerGap),
        _fixedCell(cpuTemp, wTemp, valueStyle),
      ],
    );

    Widget ramChip = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        _fixedCell('RAM ', wRamLbl, labelStyle),
        _fixedCell(ramUsage, wRam, valueStyle),
      ],
    );

    Widget gpuChip = Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
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
