import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../globals.dart';
import '../settings.dart';
import '../theme.dart';

/// Standardized modal bottom sheet for QuickMenu buttons.
/// Provides a blurred background and standard layout constraints.
Future<void> showQuickMenuModal({
  required BuildContext context,
  required Widget child,
  bool backdropFilter = true,
  double sigmaX = 3,
  double sigmaY = 3,
  double maxWidth = 280,
  double heightFactor = 0.85,
  VoidCallback? whenComplete,
}) async {
  return showModalBottomSheet<void>(
    context: context,
    anchorPoint: const Offset(100, 200),
    elevation: 0,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    constraints: BoxConstraints(maxWidth: maxWidth),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
    enableDrag: true,
    isScrollControlled: true,
    sheetAnimationStyle:
        const AnimationStyle(duration: Duration(milliseconds: 140), reverseDuration: Duration(milliseconds: 100)),
    builder: (BuildContext _) {
      return ValueListenableBuilder<bool>(
        valueListenable: Globals.themeChangeNotifier,
        builder: (BuildContext context, bool _, __) {
          final ThemeData modalTheme = globalSettings.themeTypeMode == ThemeType.dark
              ? AppTheme.getDarkThemeData(context)
              : AppTheme.getLightThemeData();
          final ColorScheme scheme = modalTheme.colorScheme;
          final Color surface = scheme.surface;
          final Animation<double>? animation = ModalRoute.of(context)?.animation;

          final Widget modalChild = FractionallySizedBox(
            heightFactor: heightFactor,
            child: Listener(
              onPointerDown: (PointerDownEvent event) {
                if (event.kind == PointerDeviceKind.mouse && event.buttons == kSecondaryMouseButton) {
                  Navigator.pop(context);
                }
              },
              child: Theme(
                data: modalTheme,
                child: Material(
                  type: MaterialType.transparency,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: AnimatedBuilder(
                        animation: animation ?? const AlwaysStoppedAnimation<double>(1.0),
                        builder: (BuildContext context, Widget? animatedChild) {
                          final double animValue = animation?.value ?? 1.0;

                          final double dragProgress = (1.0 - animValue).clamp(0.0, 1.0);

                          final double fadeWidth = 0.05 * dragProgress;
                          final double fadeStop1 = (1.0 - dragProgress - fadeWidth).clamp(0.0, 1.0);
                          final double fadeStop2 = (1.0 - dragProgress + fadeWidth).clamp(0.0, 1.0);

                          return ShaderMask(
                            shaderCallback: (Rect bounds) {
                              return LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: const <Color>[Colors.black, Colors.transparent],
                                stops: <double>[fadeStop1, fadeStop2],
                              ).createShader(bounds);
                            },
                            blendMode: BlendMode.dstIn,
                            child: animatedChild!,
                          );
                        },
                        child: Container(
                          width: maxWidth,
                          constraints: const BoxConstraints(maxHeight: 520, minHeight: 250),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(16),
                            color: surface.withValues(
                                alpha: switch (QuickMenuDesigns.values[globalSettings.quickMenuDesign]) {
                              QuickMenuDesigns.modern => 0.95,
                              QuickMenuDesigns.classic => 0.88,
                              QuickMenuDesigns.interface => 0.93,
                              // ignore: unreachable_switch_case
                              _ => 0.90,
                            }),
                            border: Border(
                              top: BorderSide(color: scheme.onSurface.withValues(alpha: 0.12), width: 0.5),
                              left: BorderSide(color: scheme.onSurface.withValues(alpha: 0.12), width: 0.5),
                              right: BorderSide(color: scheme.onSurface.withValues(alpha: 0.12), width: 0.5),
                            ),
                            boxShadow: true
                                ? null
                                // ignore: dead_code
                                : <BoxShadow>[
                                    BoxShadow(
                                      color: Colors.black.withAlpha(45),
                                      blurRadius: 25,
                                      offset: const Offset(0, 10),
                                    ),
                                    BoxShadow(
                                      color: Colors.black.withAlpha(30),
                                      blurRadius: 10,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: ClipRRect(borderRadius: BorderRadius.circular(16), child: child),
                        )),
                  ),
                ),
              ),
            ),
          );

          if (!backdropFilter) {
            return modalChild;
          }

          return BackdropFilter(
            filter: ImageFilter.blur(sigmaX: sigmaX, sigmaY: sigmaY),
            child: modalChild,
          );
        },
      );
    },
  ).whenComplete(() {
    whenComplete?.call();
  });
}
