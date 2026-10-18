import 'dart:async';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../widgets/widgets/design_preview.dart';
import '../launcher.dart';

/// Rasterizes the selected design once without presenting or activating a window.
/// The preview is discarded; Flutter retains its compiled shader programs.
class LauncherWarmup extends StatefulWidget {
  const LauncherWarmup({super.key, required this.child});

  final Widget child;

  @override
  State<LauncherWarmup> createState() => _LauncherWarmupState();
}

class _LauncherWarmupState extends State<LauncherWarmup> {
  static bool _attempted = false;
  final GlobalKey _boundaryKey = GlobalKey();
  bool _warming = false;

  @override
  void initState() {
    super.initState();
    if (_attempted || Globals.isStandaloneLauncher || Globals.quickMenuPage == QuickMenuPage.launcher) return;
    _attempted = true;
    _warming = true;
    // Let the initial build finish before driving the offscreen passes.
    unawaited(Future<void>.delayed(Duration.zero, _warmup));
  }

  Future<void> _warmup() async {
    final Stopwatch elapsed = Stopwatch()..start();
    try {
      // The first build starts the surfaces' asynchronous FragmentProgram loads.
      // A second frame incorporates those programs and exercises the shader paint
      // paths, including effects that capture their child into another texture.
      for (int pass = 0; pass < 2; pass++) {
        if (!mounted || Globals.quickMenuPage == QuickMenuPage.launcher) return;
        final WidgetsBinding binding = WidgetsBinding.instance;
        // A hidden desktop window may not receive vsync. Warm-up frames still
        // run build/layout without showing or focusing the native window.
        binding.scheduleWarmUpFrame();
        await binding.endOfFrame;
        if (!mounted || Globals.quickMenuPage == QuickMenuPage.launcher) return;

        final RenderRepaintBoundary? boundary =
            _boundaryKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
        if (boundary == null || !boundary.hasSize || boundary.size.isEmpty) return;
        // Offstage provides layout but deliberately skips painting. Record a
        // detached layer explicitly, then rasterize it; Opacity(0) alone would
        // never exercise the GPU and would leave first-show compilation intact.
        boundary.markNeedsPaint();
        PaintingContext.repaintCompositedChild(boundary, debugAlsoPaintedParent: true);
        final ui.Image image = await boundary.toImage(pixelRatio: MediaQuery.devicePixelRatioOf(context));
        image.dispose();
        // Drain shader-load microtasks before the next build, even without vsync.
        await Future<void>.delayed(Duration.zero);
      }
      Debug.add('Launcher: offscreen warm-up completed in ${elapsed.elapsedMilliseconds}ms');
    } catch (error, stack) {
      // Warm-up is optional; a driver/shader failure must not block opening.
      debugPrint('Launcher warm-up failed: $error\n$stack');
    } finally {
      if (mounted) {
        setState(() => _warming = false);
        // Also release the preview, its listeners and textures while hidden.
        WidgetsBinding.instance.scheduleWarmUpFrame();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Size size = Size(Boxes.launcherSizeWidth, Globals.launcherSize.height);
    return Stack(
      children: <Widget>[
        widget.child,
        if (_warming)
          Positioned.fill(
            child: Offstage(
              child: OverflowBox(
                alignment: Alignment.topLeft,
                minWidth: size.width,
                maxWidth: size.width,
                minHeight: size.height,
                maxHeight: size.height,
                child: RepaintBoundary(
                  key: _boundaryKey,
                  child: MediaQuery(
                    data: MediaQuery.of(context).copyWith(size: size),
                    child: const TickerMode(
                      enabled: false,
                      child: DesignPreview(
                        child: Padding(
                          padding: EdgeInsets.fromLTRB(10, 0, 10, 10),
                          child: Align(alignment: Alignment.topLeft, child: Launcher()),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}
