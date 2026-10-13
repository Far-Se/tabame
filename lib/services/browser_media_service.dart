import 'dart:async';

import 'package:flutter/foundation.dart';

import 'browser_bridge_service.dart';

class BrowserMediaTab {
  BrowserMediaTab({
    required this.id,
    required this.title,
    required this.url,
    required this.audible,
    required this.muted,
    required this.lastPlayed,
    required this.playing,
  });

  final int id;
  final String title;
  final String url;
  final bool audible;
  bool muted;
  final int lastPlayed;
  bool playing;
  String error = '';
  String notice = '';

  String get host => Uri.tryParse(url)?.host ?? '';
}

/// Keeps media history for the bridge's lifetime, including while the panel is
/// closed. Tab IDs are session-specific, so they are never saved to settings.
class BrowserMediaService extends ChangeNotifier {
  BrowserMediaService._();

  static final BrowserMediaService instance = BrowserMediaService._();

  final BrowserBridgeService _bridge = BrowserBridgeService.instance;
  final Map<int, BrowserMediaTab> _tabs = <int, BrowserMediaTab>{};
  final Set<int> _busy = <int>{};
  StreamSubscription<BrowserBridgeEvent>? _subscription;
  Timer? _debounce;
  Future<void>? _refreshFuture;
  bool _refreshAgain = false;
  bool _togglingPreferred = false;
  bool _disposed = false;
  int _generation = 0;
  int _commandRevision = 0;
  int _playOrder = 0;
  int? _preferredTabId;
  String error = '';

  BrowserBridgeStatus get status => _bridge.status;
  bool get loading => _refreshFuture != null;
  bool get busy => _busy.isNotEmpty || _togglingPreferred;
  bool isBusy(int tabId) => _busy.contains(tabId);

  List<BrowserMediaTab> get tabs => _tabs.values.toList()
    ..sort((BrowserMediaTab a, BrowserMediaTab b) {
      if (a.playing != b.playing) return a.playing ? -1 : 1;
      return b.lastPlayed.compareTo(a.lastPlayed);
    });

  void initialize() {
    if (_subscription != null || _disposed) return;
    _subscription = _bridge.events.listen((BrowserBridgeEvent event) {
      if (event.name == 'connection.changed') {
        _generation++;
        if (!status.enabled) {
          _tabs.clear();
          _preferredTabId = null;
        }
        error = '';
        notifyListeners();
        if (status.connected) _scheduleRefresh();
      } else if (event.name == 'tabs.changed') {
        _scheduleRefresh();
      }
    });
    if (status.connected) _scheduleRefresh();
  }

  void _scheduleRefresh() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      if (_refreshFuture != null) {
        _refreshAgain = true;
      } else {
        unawaited(refresh());
      }
    });
  }

  Future<void> refresh() {
    if (_refreshFuture != null) return _refreshFuture!;
    if (!status.connected || _disposed) return Future<void>.value();
    _refreshFuture = _refresh(_generation).whenComplete(() {
      _refreshFuture = null;
      if (_disposed) return;
      notifyListeners();
      if (_refreshAgain) {
        _refreshAgain = false;
        _scheduleRefresh();
      }
    });
    notifyListeners();
    return _refreshFuture!;
  }

  Future<void> _refresh(int generation) async {
    try {
      final Object? result = await _bridge.request('tabs.list');
      if (generation != _generation || !status.connected) return;
      if (result is! Map || result['tabs'] is! List) {
        throw StateError('The browser returned an invalid tab list.');
      }
      final Map<int, BrowserMediaTab> next = <int, BrowserMediaTab>{};
      for (final Object? raw in result['tabs'] as List<Object?>) {
        if (raw is! Map || raw['id'] is! num) continue;
        final int id = (raw['id'] as num).toInt();
        final String url = '${raw['url'] ?? ''}';
        final BrowserMediaTab? previous = _tabs[id]?.url == url ? _tabs[id] : null;
        final bool audible = raw['audible'] == true;
        if (!audible && previous == null) continue;
        // Keep the same object during a command so a late snapshot cannot
        // overwrite its result or briefly flip Pause back to Play.
        if (_busy.contains(id) && previous != null) {
          next[id] = previous;
          continue;
        }
        next[id] = BrowserMediaTab(
          id: id,
          title: '${raw['title'] ?? 'Untitled tab'}',
          url: url,
          audible: audible,
          muted: raw['muted'] == true,
          lastPlayed:
              audible && (previous == null || !previous.audible) ? ++_playOrder : previous?.lastPlayed ?? ++_playOrder,
          playing: previous?.playing ?? audible,
        )
          ..error = previous?.error ?? ''
          ..notice = raw['muted'] == true ? previous?.notice ?? '' : '';
      }
      _tabs
        ..clear()
        ..addAll(next);
      if (!_tabs.containsKey(_preferredTabId)) _preferredTabId = null;
      error = '';
      notifyListeners();

      // Audible indicators linger after pausing and also disappear during
      // silence. Read the players themselves for the button's actual state.
      await Future.wait<void>(next.values.map((BrowserMediaTab tab) async {
        if (_busy.contains(tab.id)) return;
        final int revision = _commandRevision;
        try {
          final List<_MediaFrame> frames = await _execute(tab, 'inspect');
          if (generation != _generation ||
              revision != _commandRevision ||
              _busy.contains(tab.id) ||
              !identical(_tabs[tab.id], tab)) return;
          tab.playing = frames.any((_MediaFrame frame) => frame.count > 0)
              ? frames.any((_MediaFrame frame) => frame.playing)
              : tab.audible;
        } catch (_) {
          // Listing still works when scripts are unavailable. Commands report
          // the actionable connector error instead of hiding the tab.
          if (generation == _generation &&
              revision == _commandRevision &&
              !_busy.contains(tab.id) &&
              identical(_tabs[tab.id], tab)) {
            tab.playing = tab.audible;
          }
        }
      }));
    } catch (failure) {
      if (generation == _generation) error = '$failure';
    }
  }

  Future<bool> togglePreferred() async {
    if (_disposed) return false;
    if (busy) return true;
    _togglingPreferred = true;
    notifyListeners();
    try {
      await refresh();
      final List<BrowserMediaTab> candidates = tabs;
      final BrowserMediaTab? tab = _tabs[_preferredTabId] ?? (candidates.isEmpty ? null : candidates.first);
      if (!status.connected || tab == null || error.isNotEmpty) return false;
      return await toggle(tab.id);
    } finally {
      _togglingPreferred = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<bool> toggle(int tabId) async {
    final BrowserMediaTab? tab = _tabs[tabId];
    if (tab == null || !status.connected || _disposed) return false;
    if (!_busy.add(tabId)) return true;
    _commandRevision++;
    final int generation = _generation;
    bool pausing = tab.playing;
    _preferredTabId = tabId;
    tab.error = '';
    tab.notice = '';
    notifyListeners();
    try {
      final List<_MediaFrame> frames = await _execute(tab, 'inspect');
      if (generation != _generation || !identical(_tabs[tabId], tab)) return false;
      final List<_MediaFrame> players = frames.where((_MediaFrame frame) => frame.count > 0).toList();
      if (players.isEmpty) {
        final String scriptError = frames.map((_MediaFrame frame) => frame.error).firstWhere(
              (String value) => value.isNotEmpty,
              orElse: () => 'No controllable audio or video found. Open the tab to control playback.',
            );
        throw StateError(scriptError);
      }
      final bool playing = players.any((_MediaFrame frame) => frame.playing);
      pausing = playing;
      players.sort((_MediaFrame a, _MediaFrame b) => b.score.compareTo(a.score));
      final List<int> frameIds = playing
          ? players.where((_MediaFrame frame) => frame.playing).map((_MediaFrame frame) => frame.id).toList()
          : <int>[players.first.id];
      final List<_MediaFrame> updated = await _execute(tab, playing ? 'pause' : 'play', frameIds: frameIds);
      if (generation != _generation || !identical(_tabs[tabId], tab)) return false;
      tab.playing = updated.any((_MediaFrame frame) => frame.playing);
      final List<String> errors =
          updated.map((_MediaFrame frame) => frame.error).where((String e) => e.isNotEmpty).toList();
      if (errors.isNotEmpty) throw StateError(errors.first);
      if (updated.isEmpty || tab.playing == playing) {
        throw StateError('The page did not ${playing ? 'pause' : 'start'} playback. Open the tab and try there.');
      }
      return true;
    } catch (failure) {
      if (generation != _generation || !identical(_tabs[tabId], tab)) return false;
      tab.error = '$failure';
      if (pausing && status.connected) {
        try {
          if (await _setMuted(tab, true, generation, verifyPage: true)) {
            tab.error = '';
            tab.notice = 'Could not pause playback. The tab was muted instead. Use Unmute to restore audio.';
          }
        } catch (muteFailure) {
          if (generation == _generation && identical(_tabs[tabId], tab)) {
            tab.error = 'Could not pause playback: $failure\nCould not mute the tab: $muteFailure';
          }
        }
      }
      // The pause failed even if muting succeeded. Returning false also opens
      // the panel after a toolbar right-click so the fallback is explained.
      return false;
    } finally {
      _busy.remove(tabId);
      _commandRevision++;
      if (!_disposed) notifyListeners();
      _scheduleRefresh();
    }
  }

  Future<void> toggleMute(int tabId) async {
    final BrowserMediaTab? tab = _tabs[tabId];
    if (tab == null || !status.connected || _disposed || !_busy.add(tabId)) return;
    _commandRevision++;
    final int generation = _generation;
    _preferredTabId = tabId;
    tab.error = '';
    tab.notice = '';
    notifyListeners();
    try {
      await _setMuted(tab, !tab.muted, generation);
    } catch (failure) {
      if (generation == _generation && identical(_tabs[tabId], tab)) tab.error = '$failure';
    } finally {
      _busy.remove(tabId);
      _commandRevision++;
      if (!_disposed) notifyListeners();
      _scheduleRefresh();
    }
  }

  Future<bool> _setMuted(BrowserMediaTab tab, bool muted, int generation, {bool verifyPage = false}) async {
    if (verifyPage) {
      // A failed script may mean the page navigated. Confirm this is still the
      // media tab before using the browser-level fallback.
      final Object? snapshot = await _bridge.request('tabs.list');
      if (generation != _generation || !identical(_tabs[tab.id], tab)) return false;
      if (snapshot is! Map || snapshot['tabs'] is! List) {
        throw StateError('The browser returned an invalid tab list.');
      }
      final bool samePage = (snapshot['tabs'] as List<Object?>)
          .whereType<Map<Object?, Object?>>()
          .any((Map<Object?, Object?> current) => current['id'] == tab.id && current['url'] == tab.url);
      if (!samePage) throw StateError('The tab closed or navigated to another page. Refresh the list.');
    }
    if (generation != _generation || !identical(_tabs[tab.id], tab)) return false;
    final Object? result = await _bridge.request(
      'tabs.mute',
      params: <String, Object?>{'tabId': tab.id, 'muted': muted},
    );
    if (generation != _generation || !identical(_tabs[tab.id], tab)) return false;
    if (result is! Map || result['id'] != tab.id || result['muted'] != muted) {
      throw StateError('The browser did not ${muted ? 'mute' : 'unmute'} the tab.');
    }
    tab.muted = muted;
    return true;
  }

  Future<List<_MediaFrame>> _execute(BrowserMediaTab tab, String action, {List<int>? frameIds}) async {
    final Object? response = await _bridge.request(
      'javascript.execute',
      params: <String, Object?>{
        'tabId': tab.id,
        'code': _mediaScript,
        'input': <String, Object?>{'action': action, 'pageUrl': tab.url},
        if (frameIds == null) 'allFrames': true else 'frameIds': frameIds,
      },
      timeout: const Duration(seconds: 10),
    );
    if (response is! Map || response['results'] is! List) {
      throw StateError('The browser returned an invalid playback response.');
    }
    if (response['pageUrl'] != tab.url) throw StateError('This tab navigated to another page. Refresh the list.');
    return (response['results'] as List<Object?>)
        .whereType<Map<Object?, Object?>>()
        .map((Map<Object?, Object?> frame) => _MediaFrame(frame))
        .toList();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _debounce?.cancel();
    unawaited(_subscription?.cancel());
    super.dispose();
  }
}

class _MediaFrame {
  _MediaFrame(Map<Object?, Object?> frame) {
    id = (frame['frameId'] as num?)?.toInt() ?? 0;
    final Object? result = frame['result'];
    if (result is Map) {
      count = (result['count'] as num?)?.toInt() ?? 0;
      playing = result['playing'] == true;
      score = (result['score'] as num?)?.toDouble() ?? 0;
      error = '${result['error'] ?? ''}';
    }
    if (frame['error'] != null) error = '${frame['error']}';
  }

  int id = 0;
  int count = 0;
  bool playing = false;
  double score = 0;
  String error = '';
}

// Runs in the connector's isolated USER_SCRIPT world, including embedded
// players. Resume only the best candidate; never start every video on a page.
const String _mediaScript = r'''
if (window === window.top && location.href !== input.pageUrl) {
  throw new Error('This tab navigated to another page. Refresh the list.');
}
const media = [];
function collect(root) {
  media.push(...root.querySelectorAll('audio, video'));
  for (const element of root.querySelectorAll('*')) {
    if (element.shadowRoot) collect(element.shadowRoot);
  }
}
collect(document);
const loaded = media.filter(element => element.currentSrc || element.src || element.srcObject);
const withSound = loaded.filter(element => !element.muted && element.volume > 0);
const players = withSound.length ? withSound : loaded;
const isPlaying = element => !element.paused && !element.ended;
const score = element =>
  (isPlaying(element) ? 1000000 : 0) +
  (!element.muted && element.volume > 0 ? 100000 : 0) +
  (element.currentTime > 0 ? 10000 : 0) +
  (element.tagName === 'AUDIO' ? 1000 : 0) +
  Math.min(999, element.clientWidth * element.clientHeight / 1000);
players.sort((a, b) => score(b) - score(a));
let error = '';
let playTimer;
try {
  if (input.action === 'pause') {
    for (const element of players.filter(isPlaying)) element.pause();
  } else if (input.action === 'play' && players.length) {
    await Promise.race([
      players[0].play(),
      new Promise((_, reject) => {
        playTimer = setTimeout(() => reject(new Error('Playback timed out. Open the tab and try there.')), 7000);
      }),
    ]);
  }
} catch (failure) {
  error = failure.message || String(failure);
} finally {
  clearTimeout(playTimer);
}
return {
  count: players.length,
  playing: players.some(isPlaying),
  score: players.length ? score(players[0]) : 0,
  error,
};
''';
