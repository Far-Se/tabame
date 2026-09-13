import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import '../launcher/widgets/crt_surface.dart';

/// Shares QuickMenu's live controls while giving each screen its own cabinet.
class MainMenuArcadeWidget extends StatelessWidget {
  const MainMenuArcadeWidget({super.key, required this.design});

  final QuickMenuDesigns design;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final bool crt = design == QuickMenuDesigns.crt;
    final bool mario = design == QuickMenuDesigns.superMario;
    final bool retro = design == QuickMenuDesigns.retro;
    final Color bg = Design.background;
    final Color accent = Design.accent;
    final Color border = Color.alphaBlend(accent.withAlpha(100), bg);
    final double radius = crt ? Design.borderRadius : 2;
    final TextStyle label = crt
        ? TextStyle(fontFamily: 'Consolas', fontSize: 11, color: Design.text, letterSpacing: 1.2)
        : GoogleFonts.pressStart2p(fontSize: Design.baseFontSize - 1, color: Design.text, height: 1.5);
    final TextStyle statusLabel = crt
        ? label.copyWith(fontSize: 10)
        : GoogleFonts.getFont(Design.uiFontFamily,
            fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text, letterSpacing: 0.2);
    final Widget screen = ColoredBox(
      color: bg,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            height: mario ? 64 : 38,
            decoration: BoxDecoration(
              color: mario ? const Color(0xFF5C94FC) : Color.alphaBlend(accent.withAlpha(18), bg),
              border: Border(bottom: BorderSide(color: border, width: crt ? 1 : 2)),
            ),
            child: Stack(
              children: <Widget>[
                if (mario) const Positioned.fill(child: IgnorePointer(child: CustomPaint(painter: _KingdomPainter()))),
                Row(children: <Widget>[
                  Expanded(
                    child: DragToMoveArea(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Text('TABAME / ${design.displayName.toUpperCase()}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: mario
                                ? label.copyWith(
                                    color: const Color(0xFFFCF4DC),
                                    shadows: const <Shadow>[Shadow(color: Color(0xFF203878), offset: Offset(2, 2))])
                                : label),
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Hide QuickMenu',
                    onPressed: () => QuickMenuFunctions.hideQuickMenu(),
                    icon: Icon(Icons.close, size: 16, color: mario ? const Color(0xFFFCF4DC) : accent),
                  ),
                ]),
              ],
            ),
          ),
          if (!user.quickActionsAtBottom) const TopBar(),
          if (user.bottomBarOnTop) PinnedAndTrayList(includeQuickActions: user.quickActionsAtBottom),
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 7, 10, 3),
            child: Row(children: <Widget>[
              Container(width: 5, height: 5, color: accent),
              const SizedBox(width: 7),
              Expanded(child: Text(crt ? 'ACTIVE WINDOWS' : 'SELECT WINDOW', style: statusLabel)),
              Text(crt ? 'ONLINE' : '1P', style: statusLabel.copyWith(color: accent)),
            ]),
          ),
          const Flexible(fit: FlexFit.loose, child: TaskBar()),
          if (!user.bottomBarOnTop) const PinnedAndTrayList(),
          if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
          if (user.libreStats) const LibreStats(withTopDivider: false),
          Container(
            decoration: BoxDecoration(border: Border(top: BorderSide(color: border))),
            child: const BottomBar(),
          ),
          if (mario)
            const SizedBox(height: 22, child: IgnorePointer(child: CustomPaint(painter: _KingdomPainter(ground: true))))
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 8),
              child: Row(children: <Widget>[
                Text(crt ? '> READY' : 'QUICK MENU', style: statusLabel.copyWith(color: accent)),
                const SizedBox(width: 12),
                Expanded(child: Container(height: crt ? 1 : 3, color: border)),
                const SizedBox(width: 8),
                Text(crt ? 'CRT' : '8 BIT', style: statusLabel),
              ]),
            ),
        ],
      ),
    );
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 203, maxHeight: MediaQuery.sizeOf(context).height - 50),
      child: Container(
        padding: EdgeInsets.all(retro ? 0 : (crt ? 6 : 5)),
        decoration: retro
            ? null
            : BoxDecoration(
                color: Color.alphaBlend(accent.withAlpha(crt ? 30 : 18), bg),
                borderRadius: BorderRadius.circular(radius),
                border: Border.all(color: mario ? const Color(0xFFB83B24) : border, width: crt ? 1 : 2),
              ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(crt ? (radius - 6).clamp(0, 100) : 0),
          child: crt
              ? CrtSurface(background: bg, accent: accent, child: screen)
              : mario
                  ? CrtSurface(
                      shaderAsset: 'resources/shaders/super_mario.frag',
                      pixelSize: 1,
                      persistenceRate: 30,
                      effectName: 'SuperMario',
                      background: bg,
                      accent: accent,
                      child: screen)
                  : RetroSurface(background: bg, accent: accent, child: screen),
        ),
      ),
    );
  }
}

/// Integer-aligned scenery remains visible when GPU effects are unavailable.
class _KingdomPainter extends CustomPainter {
  const _KingdomPainter({this.ground = false});
  final bool ground;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..isAntiAlias = false;
    void block(double x, double y, double w, double h, Color color) {
      canvas.drawRect(Rect.fromLTWH(x, y, w, h), paint..color = color);
    }

    if (ground) {
      block(0, 0, size.width, size.height, const Color(0xFF6B2818));
      for (int row = 0; row < 2; row++) {
        for (double x = row == 0 ? 0 : -12; x < size.width; x += 24) {
          block(x + 1, row * 11.0 + 1, 22, 9, const Color(0xFFC86C32));
          block(x + 1, row * 11.0 + 1, 22, 2, const Color(0xFFF8B878));
        }
      }
      return;
    }
    for (double x = 18; x < size.width; x += 130) {
      block(x, 43, 34, 8, const Color(0xFFE4EFFF));
      block(x + 8, 37, 18, 8, const Color(0xFFE4EFFF));
    }
    final double pipe = size.width - 66;
    block(pipe, 46, 23, 18, const Color(0xFF186828));
    block(pipe + 3, 46, 6, 18, const Color(0xFF80D840));
    block(pipe - 3, 42, 29, 7, const Color(0xFF186828));
    block(pipe, 43, 23, 3, const Color(0xFF80D840));
    for (double x = size.width * 0.43; x < size.width * 0.67; x += 22) {
      block(x, 40, 18, 18, const Color(0xFF9C4818));
      block(x, 40, 16, 16, const Color(0xFFF8B830));
      block(x + 2, 42, 12, 2, const Color(0xFFFFE8A0));
      const Color ink = Color(0xFF784018);
      block(x + 5, 45, 6, 2, ink);
      block(x + 9, 47, 2, 3, ink);
      block(x + 7, 49, 3, 2, ink);
      block(x + 7, 53, 2, 2, ink);
    }
  }

  @override
  bool shouldRepaint(_KingdomPainter oldDelegate) => ground != oldDelegate.ground;
}
