import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/settings.dart';
import 'launcher_design.dart';
import 'launcher_design_builder.dart';

/// Resolved visual tokens for the Ctrl+K actions modal so it follows the
/// active launcher design.
///
/// The modal lives in its own route — outside the launcher's [LauncherTheme]
/// and outside the forced [Theme] the Terminal/Zen/Blueprint designs apply in
/// the launcher page — so the per-design palette is re-derived here from the
/// same token classes the launcher frame uses.
class LauncherModalTokens {
  const LauncherModalTokens._({
    required this.design,
    required this.isDark,
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.dim,
  });

  factory LauncherModalTokens.of(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isDark = theme.brightness == Brightness.dark;
    final LauncherDesign design = user.launcherDesign;
    switch (design) {
      case LauncherDesign.terminal:
        return LauncherModalTokens._(
          design: design,
          isDark: isDark,
          surface: TerminalTokens.bg(isDark),
          accent: Design.accent,
          onSurface: TerminalTokens.fg(isDark),
          dim: TerminalTokens.dim(isDark),
        );
      case LauncherDesign.zen:
        return LauncherModalTokens._(
          design: design,
          isDark: isDark,
          surface: ZenTokens.bg(isDark),
          accent: ZenTokens.accent(isDark),
          onSurface: ZenTokens.fg(isDark),
          dim: ZenTokens.dim(isDark),
        );
      case LauncherDesign.blueprint:
        return LauncherModalTokens._(
          design: design,
          isDark: isDark,
          surface: BlueprintTokens.bg(isDark),
          accent: BlueprintTokens.accent(isDark),
          onSurface: BlueprintTokens.fg(isDark),
          dim: BlueprintTokens.dim(isDark),
        );
      case LauncherDesign.classic:
      case LauncherDesign.serene:
      case LauncherDesign.command:
      case LauncherDesign.glass:
        final Color onSurface = theme.colorScheme.onSurface;
        return LauncherModalTokens._(
          design: design,
          isDark: isDark,
          surface: theme.colorScheme.surface,
          accent: Design.accent,
          onSurface: onSurface,
          dim: onSurface.withAlpha(120),
        );
    }
  }

  final LauncherDesign design;
  final bool isDark;

  /// Card background (forced palette for Terminal/Zen/Blueprint).
  final Color surface;
  final Color accent;
  final Color onSurface;

  /// Secondary/dimmed foreground.
  final Color dim;

  /// Corner radius of the modal card — same voice as the launcher frame.
  double get frameRadius => LauncherThemeData(design: design).frameRadius;

  /// Radius for inner controls (search field, chips).
  double get controlRadius => switch (design) {
        LauncherDesign.terminal => 3.0,
        LauncherDesign.blueprint => 2.0,
        LauncherDesign.command => 6.0,
        LauncherDesign.zen => 16.0,
        LauncherDesign.glass => 14.0,
        LauncherDesign.serene => 10.0,
        LauncherDesign.classic => 10.0,
      };

  /// Designs whose controls carry a visible accent outline (console/drafting
  /// looks); the soft designs use borderless fills instead.
  bool get outlinedControls =>
      design == LauncherDesign.command || design == LauncherDesign.terminal || design == LauncherDesign.blueprint;

  /// The design voice — same font family the launcher rows use.
  TextStyle text({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return switch (design) {
      LauncherDesign.terminal => TerminalTokens.mono(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.zen => ZenTokens.soft(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.glass => GlassTokens.font(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.blueprint => BlueprintTokens.tech(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      _ => TextStyle(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
    };
  }
}

// ---------------------------------------------------------------------------
// Frame — the modal card, re-using each design's outer decoration plus its
// signature inner layers (scanlines, grid paper, dawn glow, glass sheen…).
// ---------------------------------------------------------------------------

class LauncherModalFrame extends StatelessWidget {
  const LauncherModalFrame({
    super.key,
    required this.tokens,
    required this.width,
    required this.maxHeight,
    required this.child,
  });

  final LauncherModalTokens tokens;
  final double width;
  final double maxHeight;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final LauncherDesign design = tokens.design;
    final Color accent = tokens.accent;
    final BorderRadius radius = BorderRadius.circular(tokens.frameRadius);

    Widget core = Stack(
      children: <Widget>[
        // Background flourishes.
        if (design == LauncherDesign.blueprint)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ModalSheetPainter(ink: accent)),
            ),
          ),
        if (design == LauncherDesign.zen)
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: const Alignment(-0.7, -0.9),
                    radius: 1.3,
                    colors: <Color>[accent.withAlpha(22), accent.withAlpha(0)],
                  ),
                ),
              ),
            ),
          ),
        if (design == LauncherDesign.glass) ...<Widget>[
          // Specular sheen from the top-left.
          Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.center,
                    colors: <Color>[Colors.white.withAlpha(tokens.isDark ? 24 : 90), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
          // Bright glass edge along the very top.
          Positioned(
            top: 0,
            left: 18,
            right: 18,
            height: 1.5,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Colors.transparent,
                      Colors.white.withAlpha(tokens.isDark ? 70 : 200),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
        child,
        // Foreground flourishes.
        if (design == LauncherDesign.terminal)
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ModalScanlinePainter(isDark: tokens.isDark)),
            ),
          ),
        if (design == LauncherDesign.command)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[accent.withAlpha(200), accent.withAlpha(40), Colors.transparent],
                  ),
                ),
              ),
            ),
          ),
      ],
    );

    // Glass paints its fill inside the clip (the outer decoration only carries
    // the floating shadow + refraction glow); Serene adds its frosted blur.
    if (design == LauncherDesign.glass) {
      final Color baseFill = tokens.surface.withAlpha(tokens.isDark ? 205 : 225);
      core = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.alphaBlend(Colors.white.withAlpha(tokens.isDark ? 50 : 90), baseFill),
                baseFill,
                Color.alphaBlend(accent.withAlpha(tokens.isDark ? 40 : 26), baseFill),
              ],
            ),
            border: Border.all(color: Colors.white.withAlpha(tokens.isDark ? 40 : 120), width: 1.2),
          ),
          child: core,
        ),
      );
    } else if (design == LauncherDesign.serene) {
      core = BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: core,
      );
    }

    return Container(
      width: width,
      constraints: BoxConstraints(maxHeight: maxHeight),
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 48),
      decoration: design.outerDecoration(surface: tokens.surface, accent: accent),
      child: ClipRRect(borderRadius: radius, child: core),
    );
  }
}

// ---------------------------------------------------------------------------
// Header — item identity row (icon chip + title/subtitle + mode badge).
// ---------------------------------------------------------------------------

class LauncherModalHeader extends StatelessWidget {
  const LauncherModalHeader({
    super.key,
    required this.tokens,
    required this.icon,
    required this.title,
    this.subtitle = '',
    this.badgeLabel,
  });

  final LauncherModalTokens tokens;
  final Widget icon;
  final String title;
  final String subtitle;
  final String? badgeLabel;

  BoxDecoration _chipDecoration() {
    final Color accent = tokens.accent;
    return switch (tokens.design) {
      LauncherDesign.command => BoxDecoration(
          color: accent.withAlpha(14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withAlpha(50)),
        ),
      LauncherDesign.terminal => BoxDecoration(
          color: accent.withAlpha(20),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: accent.withAlpha(60)),
        ),
      LauncherDesign.zen => BoxDecoration(
          color: accent.withAlpha(26),
          borderRadius: BorderRadius.circular(13),
        ),
      LauncherDesign.glass => BoxDecoration(
          color: Colors.white.withAlpha(tokens.isDark ? 22 : 120),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(tokens.isDark ? 40 : 140), width: 0.8),
        ),
      // Part-reference balloon, like the Blueprint result rows.
      LauncherDesign.blueprint => BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent.withAlpha(180), width: 1.2),
        ),
      _ => BoxDecoration(
          color: accent.withAlpha(28),
          borderRadius: BorderRadius.circular(8),
        ),
    };
  }

  bool get _uppercaseVoice => tokens.design == LauncherDesign.blueprint || tokens.design == LauncherDesign.command;

  @override
  Widget build(BuildContext context) {
    final Color accent = tokens.accent;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (DragStartDetails details) {
              windowManager.startDragging();
            },
            child: Container(
              width: 36,
              height: 36,
              alignment: Alignment.center,
              decoration: _chipDecoration(),
              child: icon,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tokens.text(
                    fontSize: Design.baseFontSize + 2.5,
                    fontWeight: FontWeight.w600,
                    color: tokens.onSurface,
                    height: 1.25,
                  ),
                ),
                if (subtitle.isNotEmpty)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: tokens.text(
                      fontSize: Design.baseFontSize + 0.5,
                      color: tokens.dim,
                      height: 1.2,
                    ),
                  ),
              ],
            ),
          ),
          if (badgeLabel != null)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: accent.withAlpha(20),
                borderRadius: BorderRadius.circular(tokens.controlRadius),
                border: tokens.outlinedControls ? Border.all(color: accent.withAlpha(60)) : null,
              ),
              child: Text(
                _uppercaseVoice ? badgeLabel!.toUpperCase() : badgeLabel!,
                style: tokens.text(
                  fontSize: Design.baseFontSize,
                  fontWeight: FontWeight.w600,
                  color: accent.withAlpha(200),
                  letterSpacing: _uppercaseVoice ? 1.2 : 0.2,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Footer — keyboard hints in the design's voice.
// ---------------------------------------------------------------------------

class LauncherModalFooter extends StatelessWidget {
  const LauncherModalFooter({
    super.key,
    required this.tokens,
    required this.hints,
    this.trailing,
  });

  /// (key, caption) pairs, e.g. ('↵', 'run').
  final List<(String, String)> hints;
  final (String, String)? trailing;
  final LauncherModalTokens tokens;

  @override
  Widget build(BuildContext context) {
    final Color lineColor = switch (tokens.design) {
      LauncherDesign.terminal => tokens.accent.withAlpha(40),
      LauncherDesign.blueprint => tokens.accent.withAlpha(80),
      _ => tokens.onSurface.withAlpha(16),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.design == LauncherDesign.terminal ? TerminalTokens.chrome(tokens.isDark) : null,
        border: Border(top: BorderSide(color: lineColor)),
      ),
      child: Row(
        children: <Widget>[
          for (int i = 0; i < hints.length; i++) ...<Widget>[
            if (i > 0) const SizedBox(width: 14),
            LauncherModalKbd(tokens: tokens, keyLabel: hints[i].$1, caption: hints[i].$2),
          ],
          const Spacer(),
          if (trailing != null) LauncherModalKbd(tokens: tokens, keyLabel: trailing!.$1, caption: trailing!.$2),
        ],
      ),
    );
  }
}

class LauncherModalKbd extends StatelessWidget {
  const LauncherModalKbd({
    super.key,
    required this.tokens,
    required this.keyLabel,
    required this.caption,
  });

  final LauncherModalTokens tokens;
  final String keyLabel;
  final String caption;

  @override
  Widget build(BuildContext context) {
    // Terminal renders bare mono text, like its status bar; the rest use a
    // small keycap chip.
    if (tokens.design == LauncherDesign.terminal) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            keyLabel,
            style: tokens.text(
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              color: tokens.accent.withAlpha(210),
            ),
          ),
          Text(
            ' $caption',
            style: tokens.text(fontSize: Design.baseFontSize - 1, color: tokens.dim),
          ),
        ],
      );
    }
    final Color onSurface = tokens.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(minWidth: 16),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onSurface.withAlpha(12),
            borderRadius: BorderRadius.circular(tokens.design == LauncherDesign.blueprint ? 2 : 4),
            border: Border.all(
              color: tokens.outlinedControls ? tokens.accent.withAlpha(70) : onSurface.withAlpha(28),
            ),
          ),
          child: Text(
            keyLabel,
            style: tokens.text(
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              color: onSurface.withAlpha(170),
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          caption,
          style: tokens.text(fontSize: Design.baseFontSize - 1, color: onSurface.withAlpha(110)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Painters — private copies of the launcher frame's signature textures.
// ---------------------------------------------------------------------------

/// Subtle CRT scanlines (Terminal design).
class _ModalScanlinePainter extends CustomPainter {
  const _ModalScanlinePainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = (isDark ? Colors.white : Colors.black).withAlpha(5)
      ..strokeWidth = 1;
    for (double y = 0; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ModalScanlinePainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// Grid paper with an inner sheet border and corner registration crosses
/// (Blueprint design).
class _ModalSheetPainter extends CustomPainter {
  const _ModalSheetPainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 14;
    final Paint minor = Paint()
      ..color = ink.withAlpha(14)
      ..strokeWidth = 1;
    final Paint major = Paint()
      ..color = ink.withAlpha(26)
      ..strokeWidth = 1;

    int i = 0;
    for (double x = 0.5; x <= size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? major : minor);
      i++;
    }
    i = 0;
    for (double y = 0.5; y <= size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 5 == 0 ? major : minor);
      i++;
    }

    const double inset = 5;
    final Paint border = Paint()
      ..color = ink.withAlpha(80)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Rect sheet = Rect.fromLTWH(inset + 0.5, inset + 0.5, size.width - 2 * inset - 1, size.height - 2 * inset - 1);
    canvas.drawRect(sheet, border);

    final Paint cross = Paint()
      ..color = ink.withAlpha(140)
      ..strokeWidth = 1;
    const double arm = 4;
    for (final Offset c in <Offset>[sheet.topLeft, sheet.topRight, sheet.bottomLeft, sheet.bottomRight]) {
      canvas.drawLine(Offset(c.dx - arm, c.dy), Offset(c.dx + arm, c.dy), cross);
      canvas.drawLine(Offset(c.dx, c.dy - arm), Offset(c.dx, c.dy + arm), cross);
    }
  }

  @override
  bool shouldRepaint(covariant _ModalSheetPainter oldDelegate) => oldDelegate.ink != ink;
}
