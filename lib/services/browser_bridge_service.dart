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
        'phase': phase.name,
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

  static BrowserBridgeStatus fromJson(Map<String, dynamic> json) {
    BrowserBridgePhase? phase;
    final Object? rawPhase = json['phase'];
    if (rawPhase is String) {
      for (final BrowserBridgePhase candidate in BrowserBridgePhase.values) {
        if (candidate.name == rawPhase) {
          phase = candidate;
          break;
        }
      }
    }
    phase ??= json['enabled'] != true
        ? BrowserBridgePhase.disabled
        : json['connected'] == true
            ? BrowserBridgePhase.connected
            : json['error'] is String && (json['error'] as String).isNotEmpty
                ? BrowserBridgePhase.error
                : BrowserBridgePhase.waiting;

    final Object? rawPort = json['port'];
    final Object? rawConnectedAt = json['connectedAt'];
    return BrowserBridgeStatus(
      enabled: json['enabled'] == true,
      phase: phase,
      port: rawPort is num ? rawPort.toInt() : 17373,
      error: json['error'] is String ? json['error'] as String : '',
      extensionVersion: json['extensionVersion'] is String ? json['extensionVersion'] as String : '',
      browser: json['browser'] is String ? json['browser'] as String : '',
      connectedAt: rawConnectedAt is String ? DateTime.tryParse(rawConnectedAt) : null,
    );
  }
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
  const _PendingBrowserRequest({
    required this.completer,
    required this.timer,
    this.responseSocket,
  });

  final Completer<Object?>? completer;
  final Timer timer;
  final WebSocket? responseSocket;
}

/// App-owned bridge between browser extensions and launcher plugins.
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
  static const String _launcherOrigin = 'http://127.0.0.1';
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
    'javascript.execute',
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
  final Set<WebSocket> _launcherSockets = <WebSocket>{};

  Stream<BrowserBridgeEvent> get events => _events.stream;
  BrowserBridgeStatus get status => statusNotifier.value;
  String get pairingToken => _config?.token ?? '';

  HttpServer? _server;
  WebSocket? _socket;
  WebSocket? _proxySocket;
  _BrowserBridgeConfig? _config;
  Timer? _retryTimer;
  Map<String, String>? _clientInfo;
  BrowserBridgeStatus? _remoteStatus;
  bool _launcherClient = false;
  bool _enabled = false;
  bool _starting = false;
  String _lastError = '';
  int _generation = 0;
  int _requestCounter = 0;

  Future<void> initialize({bool asLauncherClient = false}) async {
    _launcherClient = asLauncherClient;
    _enabled = Boxes.pref.getBool(settingKey) ?? false;
    _publishStatus();
    if (_enabled) await start();
  }

  Future<void> setEnabled(bool enabled) async {
    if (_enabled == enabled) {
      if (enabled && !_transportRunning && !_starting) await start();
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

  bool get _transportRunning => _launcherClient ? _proxySocket != null : _server != null;

  Future<void> start() async {
    if (!_enabled || _transportRunning || _starting) return;
    if (_launcherClient) {
      await _startLauncherClient();
      return;
    }

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

  Future<void> _startLauncherClient() async {
    final int generation = ++_generation;
    _retryTimer?.cancel();
    _retryTimer = null;
    _starting = true;
    _lastError = '';
    _remoteStatus = null;
    _publishStatus();

    try {
      _config ??= _readOrCreateConfig();
      final WebSocket socket = await WebSocket.connect(
        'ws://127.0.0.1:${_config!.port}/tabame/launcher',
        headers: <String, dynamic>{'origin': 'http://127.0.0.1'},
      );
      if (!_enabled || generation != _generation) {
        await socket.close(WebSocketStatus.goingAway, 'Launcher bridge stopped');
        return;
      }

      _proxySocket = socket;
      _starting = false;
      _lastError = '';
      socket.listen(
        (dynamic raw) => _handleProxyMessage(socket, raw),
        onDone: () => _handleProxyDone(socket),
        onError: (Object error, StackTrace stack) {
          if (_proxySocket != socket) return;
          _lastError = error.toString();
          _publishStatus();
        },
        cancelOnError: false,
      );
      _sendSocketMessage(socket, <String, Object?>{
        'type': 'hello',
        'token': _config!.token,
        'protocol': 1,
        'client': 'launcher',
      });
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

    final WebSocket? proxySocket = _proxySocket;
    _proxySocket = null;
    _remoteStatus = null;
    if (proxySocket != null) {
      await proxySocket.close(WebSocketStatus.goingAway, 'Browser bridge disabled');
    }

    final List<WebSocket> launcherSockets = _launcherSockets.toList(growable: false);
    _launcherSockets.clear();
    for (final WebSocket launcherSocket in launcherSockets) {
      _rejectPendingForSocket(launcherSocket);
      await launcherSocket.close(WebSocketStatus.goingAway, 'Browser bridge disabled');
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
    final WebSocket? socket = _launcherClient ? _proxySocket : _socket;
    if (socket == null || socket.readyState != WebSocket.open) {
      return Future<Object?>.error(StateError('Tabame Connector is not connected.'));
    }

    final String id = '${const Uuid().v4()}-${_requestCounter++}';
    final Completer<Object?> completer = Completer<Object?>();
    final Timer timer = Timer(timeout, () {
      final _PendingBrowserRequest? pending = _pending.remove(id);
      if (pending == null) return;
      _completePendingError(
        id,
        pending,
        TimeoutException('Browser request timed out: $method', timeout),
      );
    });
    _pending[id] = _PendingBrowserRequest(completer: completer, timer: timer);
    final bool sent = _sendSocketMessage(socket, <String, Object?>{
      'type': 'request',
      'id': id,
      'method': method,
      'params': params,
      'timeoutMs': timeout.inMilliseconds,
    });
    if (!sent) {
      final _PendingBrowserRequest? pending = _pending.remove(id);
      if (pending != null) {
        pending.timer.cancel();
        pending.completer?.completeError(StateError('Tabame Connector is not connected.'));
      }
    }
    return completer.future;
  }

  Future<void> _handleHttpRequest(HttpRequest request) async {
    final bool isExtensionRequest = request.uri.path == '/tabame';
    final bool isLauncherRequest = request.uri.path == '/tabame/launcher';
    if ((!isExtensionRequest && !isLauncherRequest) || !WebSocketTransformer.isUpgradeRequest(request)) {
      request.response.statusCode = HttpStatus.notFound;
      await request.response.close();
      return;
    }

    final String origin = request.headers.value('origin') ?? '';
    final bool validExtensionOrigin = RegExp(
      r'^(?:chrome-extension://[a-p]{32}|moz-extension://[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12})/?$',
    ).hasMatch(origin);
    if ((isExtensionRequest && !validExtensionOrigin) || (isLauncherRequest && origin != _launcherOrigin)) {
      request.response.statusCode = HttpStatus.forbidden;
      await request.response.close();
      return;
    }

    try {
      final WebSocket socket = await WebSocketTransformer.upgrade(request);
      _handleSocket(socket, origin, launcherClient: isLauncherRequest);
    } catch (error) {
      if (isExtensionRequest) {
        _lastError = error.toString();
        _publishStatus();
      }
    }
  }

  void _handleSocket(WebSocket socket, String origin, {required bool launcherClient}) {
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
          final bool validClient = launcherClient ? message['client'] == 'launcher' : message['client'] != 'launcher';
          if (message['type'] != 'hello' ||
              message['protocol'] != 1 ||
              !validClient ||
              token is! String ||
              !_safeEqual(token.replaceAll(RegExp(r'\s+'), ''), _config!.token)) {
            socket.close(WebSocketStatus.policyViolation, 'Authentication failed');
            return;
          }

          authenticated = true;
          authTimer.cancel();
          if (launcherClient) {
            _launcherSockets.add(socket);
            _sendSocketMessage(socket, <String, Object?>{
              'type': 'welcome',
              'protocol': 1,
              'role': 'launcher',
              'serverVersion': '0.2.0',
              'status': _buildStatus().toJson(),
            });
            return;
          }

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

        if (launcherClient) {
          _handleLauncherMessage(socket, message);
        } else {
          _handleExtensionMessage(socket, message);
        }
      },
      onDone: () {
        authTimer.cancel();
        if (launcherClient) {
          if (_launcherSockets.remove(socket)) _rejectPendingForSocket(socket);
          return;
        }
        if (_socket != socket) return;
        _socket = null;
        _clientInfo = null;
        _rejectPending('Browser connector disconnected');
        _publishStatus();
      },
      onError: (Object error, StackTrace stack) {
        if (launcherClient) return;
        if (_socket != socket) return;
        _lastError = error.toString();
        _publishStatus();
      },
      cancelOnError: false,
    );
  }

  void _handleLauncherMessage(WebSocket socket, Map<String, dynamic> message) {
    if (message['type'] == 'ping') {
      _sendSocketMessage(socket, <String, Object?>{'type': 'pong', 'at': DateTime.now().millisecondsSinceEpoch});
      return;
    }
    if (message['type'] != 'request') return;

    final Object? rawId = message['id'];
    final Object? rawMethod = message['method'];
    if (rawId is! String || rawId.isEmpty || rawMethod is! String || rawMethod.isEmpty) {
      _sendResponse(socket, rawId is String ? rawId : '',
          ok: false, error: 'Browser request requires an id and method');
      return;
    }
    if (!allowedMethods.contains(rawMethod)) {
      _sendResponse(socket, rawId, ok: false, error: 'Unsupported browser bridge method: $rawMethod');
      return;
    }
    if (_pending.containsKey(rawId)) {
      _sendResponse(socket, rawId, ok: false, error: 'Duplicate browser request id');
      return;
    }

    final WebSocket? extensionSocket = _socket;
    if (extensionSocket == null || extensionSocket.readyState != WebSocket.open) {
      _sendResponse(socket, rawId, ok: false, error: 'Tabame Connector is not connected.');
      return;
    }

    final Object? rawParams = message['params'];
    final Map<String, Object?> params =
        rawParams is Map ? rawParams.cast<String, Object?>() : const <String, Object?>{};
    final Object? rawTimeout = message['timeoutMs'];
    final int timeoutMs = (rawTimeout is num ? rawTimeout.toInt() : _requestTimeout.inMilliseconds).clamp(1000, 60000);
    final Timer timer = Timer(Duration(milliseconds: timeoutMs), () {
      final _PendingBrowserRequest? pending = _pending.remove(rawId);
      if (pending == null) return;
      _completePendingError(rawId, pending, TimeoutException('Browser request timed out: $rawMethod'));
    });
    final _PendingBrowserRequest pending = _PendingBrowserRequest(
      completer: null,
      timer: timer,
      responseSocket: socket,
    );
    _pending[rawId] = pending;

    final bool sent = _sendSocketMessage(extensionSocket, <String, Object?>{
      'type': 'request',
      'id': rawId,
      'method': rawMethod,
      'params': params,
      'timeoutMs': timeoutMs,
    });
    if (!sent) {
      _pending.remove(rawId);
      timer.cancel();
      _completePendingError(rawId, pending, StateError('Tabame Connector is not connected.'));
    }
  }

  void _handleExtensionMessage(WebSocket socket, Map<String, dynamic> message) {
    if (message['type'] == 'ping') {
      _sendSocketMessage(socket, <String, Object?>{'type': 'pong', 'at': DateTime.now().millisecondsSinceEpoch});
      return;
    }

    if (message['type'] == 'response' && message['id'] is String) {
      _completePendingResponse(message['id'] as String, message);
      return;
    }

    if (message['type'] == 'event' && message['event'] is String) {
      final Object? rawData = message['data'];
      final Map<String, Object?> data = rawData is Map ? rawData.cast<String, Object?>() : <String, Object?>{};
      _emitEvent(BrowserBridgeEvent(message['event'] as String, data));
    }
  }

  void _handleProxyMessage(WebSocket socket, dynamic raw) {
    if (_proxySocket != socket) return;

    final String text = raw is String ? raw : utf8.decode((raw as List<int>), allowMalformed: true);
    if (text.length > 256 * 1024) {
      socket.close(WebSocketStatus.messageTooBig, 'Message too large');
      return;
    }

    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (_) {
      socket.close(WebSocketStatus.unsupportedData, 'JSON required');
      return;
    }
    if (decoded is! Map) {
      socket.close(WebSocketStatus.unsupportedData, 'JSON object required');
      return;
    }
    final Map<String, dynamic> message = decoded.cast<String, dynamic>();

    if (message['type'] == 'welcome' || message['type'] == 'status') {
      final Object? rawStatus = message['status'];
      if (rawStatus is Map) {
        _remoteStatus = BrowserBridgeStatus.fromJson(rawStatus.cast<String, dynamic>());
        _lastError = '';
        _publishStatus();
      }
      return;
    }
    if (message['type'] == 'ping') {
      _sendSocketMessage(socket, <String, Object?>{'type': 'pong', 'at': DateTime.now().millisecondsSinceEpoch});
      return;
    }
    if (message['type'] == 'response' && message['id'] is String) {
      _completePendingResponse(message['id'] as String, message);
      return;
    }
    if (message['type'] == 'event' && message['event'] is String) {
      final Object? rawData = message['data'];
      final Map<String, Object?> data = rawData is Map ? rawData.cast<String, Object?>() : <String, Object?>{};
      _events.add(BrowserBridgeEvent(message['event'] as String, data));
    }
  }

  void _handleProxyDone(WebSocket socket) {
    if (_proxySocket != socket) return;
    _proxySocket = null;
    _remoteStatus = null;
    _rejectPending('Browser connector disconnected');
    if (_enabled) _lastError = 'The primary Tabame bridge disconnected.';
    _publishStatus();
    _scheduleRetry();
  }

  void _completePendingResponse(String id, Map<String, dynamic> message) {
    final _PendingBrowserRequest? pending = _pending.remove(id);
    if (pending == null) return;
    pending.timer.cancel();

    final WebSocket? responseSocket = pending.responseSocket;
    if (responseSocket != null) {
      _sendResponse(
        responseSocket,
        id,
        ok: message['ok'] == true,
        result: message['result'],
        error: message['ok'] == true ? null : '${message['error'] ?? 'Browser request failed'}',
      );
      return;
    }

    final Completer<Object?>? completer = pending.completer;
    if (completer == null || completer.isCompleted) return;
    if (message['ok'] == true) {
      completer.complete(message['result']);
    } else {
      completer.completeError(StateError('${message['error'] ?? 'Browser request failed'}'));
    }
  }

  void _completePendingError(String id, _PendingBrowserRequest pending, Object error) {
    pending.timer.cancel();
    final WebSocket? responseSocket = pending.responseSocket;
    if (responseSocket != null) {
      _sendResponse(responseSocket, id, ok: false, error: error.toString());
      return;
    }
    final Completer<Object?>? completer = pending.completer;
    if (completer != null && !completer.isCompleted) completer.completeError(error);
  }

  void _rejectPending(String message) {
    final List<MapEntry<String, _PendingBrowserRequest>> pending = _pending.entries.toList(growable: false);
    _pending.clear();
    for (final MapEntry<String, _PendingBrowserRequest> entry in pending) {
      _completePendingError(entry.key, entry.value, StateError(message));
    }
  }

  void _rejectPendingForSocket(WebSocket socket) {
    final List<String> ids = _pending.entries
        .where((MapEntry<String, _PendingBrowserRequest> entry) => entry.value.responseSocket == socket)
        .map((MapEntry<String, _PendingBrowserRequest> entry) => entry.key)
        .toList(growable: false);
    for (final String id in ids) {
      final _PendingBrowserRequest? pending = _pending.remove(id);
      if (pending != null) pending.timer.cancel();
    }
  }

  bool _sendSocketMessage(WebSocket socket, Map<String, Object?> message) {
    if (socket.readyState != WebSocket.open) return false;
    try {
      socket.add(jsonEncode(message));
      return true;
    } catch (_) {
      return false;
    }
  }

  void _sendResponse(
    WebSocket socket,
    String id, {
    required bool ok,
    Object? result,
    String? error,
  }) {
    _sendSocketMessage(socket, <String, Object?>{
      'type': 'response',
      'id': id,
      'ok': ok,
      if (ok) 'result': result,
      if (!ok) 'error': error ?? 'Browser request failed',
    });
  }

  void _scheduleRetry() {
    if (!_enabled || _retryTimer != null) return;
    _retryTimer = Timer(const Duration(seconds: 2), () {
      _retryTimer = null;
      unawaited(start());
    });
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

  BrowserBridgeStatus _buildStatus() {
    if (_launcherClient) {
      final BrowserBridgeStatus? remote = _remoteStatus;
      if (remote != null && _proxySocket != null) return remote;

      final BrowserBridgePhase phase;
      if (!_enabled) {
        phase = BrowserBridgePhase.disabled;
      } else if (_starting) {
        phase = BrowserBridgePhase.starting;
      } else if (_lastError.isNotEmpty && _proxySocket == null) {
        phase = BrowserBridgePhase.error;
      } else {
        phase = BrowserBridgePhase.waiting;
      }
      return BrowserBridgeStatus(
        enabled: _enabled,
        phase: phase,
        port: _config?.port ?? defaultPort,
        error: _lastError,
      );
    }

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
    return next;
  }

  void _emitEvent(BrowserBridgeEvent event) {
    _events.add(event);
    // Connection status has its own internal message so launcher proxies can
    // replace their local status without receiving the same event twice.
    if (_launcherClient || event.name == 'connection.changed') return;
    for (final WebSocket socket in _launcherSockets.toList(growable: false)) {
      _sendSocketMessage(socket, <String, Object?>{
        'type': 'event',
        'event': event.name,
        'data': event.data,
      });
    }
  }

  void _publishStatus() {
    final BrowserBridgeStatus next = _buildStatus();
    statusNotifier.value = next;
    _emitEvent(BrowserBridgeEvent('connection.changed', next.toJson()));
    if (_launcherClient) return;
    for (final WebSocket socket in _launcherSockets.toList(growable: false)) {
      _sendSocketMessage(socket, <String, Object?>{
        'type': 'status',
        'status': next.toJson(),
      });
    }
  }
}
