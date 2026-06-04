import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/globals.dart';
import '../../models/settings.dart';

class DesignBackdrop extends StatelessWidget {
  const DesignBackdrop();

  @override
  Widget build(BuildContext context) {
    // print("Backdrop");
    if (userSettings.activeBackdropPath.isEmpty) return const SizedBox.shrink();

    final bool isAsset = userSettings.activeBackdropPath.startsWith('resources/');
    final double opacityClamped = userSettings.themeColors.backdropOpacity.clamp(0.0, 1.0);

    return ValueListenableBuilder<bool>(
        valueListenable: Globals.themeChangeNotifier,
        builder: (_, bool refreshed, __) {
          return RepaintBoundary(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Opacity(
                    opacity: opacityClamped,
                    child: isAsset
                        ? Image.asset(
                            userSettings.activeBackdropPath,
                            fit: BoxFit.cover,
                            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                                const SizedBox.shrink(),
                          )
                        : Image.file(
                            File(userSettings.activeBackdropPath),
                            fit: BoxFit.cover,
                            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                                const SizedBox.shrink(),
                          ),
                  ),
                ),
                Positioned.fill(
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
                    child: const SizedBox.shrink(),
                  ),
                ),
              ],
            ),
          );
        });
  }
}
