import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/classes/boxes.dart';
import '../models/win32/win_utils.dart';

enum BrowserBridgePhase { disabled, starting, waiting, connected, error }

class BrowserBridgeStatus {
  const BrowserBridgeStatus({
    required this.enabled,
    required this.phase,
    required this.port,
    this.error = '',
    this.extensionVersion = '',
    this.browser = '',
    this.connectedAt,
  });

  final bool enabled;
  final BrowserBridgePhase phase;
  final int port;
  final String error;
  final String extensionVersion;
  final String browser;
  final DateTime? connectedAt;

  bool get running => phase == BrowserBridgePhase.waiting || phase == BrowserBridgePhase.connected;
  bool get connected => phase == BrowserBridgePhase.connected;

  Map<String, Object?> toJson({String? token}) => <String, Object?>{
        'enabled': enabled,
        'running': running,
        'connected': connected,
        'port': port,
        if (token != null) 'token': token,
        if (error.isNotEmpty) 'error': error,
        if (extensionVersion.isNotEmpty) 'extensionVersion': extensionVersion,
        if (browser.isNotEmpty) 'browser': browser,
        if (connectedAt != null) 'connectedAt': connectedAt!.toIso8601String(),
      };
}

class BrowserBridgeEvent {
  const BrowserBridgeEvent(this.name, this.data);

  final String name;
  final Map<String, Object?> data;
}

class _BrowserBridgeConfig {
  const _BrowserBridgeConfig({required this.token, required this.port});

  final String token;
  final int port;
}

class _PendingBrowserRequest {
  const _PendingBrowserRequest(this.completer, this.timer);

  final Completer<Object?> completer;
  final Timer timer;
}

/// App-owned bridge between the Chromium extension and launcher plugins.
///
/// The bridge is opt-in and lives for the lifetime of Tabame's QuickMenu
/// process. Plugins use the `browserBridge` host command instead of binding
/// their own WebSocket server, so opening or closing a plugin does not disturb
/// the extension connection.
class BrowserBridgeService {
  BrowserBridgeService._();

  static final BrowserBridgeService instance = BrowserBridgeService._();

  static const String settingKey = 'browserBridgeEnabled';
  static const int defaultPort = 17373;
  static const Duration _requestTimeout = Duration(seconds: 30);
  static const Set<String> allowedMethods = <String>{
    'bridge.ping',
    'tabs.list',
    'tabs.audible',
    'tabs.activate',
    'tabs.close',
    'tabs.mute',
    'tabs.pin',
    'tabs.reload',
    'tabs.duplicate',
    'tabs.open',
    'codex.usage',
  };

  final ValueNotifier<BrowserBridgeStatus> statusNotifier = ValueNotifier<BrowserBridgeStatus>(
    const BrowserBridgeStatus(
      enabled: false,
      phase: BrowserBridgePhase.disabled,
      port: defaultPort,
    ),
  );
  final StreamController<BrowserBridgeEvent> _events = StreamController<BrowserBridgeEvent>.broadcast(sync: true);
  final Map<String, _PendingBrowserRequest> _pending = <String, _PendingBrowserRequest>{};

  Stream<BrowserBridgeEvent> get events => _events.stream;
  BrowserBridgeStatus get status => statusNotifier.value;
  String get pairingToken => _config?.token ?? '';

  HttpServer? _server;
  WebSocket? _socket;
  _BrowserBridgeConfig? _config;
  Timer? _retryTimer;
  Map<String, String>? _clientInfo;
  bool _enabled = false;
  bool _starting = false;
  String _lastError = '';
  int _generation = 0;
  int _requestCounter = 0;

  Future<void> initialize() async {
    _enabled = Boxes.pref.getBool(settingKey) ?? false;
    _publishStatus();
    if (_enabled) await start();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) {
      if (enabled && _server == null && !_starting) await start();
      return;
    }
    _enabled = enabled;
    await Boxes.pref.setBool(settingKey, enabled);
    if (enabled) {
      await start();
    } else {
      await stop();
    }
  }

  Future<void> start() async {
    if (!_enabled || _server != null || _starting) return;
    final int generation = ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _starting = true;
    _lastError = '';
    _publishStatus();

    try {
      _config ??= _readOrCreateConfig();
      final HttpServer server = await HttpServer.bind(
        InternetAddress.loopbackIPv4,
        _config!.port,
        shared: false,
      );
      if (!_enabled || generation != _generation) {
        await server.close(force: true);
        return;
      }
      _server = server;
      _starting = false;
      _lastError = '';
      server.listen(
        _handleHttpRequest,
        onError: (Object error, StackTrace stack) {
          _lastError = error.toString();
          _publishStatus();
        },
      );
      _publishStatus();
    } catch (error) {
      if (generation != _generation) return;
      _starting = false;
      _lastError = error.toString();
      _publishStatus();
      _scheduleRetry();
    }
  }

  Future<void> stop() async {
    _generation++;
    _starting = false;
    _retryTimer?.cancel();
    _retryTimer = null;
    _lastError = '';

    final WebSocket? socket = _socket;
    _socket = null;
    _clientInfo = null;
    if (socket != null) {
      await socket.close(WebSocketStatus.goingAway, 'Browser bridge disabled');
    }

    final HttpServer? server = _server;
    _server = null;
    if (server != null) await server.close(force: true);
    _rejectPending('Browser bridge disabled');
    _publishStatus();
  }

  Future<Object?> request(
    String method, {
    Map<String, Object?> params = const <String, Object?>{},
    Duration timeout = _requestTimeout,
  }) {
    if (!allowedMethods.contains(method)) {
      return Future<Object?>.error(StateError('Unsupported browser bridge method: $method'));
    }
    if (!_enabled) {
      return Future<Object?>.error(
        StateError('The persistent browser connector is disabled in Launcher Plugins.'),
      );
    }
    final WebSocket? socket = _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      return Future<Object?>.error(StateError('Tabame Connector is not connected.'));
    }

    final String id = '${const Uuid().v4()}-${_requestCounter++}';
    final Completer<Object?> completer = Completer<Object?>();
    final Timer timer = Timer(timeout, () {
      final _PendingBrowserRequest? pending = _pending.remove(id);
      pending?.completer.completeError(TimeoutException('Browser request timed out: $method', timeout));
    });
    _pending[id] = _PendingBrowserRequest(completer, timer);
    socket.add(jsonEncode(<String, Object?>{
      'type': 'request',
      'id': id,
      'method': method,
      'params': params,
    }));
    return completer.future;
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    if (request.uri.path != '/tabame' || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final String origin = request.headers.value('origin') ?? '';
    if (!RegExp(r'^chrome-extension://[a-p]{32}/?$').hasMatch(origin)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    try {
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      _handleSocket(socket, origin);
    } catch (error) {
      _lastError = error.toString();
      _publishStatus();
    }
  }

  void _handleSocket(WebSocket socket, String origin) {
    bool authenticated = false;
    final Timer authTimer = Timer(const Duration(seconds: 5), () {
      if (!authenticated) socket.close(WebSocketStatus.policyViolation, 'Authentication timeout');
    });

    socket.listen(
      (dynamic raw) {
        final String text = raw is String ? raw : utf8.decode((raw as List<int>), allowMalformed: true);
        if (text.length > 256 * 1024) {
          socket.close(WebSocketStatus.messageTooBig, 'Message too large');
          return;
        }

        Map<String, dynamic> message;
        try {
          final Object? decoded = jsonDecode(text);
          if (decoded is! Map) throw const FormatException('JSON object required');
          message = decoded.cast<String, dynamic>();
        } catch (_) {
          socket.close(WebSocketStatus.unsupportedData, 'JSON required');
          return;
        }

        if (!authenticated) {
          final Object? token = message['token'];
          if (message['type'] != 'hello' ||
              message['protocol'] != 1 ||
              token is! String ||
              !_safeEqual(token.replaceAll(RegExp(r'\s+'), ''), _config!.token)) {
            socket.close(WebSocketStatus.policyViolation, 'Authentication failed');
            return;
          }

          authenticated = true;
          authTimer.cancel();
          final WebSocket? previous = _socket;
          _socket = socket;
          _clientInfo = <String, String>{
            'extensionVersion': '${message['extensionVersion'] ?? 'unknown'}',
            'browser': '${message['userAgent'] ?? 'unknown'}',
            'origin': origin,
            'connectedAt': DateTime.now().toUtc().toIso8601String(),
          };
          if (previous != null && previous != socket) {
            previous.close(1012, 'Replaced by a new connector session');
          }
          socket.add(jsonEncode(<String, Object?>{
            'type': 'welcome',
            'protocol': 1,
            'serverVersion': '0.2.0',
          }));
          _publishStatus();
          return;
        }

        _handleExtensionMessage(socket, message);
      },
      onDone: () {
        authTimer.cancel();
        if (_socket != socket) return;
        _socket = null;
        _clientInfo = null;
        _rejectPending('Browser connector disconnected');
        _publishStatus();
      },
      onError: (Object error, StackTrace stack) {
        if (_socket != socket) return;
        _lastError = error.toString();
        _publishStatus();
      },
      cancelOnError: false,
    );
  }

  void _handleExtensionMessage(WebSocket socket, Map<String, dynamic> message) {
    if (message['type'] == 'ping') {
      socket.add(jsonEncode(<String, Object?>{'type': 'pong', 'at': DateTime.now().millisecondsSinceEpoch}));
      return;
    }

    if (message['type'] == 'response' && message['id'] is String) {
      final _PendingBrowserRequest? pending = _pending.remove(message['id']);
      if (pending == null) return;
      pending.timer.cancel();
      if (message['ok'] == true) {
        pending.completer.complete(message['result']);
      } else {
        pending.completer.completeError(StateError('${message['error'] ?? 'Browser request failed'}'));
      }
      return;
    }

    if (message['type'] == 'event' && message['event'] is String) {
      final Object? rawData = message['data'];
      final Map<String, Object?> data = rawData is Map ? rawData.cast<String, Object?>() : <String, Object?>{};
      _events.add(BrowserBridgeEvent(message['event'] as String, data));
    }
  }

  void _scheduleRetry() {
    if (!_enabled || _retryTimer != null) return;
    _retryTimer = Timer(const Duration(seconds: 2), () {
      _retryTimer = null;
      unawaited(start());
    });
  }

  void _rejectPending(String message) {
    for (final _PendingBrowserRequest pending in _pending.values) {
      pending.timer.cancel();
      pending.completer.completeError(StateError(message));
    }
    _pending.clear();
  }

  _BrowserBridgeConfig _readOrCreateConfig() {
    final File shared = File('${WinUtils.getTabameAppDataFolder()}\\browser-bridge.json');
    final File legacy = File('${WinUtils.getPluginsFolder()}\\browser\\bridge-config.json');
    final _BrowserBridgeConfig? existing = _readConfig(shared) ?? _readConfig(legacy);
    final _BrowserBridgeConfig config = existing ??
        _BrowserBridgeConfig(
          token: base64Url.encode(List<int>.generate(32, (_) => Random.secure().nextInt(256))).replaceAll('=', ''),
          port: defaultPort,
        );
    if (_readConfig(shared) == null) {
      shared.parent.createSync(recursive: true);
      shared.writeAsStringSync(
        '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{
              'token': config.token,
              'port': config.port
            })}\n',
      );
    }
    return config;
  }

  static _BrowserBridgeConfig? _readConfig(File file) {
    try {
      final Object? decoded = jsonDecode(file.readAsStringSync());
      if (decoded is! Map) return null;
      final Object? token = decoded['token'];
      final int? port = decoded['port'] is num ? (decoded['port'] as num).toInt() : null;
      if (token is! String || token.length < 32 || port == null || port < 1024 || port > 65535) return null;
      return _BrowserBridgeConfig(token: token, port: port);
    } catch (_) {
      return null;
    }
  }

  static bool _safeEqual(String left, String right) {
    int difference = left.length ^ right.length;
    final int length = max(left.length, right.length);
    for (int index = 0; index < length; index++) {
      final int a = index < left.length ? left.codeUnitAt(index) : 0;
      final int b = index < right.length ? right.codeUnitAt(index) : 0;
      difference |= a ^ b;
    }
    return difference == 0;
  }

  void _publishStatus() {
    final Map<String, String>? client = _clientInfo;
    final BrowserBridgePhase phase;
    if (!_enabled) {
      phase = BrowserBridgePhase.disabled;
    } else if (_starting) {
      phase = BrowserBridgePhase.starting;
    } else if (_lastError.isNotEmpty && _server == null) {
      phase = BrowserBridgePhase.error;
    } else if (_socket != null) {
      phase = BrowserBridgePhase.connected;
    } else {
      phase = BrowserBridgePhase.waiting;
    }

    final BrowserBridgeStatus next = BrowserBridgeStatus(
      enabled: _enabled,
      phase: phase,
      port: _config?.port ?? defaultPort,
      error: _lastError,
      extensionVersion: client?['extensionVersion'] ?? '',
      browser: client?['browser'] ?? '',
      connectedAt: client?['connectedAt'] == null ? null : DateTime.tryParse(client!['connectedAt']!),
    );
    statusNotifier.value = next;
    _events.add(BrowserBridgeEvent('connection.changed', next.toJson()));
  }
}
