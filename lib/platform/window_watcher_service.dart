import 'dart:async';

import 'platform_models.dart';
import 'window_service.dart';

/// Shared polling orchestration for window enumeration and launcher search.
///
/// Platform adapters own native enumeration, identity conversion, metadata, and
/// activation. This class owns snapshot lifecycle, conservative filtering,
/// duplicate handling, refresh state, and the stream consumed by portable UI.
class WindowWatcherService {
  WindowWatcherService({WindowService? service}) : _service = service;

  static final WindowWatcherService instance = WindowWatcherService();

  final WindowService? _service;
  final StreamController<List<PlatformWindow>> _changes = StreamController<List<PlatformWindow>>.broadcast(sync: true);
  Timer? _timer;
  bool _fetching = false;
  List<PlatformWindow> _windows = const <PlatformWindow>[];

  WindowService get service => _service ?? WindowService.instance;

  List<PlatformWindow> get windows => List<PlatformWindow>.unmodifiable(_windows);

  Stream<List<PlatformWindow>> get changes => _changes.stream;

  bool get isAvailable => service.isAvailable;

  bool get isActivationAvailable => service.isActivationAvailable;

  bool get isPreviewAvailable => service.isPreviewAvailable;

  String get unavailableReason => service.unavailableReason;

  String get activationUnavailableReason => service.activationUnavailableReason;

  bool get isFetching => _fetching;

  /// Refreshes one neutral snapshot. A second caller while a refresh is in
  /// flight receives `false` and can use the previous snapshot.
  Future<bool> refresh() async {
    if (_fetching) return false;
    _fetching = true;
    try {
      if (!service.isAvailable) {
        _replace(const <PlatformWindow>[]);
        return false;
      }

      final List<PlatformWindow> raw = await service.enumerate();
      final List<PlatformWindow> next = _normalise(raw);
      _replace(next);
      return true;
    } catch (_) {
      // A permission change or disappearing desktop service is a capability
      // transition, not a reason to take down the launcher.
      _replace(const <PlatformWindow>[]);
      return false;
    } finally {
      _fetching = false;
    }
  }

  /// Starts conservative polling for consumers that need a live snapshot.
  /// Calling it repeatedly is idempotent; [refresh] remains available for
  /// search handlers that want to control their own timing.
  Future<void> start({Duration interval = const Duration(milliseconds: 900)}) async {
    if (_timer != null) return;
    _timer = Timer.periodic(interval, (_) => unawaited(refresh()));
    await refresh();
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
  }

  Future<bool> activate(PlatformWindow window) async {
    if (!service.isActivationAvailable) return false;
    return service.activate(window);
  }

  Future<PlatformWindowPreview?> capturePreview(PlatformWindow window) async {
    if (!service.isPreviewAvailable) return null;
    return service.capturePreview(window);
  }

  bool containsExecutable(String value) {
    final String query = value.toLowerCase();
    return _windows.any((PlatformWindow window) =>
        window.executable.toLowerCase() == query || window.applicationName.toLowerCase() == query);
  }

  List<PlatformWindow> _normalise(List<PlatformWindow> raw) {
    final Set<String> seen = <String>{};
    final List<PlatformWindow> result = <PlatformWindow>[];
    for (final PlatformWindow window in raw) {
      if (window.identity.isEmpty || window.title.trim().isEmpty || !window.isOnScreen) continue;
      if (!seen.add(window.identity)) continue;
      result.add(window);
    }
    return List<PlatformWindow>.unmodifiable(result);
  }

  void _replace(List<PlatformWindow> next) {
    final bool changed = !_sameSnapshot(_windows, next);
    _windows = next;
    if (changed && !_changes.isClosed) _changes.add(_windows);
  }

  bool _sameSnapshot(List<PlatformWindow> previous, List<PlatformWindow> next) {
    if (previous.length != next.length) return false;
    for (int index = 0; index < previous.length; index++) {
      if (previous[index] != next[index]) return false;
      final PlatformWindow oldWindow = previous[index];
      final PlatformWindow newWindow = next[index];
      if (oldWindow.title != newWindow.title ||
          oldWindow.applicationName != newWindow.applicationName ||
          oldWindow.executable != newWindow.executable ||
          oldWindow.executablePath != newWindow.executablePath ||
          oldWindow.helpText != newWindow.helpText ||
          oldWindow.isPinned != newWindow.isPinned ||
          oldWindow.isMinimized != newWindow.isMinimized ||
          oldWindow.x != newWindow.x ||
          oldWindow.y != newWindow.y ||
          oldWindow.width != newWindow.width ||
          oldWindow.height != newWindow.height) {
        return false;
      }
    }
    return true;
  }
}
