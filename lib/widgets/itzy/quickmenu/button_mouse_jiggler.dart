import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:win32/win32.dart';

import '../../../models/globals.dart';
import '../../widgets/quick_actions_item.dart';

/// Owns the jiggle [Timer] at top level so it keeps running while the QuickMenu
/// is hidden-but-mounted (see the QuickMenu RAM strategy — the tree stays alive
/// on hide, and widget state would otherwise be the wrong place to hold it).
class MouseJigglerController {
  MouseJigglerController._();

  static Timer? _timer;
  static const Duration _interval = Duration(seconds: 30);

  static bool get isRunning => _timer != null;

  static void setEnabled(bool enabled) {
    Globals.mouseJiggler = enabled;
    if (enabled) {
      _timer ??= Timer.periodic(_interval, (_) => _nudge());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  /// Moves the cursor one pixel and back so idle/away detection resets without
  /// meaningfully disturbing the pointer.
  static void _nudge() {
    final Pointer<POINT> point = calloc<POINT>();
    try {
      if (GetCursorPos(point) == 0) return;
      final int x = point.ref.x;
      final int y = point.ref.y;
      SetCursorPos(x + 1, y);
      Future<void>.delayed(const Duration(milliseconds: 40), () => SetCursorPos(x, y));
    } finally {
      free(point);
    }
  }
}

class MouseJigglerButton extends StatefulWidget {
  const MouseJigglerButton({super.key});

  @override
  State<MouseJigglerButton> createState() => _MouseJigglerButtonState();
}

class _MouseJigglerButtonState extends State<MouseJigglerButton> {
  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "Mouse jiggler",
      icon: Icon(
        Icons.mouse_rounded,
        color: Globals.mouseJiggler ? Colors.red : Theme.of(context).iconTheme.color,
      ),
      onTap: () {
        MouseJigglerController.setEnabled(!Globals.mouseJiggler);
        setState(() {});
      },
    );
  }
}
