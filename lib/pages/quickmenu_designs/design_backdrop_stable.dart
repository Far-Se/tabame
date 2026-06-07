import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../widgets/quickmenu/design_backdrop.dart';

/// A backdrop layer that is **always kept in the widget tree** so Flutter never
/// unmounts/remounts [DesignBackdrop].
///
/// ## Why two bugs shared the same root cause
///
/// Previously, the backdrop was added/removed with a conditional expression:
///
///   if (condition) Positioned.fill(child: DesignBackdrop())
///
/// This means Flutter destroys and recreates the element every time the
/// condition flips, which caused:
///
///   1. **Flicker on parent setState** — the remount reset internal widget
///      state, producing a one-frame full-opacity flash before any opacity
///      transition could run.
///
///   2. **Visibility toggle desync** — after returning SizedBox.shrink() once,
///      the GlobalKey subtree was unmounted.  When the condition became true
///      again, Flutter could not match the stale key and the backdrop stayed
///      blank until a design-switch forced a full rebuild.
///
/// ## The fix
///
/// Use [Offstage] so the element and its [RenderObject] are **never removed
/// from the tree** — they are simply skipped during paint and hit-testing when
/// `offstage: true`.  This costs nothing when hidden (no paint, no layout
/// contribution) while keeping the element alive so no remount ever occurs.
///
/// [RepaintBoundary] isolates backdrop repaints from the parent and the stable
/// [GlobalKey] preserves element identity across any ancestor rebuild.
///
/// Replace every inline:
///   if (condition) const Positioned.fill(child: DesignBackdrop()),
/// with:
///   const StableBackdrop(),
class StableBackdrop extends StatelessWidget {
  const StableBackdrop({super.key});

  static final GlobalKey _backdropKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final bool hasBackdrop =
        userSettings.themeColors.backdropType.isNotEmpty && userSettings.activeBackdropPath.isNotEmpty;

    return Positioned.fill(
      child: Offstage(
        // offstage:true  → element stays alive, nothing is painted or hit-tested.
        // offstage:false → element is fully active and visible.
        offstage: !hasBackdrop,
        child: RepaintBoundary(
          key: _backdropKey,
          child: const DesignBackdrop(),
        ),
      ),
    );
  }
}
