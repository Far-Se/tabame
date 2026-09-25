import 'package:flutter/material.dart';

import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../widgets/widgets/custom_border.dart';

/// Applies the active QuickMenu theme's corner style to the whole design.
class QuickMenuCornerClip extends StatelessWidget {
  const QuickMenuCornerClip({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final CornerShape shape = switch (user.themeColors.cornerShape) {
      ThemeCornerShape.round => CornerShape.round,
      ThemeCornerShape.squircle => CornerShape.squircle,
      ThemeCornerShape.bevel => CornerShape.bevel,
    };
    final ShapeBorder corners = CornerShapeBorder.all(
      borderRadius: BorderRadius.circular(Design.borderRadius),
      shape: shape,
      curveSegments: 16,
    );

    return Material(
      type: MaterialType.transparency,
      animationDuration: Duration.zero,
      shape: corners,
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }
}
