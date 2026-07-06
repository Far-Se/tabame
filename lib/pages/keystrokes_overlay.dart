import 'dart:async';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../logic/app_startup.dart';
import '../models/classes/boxes.dart';
import '../models/settings.dart';

/// Keystroke & Click Visualizer overlay.
///
/// A transparent, click-through window spanning the whole virtual desktop that
/// renders recently pressed key combos (as badges) and mouse clicks (as
/// ripples), for screencasts and live demos. Input arrives system-wide from the
/// native low-level hooks via [enableKeystrokeVisualizer] / [KeyVizEvent].
///
/// All appearance is driven by `user.keystrokes*` settings (see the Keystrokes
/// Interface subpage). The overlay is toggled from the QuickMenu button by
/// launching / closing this `-keystrokes` process.
Future<void> startKeystrokes() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStartup.initialize();
  await windowManager.ensureInitialized();
  await Boxes.registerBoxes(justLoad: true);

  const WindowOptions windowOptions = WindowOptions(
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: true,
    title: "Tabame Keystrokes",
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
  });

  runApp(const KeystrokesApp());
}

class KeystrokesApp extends StatelessWidget {
  const KeystrokesApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      color: Colors.transparent,
      home: KeystrokesOverlay(),
    );
  }
}

class _KeyBadge {
  final String label;
  final int id;
  DateTime bornAt;
  _KeyBadge(this.label, this.id) : bornAt = DateTime.now();
}

/// A horizontal line of badges. Plain typing flows left-to-right within one row
/// (old presses drift to the left); a hotkey/chord starts its own row and grows
/// as the chord builds up ("Ctrl", "Ctrl + Shift", "Ctrl + Shift + F").
class _KeyRow {
  final int id;
  final bool isHotkey;
  final List<_KeyBadge> badges = <_KeyBadge>[];
  DateTime lastAt = DateTime.now();
  _KeyRow(this.id, this.isHotkey);
}

class _ClickRipple {
  final Offset pos; // overlay-local
  final Color color;
  final DateTime bornAt = DateTime.now();
  _ClickRipple(this.pos, this.color);
}

class KeystrokesOverlay extends StatefulWidget {
  const KeystrokesOverlay({super.key});

  @override
  State<KeystrokesOverlay> createState() => _KeystrokesOverlayState();
}

class _KeystrokesOverlayState extends State<KeystrokesOverlay> with TabameListener {
  int _vLeft = 0;
  int _vTop = 0;
  int _vWidth = 0;
  int _vHeight = 0;

  int _overlayHwnd = 0;
  int _nextId = 0;
  int _nextRowId = 0;

  final List<_KeyRow> _rows = <_KeyRow>[];
  final List<_ClickRipple> _ripples = <_ClickRipple>[];

  Timer? _ticker;

  static const Duration _clickLife = Duration(milliseconds: 600);
  // Presses further apart than this start a fresh row instead of joining the
  // current one.
  static const int _groupGapMs = 1200;
  static const int _maxRows = 6;
  static const int _maxRowLen = 12;

  @override
  void initState() {
    super.initState();
    NativeHooks.registerCallHandler();
    NativeHooks.addListener(this);

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _sizeToVirtualScreen();
      _setupOverlayWindow();
      await enableKeystrokeVisualizer(true);
    });

    // ~30fps drives badge fade-out and click-ripple animation.
    _ticker = Timer.periodic(const Duration(milliseconds: 33), (_) => _prune());
  }

  @override
  void dispose() {
    _ticker?.cancel();
    NativeHooks.removeListener(this);
    unawaited(enableKeystrokeVisualizer(false));
    super.dispose();
  }

  int get _fadeMs => user.keystrokesFadeMs;

  void _prune() {
    final DateTime now = DateTime.now();
    final bool hadContent = _rows.isNotEmpty || _ripples.isNotEmpty;
    for (final _KeyRow r in _rows) {
      r.badges.removeWhere((_KeyBadge b) => now.difference(b.bornAt).inMilliseconds > _fadeMs);
    }
    _rows.removeWhere((_KeyRow r) => r.badges.isEmpty);
    _ripples.removeWhere((_ClickRipple r) => now.difference(r.bornAt) > _clickLife);
    // Repaint while anything is (or just was) on screen (badges fade over life).
    if (hadContent || _rows.isNotEmpty || _ripples.isNotEmpty) {
      if (mounted) setState(() {});
    }
  }

  // ---- Native event stream -------------------------------------------------
  @override
  void onKeyVizEvent(KeyVizEvent event) {
    if (!mounted) return;
    if (event.isClick) {
      if (!user.keystrokesShowClicks) return;
      _addClick(event);
    } else {
      _addKey(event);
    }
  }

  void _addKey(KeyVizEvent e) {
    final bool hasMod = e.ctrl || e.alt || e.shift || e.win;
    final bool isModifierKey = _modifierVks.contains(e.code);
    // "Modifiers only" hides bare typing but still shows real chords.
    if (user.keystrokesModifiersOnly && !hasMod && !isModifierKey) return;

    final String label = _comboLabel(e);
    if (label.isEmpty) return;

    final bool isHotkey = hasMod || isModifierKey;
    final DateTime now = DateTime.now();

    setState(() {
      final _KeyRow? last = _rows.isNotEmpty ? _rows.last : null;
      final bool stale = last == null || now.difference(last.lastAt).inMilliseconds > _groupGapMs;

      if (isHotkey) {
        // Grow the current chord so it reads as one building combo — each new
        // key extends the previous badge ("Ctrl" -> "Ctrl + Shift" ->
        // "Ctrl + Shift + F"). A different chord (or a pause) starts a new row.
        if (!stale && last.isHotkey) {
          final _KeyBadge tip = last.badges.last;
          if (label == tip.label) {
            last.lastAt = now; // auto-repeat while holding — just keep it alive
          } else if (label.startsWith(tip.label)) {
            last.badges.add(_KeyBadge(label, _nextId++));
            last.lastAt = now;
            while (last.badges.length > _maxRowLen) {
              last.badges.removeAt(0);
            }
          } else {
            _startRow(true, label, now);
          }
        } else {
          _startRow(true, label, now);
        }
      } else {
        // Plain typing flows left-to-right in one row until a pause or a chord.
        if (!stale && !last.isHotkey) {
          last.badges.add(_KeyBadge(label, _nextId++));
          last.lastAt = now;
          while (last.badges.length > _maxRowLen) {
            last.badges.removeAt(0);
          }
        } else {
          _startRow(false, label, now);
        }
      }

      while (_rows.length > _maxRows) {
        _rows.removeAt(0);
      }
    });
  }

  void _startRow(bool isHotkey, String label, DateTime now) {
    final _KeyRow row = _KeyRow(_nextRowId++, isHotkey);
    row.badges.add(_KeyBadge(label, _nextId++));
    row.lastAt = now;
    _rows.add(row);
  }

  void _addClick(KeyVizEvent e) {
    final Offset local = Offset((e.x - _vLeft).toDouble(), (e.y - _vTop).toDouble());
    Color color;
    switch (e.code) {
      case 0: // left
        color = const Color(0xFF4FC3F7);
      case 1: // right
        color = const Color(0xFFFF8A65);
      case 2: // middle
        color = const Color(0xFFBA68C8);
      case 3: // wheel up
      case 4: // wheel down
        color = const Color(0xFF81C784);
      default:
        color = const Color(0xFFFFD54F);
    }
    setState(() {
      _ripples.add(_ClickRipple(local, color));
      while (_ripples.length > 12) {
        _ripples.removeAt(0);
      }
    });
  }

  String _comboLabel(KeyVizEvent e) {
    final List<String> parts = <String>[];
    // Show live modifiers, but avoid duplicating the pressed modifier itself.
    if (e.ctrl && e.code != VK_CONTROL && e.code != VK_LCONTROL && e.code != VK_RCONTROL) parts.add("Ctrl");
    if (e.alt && e.code != VK_MENU && e.code != VK_LMENU && e.code != VK_RMENU) parts.add("Alt");
    if (e.shift && e.code != VK_SHIFT && e.code != VK_LSHIFT && e.code != VK_RSHIFT) parts.add("Shift");
    if (e.win && e.code != VK_LWIN && e.code != VK_RWIN) parts.add("Win");
    final String key = _vkToLabel(e.code);
    if (key.isEmpty) return "";
    parts.add(key);
    return parts.join(" + ");
  }

  // ---- Window sizing / styling --------------------------------------------
  void _sizeToVirtualScreen() {
    _vLeft = GetSystemMetrics(SM_XVIRTUALSCREEN);
    _vTop = GetSystemMetrics(SM_YVIRTUALSCREEN);
    _vWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
    _vHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);
    if (_vWidth == 0) {
      _vWidth = GetSystemMetrics(SM_CXSCREEN);
      _vHeight = GetSystemMetrics(SM_CYSCREEN);
    }
  }

  void _setupOverlayWindow() {
    _overlayHwnd = GetAncestor(GetActiveWindow(), GA_ROOT);
    if (_overlayHwnd == 0) return;
    final int style = GetWindowLongPtr(_overlayHwnd, GWL_STYLE);
    SetWindowLongPtr(
      _overlayHwnd,
      GWL_STYLE,
      style & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU),
    );
    final int exStyle = GetWindowLongPtr(_overlayHwnd, GWL_EXSTYLE);
    SetWindowLongPtr(
      _overlayHwnd,
      GWL_EXSTYLE,
      exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW | WS_EX_TOPMOST,
    );
    SetLayeredWindowAttributes(_overlayHwnd, 0, 255, LWA_ALPHA);
    unawaited(excludeWindowFromCapture(_overlayHwnd));
    SetWindowPos(_overlayHwnd, HWND_TOPMOST, _vLeft, _vTop, _vWidth, _vHeight,
        SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW);
  }

  // ---- Build ---------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final double scale = (user.keystrokesScale.clamp(60, 200)) / 100.0;
    return IgnorePointer(
      ignoring: true,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: <Widget>[
            // Click ripples layer.
            CustomPaint(
              size: Size.infinite,
              painter: _RipplePainter(List<_ClickRipple>.of(_ripples), _clickLife),
            ),
            // Key badges layer, anchored per the configured position.
            _positioned(
              child: _KeyRowsView(
                rows: List<_KeyRow>.of(_rows),
                scale: scale,
                fadeMs: _fadeMs,
                bottomAligned: user.keystrokesPosition >= 2,
                rowAlign: _rowAlign,
              ),
            ),
          ],
        ),
      ),
    );
  }

  CrossAxisAlignment get _rowAlign {
    switch (user.keystrokesPosition) {
      case 0: // top-left
      case 4: // bottom-left
        return CrossAxisAlignment.start;
      case 3: // bottom-right
        return CrossAxisAlignment.end;
      case 1: // top-center
      case 2: // bottom-center
      default:
        return CrossAxisAlignment.center;
    }
  }

  Widget _positioned({required Widget child}) {
    const double margin = 40;
    switch (user.keystrokesPosition) {
      case 0: // top-left
        return Positioned(left: margin, top: margin, child: child);
      case 1: // top-center
        return Positioned(top: margin, left: 0, right: 0, child: Center(child: child));
      case 3: // bottom-right
        return Positioned(right: margin, bottom: margin, child: child);
      case 4: // bottom-left
        return Positioned(left: margin, bottom: margin, child: child);
      case 2: // bottom-center
      default:
        return Positioned(bottom: margin, left: 0, right: 0, child: Center(child: child));
    }
  }
}

/// A vertical stack of rows; each row is a horizontal line of fading badges.
class _KeyRowsView extends StatelessWidget {
  final List<_KeyRow> rows;
  final double scale;
  final int fadeMs;
  final bool bottomAligned;
  final CrossAxisAlignment rowAlign;
  const _KeyRowsView({
    required this.rows,
    required this.scale,
    required this.fadeMs,
    required this.bottomAligned,
    required this.rowAlign,
  });

  @override
  Widget build(BuildContext context) {
    final DateTime now = DateTime.now();
    final List<Widget> rowWidgets = <Widget>[];
    for (final _KeyRow row in rows) {
      final int len = row.badges.length;
      final List<Widget> chips = <Widget>[];
      for (int i = 0; i < len; i++) {
        final _KeyBadge b = row.badges[i];
        final int age = now.difference(b.bornAt).inMilliseconds;
        // Tail fade over the last 500ms of the badge's life.
        final double ageOp = age >= fadeMs ? 0.0 : (age > fadeMs - 500 ? (fadeMs - age) / 500.0 : 1.0);
        // Older presses (further from the newest) dim quickly, so a fast typist's
        // row stays short instead of marching across the screen.
        final int fromNewest = len - 1 - i;
        final double posOp = (1.0 - fromNewest * 0.15).clamp(0.0, 1.0);
        chips.add(Opacity(
          key: ValueKey<int>(b.id),
          opacity: (ageOp * posOp).clamp(0.0, 1.0),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 3 * scale),
            child: _KeyChip(label: b.label, scale: scale),
          ),
        ));
      }
      rowWidgets.add(Padding(
        key: ValueKey<int>(row.id),
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: chips,
        ),
      ));
    }
    final List<Widget> ordered = bottomAligned ? rowWidgets : rowWidgets.reversed.toList();
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: rowAlign,
      children: ordered,
    );
  }
}

class _KeyChip extends StatelessWidget {
  final String label;
  final double scale;
  const _KeyChip({required this.label, required this.scale});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16 * scale, vertical: 9 * scale),
      decoration: BoxDecoration(
        color: const Color(0xEE12181F),
        borderRadius: BorderRadius.circular(10 * scale),
        border: Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 12 * scale, offset: Offset(0, 3 * scale)),
        ],
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white,
          fontSize: 22 * scale,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

class _RipplePainter extends CustomPainter {
  final List<_ClickRipple> ripples;
  final Duration life;
  const _RipplePainter(this.ripples, this.life);

  @override
  void paint(Canvas canvas, Size size) {
    final DateTime now = DateTime.now();
    for (final _ClickRipple r in ripples) {
      final double t = (now.difference(r.bornAt).inMilliseconds / life.inMilliseconds).clamp(0.0, 1.0);
      final double radius = 14 + t * 34;
      final double opacity = (1.0 - t) * 0.8;
      canvas.drawCircle(
        r.pos,
        radius,
        Paint()
          ..color = r.color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3.5,
      );
      canvas.drawCircle(r.pos, 5, Paint()..color = r.color.withValues(alpha: (1.0 - t) * 0.5));
    }
  }

  @override
  bool shouldRepaint(_RipplePainter old) => true;
}

// ---------------------------------------------------------------------------
// Virtual-key mapping
// ---------------------------------------------------------------------------
const Set<int> _modifierVks = <int>{
  VK_CONTROL, VK_LCONTROL, VK_RCONTROL, //
  VK_MENU, VK_LMENU, VK_RMENU, //
  VK_SHIFT, VK_LSHIFT, VK_RSHIFT, //
  VK_LWIN, VK_RWIN,
};

String _vkToLabel(int vk) {
  // Letters and top-row digits map directly to their ASCII glyph.
  if (vk >= 0x41 && vk <= 0x5A) return String.fromCharCode(vk); // A-Z
  if (vk >= 0x30 && vk <= 0x39) return String.fromCharCode(vk); // 0-9
  if (vk >= VK_NUMPAD0 && vk <= VK_NUMPAD9) return "Num${vk - VK_NUMPAD0}";
  if (vk >= VK_F1 && vk <= VK_F24) return "F${vk - VK_F1 + 1}";
  switch (vk) {
    case VK_CONTROL:
    case VK_LCONTROL:
    case VK_RCONTROL:
      return "Ctrl";
    case VK_MENU:
    case VK_LMENU:
    case VK_RMENU:
      return "Alt";
    case VK_SHIFT:
    case VK_LSHIFT:
    case VK_RSHIFT:
      return "Shift";
    case VK_LWIN:
    case VK_RWIN:
      return "Win";
    case VK_SPACE:
      return "Space";
    case VK_RETURN:
      return "Enter";
    case VK_TAB:
      return "Tab";
    case VK_ESCAPE:
      return "Esc";
    case VK_BACK:
      return "Backspace";
    case VK_DELETE:
      return "Del";
    case VK_INSERT:
      return "Ins";
    case VK_HOME:
      return "Home";
    case VK_END:
      return "End";
    case VK_PRIOR:
      return "PgUp";
    case VK_NEXT:
      return "PgDn";
    case VK_UP:
      return "↑";
    case VK_DOWN:
      return "↓";
    case VK_LEFT:
      return "←";
    case VK_RIGHT:
      return "→";
    case VK_CAPITAL:
      return "CapsLock";
    case VK_SNAPSHOT:
      return "PrtSc";
    case VK_OEM_PLUS:
      return "+";
    case VK_OEM_MINUS:
      return "-";
    case VK_OEM_COMMA:
      return ",";
    case VK_OEM_PERIOD:
      return ".";
    case VK_OEM_1:
      return ";";
    case VK_OEM_2:
      return "/";
    case VK_OEM_3:
      return "`";
    case VK_OEM_4:
      return "[";
    case VK_OEM_5:
      return r"\";
    case VK_OEM_6:
      return "]";
    case VK_OEM_7:
      return "'";
    case VK_MULTIPLY:
      return "Num*";
    case VK_ADD:
      return "Num+";
    case VK_SUBTRACT:
      return "Num-";
    case VK_DIVIDE:
      return "Num/";
    case VK_DECIMAL:
      return "Num.";
    default:
      return "";
  }
}
