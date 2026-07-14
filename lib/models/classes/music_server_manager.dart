import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';

import '../../services/music_local_indexer.dart';
import '../db/music_library_db.dart';
import '../win32/win_utils.dart';
import 'music_server.dart';

class MusicServerManager {
  static const String localSourceId = 'local';
  static const String localSourceName = 'Local';
  static const Duration _maxSongDuration = Duration(hours: 24);

  static String get _filePath => "${WinUtils.getTabameAppDataFolder(settings: true)}\\music_servers.json";
  static String get _activeSourcePath => "${WinUtils.getTabameAppDataFolder(settings: true)}\\music_active_source.txt";
  static String get _queueFilePath =>
      "${WinUtils.getTabameAppDataFolder()}\\cache${kDebugMode ? "\\debug" : ""}\\music_queue.json";

  static List<MusicServerConfig> _configs = <MusicServerConfig>[];
  static String? _activeConfigId;
  static bool _isConnected = false;

  /// Human-readable reason the last [setActiveServer] attempt failed, or null on
  /// success. Surfaced to the user so a broken Subsonic/Jellyfin connection can
  /// explain itself instead of silently returning an empty library.
  static String? lastConnectionError;
  static final AudioPlayer player = AudioPlayer();
  static List<MusicItem> _queue = <MusicItem>[];
  static bool _listenersSetup = false;
  static String? _lastRecordedLocalPlayKey;
  static final ValueNotifier<bool> shuffleEnabledNotifier = ValueNotifier<bool>(false);

  // Playback preferences (persisted across restarts in a manager-owned prefs file
  // rather than the shared settings.json, so frequent slider writes stay isolated).
  static const double minSpeed = 0.5;
  static const double maxSpeed = 2.0;
  static final ValueNotifier<double> volumeNotifier = ValueNotifier<double>(1.0);
  static final ValueNotifier<double> speedNotifier = ValueNotifier<double>(1.0);
  static double _volumeBeforeMute = 1.0;
  static Timer? _prefsSaveDebounce;

  // Sleep timer state. Kept in the manager so it survives the QuickMenu closing.
  static Timer? _sleepTimer;
  static Timer? _sleepTicker;
  static DateTime? _sleepEndsAt;
  static bool _sleepEndOfTrack = false;
  static StreamSubscription<int?>? _sleepIndexSub;
  static StreamSubscription<ProcessingState>? _sleepProcSub;
  static final ValueNotifier<Duration?> sleepRemainingNotifier = ValueNotifier<Duration?>(null);

  static String get _playbackPrefsPath =>
      "${WinUtils.getTabameAppDataFolder(settings: true)}\\music_playback_prefs.json";

  static List<MusicServerConfig> get configs => _configs;
  static String? get activeConfigId => _activeConfigId;
  static bool get isConnected => _isConnected;
  static bool get isLocalActive => _activeConfigId == localSourceId;
  static List<MusicItem> get queue => List<MusicItem>.unmodifiable(_queue);
  static bool get shuffleEnabled => shuffleEnabledNotifier.value;
  static bool get sleepTimerActive => _sleepEndsAt != null || _sleepEndOfTrack;
  static bool get sleepEndOfTrack => _sleepEndOfTrack;

  static Future<void> setShuffleEnabled(bool enabled) async {
    shuffleEnabledNotifier.value = enabled;
    await player.setShuffleModeEnabled(enabled);
  }

  // Volume / mute -------------------------------------------------------------

  static Future<void> setVolume(double volume) async {
    final double v = volume.clamp(0.0, 1.0);
    volumeNotifier.value = v;
    try {
      await player.setVolume(v);
    } catch (e) {
      debugPrint("MusicServerManager.setVolume error: $e");
    }
    _savePlaybackPrefsDebounced();
  }

  static Future<void> nudgeVolume(double delta) => setVolume(volumeNotifier.value + delta);

  /// Toggles between silence and the last non-zero volume.
  static Future<void> toggleMute() async {
    if (volumeNotifier.value > 0) {
      _volumeBeforeMute = volumeNotifier.value;
      await setVolume(0);
    } else {
      await setVolume(_volumeBeforeMute <= 0 ? 1.0 : _volumeBeforeMute);
    }
  }

  // Playback speed ------------------------------------------------------------

  static Future<void> setSpeed(double speed) async {
    final double s = speed.clamp(minSpeed, maxSpeed);
    speedNotifier.value = s;
    try {
      await player.setSpeed(s);
    } catch (e) {
      debugPrint("MusicServerManager.setSpeed error: $e");
    }
    _savePlaybackPrefsDebounced();
  }

  // Prefs persistence ---------------------------------------------------------

  static Future<void> _loadPlaybackPrefs() async {
    try {
      final File file = File(_playbackPrefsPath);
      if (!file.existsSync()) return;
      final dynamic decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return;
      final double volume = (decoded['volume'] as num?)?.toDouble() ?? 1.0;
      final double speed = (decoded['speed'] as num?)?.toDouble() ?? 1.0;
      volumeNotifier.value = volume.clamp(0.0, 1.0);
      speedNotifier.value = speed.clamp(minSpeed, maxSpeed);
      _volumeBeforeMute = volumeNotifier.value > 0 ? volumeNotifier.value : 1.0;
    } catch (e) {
      debugPrint("MusicServerManager._loadPlaybackPrefs error: $e");
    }
  }

  static void _savePlaybackPrefsDebounced() {
    _prefsSaveDebounce?.cancel();
    _prefsSaveDebounce = Timer(const Duration(milliseconds: 600), () => unawaited(_savePlaybackPrefs()));
  }

  static Future<void> _savePlaybackPrefs() async {
    try {
      final File file = File(_playbackPrefsPath);
      if (!file.existsSync()) await file.create(recursive: true);
      await file.writeAsString(jsonEncode(<String, dynamic>{
        'volume': volumeNotifier.value,
        'speed': speedNotifier.value,
      }));
    } catch (e) {
      debugPrint("MusicServerManager._savePlaybackPrefs error: $e");
    }
  }

  // Sleep timer ---------------------------------------------------------------

  /// Pauses playback after [duration] elapses, counting down every second.
  static void startSleepTimer(Duration duration) {
    cancelSleepTimer();
    if (duration <= Duration.zero) return;
    _sleepEndsAt = DateTime.now().add(duration);
    sleepRemainingNotifier.value = duration;
    _sleepTimer = Timer(duration, _fireSleep);
    _sleepTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      final DateTime? endsAt = _sleepEndsAt;
      if (endsAt == null) return;
      final Duration remaining = endsAt.difference(DateTime.now());
      sleepRemainingNotifier.value = remaining.isNegative ? Duration.zero : remaining;
    });
  }

  /// Pauses playback once the current track finishes.
  static void startSleepAtEndOfTrack() {
    cancelSleepTimer();
    _sleepEndOfTrack = true;
    sleepRemainingNotifier.value = null;
    final int startIndex = player.currentIndex ?? 0;
    _sleepIndexSub = player.currentIndexStream.listen((int? index) {
      if (index != null && index != startIndex) _fireSleep();
    });
    _sleepProcSub = player.processingStateStream.listen((ProcessingState state) {
      if (state == ProcessingState.completed) _fireSleep();
    });
  }

  static void _fireSleep() {
    cancelSleepTimer();
    unawaited(player.pause());
  }

  static void cancelSleepTimer() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepTicker?.cancel();
    _sleepTicker = null;
    unawaited(_sleepIndexSub?.cancel());
    _sleepIndexSub = null;
    unawaited(_sleepProcSub?.cancel());
    _sleepProcSub = null;
    _sleepEndsAt = null;
    _sleepEndOfTrack = false;
    sleepRemainingNotifier.value = null;
  }

  // just_audio_windows drops shuffle mode on track navigation/queue reload; reassert our
  // desired state so the toggle stays persistent instead of silently reverting.
  static Future<void> _reapplyShuffleMode() async {
    if (shuffleEnabledNotifier.value && !player.shuffleModeEnabled) {
      await player.setShuffleModeEnabled(true);
    }
  }

  static Future<bool> get hasSavedQueue async {
    final File file = File(_queueFilePath);
    if (!file.existsSync()) return false;
    try {
      final String content = await file.readAsString();
      final dynamic decoded = jsonDecode(content);
      // ignore: always_specify_types
      return decoded is Map<String, dynamic> && decoded['songIds'] is List && (decoded['songIds'] as List).isNotEmpty;
    } catch (_) {
      return false;
    }
  }

  static bool wasInitiated = false;
  static Future<void> init() async {
    await loadConfigs();
    final String? savedSourceId = await _loadActiveSourceId();
    if (savedSourceId == localSourceId) {
      await setLocalActive();
    } else if (_configs.isNotEmpty) {
      final MusicServerConfig? savedConfig =
          savedSourceId == null ? null : _configs.firstWhereOrNull((MusicServerConfig e) => e.id == savedSourceId);
      final MusicServerConfig def =
          savedConfig ?? _configs.firstWhere((MusicServerConfig e) => e.isDefault, orElse: () => _configs.first);
      await setActiveServer(def);
    }
    _setupPlayerListeners();
    await _loadPlaybackPrefs();
    try {
      await player.setVolume(volumeNotifier.value);
      await player.setSpeed(speedNotifier.value);
    } catch (e) {
      debugPrint("MusicServerManager.init apply prefs error: $e");
    }
    wasInitiated = true;
  }

  static void _setupPlayerListeners() {
    if (_listenersSetup) return;
    _listenersSetup = true;
    player.currentIndexStream.listen((int? index) {
      if (index != null) {
        _updateCacheIndex(index);
        _recordLocalPlayForIndex(index);
        unawaited(_reapplyShuffleMode());
      }
    });
  }

  static void _updateCacheIndex(int index) {
    try {
      final File file = File(_queueFilePath);
      if (!file.existsSync()) return;
      final String content = file.readAsStringSync();
      // Use regex to replace currentIndex value without full decode/encode
      final String updated = content.replaceFirst(RegExp(r'"currentIndex":\s*\d+'), '"currentIndex":$index');
      if (updated != content) {
        file.writeAsStringSync(updated);
      }
    } catch (e) {
      debugPrint("MusicServerManager._updateCacheIndex error: $e");
    }
  }

  static Future<List<MusicServerConfig>> loadConfigs() async {
    final File file = File(_filePath);
    if (!file.existsSync()) return <MusicServerConfig>[];
    try {
      final String content = await file.readAsString();
      final List<dynamic> decoded = jsonDecode(content);
      _configs = decoded.map((dynamic e) => MusicServerConfig.fromMap(e as Map<String, dynamic>)).toList();
      return _configs;
    } catch (_) {
      return <MusicServerConfig>[];
    }
  }

  static Future<void> saveConfigs() async {
    final File file = File(_filePath);
    if (!file.existsSync()) await file.create(recursive: true);
    await file.writeAsString(jsonEncode(_configs.map((MusicServerConfig e) => e.toMap()).toList()));
  }

  static Future<bool> saveCurrentQueue() async {
    final List<MusicItem> items = _currentPlaybackQueue();
    if (items.isEmpty || _activeConfigId == null) return false;
    final File file = File(_queueFilePath);
    if (!file.existsSync()) await file.create(recursive: true);
    await file.writeAsString(jsonEncode(<String, dynamic>{
      'serverId': _activeConfigId,
      'currentIndex': player.currentIndex ?? 0,
      'songIds': items.map((MusicItem item) => item.id).toList(growable: false),
      'snapshot': items.map((MusicItem item) => item.toMap()).toList(growable: false),
      'savedAt': DateTime.now().toIso8601String(),
    }));
    return true;
  }

  static Future<bool> restoreSavedQueue({bool play = false, bool replaceExisting = false}) async {
    if (!replaceExisting && (_queue.isNotEmpty || player.sequence.isNotEmpty == true)) return false;

    final File file = File(_queueFilePath);
    if (!file.existsSync() || _activeConfigId == null) return false;

    try {
      final String content = await file.readAsString();
      final dynamic decoded = jsonDecode(content);
      if (decoded is! Map<String, dynamic>) return false;
      if (decoded['serverId'] != _activeConfigId) return false;

      final List<dynamic>? rawIds = decoded['songIds'] as List<dynamic>?;
      if (rawIds == null || rawIds.isEmpty) return false;

      // Fast path: restore directly from the saved snapshot without network/DB round-trips.
      final List<dynamic>? snapshot = decoded['snapshot'] as List<dynamic>?;
      List<MusicItem> restored = <MusicItem>[];
      if (snapshot != null && snapshot.length == rawIds.length) {
        for (final dynamic raw in snapshot) {
          if (raw is Map<String, dynamic>) {
            final MusicItem item = MusicItem.fromMap(raw);
            if (item.streamUrl != null) restored.add(item);
          }
        }
      }

      // Slow path fallback: fetch each song individually (e.g. snapshot missing or corrupt).
      if (restored.isEmpty) {
        for (final dynamic rawId in rawIds) {
          final String songId = rawId.toString();
          final MusicItem? item = await getSongDetails(songId);
          if (item != null && item.streamUrl != null) restored.add(item);
        }
      }

      if (restored.isEmpty) return false;

      final int initialIndex = decoded['currentIndex'] is int ? decoded['currentIndex'] as int : 0;
      await _loadQueue(restored, initialIndex: initialIndex, play: play);
      return true;
    } catch (e) {
      debugPrint("MusicServerManager.restoreSavedQueue error: $e");
      return false;
    }
  }

  static Future<void> clearSavedQueue() async {
    final File file = File(_queueFilePath);
    if (file.existsSync()) await file.delete();
  }

  static Future<void> _clearPlaybackMemory() async {
    _queue = <MusicItem>[];
    _lastRecordedLocalPlayKey = null;
    try {
      await player.stop();
    } catch (e) {
      debugPrint("MusicServerManager._clearPlaybackMemory stop error: $e");
    }
    try {
      await player.clearAudioSources();
    } catch (e) {
      debugPrint("MusicServerManager._clearPlaybackMemory clear error: $e");
    }
    try {
      await player.setShuffleModeEnabled(false);
      await player.setLoopMode(LoopMode.off);
    } catch (e) {
      debugPrint("MusicServerManager._clearPlaybackMemory mode reset error: $e");
    }
  }

  static Future<String?> _loadActiveSourceId() async {
    final File file = File(_activeSourcePath);
    if (!file.existsSync()) return null;
    try {
      final String value = (await file.readAsString()).trim();
      return value.isEmpty ? null : value;
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveActiveSourceId(String? id) async {
    final File file = File(_activeSourcePath);
    if (id == null || id.trim().isEmpty) {
      if (file.existsSync()) await file.delete();
      return;
    }
    if (!file.existsSync()) await file.create(recursive: true);
    await file.writeAsString(id);
  }

  static Future<bool> setLocalActive() async {
    await MusicLibraryDb.instance.database;
    _activeConfigId = localSourceId;
    _isConnected = true;
    await _saveActiveSourceId(localSourceId);
    return true;
  }

  static Future<bool> setActiveServer(MusicServerConfig config) async {
    if (config.id == localSourceId) return setLocalActive();
    lastConnectionError = null;
    try {
      final String baseUrl = _normalizeServerUrl(config.url);
      debugPrint("MusicServerManager: Testing connection to $baseUrl...");

      _PingResult result = await _pingServer(baseUrl, config);

      // Jellyfin only speaks Subsonic through its third-party "Subsonic API" plugin,
      // which is commonly mounted under /sb. Auto-probe that path before giving up.
      if (!result.ok && result.shouldRetryWithSb && !baseUrl.endsWith('/sb')) {
        final _PingResult sbResult = await _pingServer('$baseUrl/sb', config);
        if (sbResult.ok) {
          await _rewriteServerUrl(config.id, '$baseUrl/sb');
          result = sbResult;
        }
      }

      if (result.ok) {
        _activeConfigId = config.id;
        _isConnected = true;
        lastConnectionError = null;
        await _saveActiveSourceId(config.id);
        debugPrint("MusicServerManager: Connected successfully!");
        return true;
      }

      _isConnected = false;
      lastConnectionError = result.error;
      debugPrint("MusicServerManager: Connection failed: ${result.error}");
      return false;
    } catch (e, stack) {
      debugPrint("MusicServerManager.setActiveServer error: $e");
      debugPrint(stack.toString());
      _isConnected = false;
      _activeConfigId = null;
      lastConnectionError = _friendlyNetworkError(e);
      return false;
    }
  }

  static String _normalizeServerUrl(String raw) {
    String url = raw.trim();
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.endsWith('/rest')) url = url.substring(0, url.length - 5);
    return url;
  }

  /// Pings a Subsonic-compatible endpoint and classifies the outcome into a
  /// user-readable message. Network/socket failures are rethrown to the caller.
  static Future<_PingResult> _pingServer(String baseUrl, MusicServerConfig config) async {
    final Uri uri = Uri.parse('$baseUrl/rest/ping.view').replace(queryParameters: <String, String>{
      'u': config.username,
      ..._authParams(config),
      'c': 'Tabame',
      'v': '1.16.1',
      'f': 'json',
    });

    final http.Response response = await http.get(uri).timeout(const Duration(seconds: 12));
    final String? contentType = response.headers['content-type'];
    debugPrint("MusicServerManager: ping $baseUrl -> ${response.statusCode} ($contentType)");

    if (response.statusCode == 404) {
      return _PingResult.fail(
        'No Subsonic API found at $baseUrl (404). If this is Jellyfin, install the "Subsonic API" '
        'plugin and restart the server — it is usually served under /sb.',
        retryWithSb: true,
      );
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      return _PingResult.fail('Server refused the login (HTTP ${response.statusCode}). Check the username and password.');
    }
    if (response.statusCode != 200) {
      return _PingResult.fail('Server returned HTTP ${response.statusCode}.');
    }

    final String body = response.body.trim();
    if (body.isEmpty) {
      return _PingResult.fail('Server returned an empty response. Is the Subsonic API enabled?', retryWithSb: true);
    }

    final bool looksJson =
        (contentType != null && (contentType.contains('json') || contentType.contains('text/javascript'))) ||
            body.startsWith('{');
    if (!looksJson || body.startsWith('<')) {
      final bool html = body.contains('<html') || body.contains('<!DOCTYPE');
      return _PingResult.fail(
        html
            ? 'Server returned a web page instead of the Subsonic API. Double-check the URL and port.'
            : 'Server replied in an unexpected format${contentType == null ? '' : ' ($contentType)'}.',
        retryWithSb: true,
      );
    }

    dynamic decoded;
    try {
      decoded = jsonDecode(body);
    } catch (_) {
      return _PingResult.fail('Could not parse the server response as JSON.', retryWithSb: true);
    }

    final dynamic sub = decoded is Map ? decoded['subsonic-response'] : null;
    if (sub == null) {
      return _PingResult.fail('Response was not a Subsonic reply. Is this a Subsonic-compatible server?',
          retryWithSb: true);
    }
    if (sub['status'] == 'ok') return _PingResult.success();

    // status == "failed": surface the server's own error, plus a Jellyfin hint on auth codes.
    final dynamic err = sub['error'];
    final int? code = err is Map ? (err['code'] is int ? err['code'] as int : int.tryParse('${err['code']}')) : null;
    final String? serverMsg = err is Map && err['message'] != null ? err['message'].toString() : null;
    final bool authError = code == 40 || code == 41 || code == 44 || code == 45;
    final String hint = authError
        ? ' If this is Jellyfin, its Subsonic plugin may not support the token login Tabame uses '
            '(Jellyfin stores only hashed passwords).'
        : '';
    return _PingResult.fail(
      'Server rejected the connection${serverMsg != null ? ': $serverMsg' : ''}'
      '${code != null ? ' (code $code)' : ''}.$hint',
    );
  }

  static Future<void> _rewriteServerUrl(String id, String newUrl) async {
    final int idx = _configs.indexWhere((MusicServerConfig e) => e.id == id);
    if (idx == -1) return;
    final MusicServerConfig old = _configs[idx];
    _configs[idx] = MusicServerConfig(
      id: old.id,
      name: old.name,
      url: newUrl,
      username: old.username,
      password: old.password,
      type: old.type,
      isDefault: old.isDefault,
    );
    await saveConfigs();
  }

  static String _friendlyNetworkError(Object e) {
    if (e is TimeoutException) {
      return 'The server did not respond in time. Check the URL and that the server is reachable.';
    }
    if (e is SocketException) return 'Could not reach the server. Check the URL, port, and your network.';
    if (e is HandshakeException) return 'TLS handshake failed. Check http vs https and the certificate.';
    if (e is FormatException) return 'The server sent a malformed response.';
    return 'Connection failed: $e';
  }

  static Future<void> resetPlayback() async {
    try {
      await saveCurrentQueue();
      await _clearPlaybackMemory();
    } catch (e) {
      debugPrint("MusicServerManager.resetPlayback error: $e");
    }
  }

  static Future<void> disconnect() async {
    try {
      await saveCurrentQueue();
      await _clearPlaybackMemory();
    } catch (e) {
      debugPrint("MusicServerManager.disconnect error: $e");
    } finally {
      _isConnected = false;
      _activeConfigId = null;
      await _saveActiveSourceId(null);
    }
  }

  static Future<List<MusicRoot>> getLocalRoots() => MusicLibraryDb.instance.getRoots();

  static Future<void> addLocalRoot(String path) => MusicLibraryDb.instance.addRoot(path);

  static Future<void> removeLocalRoot(String path) => MusicLibraryDb.instance.removeRoot(path);

  static Future<int> getLocalSongCount() => MusicLibraryDb.instance.countSongs();

  static Future<MusicIndexResult> reindexLocalAll() => MusicLocalIndexer.instance.reindexAll();

  static Future<MusicIndexResult> reindexLocalFolder(String folderPath) =>
      MusicLocalIndexer.instance.reindexFolder(folderPath);

  static Future<bool> addServer(MusicServerConfig config) async {
    _configs.add(config);
    await saveConfigs();
    if (_configs.length == 1) await setActiveServer(config);
    return true;
  }

  static Future<void> removeServer(String id) async {
    _configs.removeWhere((MusicServerConfig e) => e.id == id);
    await saveConfigs();
  }

  // API Methods
  static String _buildUrl(String method, Map<String, String> params) {
    final MusicServerConfig? config = _configs.firstWhereOrNull((MusicServerConfig e) => e.id == _activeConfigId);
    if (config == null) return "";

    final String url = _normalizeServerUrl(config.url);

    final Uri uri = Uri.parse("$url/rest/$method.view").replace(queryParameters: <String, String>{
      'u': config.username,
      ..._authParams(config),
      'c': 'Tabame',
      'v': '1.16.1',
      'f': 'json',
      ...params,
    });
    return uri.toString();
  }

  static Future<dynamic> _callRest(String method, [Map<String, String>? params]) async {
    if (!_isConnected) return null;
    final String url = _buildUrl(method, params ?? <String, String>{});
    if (url.isEmpty) return null;

    try {
      final http.Response response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) return null;
      final dynamic decoded = jsonDecode(response.body);
      return decoded['subsonic-response'];
    } catch (e) {
      debugPrint("MusicServerManager._callRest($method) error: $e");
      return null;
    }
  }

  static Future<List<MusicItem>> getArtists() async {
    if (isLocalActive) return MusicLibraryDb.instance.getArtists();

    final dynamic res = await _callRest('getArtists');
    if (res == null || res['status'] != 'ok') return <MusicItem>[];

    final List<MusicItem> items = <MusicItem>[];
    final dynamic indices = res['artists']?['index'];
    if (indices != null) {
      for (final dynamic index in indices) {
        final dynamic artists = index['artist'];
        if (artists != null) {
          for (final dynamic a in artists) {
            items.add(MusicItem(
              id: a['id'].toString(),
              title: a['name'] ?? "Unknown",
              isFolder: true,
              type: MusicItemType.artist,
            ));
          }
        }
      }
    }
    return items;
  }

  static Future<List<MusicItem>> getAlbums(String artistId) async {
    if (isLocalActive) return MusicLibraryDb.instance.getAlbums(artistId);

    final dynamic res = await _callRest('getArtist', <String, String>{'id': artistId});
    if (res == null || res['status'] != 'ok') return <MusicItem>[];

    final List<MusicItem> items = <MusicItem>[];
    final dynamic albums = res['artist']?['album'];
    if (albums != null) {
      for (final dynamic a in albums) {
        items.add(MusicItem(
          id: a['id'].toString(),
          title: a['name'] ?? "Unknown",
          artist: res['artist']['name'],
          coverUrl: _buildUrl('getCoverArt', <String, String>{'id': a['coverArt'] ?? ""}),
          isFolder: true,
          type: MusicItemType.album,
        ));
      }
    }
    return items;
  }

  static Future<List<MusicItem>> getSongs(String albumId) async {
    if (isLocalActive) return MusicLibraryDb.instance.getAlbumSongs(albumId);

    final dynamic res = await _callRest('getAlbum', <String, String>{'id': albumId});
    if (res == null || res['status'] != 'ok') return <MusicItem>[];

    final List<MusicItem> items = <MusicItem>[];
    final dynamic songs = res['album']?['song'];
    if (songs != null) {
      for (final dynamic s in songs) {
        items.add(MusicItem(
          id: s['id'].toString(),
          title: s['title'] ?? "Unknown",
          artist: s['artist'],
          album: s['album'],
          duration: _durationFromSeconds(s['duration']),
          durationNeedsRefresh: _durationNeedsRefresh(s['duration']),
          coverUrl: _buildUrl('getCoverArt', <String, String>{'id': s['coverArt'] ?? ""}),
          streamUrl: _buildUrl('stream', <String, String>{'id': s['id'].toString(), 'format': 'mp3'}),
          starred: s['starred'] != null,
        ));
      }
    }
    return items;
  }

  static Future<List<MusicItem>> getIndexedFolders() async {
    if (isLocalActive) return MusicLibraryDb.instance.getRootFolders();

    final dynamic res = await _callRest('getIndexes');
    if (res == null || res['status'] != 'ok') return <MusicItem>[];

    final List<MusicItem> items = <MusicItem>[];

    final dynamic shortcuts = res['indexes']?['shortcut'];
    if (shortcuts != null) {
      for (final dynamic shortcut in shortcuts) {
        items.add(MusicItem(
          id: shortcut['id'].toString(),
          title: shortcut['name'] ?? "Unknown",
          isFolder: true,
          type: MusicItemType.folder,
        ));
      }
    }

    final dynamic indices = res['indexes']?['index'];
    if (indices != null) {
      for (final dynamic index in indices) {
        final dynamic artists = index['artist'];
        if (artists != null) {
          for (final dynamic artist in artists) {
            items.add(MusicItem(
              id: artist['id'].toString(),
              title: artist['name'] ?? "Unknown",
              isFolder: true,
              type: MusicItemType.folder,
            ));
          }
        }
      }
    }

    return items;
  }

  static Future<List<MusicItem>> getMusicDirectory(String directoryId) async {
    if (isLocalActive) return MusicLibraryDb.instance.getDirectory(directoryId);

    final dynamic res = await _callRest('getMusicDirectory', <String, String>{'id': directoryId});
    if (res == null || res['status'] != 'ok') return <MusicItem>[];

    final List<MusicItem> items = <MusicItem>[];
    final dynamic children = res['directory']?['child'];
    if (children != null) {
      for (final dynamic child in children) {
        final bool isDir = child['isDir'] == true;
        items.add(MusicItem(
          id: child['id'].toString(),
          title: child['title'] ?? child['name'] ?? "Unknown",
          artist: child['artist'],
          album: child['album'],
          duration: _durationFromSeconds(child['duration']),
          durationNeedsRefresh: _durationNeedsRefresh(child['duration']),
          coverUrl: child['coverArt'] == null
              ? null
              : _buildUrl('getCoverArt', <String, String>{'id': child['coverArt'].toString()}),
          streamUrl:
              isDir ? null : _buildUrl('stream', <String, String>{'id': child['id'].toString(), 'format': 'mp3'}),
          isFolder: isDir,
          type: isDir ? MusicItemType.folder : MusicItemType.song,
          starred: child['starred'] != null,
        ));
      }
    }
    return items;
  }

  static Future<List<MusicItem>> getMusicDirectorySongsRecursive(String directoryId) async {
    if (isLocalActive) return MusicLibraryDb.instance.getDirectorySongsRecursive(directoryId);

    final List<MusicItem> songs = <MusicItem>[];
    final Set<String> visitedDirectoryIds = <String>{};

    Future<void> collect(String id) async {
      if (!visitedDirectoryIds.add(id)) return;

      final List<MusicItem> children = await getMusicDirectory(id);
      for (final MusicItem child in children) {
        if (child.isFolder) {
          await collect(child.id);
        } else if (child.streamUrl != null) {
          songs.add(child);
        }
      }
    }

    await collect(directoryId);
    return songs;
  }

  static Future<List<MusicItem>> search(String query) async {
    if (query.isEmpty) return <MusicItem>[];
    if (isLocalActive) return MusicLibraryDb.instance.search(query);

    final dynamic res = await _callRest('search3', <String, String>{
      'query': query,
      'songCount': '50',
      'albumCount': '20',
      'artistCount': '20',
    });
    if (res == null || res['status'] != 'ok') return <MusicItem>[];

    final dynamic searchResult = res['searchResult3'];
    if (searchResult == null) return <MusicItem>[];

    final List<MusicItem> items = <MusicItem>[];

    if (searchResult['artist'] != null) {
      for (final dynamic a in searchResult['artist']) {
        items.add(MusicItem(
          id: a['id'].toString(),
          title: a['name'] ?? "Unknown",
          isFolder: true,
          type: MusicItemType.artist,
        ));
      }
    }

    if (searchResult['album'] != null) {
      for (final dynamic a in searchResult['album']) {
        items.add(MusicItem(
          id: a['id'].toString(),
          title: a['name'] ?? "Unknown",
          artist: a['artist'] as String?,
          isFolder: true,
          type: MusicItemType.album,
          coverUrl: _buildUrl('getCoverArt', <String, String>{'id': a['coverArt']?.toString() ?? ""}),
        ));
      }
    }

    if (searchResult['song'] != null) {
      for (final dynamic s in searchResult['song']) {
        items.add(MusicItem(
          id: s['id'].toString(),
          title: s['title'] ?? "Unknown",
          artist: s['artist'],
          album: s['album'],
          duration: _durationFromSeconds(s['duration']),
          durationNeedsRefresh: _durationNeedsRefresh(s['duration']),
          coverUrl: _buildUrl('getCoverArt', <String, String>{'id': s['coverArt'] ?? ""}),
          streamUrl: _buildUrl('stream', <String, String>{'id': s['id'].toString(), 'format': 'mp3'}),
          starred: s['starred'] != null,
        ));
      }
    }

    return items;
  }

  static Future<List<MusicPlaylist>> getPlaylists() async {
    if (isLocalActive) return MusicLibraryDb.instance.getPlaylists();

    final dynamic res = await _callRest('getPlaylists');
    if (res == null || res['status'] != 'ok') return <MusicPlaylist>[];

    final List<MusicPlaylist> playlists = <MusicPlaylist>[];
    final dynamic list = res['playlists']?['playlist'];
    if (list != null) {
      for (final dynamic p in list) {
        playlists.add(MusicPlaylist(
          id: p['id'].toString(),
          name: p['name'] ?? "Untitled",
          songCount: p['songCount'] ?? 0,
          duration: _durationFromSeconds(p['duration'], maxDuration: const Duration(days: 365)) ?? Duration.zero,
        ));
      }
    }
    return playlists;
  }

  static Future<bool> createPlaylist(String name) async {
    final String trimmedName = name.trim();
    if (trimmedName.isEmpty) return false;
    if (isLocalActive) return MusicLibraryDb.instance.createPlaylist(trimmedName);

    final dynamic res = await _callRest('createPlaylist', <String, String>{'name': trimmedName});
    return res != null && res['status'] == 'ok';
  }

  static Future<bool> addSongToPlaylist({
    required String playlistId,
    required String songId,
  }) async {
    if (isLocalActive) {
      return MusicLibraryDb.instance.addSongToPlaylist(playlistId: playlistId, songId: songId);
    }

    final dynamic res = await _callRest('updatePlaylist', <String, String>{
      'playlistId': playlistId,
      'songIdToAdd': songId,
    });
    return res != null && res['status'] == 'ok';
  }

  static Future<bool> deletePlaylist(String playlistId) async {
    if (isLocalActive) return MusicLibraryDb.instance.deletePlaylist(playlistId);

    final dynamic res = await _callRest('deletePlaylist', <String, String>{'id': playlistId});
    return res != null && res['status'] == 'ok';
  }

  static Future<bool> removeSongFromPlaylist({
    required String playlistId,
    required int songIndex,
  }) async {
    if (isLocalActive) {
      return MusicLibraryDb.instance.removeSongFromPlaylist(playlistId: playlistId, songIndex: songIndex);
    }

    final dynamic res = await _callRest('updatePlaylist', <String, String>{
      'playlistId': playlistId,
      'songIndexToRemove': '$songIndex',
    });
    return res != null && res['status'] == 'ok';
  }

  static Future<bool> setSongStarred({
    required String songId,
    required bool starred,
  }) async {
    if (isLocalActive) {
      final bool success = await MusicLibraryDb.instance.setSongStars(songId: songId, starsCount: starred ? 1 : 0);
      if (success) {
        _queue = _queue
            .map((MusicItem item) =>
                item.id == songId ? item.copyWith(starred: starred, starsCount: starred ? 1 : 0) : item)
            .toList(growable: false);
      }
      return success;
    }

    final dynamic res = await _callRest(starred ? 'star' : 'unstar', <String, String>{'id': songId});
    if (res != null && res['status'] == 'ok') {
      _queue = _queue
          .map((MusicItem item) => item.id == songId ? item.copyWith(starred: starred) : item)
          .toList(growable: false);
      return true;
    }
    return false;
  }

  static Future<List<MusicItem>> getStarredSongs() async {
    if (isLocalActive) return MusicLibraryDb.instance.getStarredSongs();

    final dynamic res = await _callRest('getStarred2');
    if (res == null || res['status'] != 'ok') return <MusicItem>[];

    final List<MusicItem> items = <MusicItem>[];
    final dynamic songs = res['starred2']?['song'];
    if (songs != null) {
      for (final dynamic s in songs) {
        items.add(_musicItemFromSong(s));
      }
    }
    return items;
  }

  static Future<List<MusicItem>> getAlbumListSongs(String type, {int size = 25}) async {
    if (isLocalActive) {
      if (type == 'recent') return MusicLibraryDb.instance.getRecentlyPlayedSongs(limit: size);
      return MusicLibraryDb.instance.getMostPlayedSongs(limit: size);
    }

    final dynamic res = await _callRest('getAlbumList2', <String, String>{
      'type': type,
      'size': size.toString(),
    });
    if (res == null || res['status'] != 'ok') return <MusicItem>[];

    final List<MusicItem> items = <MusicItem>[];
    final dynamic albums = res['albumList2']?['album'];
    if (albums != null) {
      for (final dynamic album in albums) {
        final List<MusicItem> songs = await getSongs(album['id'].toString());
        items.addAll(songs);
      }
    }
    return items;
  }

  static Future<List<MusicItem>> getPlaylistSongs(String playlistId) async {
    if (isLocalActive) return MusicLibraryDb.instance.getPlaylistSongs(playlistId);

    final dynamic res = await _callRest('getPlaylist', <String, String>{'id': playlistId});
    if (res == null || res['status'] != 'ok') return <MusicItem>[];

    final List<MusicItem> items = <MusicItem>[];
    final dynamic songs = res['playlist']?['entry'];
    if (songs != null) {
      for (final dynamic s in songs) {
        items.add(MusicItem(
          id: s['id'].toString(),
          title: s['title'] ?? "Unknown",
          artist: s['artist'],
          album: s['album'],
          duration: _durationFromSeconds(s['duration']),
          durationNeedsRefresh: _durationNeedsRefresh(s['duration']),
          coverUrl: _buildUrl('getCoverArt', <String, String>{'id': s['coverArt'] ?? ""}),
          streamUrl: _buildUrl('stream', <String, String>{'id': s['id'].toString(), 'format': 'mp3'}),
          starred: s['starred'] != null,
        ));
      }
    }
    return items;
  }

  // Playback
  static Future<void> playSong(MusicItem item) async {
    await playQueue(<MusicItem>[item]);
  }

  static Future<void> playQueue(List<MusicItem> items, {int initialIndex = 0}) async {
    final int clampedInitialIndex = items.isEmpty ? 0 : initialIndex.clamp(0, items.length - 1);
    final MusicItem? requestedItem = items.isEmpty ? null : items[clampedInitialIndex];
    final List<MusicItem> playable = await _resolvePlayableQueueItems(items);
    if (playable.isEmpty) return;

    final int resolvedInitialIndex;
    if (requestedItem == null) {
      resolvedInitialIndex = 0;
    } else {
      final int matchedIndex = playable.indexWhere(
        (MusicItem item) =>
            item.id == requestedItem.id || (item.localPath != null && item.localPath == requestedItem.localPath),
      );
      resolvedInitialIndex = matchedIndex >= 0 ? matchedIndex : 0;
    }

    await _loadQueue(playable, initialIndex: resolvedInitialIndex, play: true);
    await saveCurrentQueue();
  }

  static List<AudioSource> _toAudioSources(List<MusicItem> items) => items
      .map((MusicItem item) => AudioSource.uri(Uri.parse(item.streamUrl!), tag: item))
      .toList(growable: false);

  /// Appends [items] to the end of the current queue. Starts a fresh queue when
  /// nothing is playing.
  static Future<void> addToQueue(List<MusicItem> items) async {
    final List<MusicItem> playable = await _resolvePlayableQueueItems(items);
    if (playable.isEmpty) return;
    if (player.sequence.isEmpty) {
      await playQueue(playable);
      return;
    }
    try {
      await player.addAudioSources(_toAudioSources(playable));
      _queue = _currentPlaybackQueue();
      await saveCurrentQueue();
    } catch (e) {
      debugPrint("MusicServerManager.addToQueue error: $e");
    }
  }

  /// Inserts [items] immediately after the current track. Starts a fresh queue
  /// when nothing is playing.
  static Future<void> playNext(List<MusicItem> items) async {
    final List<MusicItem> playable = await _resolvePlayableQueueItems(items);
    if (playable.isEmpty) return;
    if (player.sequence.isEmpty) {
      await playQueue(playable);
      return;
    }
    try {
      final int insertAt = ((player.currentIndex ?? -1) + 1).clamp(0, player.sequence.length);
      await player.insertAudioSources(insertAt, _toAudioSources(playable));
      _queue = _currentPlaybackQueue();
      await saveCurrentQueue();
    } catch (e) {
      debugPrint("MusicServerManager.playNext error: $e");
    }
  }

  static Future<void> removeFromQueueAt(int index) async {
    if (index < 0 || index >= player.sequence.length) return;
    try {
      await player.removeAudioSourceAt(index);
      _queue = _currentPlaybackQueue();
      await saveCurrentQueue();
    } catch (e) {
      debugPrint("MusicServerManager.removeFromQueueAt error: $e");
    }
  }

  static Future<void> moveQueueItem(int oldIndex, int newIndex) async {
    final int length = player.sequence.length;
    if (oldIndex < 0 || oldIndex >= length || newIndex < 0 || newIndex >= length || oldIndex == newIndex) return;
    try {
      await player.moveAudioSource(oldIndex, newIndex);
      _queue = _currentPlaybackQueue();
      await saveCurrentQueue();
    } catch (e) {
      debugPrint("MusicServerManager.moveQueueItem error: $e");
    }
  }

  static Future<void> _loadQueue(List<MusicItem> playable, {required int initialIndex, required bool play}) async {
    try {
      await player.stop();
      _queue = playable;
      _lastRecordedLocalPlayKey = null;
      await player.setAudioSources(
        playable
            .map(
              (MusicItem item) => AudioSource.uri(
                Uri.parse(item.streamUrl!),
                tag: item,
              ),
            )
            .toList(growable: false),
        initialIndex: initialIndex.clamp(0, playable.length - 1),
      );
      await _reapplyShuffleMode();
      if (play) {
        final ProcessingState current = player.processingState;
        if (current == ProcessingState.idle || current == ProcessingState.loading) {
          await player.processingStateStream
              .firstWhere((ProcessingState s) => s != ProcessingState.idle && s != ProcessingState.loading)
              .timeout(const Duration(seconds: 10), onTimeout: () => ProcessingState.idle);
        }
        await Future<void>.delayed(const Duration(milliseconds: 600));
        await player.play();
      }
    } catch (e) {
      debugPrint("MusicServerManager.playQueue error: $e");
    }
  }

  static List<MusicItem> _currentPlaybackQueue() {
    final List<IndexedAudioSource> sequence = player.sequence;
    if (sequence.isEmpty) return _queue;
    return <MusicItem>[
      for (final IndexedAudioSource source in sequence)
        if (source.tag is MusicItem) source.tag as MusicItem,
    ];
  }

  static void _recordLocalPlayForIndex(int index) {
    if (!isLocalActive) return;
    final List<MusicItem> items = _currentPlaybackQueue();
    if (index < 0 || index >= items.length) return;
    final MusicItem item = items[index];
    if (item.localPath == null) return;

    final String key = '$index:${item.id}:${item.localPath}';
    if (_lastRecordedLocalPlayKey == key) return;
    _lastRecordedLocalPlayKey = key;

    unawaited(MusicLibraryDb.instance.incrementPlayCount(item.id));
    _queue = _queue
        .map((MusicItem queued) => queued.id == item.id ? queued.copyWith(playCount: queued.playCount + 1) : queued)
        .toList(growable: false);
  }

  static Future<List<MusicItem>> _refetchItemsWithBadDuration(List<MusicItem> items) async {
    final List<MusicItem> resolved = <MusicItem>[];
    for (final MusicItem item in items) {
      if (item.streamUrl == null || !item.durationNeedsRefresh) {
        resolved.add(item);
        continue;
      }

      final MusicItem? refetched = await getSongDetails(item.id);
      resolved.add(refetched ?? item);
    }
    return resolved;
  }

  static Future<List<MusicItem>> _resolvePlayableQueueItems(List<MusicItem> items) async {
    final List<MusicItem> durationResolved = await _refetchItemsWithBadDuration(items);
    final List<MusicItem> playable = <MusicItem>[];

    for (final MusicItem item in durationResolved) {
      MusicItem resolvedItem = item;
      if (isLocalActive) {
        final MusicItem? refetched = await getSongDetails(item.id);
        if (refetched != null) resolvedItem = refetched;
      }

      if (resolvedItem.streamUrl == null) continue;
      if (isLocalActive) {
        final String? path = resolvedItem.localPath;
        if (path == null || path.trim().isEmpty || !File(path).existsSync()) {
          debugPrint('MusicServerManager.playQueue skipping missing local file: ${resolvedItem.id} -> $path');
          continue;
        }
      }
      playable.add(resolvedItem);
    }

    return playable;
  }

  static Future<MusicItem?> getSongDetails(String songId) async {
    if (isLocalActive) return MusicLibraryDb.instance.getSongByItemId(songId);

    final dynamic res = await _callRest('getSong', <String, String>{'id': songId});
    if (res == null || res['status'] != 'ok' || res['song'] == null) return null;
    final dynamic s = res['song'];
    return MusicItem(
      id: s['id'].toString(),
      title: s['title'] ?? "Unknown",
      artist: s['artist'],
      album: s['album'],
      duration: _durationFromSeconds(s['duration']),
      durationNeedsRefresh: _durationNeedsRefresh(s['duration']),
      coverUrl: _buildUrl('getCoverArt', <String, String>{'id': s['coverArt'] ?? ""}),
      streamUrl: _buildUrl('stream', <String, String>{'id': s['id'].toString(), 'format': 'mp3'}),
      starred: s['starred'] != null,
    );
  }

  static MusicItem _musicItemFromSong(dynamic s) {
    return MusicItem(
      id: s['id'].toString(),
      title: s['title'] ?? "Unknown",
      artist: s['artist'],
      album: s['album'],
      duration: _durationFromSeconds(s['duration']),
      durationNeedsRefresh: _durationNeedsRefresh(s['duration']),
      coverUrl: _buildUrl('getCoverArt', <String, String>{'id': s['coverArt'] ?? ""}),
      streamUrl: _buildUrl('stream', <String, String>{'id': s['id'].toString(), 'format': 'mp3'}),
      starred: s['starred'] != null,
    );
  }

  static bool _durationNeedsRefresh(dynamic raw) {
    return raw == null || _durationFromSeconds(raw) == null;
  }

  static Duration? _durationFromSeconds(dynamic raw, {Duration maxDuration = _maxSongDuration}) {
    final int? seconds = switch (raw) {
      final int value => value,
      final double value => value.round(),
      // ignore: unreachable_switch_case
      final num value => value.round(),
      final String value => int.tryParse(value),
      _ => null,
    };

    if (seconds == null || seconds <= 0) return null;
    final Duration duration = Duration(seconds: seconds);
    if (duration > maxDuration) return null;
    return duration;
  }

  static String createSalt() {
    const String chars = 'abcdefghijklmnopqrstuvwxyz0123456789';
    final Random rnd = Random.secure();
    return String.fromCharCodes(Iterable<int>.generate(6, (int _) => chars.codeUnitAt(rnd.nextInt(chars.length))));
  }

  static String createToken(String password, String salt) {
    return md5.convert(utf8.encode(password + salt)).toString();
  }

  /// Builds the Subsonic authentication query parameters for [config].
  ///
  /// Subsonic/Navidrome use salted token auth (`t`/`s`), which is safe to send
  /// over any transport. Jellyfin's Subsonic plugin can't validate that token
  /// (Jellyfin stores only hashed passwords), so for [MusicServerType.jellyfin]
  /// we fall back to legacy hex-encoded password auth (`p=enc:...`). That is
  /// effectively cleartext on the wire — the UI warns users to prefer https.
  static Map<String, String> _authParams(MusicServerConfig config) {
    if (config.type == MusicServerType.jellyfin) {
      return <String, String>{'p': 'enc:${_hexEncode(config.password)}'};
    }
    final String salt = createSalt();
    return <String, String>{'t': createToken(config.password, salt), 's': salt};
  }

  static String _hexEncode(String value) {
    return utf8.encode(value).map((int b) => b.toRadixString(16).padLeft(2, '0')).join();
  }
}

/// Outcome of a single Subsonic ping attempt. [shouldRetryWithSb] flags failures
/// that are consistent with Jellyfin's Subsonic plugin living under /sb.
class _PingResult {
  const _PingResult._(this.ok, this.error, this.shouldRetryWithSb);
  factory _PingResult.success() => const _PingResult._(true, null, false);
  factory _PingResult.fail(String error, {bool retryWithSb = false}) => _PingResult._(false, error, retryWithSb);

  final bool ok;
  final String? error;
  final bool shouldRetryWithSb;
}
