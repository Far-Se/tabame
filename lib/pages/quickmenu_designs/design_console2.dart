// ============================================================================
// QuickMenuDesigns.console
//
// A "Command Prompt" / TUI-flavored design:
//  - flat, opaque panel (no glass/blur — real terminals aren't translucent)
//  - sharp corners (borderRadius: 0)
//  - Consolas everywhere, classic cmd.exe palette (black bg / gray text /
//    bright green accent), with a light "light-terminal" variant too
//  - box-drawing (┌ ┐ └ ┘) corner frame + scanline texture + a blinking
//    block cursor in the title strip, dashed ASCII-style section dividers
//
// Drop this alongside design_serene.dart / design_stable.dart etc. Wire the
// `console` value into the `QuickMenuDesigns` enum, add the QMDesignThemeSet
// entry to the theme table, and add the `_FrameSpec` case to the modal/popup
// frame switch — all three snippets are below.
// ============================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import 'design_backdrop_stable.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';

// ----------------------------------------------------------------------------
// 1. THEME COLORS — add this entry to the QMDesignThemeSet table, next to
//    the QuickMenuDesigns.vector entry shown in the prompt.
// ----------------------------------------------------------------------------
//
//   QuickMenuDesigns.console2.displayName: QMDesignThemeSet(
//     lightTheme: _defaultThemeColors(
//       background: const Color(0xffF3F3F3),   // Win terminal "Campbell Light" paper
//       textColor: const Color(0xff0C0C0C),    // near-black console text
//       accentColor: const Color(0xff0037DA),  // classic cmd.exe blue
//       gradientAlpha: 0,                      // flat — no glow/gradient
//       uiFontFamily: 'Consolas',
//       uiFontWeight: 400,
//       entryFontFamily: 'Consolas',
//       entryFontWeight: 700,
//       borderRadius: 0,
//       baseFontSize: 10,
//     ),
//     darkTheme: _defaultThemeColors(
//       background: const Color(0xff0C0C0C),   // cmd.exe black
//       textColor: const Color(0xffCCCCCC),    // cmd.exe light gray
//       accentColor: const Color(0xff16C60C),  // cmd.exe bright green
//       gradientAlpha: 0,
//       uiFontFamily: 'Consolas',
//       uiFontWeight: 400,
//       entryFontFamily: 'Consolas',
//       entryFontWeight: 700,
//       borderRadius: 0,
//       baseFontSize: 10,
//     ),
//   ),

// ----------------------------------------------------------------------------
// 2. POPUP / MODAL FRAME SPEC — add this case next to the
//    QuickMenuDesigns.vector => _FrameSpec(...) case.
// ----------------------------------------------------------------------------
//
//   QuickMenuDesigns.console2 => _FrameSpec(
//     decoration: BoxDecoration(
//       borderRadius: radius, // Design.borderRadius is 0 for this theme anyway
//       color: bg.withValues(alpha: 1.0), // opaque — terminal windows don't glass
//       border: Border.all(
//         color: accent.withValues(alpha: isDark ? 0.55 : 0.45),
//         width: 1,
//       ),
//     ),
//     underlays: <Widget>[
//       CustomPaint(painter: _ConsoleScanPainter(text.withValues(alpha: isDark ? 0.045 : 0.035))),
//     ],
//     overlays: <Widget>[
//       CustomPaint(painter: _ConsoleFramePainter(accent)),
//       const _ConsoleCursorBlink(),
//     ],
//   ),

// ----------------------------------------------------------------------------
// 3. PANEL WIDGET
// ----------------------------------------------------------------------------

class MainMenuConsole2Widget extends StatelessWidget {
  const MainMenuConsole2Widget({super.key});

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Design.accent;
    final Color surface = theme.colorScheme.surface;
    final bool isDark = theme.brightness == Brightness.dark;

    // Terminal windows are opaque — no translucency curve needed, but we
    // keep the shape so a user-adjusted opacity setting still applies.
    final double baseAlpha = user.activeBackdropPath.isNotEmpty ? 0.94 : 1.0;
    final Color panelBase = surface.withValues(alpha: baseAlpha);
    final Color borderColor = accent.withValues(alpha: isDark ? 0.55 : 0.45);
    final Color dividerColor = theme.colorScheme.onSurface.withValues(alpha: 0.16);
    final Color scanColor = theme.colorScheme.onSurface.withValues(alpha: isDark ? 0.05 : 0.035);

    final double radius = Design.borderRadius; // 0 for this theme

    return ConstrainedBox(
      constraints: BoxConstraints(
        minHeight: 203,
        maxHeight: MediaQuery.of(context).size.height - 50,
      ),
      child: RepaintBoundary(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: Stack(
            children: <Widget>[
              // Flat opaque terminal-window background — no blur.
              Positioned.fill(
                child: RepaintBoundary(
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(radius),
                      color: panelBase,
                      border: Border.all(color: borderColor, width: 1),
                    ),
                  ),
                ),
              ),
              // CRT scanline texture.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: ConsoleScanPainter(scanColor)),
                ),
              ),
              if (Design.hasBackdrop) const StableBackdrop(),
              RepaintBoundary(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    // DragToMoveArea(child: _ConsoleTitleStrip(accent: accent, dividerColor: dividerColor)),
                    if (!user.quickActionsAtBottom) ...<Widget>[
                      Container(
                        padding: const EdgeInsets.fromLTRB(4, 5, 10, 6),
                        child: const TopBar(),
                      ),
                      _AsciiDivider(color: dividerColor),
                    ] else if (user.bottomBarOnTop)
                      const PinnedAndTrayList()
                    else
                      const SizedBox(height: 3),
                    const TaskBar(),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: _AsciiDivider(color: dividerColor),
                    ),
                    if (!user.bottomBarOnTop) const PinnedAndTrayList(),
                    if (user.taskManagerStats) const TaskbarStats(),
                    if (user.libreStats) const LibreStats(),
                    Container(
                      padding: const EdgeInsets.fromLTRB(0, 4, 2, 6),
                      child: const BottomBar(),
                    ),
                  ],
                ),
              ),
              // Corner box-drawing frame, painted last so it sits on top.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: ConsoleFramePainter(accent)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "C:\QuickMenu>" title strip with a blinking block cursor, in place of a
/// generic top bar decoration — this is what sells the CMD look at a glance.
// ignore: unused_element
class _ConsoleTitleStrip extends StatelessWidget {
  final Color accent;
  final Color dividerColor;
  const _ConsoleTitleStrip({required this.accent, required this.dividerColor});

  @override
  Widget build(BuildContext context) {
    final TextStyle style = TextStyle(
      fontFamily: 'Consolas',
      fontWeight: FontWeight.w700,
      fontSize: 11,
      color: accent,
      letterSpacing: 0.2,
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text('C:\\QuickMenu>', style: style),
          const SizedBox(width: 4),
          const ConsoleCursorBlink(inline: true),
        ],
      ),
    );
  }
}

/// A dashed, ASCII-style section divider ( ------------- ) instead of a
/// plain Material Divider, matching the TUI aesthetic.
class _AsciiDivider extends StatelessWidget {
  final Color color;
  const _AsciiDivider({required this.color});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 7,
      child: CustomPaint(
        size: const Size(double.infinity, 7),
        painter: _DashedLinePainter(color),
      ),
    );
  }
}

/// A blinking block cursor ("█") — used inline in the title strip and can
/// also be dropped in as a standalone overlay widget for popups.
class ConsoleCursorBlink extends StatefulWidget {
  final bool inline;
  const ConsoleCursorBlink({this.inline = false});

  @override
  State<ConsoleCursorBlink> createState() => _ConsoleCursorBlinkState();
}

class _ConsoleCursorBlinkState extends State<ConsoleCursorBlink> {
  bool _visible = true;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(milliseconds: 530), (_) {
      if (!mounted || !QuickMenuFunctions.isQuickMenuVisible) return;
      setState(() => _visible = !_visible);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Widget block = AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 90),
      child: Container(width: 7, height: 13, color: accent),
    );
    if (widget.inline) return block;
    return Positioned(right: 10, bottom: 8, child: block);
  }
}

// ----------------------------------------------------------------------------
// 4. CUSTOM PAINTERS
// ----------------------------------------------------------------------------

/// Faint horizontal scanlines for a CRT-terminal feel. Cheap to paint —
/// draws every 3rd pixel row as a hairline.
class ConsoleScanPainter extends CustomPainter {
  final Color color;
  const ConsoleScanPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant ConsoleScanPainter oldDelegate) => oldDelegate.color != color;
}

/// Box-drawing corner frame (┌ ┐ └ ┘), TUI-style — painted as two short
/// perpendicular strokes per corner rather than glyphs, so it scales cleanly
/// with the panel instead of relying on font metrics.
class ConsoleFramePainter extends CustomPainter {
  final Color accent;
  final double armLength;
  final double inset;
  const ConsoleFramePainter(this.accent, {this.armLength = 10, this.inset = 3});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = accent.withValues(alpha: 0.9)
      ..strokeWidth = 1.4
      ..style = PaintingStyle.stroke;

    final double l = inset;
    final double r = size.width - inset;
    final double t = inset;
    final double b = size.height - inset;

    // Top-left ┌
    canvas.drawLine(Offset(l, t), Offset(l + armLength, t), paint);
    canvas.drawLine(Offset(l, t), Offset(l, t + armLength), paint);
    // Top-right ┐
    canvas.drawLine(Offset(r, t), Offset(r - armLength, t), paint);
    canvas.drawLine(Offset(r, t), Offset(r, t + armLength), paint);
    // Bottom-left └
    canvas.drawLine(Offset(l, b), Offset(l + armLength, b), paint);
    canvas.drawLine(Offset(l, b), Offset(l, b - armLength), paint);
    // Bottom-right ┘
    canvas.drawLine(Offset(r, b), Offset(r - armLength, b), paint);
    canvas.drawLine(Offset(r, b), Offset(r, b - armLength), paint);
  }

  @override
  bool shouldRepaint(covariant ConsoleFramePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.armLength != armLength || oldDelegate.inset != inset;
}

/// Even-dash horizontal rule ( ---- ---- ---- ) used by [_AsciiDivider].
class _DashedLinePainter extends CustomPainter {
  final Color color;
  final double dashWidth;
  final double gapWidth;
  const _DashedLinePainter(this.color)
      : gapWidth = 3,
        dashWidth = 4;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    final double y = size.height / 2;
    double x = 0;
    while (x < size.width) {
      canvas.drawLine(Offset(x, y), Offset(x + dashWidth, y), paint);
      x += dashWidth + gapWidth;
    }
  }

  @override
  bool shouldRepaint(covariant _DashedLinePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.dashWidth != dashWidth || oldDelegate.gapWidth != gapWidth;
}
