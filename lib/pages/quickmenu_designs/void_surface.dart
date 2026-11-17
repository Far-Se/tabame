import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../models/util/theme_colors.dart';
import 'design_backdrop_stable.dart';

/// Tone for the instrument shelves above and below the window list. The list
/// keeps the plain ground, so the part you read is the calmest part.
Color voidShelf(Color ink, {required bool dark}) => ink.withValues(alpha: dark ? 0.04 : 0.035);

/// Edge of a shelf, and the frame around the panel.
Color voidRule(Color ink, {required bool dark}) => ink.withValues(alpha: dark ? 0.11 : 0.10);

/// Matte ground for the Void QuickMenu: one tinted neutral with a barely
/// there top-left lift. Nothing moves and nothing glows.
class VoidSurface extends StatelessWidget {
  const VoidSurface({
    super.key,
    required this.child,
    required this.ground,
    required this.dark,
    this.wash = 0.16,
    this.surfaceOpacity = 1,
    this.includeBackdrop = false,
  });

  final Widget child;
  final Color ground;
  final bool dark;

  /// 0 is flat; 1 is the strongest lift the theme's gradient setting allows.
  final double wash;
  final double surfaceOpacity;
  final bool includeBackdrop;

  static bool _panelFades(List<double> points) {
    for (int i = 1; i < points.length; i += 2) {
      if (points[i] < 0.999) return true;
    }
    return false;
  }

  static Shader _opacityShader(Rect bounds) {
    final List<double> points = Design.panelOpacityPoints;
    return LinearGradient(
      begin: panelAlignmentMap[Design.panelOpacityBegin] ?? Alignment.topCenter,
      end: panelAlignmentMap[Design.panelOpacityEnd] ?? Alignment.bottomCenter,
      colors: <Color>[
        for (int i = 1; i < points.length; i += 2) Colors.white.withValues(alpha: points[i].clamp(0.0, 1.0)),
      ],
      stops: <double>[
        for (int i = 0; i + 1 < points.length; i += 2) points[i],
      ],
    ).createShader(bounds);
  }

  @override
  Widget build(BuildContext context) {
    final bool highContrast = MediaQuery.highContrastOf(context);
    final double strength = highContrast ? 0 : wash.clamp(0.0, 1.0);
    final double opacity = highContrast ? 1 : surfaceOpacity.clamp(0.0, 1.0);
    final Color lift = Color.lerp(ground, Colors.white, (dark ? 0.20 : 0.45) * strength)!;
    final Color rest = Color.lerp(ground, Colors.black, (dark ? 0.30 : 0.16) * strength)!;

    Widget field = DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            lift.withValues(alpha: opacity),
            ground.withValues(alpha: opacity),
            rest.withValues(alpha: opacity),
          ],
          stops: const <double>[0, 0.45, 1],
        ),
      ),
      child: const SizedBox.expand(),
    );
    final List<double> points = Design.panelOpacityPoints;
    if (!highContrast && points.length >= 4 && _panelFades(points)) {
      field = ShaderMask(blendMode: BlendMode.dstIn, shaderCallback: _opacityShader, child: field);
    }

    return Stack(
      children: <Widget>[
        if (includeBackdrop) const StableBackdrop(),
        Positioned.fill(child: RepaintBoundary(child: field)),
        child,
      ],
    );
  }
}
