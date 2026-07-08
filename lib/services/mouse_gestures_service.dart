import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:win32/win32.dart';

import '../logic/error_handler.dart';
import '../models/classes/boxes.dart';
import '../models/classes/hotkeys.dart';
import '../models/classes/saved_maps.dart';
import '../models/win32/keys.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win_utils.dart';

/// Hot corners + right-button mouse gestures, driven by a lightweight cursor
/// poller in the QuickMenu process (no extra native hooks — the generic
/// `WinHooks` channel handler would clobber the main tabamewin32 listener).
///
/// Hot corners: the cursor dwelling in a corner of the primary display for
/// [MouseControlConfig.cornerDwellMs] fires that corner's action, re-armed only
/// after the cursor leaves the corner.
///
/// Gestures: while the right mouse button is held, the pointer path is sampled
/// at 20 ms and tokenized into cardinal strokes (L/R/U/D, e.g. "RD" = right
/// then down). On release the matching binding fires. The button is only
/// observed — never swallowed — so ordinary right-clicks are untouched; if a
/// context menu popped on release, it is dismissed with an Escape keypress.
class MouseGesturesService {
  MouseGesturesService._();
  static final MouseGesturesService instance = MouseGesturesService._();

  static const int _idleIntervalMs = 120;
  static const int _captureIntervalMs = 20;
  static const int _strokeThresholdPx = 50;

  MouseControlConfig _config = MouseControlConfig();
  Timer? _idleTimer;
  Timer? _captureTimer;

  // Hot-corner state.
  String _cornerCandidate = '';
  int _cornerEnterMs = 0;
  bool _cornerFired = false;

  // Gesture state.
  final List<PointXY> _points = <PointXY>[];

  void init() => applyConfig();

  /// (Re)reads the config and starts/stops the poller accordingly. Call after
  /// every settings change.
  void applyConfig() {
    _config = Boxes.mouseControl;
    _idleTimer?.cancel();
    _idleTimer = null;
    _captureTimer?.cancel();
    _captureTimer = null;
    _points.clear();
    _cornerCandidate = '';
    _cornerFired = false;

    if (!_config.hotCornersEnabled && !_config.gesturesEnabled) return;
    _idleTimer = Timer.periodic(const Duration(milliseconds: _idleIntervalMs), (Timer _) => _idleTick());
  }

  void dispose() {
    _idleTimer?.cancel();
    _captureTimer?.cancel();
  }

  void _idleTick() {
    try {
      if (_captureTimer != null) return;
      if (_config.gesturesEnabled && _rightButtonHeld()) {
        _beginCapture();
        return;
      }
      if (_config.hotCornersEnabled) _cornerTick();
    } catch (e, s) {
      unawaited(ErrorLogger.log('MouseGesturesService', e.toString(), s));
    }
  }

  bool _rightButtonHeld() => (GetAsyncKeyState(VK_RBUTTON) & 0x8000) != 0;

  /// Raw physical cursor position — corner checks compare against the physical
  /// GetSystemMetrics sizes, so the DPI-scaled WinUtils.getMousePos won't do.
  PointXY _cursorPos() {
    final Pointer<POINT> point = calloc<POINT>();
    GetCursorPos(point);
    final PointXY pos = PointXY(X: point.ref.x, Y: point.ref.y);
    free(point);
    return pos;
  }

  // ---------------------------------------------------------------------------
  // Hot corners
  // ---------------------------------------------------------------------------

  void _cornerTick() {
    final PointXY pos = _cursorPos();
    final int screenWidth = GetSystemMetrics(SM_CXSCREEN);
    final int screenHeight = GetSystemMetrics(SM_CYSCREEN);
    final int size = _config.cornerSizePx;

    String corner = '';
    if (pos.X <= size && pos.Y <= size) {
      corner = 'tl';
    } else if (pos.X >= screenWidth - 1 - size && pos.Y <= size) {
      corner = 'tr';
    } else if (pos.X <= size && pos.Y >= screenHeight - 1 - size) {
      corner = 'bl';
    } else if (pos.X >= screenWidth - 1 - size && pos.Y >= screenHeight - 1 - size) {
      corner = 'br';
    }

    if (corner.isEmpty) {
      _cornerCandidate = '';
      _cornerFired = false;
      return;
    }
    if (corner != _cornerCandidate) {
      _cornerCandidate = corner;
      _cornerEnterMs = DateTime.now().millisecondsSinceEpoch;
      _cornerFired = false;
      return;
    }
    if (_cornerFired) return;
    if (DateTime.now().millisecondsSinceEpoch - _cornerEnterMs >= _config.cornerDwellMs) {
      _cornerFired = true;
      final GestureAction? action = _config.corners[corner];
      if (action != null && action.isSet) executeAction(action);
    }
  }

  // ---------------------------------------------------------------------------
  // Mouse gestures
  // ---------------------------------------------------------------------------

  void _beginCapture() {
    _points
      ..clear()
      ..add(_cursorPos());
    _captureTimer = Timer.periodic(const Duration(milliseconds: _captureIntervalMs), (Timer _) => _captureTick());
  }

  void _captureTick() {
    try {
      _points.add(_cursorPos());
      if (_rightButtonHeld()) {
        // Safety valve: a 15s hold is not a gesture (games, drag operations).
        if (_points.length > 750) _endCapture(run: false);
        return;
      }
      _endCapture(run: true);
    } catch (e, s) {
      _endCapture(run: false);
      unawaited(ErrorLogger.log('MouseGesturesService', e.toString(), s));
    }
  }

  void _endCapture({required bool run}) {
    _captureTimer?.cancel();
    _captureTimer = null;
    if (!run) return;

    final String pattern = _classify(_points);
    _points.clear();
    if (pattern.isEmpty) return;

    MouseGestureBinding? match;
    for (final MouseGestureBinding binding in _config.gestures) {
      if (binding.enabled && binding.action.isSet && binding.pattern == pattern) {
        match = binding;
        break;
      }
    }
    if (match == null) return;

    final GestureAction action = match.action;
    // The release may have opened a context menu under the cursor — dismiss it
    // (menu windows use the #32768 class) before running the action.
    Timer(const Duration(milliseconds: 120), () {
      try {
        if (FindWindow(TEXT('#32768'), nullptr) != 0) {
          WinKeys.single(VK.ESCAPE, KeySentMode.normal);
        }
      } catch (_) {}
      Timer(const Duration(milliseconds: 80), () => executeAction(action));
    });
  }

  /// Tokenizes the sampled path into cardinal strokes: displacement accumulates
  /// until it exceeds [_strokeThresholdPx], emitting L/R/U/D and resetting.
  /// Consecutive identical tokens collapse. More than 4 tokens is noise.
  String _classify(List<PointXY> points) {
    if (points.length < 2) return '';
    String tokens = '';
    String currentDirection = '';
    int accumulatedX = 0;
    int accumulatedY = 0;

    for (int i = 1; i < points.length; i++) {
      accumulatedX += points[i].X - points[i - 1].X;
      accumulatedY += points[i].Y - points[i - 1].Y;
      if (accumulatedX.abs() < _strokeThresholdPx && accumulatedY.abs() < _strokeThresholdPx) continue;

      final String direction = accumulatedX.abs() >= accumulatedY.abs()
          ? (accumulatedX > 0 ? 'R' : 'L')
          : (accumulatedY > 0 ? 'D' : 'U');
      if (direction != currentDirection) {
        tokens += direction;
        currentDirection = direction;
      }
      accumulatedX = 0;
      accumulatedY = 0;
    }

    if (tokens.length > 4) return '';
    return tokens;
  }

  // ---------------------------------------------------------------------------
  // Action execution (shared by corners and gestures)
  // ---------------------------------------------------------------------------

  static void executeAction(GestureAction action) {
    switch (action.type) {
      case 'function':
        HotKeyInfo.tabameFunctionsMap[action.value]?.call();
        break;
      case 'popup':
        QuickMenuFunctions.openQuickMenuWithAction(action.value, center: true);
        break;
      case 'command':
        WinUtils.open(action.value);
        break;
      case 'keys':
        WinKeys.send(action.value);
        break;
    }
  }
}
