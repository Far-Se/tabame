import 'dart:math';

import 'package:http/http.dart' as http;

import '../models/classes/boxes.dart';
import '../platform/windows/tabamewin32_api.dart';

/// Session cache shared by prefetches and every LibreStats widget instance.
/// Refreshes are caller-driven; this service never starts a background timer.
class LibreStatsService {
  LibreStatsService._();

  static final LibreStatsService instance = LibreStatsService._();

  HardwareData? _cached;
  String? _configuredUrl;
  String? _workingUrl;
  DateTime? _lastFetched;
  Future<void>? _pending;

  HardwareData? get cached => Boxes.pref.getString('libreUrl') == _configuredUrl ? _cached : null;

  Future<void> refresh() {
    final String? url = Boxes.pref.getString('libreUrl');
    if (url != _configuredUrl) {
      _configuredUrl = url;
      _workingUrl = null;
      _cached = null;
      _lastFetched = null;
      _pending = null;
    }
    if (url == null || url.isEmpty) return Future<void>.value();
    final Future<void>? pending = _pending;
    if (pending != null) return pending;
    final DateTime? lastFetched = _lastFetched;
    if (lastFetched != null && DateTime.now().difference(lastFetched) < const Duration(seconds: 1)) {
      return Future<void>.value();
    }
    late final Future<void> request;
    request = _fetchStats(url).whenComplete(() {
      if (identical(_pending, request)) _pending = null;
    });
    _pending = request;
    return request;
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

  /// Builds the candidate fallback URLs using the configured port.
  List<String> _fallbackUrls(String url) {
    final Uri uri = Uri.tryParse(url) ?? Uri();
    final int port = uri.hasPort ? uri.port : 8085;
    return _fallbackHosts.map((String host) => 'http://$host:$port/').toList();
  }

  Future<void> _fetchStats(String configuredUrl) async {
    String baseUrl = _workingUrl ?? configuredUrl;
    String? body = await _fetchBody(baseUrl);

    // Configured URL failed – try the known fallback hosts on the same port.
    if (body == null) {
      for (final String candidate in _fallbackUrls(baseUrl)) {
        if (candidate == baseUrl) continue;
        final String? fallbackBody = await _fetchBody(candidate);
        if (fallbackBody != null) {
          baseUrl = candidate; // Switch in-memory only (not Boxes settings).
          body = fallbackBody;
          break;
        }
      }
    }

    if (body == null || configuredUrl != _configuredUrl) return;
    _workingUrl = baseUrl;

    final double gpuVideo = _extractByName(body, 'GPU Video Engine', type: 'Load');
    final double gpuCore = _extractByName(body, 'GPU Core', type: 'Load');
    _cached = HardwareData(
      cpuUsage: _extractByName(body, 'CPU Total', type: 'Load'),
      cpuTemp: _extractByName(body, 'CPU Package', type: 'Temperature'),
      ramUsage: _extractByName(body, 'Memory', type: 'Load'),
      gpuUsage: max(gpuCore, gpuVideo),
      gpuTemp: _extractByName(body, 'GPU Core', type: 'Temperature'),
    );
    _lastFetched = DateTime.now();
  }
}
