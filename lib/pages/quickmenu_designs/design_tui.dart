import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/settings.dart';
import '../../models/util/quickmenu_tui_theme.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

/// A cmd-style console around the live QuickMenu controls.
class MainMenuTuiWidget extends StatelessWidget {
  const MainMenuTuiWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: QuickMenuTuiTheme.theme(Theme.of(context)),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: 203, maxHeight: MediaQuery.sizeOf(context).height - 50),
        child: Container(
          decoration: BoxDecoration(
              color: Design.glassColor(QuickMenuTuiTheme.background),
              border: Border.all(color: QuickMenuTuiTheme.border)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: <Widget>[
              const _TuiTitleBar(),
              Flexible(
                  child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // Padding(
                    //     padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    //     child: Text('Tabame QuickMenu', style: QuickMenuTuiTheme.text())),
                    if (!user.quickActionsAtBottom) ...<Widget>[
                      const _TuiSeparator(),
                      const TopBar(),
                    ] else if (user.bottomBarOnTop) ...<Widget>[
                      const _TuiSeparator(),
                      const PinnedAndTrayList(),
                    ],
                    const _TuiSeparator(),
                    const Padding(padding: EdgeInsets.symmetric(horizontal: 4), child: TaskBar()),
                    if (!user.bottomBarOnTop) ...<Widget>[
                      const _TuiSeparator(),
                      const PinnedAndTrayList(),
                    ],
                    if (user.taskManagerStats) ...<Widget>[
                      const _TuiSeparator(),
                      const TaskbarStats(withTopDivider: false),
                    ],
                    if (user.libreStats) ...<Widget>[
                      const _TuiSeparator(),
                      const LibreStats(withTopDivider: false),
                    ],
                    // Padding(
                    //     padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
                    //     child: Text('Right-click a window for commands.',
                    //         style:
                    //             QuickMenuTuiTheme.text(color: QuickMenuTuiTheme.dim, size: Design.baseFontSize + 2))),
                    const Padding(padding: EdgeInsets.fromLTRB(4, 0, 4, 4), child: BottomBar()),
                  ],
                ),
              )),
            ],
          ),
        ),
      ),
    );
  }
}

class _TuiSeparator extends StatelessWidget {
  const _TuiSeparator();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: SizedBox(height: 1, child: CustomPaint(painter: _DashPainter(QuickMenuTuiTheme.border))),
      );
}

class _DashPainter extends CustomPainter {
  const _DashPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    for (double x = 0; x < size.width; x += 6) {
      canvas.drawRect(Rect.fromLTWH(x, 0, (size.width - x).clamp(0, 3).toDouble(), 1), paint);
    }
  }

  @override
  bool shouldRepaint(_DashPainter oldDelegate) => color != oldDelegate.color;
}

class _TuiTitleBar extends StatelessWidget {
  const _TuiTitleBar();

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: Color.alphaBlend(QuickMenuTuiTheme.foreground.withValues(alpha: 0.1), QuickMenuTuiTheme.background),
          border: Border(bottom: BorderSide(color: QuickMenuTuiTheme.border)),
        ),
        child: Row(children: <Widget>[
          Expanded(
              child: DragToMoveArea(
                  child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
            child: Row(children: <Widget>[
              Text('>_', style: QuickMenuTuiTheme.text(size: 13)),
              const SizedBox(width: 8),
              Expanded(
                  child: Text('Tabame - Command Prompt',
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontFamily: 'Segoe UI', fontSize: 12, color: QuickMenuTuiTheme.foreground))),
            ]),
          ))),
          IconButton(
              tooltip: 'Close QuickMenu',
              onPressed: QuickMenuFunctions.hideQuickMenu,
              constraints: const BoxConstraints(minWidth: 40, minHeight: 30),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              style: IconButton.styleFrom(shape: const RoundedRectangleBorder()),
              icon: Text('×', style: QuickMenuTuiTheme.text(size: 18))),
        ]),
      );
}
