import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../models/design_settings.dart';
import '../../models/settings.dart';
import '../../pages/launcher/widgets/ivory_grove_surface.dart';
import '../../pages/launcher/widgets/liquid_metal_surface.dart';
import '../../pages/launcher/widgets/radiant_surface.dart';
import '../../pages/launcher/widgets/satin_surface.dart';
import '../../pages/launcher/widgets/ukiyoe_surface.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/info_bar.dart';
import '../../widgets/quickmenu/libre_stats.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/taskbar_stats.dart';
import '../../widgets/quickmenu/top_bar.dart';
import '../../widgets/widgets/glass_surface.dart';

Color _quickMenuGlassColor(Color color) => Design.glassColor(color);

Gradient _quickMenuGlassGradient(Gradient gradient) =>
    Design.glassEnabled ? gradient.scale(Design.glassOpacity) : gradient;

/// QuickMenu frames adapted from the material and type treatments in the
/// matching Launcher designs. The shared menu content remains the normal
/// QuickMenu widget tree.
class MainMenuLauncherPortWidget extends StatelessWidget {
  const MainMenuLauncherPortWidget({super.key, required this.design});

  final QuickMenuDesigns design;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild when the active QuickMenu palette changes.
    final Color background = Design.background;
    final Color foreground = Design.text;
    final Color accent = Design.accent;
    final bool isDark = ThemeData.estimateBrightnessForColor(background) == Brightness.dark;
    final double radius = Design.borderRadius;
    final Widget menu = _buildMenu(context, foreground, accent, isDark);

    final Widget frame = switch (design) {
      QuickMenuDesigns.ivoryGrove => _ivoryGroveFrame(menu, background, foreground, accent, radius, isDark),
      QuickMenuDesigns.ukiyoe => _ukiyoeFrame(menu, background, accent, radius, isDark),
      QuickMenuDesigns.radiant => _radiantFrame(menu, background, accent, radius, isDark),
      QuickMenuDesigns.nouveau => _nouveauFrame(menu, background, foreground, accent, radius, isDark),
      QuickMenuDesigns.satin => _satinFrame(menu, background, foreground, accent, radius),
      QuickMenuDesigns.liquidMetal => _metalFrame(menu, background, foreground, accent, radius, isDark),
      QuickMenuDesigns.opticalGlass => _opticalGlassFrame(menu, background, foreground, accent, radius, isDark),
      _ => menu,
    };

    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: 203, maxHeight: MediaQuery.sizeOf(context).height - 50),
      child: RepaintBoundary(
        child: GlassClipRRect(
          borderRadius: BorderRadius.circular(radius),
          child: frame,
        ),
      ),
    );
  }

  Widget _buildMenu(BuildContext context, Color foreground, Color accent, bool isDark) {
    final ThemeData theme = Theme.of(context);
    final Color divider = foreground.withValues(alpha: isDark ? 0.17 : 0.14);
    return Theme(
      data: theme.copyWith(
        iconTheme: IconThemeData(color: foreground),
        dividerColor: divider,
        hoverColor: accent.withValues(alpha: 0.11),
        focusColor: accent.withValues(alpha: 0.16),
      ),
      child: Material(
        type: MaterialType.transparency,
        textStyle: theme.textTheme.bodyMedium?.copyWith(color: foreground, fontSize: Design.baseFontSize),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            if (!user.quickActionsAtBottom) ...<Widget>[
              const Padding(
                padding: EdgeInsets.fromLTRB(7, 6, 10, 5),
                child: TopBar(),
              ),
              Divider(height: 1, thickness: 0.7, color: divider),
            ] else if (user.bottomBarOnTop)
              const Padding(
                padding: EdgeInsets.only(top: 4),
                child: PinnedAndTrayList(),
              )
            else
              const SizedBox(height: 4),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: design == QuickMenuDesigns.nouveau ? 13 : 7),
              child: const TaskBar(),
            ),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: design == QuickMenuDesigns.ukiyoe ? 16 : 12),
              child: Divider(height: 1, thickness: 0.6, color: divider),
            ),
            if (!user.bottomBarOnTop) const PinnedAndTrayList(),
            if (user.taskManagerStats) const TaskbarStats(withTopDivider: false),
            if (user.libreStats) const LibreStats(withTopDivider: false),
            const Padding(
              padding: EdgeInsets.fromLTRB(0, 4, 2, 6),
              child: BottomBar(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ivoryGroveFrame(
    Widget menu,
    Color background,
    Color foreground,
    Color accent,
    double radius,
    bool isDark,
  ) {
    final Color edge =
        Color.alphaBlend((isDark ? foreground : Colors.white).withValues(alpha: isDark ? 0.24 : 0.72), background);
    return Container(
      decoration: BoxDecoration(
        gradient: _quickMenuGlassGradient(
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[background, Color.alphaBlend(accent.withValues(alpha: 0.045), background)],
          ),
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: edge),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.13), blurRadius: 22, offset: const Offset(0, 8)),
        ],
      ),
      child: IvoryGroveSurface(ink: foreground, child: menu),
    );
  }

  Widget _ukiyoeFrame(
    Widget menu,
    Color background,
    Color accent,
    double radius,
    bool isDark,
  ) {
    final Color vermilion = isDark ? const Color(0xFFD18A70) : const Color(0xFFAD4737);
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withValues(alpha: 0.72), width: 1.1),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: UkiyoeSurface(
              material: UkiyoeMaterial.paper,
              radius: radius,
              background: background,
              ink: accent,
              vermilion: vermilion,
              surfaceOpacity: Design.glassOpacity,
              useLauncherCorners: false,
              child: const SizedBox.expand(),
            ),
          ),
          Positioned(
            right: 0,
            bottom: 0,
            left: 0,
            height: 48,
            child: IgnorePointer(
              child: Opacity(
                opacity: isDark ? 0.16 : 0.12,
                child: UkiyoeSurface(
                  material: UkiyoeMaterial.landscape,
                  radius: 0,
                  background: background,
                  ink: accent,
                  vermilion: vermilion,
                  surfaceOpacity: Design.glassOpacity,
                  useLauncherCorners: false,
                  child: const SizedBox.expand(),
                ),
              ),
            ),
          ),
          menu,
          Positioned(
            top: 8,
            right: 12,
            child: IgnorePointer(
              child: Container(
                width: 9,
                height: 9,
                decoration: BoxDecoration(
                  color: vermilion,
                  border: Border.all(color: background.withValues(alpha: 0.65), width: 1),
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _radiantFrame(Widget menu, Color background, Color accent, double radius, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: Design.glassEnabled ? Colors.transparent : background,
        borderRadius: BorderRadius.circular(radius),
        // border: Border.all(color: accent.withValues(alpha: isDark ? 0.42 : 0.28)),
      ),
      child: RadiantMotion(
        child: RadiantSurface(
          kind: RadiantSurfaceKind.frame,
          radius: radius,
          background: background,
          accent: accent,
          surfaceOpacity: Design.glassOpacity,
          useLauncherCorners: false,
          frameInset: 3,
          framePadding: 3,
          child: menu,
        ),
      ),
    );
  }

  Widget _nouveauFrame(Widget menu, Color background, Color foreground, Color accent, double radius, bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: _quickMenuGlassColor(background),
        gradient: _quickMenuGlassGradient(
          LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[background, Color.alphaBlend(accent.withValues(alpha: 0.035), background)],
          ),
        ),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withValues(alpha: isDark ? 0.62 : 0.54)),
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(
                painter: _NouveauQuickMenuFramePainter(
                  ink: foreground.withValues(alpha: isDark ? 0.55 : 0.44),
                  brass: isDark ? const Color(0xFFC9A36B) : const Color(0xFFA1763D),
                ),
              ),
            ),
          ),
          Padding(padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5), child: menu),
        ],
      ),
    );
  }

  Widget _satinFrame(Widget menu, Color background, Color foreground, Color accent, double radius) {
    return SatinSurface(
      radius: radius,
      background: background,
      foreground: foreground,
      accent: accent,
      surfaceOpacity: Design.glassOpacity,
      useLauncherCorners: false,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          border: Border.all(color: foreground.withValues(alpha: 0.16)),
        ),
        child: menu,
      ),
    );
  }

  Widget _metalFrame(Widget menu, Color background, Color foreground, Color accent, double radius, bool isDark) {
    final BoxDecoration edge = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: foreground.withValues(alpha: isDark ? 0.25 : 0.30)),
    );
    return LiquidMetalMotion(
      child: LiquidMetalSurface(
        radius: radius,
        raised: false,
        background: background,
        foreground: foreground,
        accent: accent,
        surfaceOpacity: Design.glassOpacity,
        useLauncherCorners: false,
        child: LiquidMetalSurface(
          radius: radius,
          overlay: true,
          background: background,
          foreground: foreground,
          accent: accent,
          surfaceOpacity: Design.glassOpacity,
          useLauncherCorners: false,
          child: Container(decoration: edge, child: menu),
        ),
      ),
    );
  }

  Widget _opticalGlassFrame(Widget menu, Color background, Color foreground, Color accent, double radius, bool isDark) {
    final BoxDecoration edge = BoxDecoration(
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: accent.withValues(alpha: isDark ? 0.50 : 0.43)),
      boxShadow: <BoxShadow>[
        BoxShadow(color: accent.withValues(alpha: isDark ? 0.11 : 0.09), blurRadius: 18, spreadRadius: -5),
      ],
    );
    return LiquidMetalMotion(
      child: OpticalGlassSurface(
        radius: radius,
        raised: false,
        background: background,
        foreground: foreground,
        accent: accent,
        surfaceOpacity: Design.glassOpacity,
        useLauncherCorners: false,
        child: OpticalGlassSurface(
          radius: radius,
          overlay: true,
          background: background,
          foreground: foreground,
          accent: accent,
          surfaceOpacity: Design.glassOpacity,
          useLauncherCorners: false,
          child: Container(decoration: edge, child: menu),
        ),
      ),
    );
  }
}

class _NouveauQuickMenuFramePainter extends CustomPainter {
  const _NouveauQuickMenuFramePainter({required this.ink, required this.brass});

  final Color ink;
  final Color brass;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width < 60 || size.height < 60) return;
    final double scale = (math.min(size.width / 430, size.height / 260)).clamp(0.5, 1.0).toDouble();
    final Paint rule = Paint()
      ..color = ink
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    final Paint gold = Paint()
      ..color = brass.withValues(alpha: 0.72)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(4, 4, size.width - 8, size.height - 8),
        Radius.circular(math.max(2, scale * 9)),
      ),
      rule,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(7, 7, size.width - 14, size.height - 14),
        Radius.circular(math.max(1, scale * 6)),
      ),
      Paint()
        ..color = ink.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.45,
    );

    for (int corner = 0; corner < 4; corner++) {
      canvas.save();
      canvas.translate(corner.isOdd ? size.width - 4 : 4, corner >= 2 ? size.height - 4 : 4);
      canvas.scale(corner.isOdd ? -scale : scale, corner >= 2 ? -scale : scale);
      final Path scroll = Path()
        ..moveTo(2, 34)
        ..lineTo(2, 17)
        ..cubicTo(2, 7, 11, 5, 19, 5)
        ..lineTo(35, 5)
        ..cubicTo(28, 5, 27, 14, 33, 15)
        ..cubicTo(39, 16, 40, 7, 34, 7);
      canvas.drawPath(scroll, rule);
      final Path leaf = Path()
        ..moveTo(5, 23)
        ..cubicTo(13, 18, 19, 20, 22, 28)
        ..cubicTo(14, 30, 8, 28, 5, 23)
        ..moveTo(7, 24)
        ..lineTo(20, 27);
      canvas.drawPath(leaf, rule);
      canvas.drawCircle(const Offset(27, 29), 2, gold);
      canvas.restore();
    }
  }

  @override
  bool shouldRepaint(covariant _NouveauQuickMenuFramePainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.brass != brass;
}
