import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../models/globals.dart';

class DesignBackdrop extends StatelessWidget {
  final String path;
  final double opacity;
  const DesignBackdrop({super.key, required this.path, required this.opacity});

  @override
  Widget build(BuildContext context) {
    if (path.isEmpty) return const SizedBox.shrink();

    final bool isAsset = path.startsWith('resources/');
    final double opacityClamped = opacity.clamp(0.0, 1.0);

    return ValueListenableBuilder<bool>(
      valueListenable: Globals.themeChangeNotifier,
      builder: (BuildContext context, bool value, Widget? child) {
        return RepaintBoundary(
          child: Stack(
            children: <Widget>[
              Positioned.fill(
                child: Opacity(
                  opacity: opacityClamped,
                  child: isAsset
                      ? Image.asset(
                          path,
                          fit: BoxFit.cover,
                          errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) =>
                              const SizedBox.shrink(),
                        )
                      : Image.file(
                          File(path),
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
      },
    );
  }
}
