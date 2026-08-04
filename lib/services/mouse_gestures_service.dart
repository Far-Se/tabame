import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';

import '../logic/error_handler.dart';
import '../models/classes/boxes.dart';
import '../models/classes/hotkeys.dart';
import '../models/classes/saved_maps.dart';
import '../models/settings.dart';
import '../models/win32/keys.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win_utils.dart';
import '../pages/color_picker/win32_helper.dart';

/// Hot corners + right/middle-button mouse gestures, driven by a lightweight cursor
/// poller in the QuickMenu process (no extra native hooks — the generic
/// `WinHooks` channel handler would clobber the main tabamewin32 listener).
///
/// Hot corners: the cursor dwelling in a corner of the primary display for
/// [MouseControlConfig.cornerDwellMs] fires that corner's action, re-armed only
/// after the cursor leaves the corner.
///
/// Gestures: while the right or middle mouse button is held, the pointer path is sampled
/// at 20 ms and tokenized into cardinal strokes (L/R/U/D, e.g. "RD" = right
/// then down). On release the matching binding fires. The button is only
/// observed — never swallowed — so ordinary right-clicks are untouched; if a
/// context menu popped on release, it is dismissed with an Escape keypress.
class MouseGesturesService extends TabameListener {
  MouseGesturesService._();
  static final MouseGesturesService instance = MouseGesturesService._();

  static const int _idleIntervalMs = 120;
  // static const int _maxGestureDurationMs = 600;
  MouseControlConfig _config = MouseControlConfig();
  Timer? _cornerTimer;
  bool _listening = false;

  // Hot-corner state.
  String _cornerCandidate = '';
  int _cornerEnterMs = 0;
  bool _cornerFired = false;

  void init() {
    if (!_listening) {
      NativeHooks.addListener(this);
      _listening = true;
    }
    applyConfig();
  }

  /// (Re)reads the config and starts/stops the poller accordingly. Call after
  /// every settings change.
  void applyConfig() {
    _config = Boxes.mouseControl;
    _cornerTimer?.cancel();
    _cornerTimer = null;
    _cornerCandidate = '';
    _cornerFired = false;

    unawaited(_configureNativeGestures());
    if (_config.hotCornersEnabled) {
      _cornerTimer = Timer.periodic(const Duration(milliseconds: _idleIntervalMs), (Timer _) => _cornerTickSafely());
    }
  }

  void dispose() {
    _cornerTimer?.cancel();
    unawaited(tabameWin32MethodChannel.invokeMethod<void>('configureMouseGestures', <String, bool>{
      'rightEnabled': false,
      'middleEnabled': false,
    }));
    if (_listening) NativeHooks.removeListener(this);
    _listening = false;
  }

  Future<void> _configureNativeGestures() async {
    try {
      final bool enabled = _config.gesturesEnabled;
      await tabameWin32MethodChannel.invokeMethod<void>('configureMouseGestures', <String, bool>{
        'rightEnabled': enabled && _hasGestureForButton('right'),
        'middleEnabled': enabled && _hasGestureForButton('middle'),
      });
    } catch (e, s) {
      unawaited(ErrorLogger.log('MouseGesturesService', e.toString(), s));
    }
  }

  bool _hasGestureForButton(String button) => _config.gestures.any(
        (MouseGestureBinding binding) => binding.enabled && binding.action.isSet && binding.button == button,
      );

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

  void _cornerTickSafely() {
    try {
      _cornerTick();
    } catch (e, s) {
      unawaited(ErrorLogger.log('MouseGesturesService', e.toString(), s));
    }
  }

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

  @override
  void onMouseGesture(String button, String pattern, int durationMs) {
    if (durationMs > user.mouseGestureMaxDelay) return;

    MouseGestureBinding? match;
    for (final MouseGestureBinding binding in _config.gestures) {
      if (binding.enabled && binding.action.isSet && binding.button == button && binding.pattern == pattern) {
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
    Win32Helper.playPopSound();
  }
}
