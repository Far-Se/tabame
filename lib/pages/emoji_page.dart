import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:math' as math;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes/quick_menu_box.dart';
import '../models/globals.dart';
import '../models/settings.dart';
import '../models/win32/keys.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../widgets/widgets/emoji_picker_modal.dart';

class EmojiPage extends StatefulWidget {
  const EmojiPage({super.key});

  @override
  State<EmojiPage> createState() => _EmojiPageState();
}

class _EmojiPageState extends State<EmojiPage> with QuickMenuTriggers, WindowListener {
  static const double _windowWidth = 420;
  static const double _windowHeight = 520;
  static const double _screenPadding = 12;

  bool _submitting = false;

  DateTime? shownDate;
  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    WindowManager.instance.addListener(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_positionWindowNearFocusedElement());
      shownDate = DateTime.now();
    });
  }

  @override
  Future<void> onQuickMenuVisible(QuickMenuPage type, bool center) async {
    if (type == QuickMenuPage.emojiPicker) {
      _positionWindowNearFocusedElement();
      shownDate = DateTime.now();
      if (mounted) setState(() {});
    }
  }

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "emojiPicker:refresh") {
      Debug.add("emojiPicker:refresh");
      _positionWindowNearFocusedElement();
      shownDate = DateTime.now();
    }
  }

  @override
  void onWindowBlur() {
    if (shownDate != null && DateTime.now().millisecondsSinceEpoch - shownDate!.millisecondsSinceEpoch > 600) {
      QuickMenuFunctions.hideQuickMenu();
    }
  }

  void _closeEmojiPicker() async {
    await _refocusPreviousWindow();
    QuickMenuFunctions.hideQuickMenu();
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    WindowManager.instance.removeListener(this);
    // QuickMenuFunctions.toggleQuickMenu(visible: false, type: QuickMenuPage.quickMenu);
    // QuickMenuFunctions.refreshQuickMenu();
    super.dispose();
  }

  late WinRect focusedRect;
  Future<void> _positionWindowNearFocusedElement() async {
    if (shownDate != null && DateTime.now().millisecondsSinceEpoch - shownDate!.millisecondsSinceEpoch < 250) return;
    try {
      Monitor.fetchMonitors();

      await windowManager.setMinimumSize(const Size(320, 420));
      await windowManager.setSize(const Size(_windowWidth, _windowHeight));
      // final CaretDebugInfo result = await getFocusedElementCaretRectDebug();
      // print(result);
      focusedRect = Globals.focusedRect ?? await getFocusedElementCaretRect();
      // focusedRect = await getFocusedElementRect();
      if (focusedRect.left < 0 || focusedRect.isEmpty) {
        final List<int> mouse = WinUtils.getMousePosXY();
        focusedRect.left = mouse[0];
        focusedRect.top = mouse[1] - 30;
        focusedRect.bottom = mouse[1] + 30;
      }
      final PointXY anchor = PointXY.from(
        focusedRect.left + math.max(0, focusedRect.width ~/ 2),
        focusedRect.bottom,
      );

      int monitorHandle = Monitor.getMonitorFromPoint(anchor);
      Square? monitorBounds = Monitor.monitorSizes[monitorHandle];
      monitorBounds ??= Monitor.monitorSizes[Monitor.getCursorMonitor()];
      monitorBounds ??= Monitor.monitorSizes.isNotEmpty ? Monitor.monitorSizes.values.first : null;
      if (monitorBounds == null) return;

      final double maxWidth = math.max(320, monitorBounds.width - (_screenPadding * 2));
      final double maxHeight = math.max(420, monitorBounds.height - (_screenPadding * 2));
      final double targetWidth = math.min(_windowWidth, maxWidth);
      final double targetHeight = math.min(_windowHeight, maxHeight);

      await windowManager.setSize(Size(targetWidth, targetHeight));

      double targetX = focusedRect.left.toDouble();
      double targetY = focusedRect.bottom.toDouble() + 8;

      final double minX = monitorBounds.x + _screenPadding;
      final double minY = monitorBounds.y + _screenPadding;
      final double maxX = monitorBounds.x + monitorBounds.width - targetWidth - _screenPadding;
      final double maxY = monitorBounds.y + monitorBounds.height - targetHeight - _screenPadding;

      targetX = targetX.clamp(minX, math.max(minX, maxX));
      targetY = targetY.clamp(minY, math.max(minY, maxY));

      if (focusedRect.bottom + targetHeight + _screenPadding > monitorBounds.y + monitorBounds.height) {
        final double aboveY = focusedRect.top.toDouble() - targetHeight - 8;
        targetY = aboveY.clamp(minY, math.max(minY, maxY));
      }

      await windowManager.setPosition(Offset(targetX, targetY), animate: false);
      Win32.activateWindow(Win32.hWnd);
    } catch (_) {}
  }

  Future<void> _refocusPreviousWindow() async {
    final int targetHwnd = Globals.lastFocusedWinHWND;
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final Pointer<POINT> cursorPointPointer = calloc<POINT>();
    cursorPointPointer.ref.x = focusedRect.left;
    cursorPointPointer.ref.y = focusedRect.bottom;

    final int hWnd = WindowFromPoint(cursorPointPointer.ref);
    free(cursorPointPointer);
    if (hWnd != 0) {
      Win32.activateWindow(hWnd);
    } else {
      Win32.activateWindow(targetHwnd);
    }
  }

  Future<void> _handleEmojiSelected(String emoji) async {
    if (_submitting) return;
    _submitting = true;

    await Clipboard.setData(ClipboardData(text: emoji));
    Globals.quickMenuPage = QuickMenuPage.quickMenu;
    await QuickMenuFunctions.hideQuickMenu();
    await _refocusPreviousWindow();

    await Future<void>.delayed(const Duration(milliseconds: 60));
    WinKeys.send("{#CONTROL}V{|}");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Focus(
        focusNode: FocusNode(),
        onKeyEvent: (FocusNode x, KeyEvent event) {
          if (event.logicalKey == LogicalKeyboardKey.escape) {
            _closeEmojiPicker();

            return KeyEventResult.handled;
          }
          return KeyEventResult.ignored;
        },
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: EmojiPickerModal(
              title: "Emoji Picker",
              quickTip: "Press Ctrl+V if it doesn't paste",
              onEmojiSelected: _handleEmojiSelected,
              userPredefined: false,
              onCloseRequested: _closeEmojiPicker,
            ),
          ),
        ),
      ),
    );
  }
}
