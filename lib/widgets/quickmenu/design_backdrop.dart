import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/globals.dart';
import '../../models/settings.dart';

class DesignBackdrop extends StatelessWidget {
  const DesignBackdrop();

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
        valueListenable: Globals.themeChangeNotifier,
        builder: (_, bool refreshed, __) {
          final String activePath = user.activeBackdropPath;
          if (activePath.isEmpty) return const SizedBox.shrink();

          final bool isAsset = activePath.startsWith('resources/');
          final double opacityClamped = Design.backdropOpacity.clamp(0.0, 1.0);

          return RepaintBoundary(
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: Opacity(
                    opacity: opacityClamped,
                    child: isAsset
                        ? Image.asset(
                            activePath,
                            key: ValueKey<String>(activePath),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
                            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                                const SizedBox.shrink(),
                          )
                        : Image.file(
                            File(activePath),
                            key: ValueKey<String>(activePath),
                            fit: BoxFit.cover,
                            gaplessPlayback: true,
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
