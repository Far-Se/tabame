part of '../launcher_design_builder.dart';

/// Stop decorative loops at a stable frame when motion is disabled or hidden.
void _syncRepeatingAnimation(AnimationController controller, BuildContext context, {bool active = true}) {
  final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
  if (active && !reduceMotion && TickerMode.valuesOf(context).enabled) {
    if (!controller.isAnimating) controller.repeat();
  } else {
    controller.stop();
    controller.value = 0;
  }
}
