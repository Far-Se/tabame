import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/design_settings.dart';
import '../../models/settings.dart';
import 'launcher_corners.dart';
import 'launcher_design.dart';
import 'launcher_design_builder.dart';
import 'widgets/capillary_surface.dart';
import 'widgets/thermal_surface.dart';
import 'widgets/satin_surface.dart';
import 'widgets/liquid_metal_surface.dart';
import 'widgets/crt_surface.dart';

/// Presentation tokens for the actions modal. The route can live outside
/// LauncherTheme, so it uses the same palette resolver as the launcher page.
class LauncherModalTokens {
  const LauncherModalTokens._({required this.design, required LauncherPalette palette}) : _palette = palette;

  factory LauncherModalTokens.of(BuildContext context) {
    final LauncherDesign design = user.launcherDesign;
    final LauncherPalette? inherited =
        LauncherTheme.maybeOf(context)?.design == design ? LauncherTheme.maybePaletteOf(context) : null;
    return LauncherModalTokens._(
      design: design,
      palette: inherited ?? LauncherPalette.resolve(design, brightness: Theme.of(context).brightness),
    );
  }

  final LauncherDesign design;
  final LauncherPalette _palette;

  bool get isDark => _palette.isDark;
  Color get surface => _palette.modalSurface;
  Color get accent => _palette.modalAccent;
  Color get onSurface => _palette.onSurface;
  Color get dim => _palette.dim;

  /// Foreground used by controls while they carry the design's selection
  /// highlight. Legacy Windows palettes use a dark blue highlight, so their
  /// selected labels need a light foreground instead of [onSurface].
  Color get onSelection => switch (design) {
        LauncherDesign.windowsXp => Colors.white,
        LauncherDesign.windows98 => Windows98Tokens.light,
        _ => onSurface,
      };

  /// Corner radius of the modal card — same voice as the launcher frame.
  double get frameRadius => LauncherThemeData(design: design).frameRadius;

  /// Radius for inner controls (search field, chips).
  double get controlRadius => LauncherThemeData(design: design).config.controlRadius;

  /// Designs whose controls carry a visible accent outline (console/drafting
  /// looks); the soft designs use borderless fills instead.
  bool get outlinedControls => LauncherThemeData(design: design).config.outlinedControls;

  /// The design voice — same font family the launcher rows use.
  TextStyle text({
    double? fontSize,
    FontWeight? fontWeight,
    Color? color,
    double? letterSpacing,
    double? height,
  }) {
    return switch (design) {
      LauncherDesign.satin => SatinTokens.font(
          size: fontSize ?? 14,
          color: color ?? onSurface,
          weight: fontWeight ?? FontWeight.w500,
          spacing: letterSpacing ?? 0,
        ).copyWith(height: height),
      LauncherDesign.thermal => ThermalTokens.font(
          size: fontSize ?? 14,
          color: color ?? onSurface,
          weight: fontWeight ?? FontWeight.w500,
          spacing: letterSpacing ?? 0,
        ).copyWith(height: height),
      LauncherDesign.capillary => CapillaryTokens.resolve(isDark)
          .font(
            size: fontSize ?? 14,
            color: color ?? onSurface,
            weight: fontWeight ?? FontWeight.w500,
            spacing: letterSpacing ?? 0,
          )
          .copyWith(height: height),
      LauncherDesign.crt => CrtTokens.font(size: fontSize ?? 14, color: color ?? onSurface, spacing: letterSpacing)
          .copyWith(fontWeight: fontWeight, height: height),
      LauncherDesign.toon => ToonTokens.font(
          size: fontSize ?? 13,
          color: color ?? onSurface,
          spacing: letterSpacing,
          weight: fontWeight ?? FontWeight.w600,
          height: height,
        ),
      LauncherDesign.retro => RetroTokens.pixel(
          size: fontSize ?? 18,
          color: color ?? onSurface,
          spacing: letterSpacing,
          weight: fontWeight ?? FontWeight.w400,
          height: height,
        ),
      LauncherDesign.opticalGlass => OpticalGlassTokens.font(
              size: fontSize ?? 14,
              weight: fontWeight ?? FontWeight.w500,
              color: color ?? onSurface,
              spacing: letterSpacing ?? 0)
          .copyWith(height: height),
      LauncherDesign.liquidMetal => LiquidMetalTokens.font(
              size: fontSize ?? 14,
              weight: fontWeight ?? FontWeight.w500,
              color: color ?? onSurface,
              spacing: letterSpacing ?? 0)
          .copyWith(height: height),
      LauncherDesign.tui => TuiTokens.mono(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.omarchy => OmarchyTokens.mono(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.terminal => TerminalTokens.mono(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.terminal2 => Terminal2Tokens.mono(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.zen => ZenTokens.soft(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.glass => GlassTokens.font(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.blueprint => BlueprintTokens.tech(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.transit => TransitTokens.sign(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.fluent => FluentTokens.segoe(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.manifesto => ManifestoTokens.body(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.orbit => OrbitTokens.disp(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.windowsXp => WindowsXpTokens.tahoma(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.windows98 => Windows98Tokens.system(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.notion => NotionTokens.ui(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.switchboard => SwitchboardTokens.body(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.relay => RelayTokens.body(
          fontSize: fontSize, fontWeight: fontWeight, color: color, letterSpacing: letterSpacing, height: height),
      LauncherDesign.newCast => RaycastTokens.ui(
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
    this.maxHeight = double.infinity,
    this.constraints,
    this.margin = const EdgeInsets.symmetric(
      horizontal: 24,
      vertical: 48,
    ),
    required this.child,
  });

  final LauncherModalTokens tokens;
  final double width;
  final double maxHeight;

  /// Overrides the [maxHeight]-derived constraints when provided (used by the
  /// QuickMenu popup frame, which also carries a minHeight).
  final BoxConstraints? constraints;

  final EdgeInsetsGeometry margin;
  final Widget child;

  LauncherDesign get design => tokens.design;
  Color get accent => tokens.accent;

  @override
  Widget build(BuildContext context) {
    Widget core = _buildCore(context);

    core = _applyBackdropEffect(core);

    if (design == LauncherDesign.satin) {
      core = SatinSurface(radius: tokens.frameRadius, child: core);
    }

    if (design == LauncherDesign.thermal) {
      core = ThermalSurface(radius: tokens.frameRadius, child: core);
    }

    if (design == LauncherDesign.capillary) {
      core = CapillaryMotion(
        child: CapillarySurface(
          kind: CapillarySurfaceKind.paper,
          radius: tokens.frameRadius,
          child: CapillarySurface(kind: CapillarySurfaceKind.overlay, radius: tokens.frameRadius, child: core),
        ),
      );
    }

    if (design == LauncherDesign.opticalGlass) {
      core = LiquidMetalMotion(
          child: OpticalGlassSurface(
        raised: false,
        radius: tokens.frameRadius,
        child: OpticalGlassSurface(overlay: true, radius: tokens.frameRadius, child: core),
      ));
    }

    if (design == LauncherDesign.liquidMetal) {
      core = LiquidMetalMotion(
          child: LiquidMetalSurface(
        radius: tokens.frameRadius,
        child: LiquidMetalSurface(overlay: true, radius: tokens.frameRadius, child: core),
      ));
    }

    if (design == LauncherDesign.retro) {
      core = RetroSurface(
        background: tokens.surface,
        accent: tokens.accent,
        child: core,
      );
    }

    if (design == LauncherDesign.toon) {
      core = CrtSurface(
        shaderAsset: 'resources/shaders/toon.frag',
        animateEffect: false,
        effectName: 'Toon',
        background: ToonTokens.background,
        accent: ToonTokens.orange,
        child: ColoredBox(color: ToonTokens.background, child: core),
      );
    }

    return LauncherSurface(
      width: width,
      constraints: constraints ?? BoxConstraints(maxHeight: maxHeight),
      margin: margin,
      decoration: design.outerDecoration(
        surface: tokens.surface,
        accent: accent,
      ),
      child: core,
    );
  }

  Widget _buildCore(BuildContext context) {
    return Stack(
      fit: StackFit.passthrough,
      children: <Widget>[
        ..._buildBackgroundFlourishes(),
        _buildContent(context),
        ..._buildForegroundFlourishes(),
      ],
    );
  }

  Widget _buildContent(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: _surfaceColor(context),
      ),
      child: child,
    );
  }

  Color _surfaceColor(BuildContext context) {
    return switch (design) {
      LauncherDesign.satin => Colors.transparent,
      LauncherDesign.thermal => Colors.transparent,
      LauncherDesign.capillary => Colors.transparent,
      LauncherDesign.opticalGlass => Colors.transparent,
      LauncherDesign.liquidMetal => Colors.transparent,
      LauncherDesign.toon => Colors.transparent,
      LauncherDesign.omarchy => tokens.surface,
      LauncherDesign.tui => tokens.surface,
      LauncherDesign.retro => tokens.surface,
      LauncherDesign.relay || LauncherDesign.newCast || LauncherDesign.notion => tokens.surface.withValues(alpha: 0.98),
      LauncherDesign.windows98 => Windows98Tokens.face,
      LauncherDesign.windowsXp => WindowsXpTokens.surface,
      LauncherDesign.manifesto => tokens.surface.withValues(alpha: 0.96),

      // Matrix text needs a solid reading surface;
      // keep the launcher backdrop outside the modal.
      LauncherDesign.matrix => tokens.surface.withValues(alpha: 1.0),
      _ => Theme.of(context).colorScheme.surface.withValues(alpha: 0.4),
    };
  }

  List<Widget> _buildBackgroundFlourishes() {
    return switch (design) {
      LauncherDesign.blueprint => <Widget>[
          _fill(
            CustomPaint(
              painter: _ModalSheetPainter(ink: accent),
            ),
          ),
        ],
      LauncherDesign.zen => <Widget>[
          _fill(
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.7, -0.9),
                  radius: 1.3,
                  colors: <Color>[
                    accent.withAlpha(22),
                    accent.withAlpha(0),
                  ],
                ),
              ),
            ),
          ),
        ],
      LauncherDesign.manifesto => <Widget>[
          _fill(
            CustomPaint(
              painter: _ModalManifestoPainter(
                ink: tokens.onSurface.withAlpha(20),
              ),
            ),
          ),
        ],
      LauncherDesign.orbit => <Widget>[
          _fill(
            CustomPaint(
              painter: _ModalOrbitPainter(
                ink: accent,
                isDark: tokens.isDark,
              ),
            ),
          ),
        ],
      LauncherDesign.glass => <Widget>[
          _buildGlassSheen(),
          _buildGlassTopEdge(),
        ],
      _ => const <Widget>[],
    };
  }

  List<Widget> _buildForegroundFlourishes() {
    return switch (design) {
      LauncherDesign.terminal => <Widget>[
          _fill(
            CustomPaint(
              painter: _ModalScanlinePainter(
                isDark: tokens.isDark,
              ),
            ),
          ),
        ],
      LauncherDesign.command => <Widget>[
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 2,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      accent.withAlpha(200),
                      accent.withAlpha(40),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      LauncherDesign.manifesto => <Widget>[
          Positioned(
            top: 0,
            right: 0,
            width: 34,
            height: 7,
            child: IgnorePointer(
              child: ColoredBox(color: accent),
            ),
          ),
        ],
      _ => const <Widget>[],
    };
  }

  Widget _applyBackdropEffect(Widget core) {
    return switch (design) {
      LauncherDesign.glass => _buildGlassBackdrop(core),
      LauncherDesign.serene => BackdropFilter(
          filter: ui.ImageFilter.blur(
            sigmaX: 24,
            sigmaY: 24,
          ),
          child: core,
        ),
      _ => core,
    };
  }

  Widget _buildGlassBackdrop(Widget core) {
    final Color baseFill = tokens.surface.withAlpha(
      tokens.isDark ? 205 : 225,
    );

    return BackdropFilter(
      filter: ui.ImageFilter.blur(
        sigmaX: 30,
        sigmaY: 30,
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(tokens.frameRadius),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Color.alphaBlend(
                Colors.white.withAlpha(
                  tokens.isDark ? 50 : 90,
                ),
                baseFill,
              ),
              baseFill,
              Color.alphaBlend(
                accent.withAlpha(
                  tokens.isDark ? 40 : 26,
                ),
                baseFill,
              ),
            ],
          ),
          border: Border.all(
            color: Colors.white.withAlpha(
              tokens.isDark ? 40 : 120,
            ),
            width: 1.2,
          ),
        ).withLauncherCorners(),
        child: core,
      ),
    );
  }

  Widget _buildGlassSheen() {
    return _fill(
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.center,
            colors: <Color>[
              Colors.white.withAlpha(
                tokens.isDark ? 24 : 90,
              ),
              Colors.transparent,
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildGlassTopEdge() {
    return Positioned(
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
                Colors.white.withAlpha(
                  tokens.isDark ? 70 : 200,
                ),
                Colors.transparent,
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _fill(Widget child) {
    return Positioned.fill(
      child: IgnorePointer(
        child: child,
      ),
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

  Decoration _chipDecoration() {
    final Color accent = tokens.accent;
    return switch (tokens.design) {
      LauncherDesign.command => BoxDecoration(
          color: accent.withAlpha(14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: accent.withAlpha(50)),
        ).withLauncherCorners(),
      LauncherDesign.terminal => BoxDecoration(
          color: accent.withAlpha(20),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: accent.withAlpha(60)),
        ).withLauncherCorners(),
      LauncherDesign.retro => BoxDecoration(
          color: RetroTokens.panel,
          border: Border.all(color: RetroTokens.cyan.withAlpha(150)),
        ),
      LauncherDesign.terminal2 => BoxDecoration(
          color: Terminal2Tokens.raised(tokens.isDark),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: accent.withAlpha(80)),
        ).withLauncherCorners(),
      LauncherDesign.zen => BoxDecoration(
          color: accent.withAlpha(26),
          borderRadius: BorderRadius.circular(13),
        ).withLauncherCorners(),
      LauncherDesign.glass => BoxDecoration(
          color: Colors.white.withAlpha(tokens.isDark ? 22 : 120),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white.withAlpha(tokens.isDark ? 40 : 140), width: 0.8),
        ).withLauncherCorners(),
      // Part-reference balloon, like the Blueprint result rows.
      LauncherDesign.blueprint => BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent.withAlpha(180), width: 1.2),
        ),
      // Line roundel, like the Transit search bar bullet.
      LauncherDesign.transit => BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: accent, width: 2.4),
        ),
      // Faint WinUI layer chip with a hairline stroke.
      LauncherDesign.fluent => BoxDecoration(
          color: tokens.onSurface.withAlpha(14),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: FluentTokens.stroke(tokens.isDark)),
        ).withLauncherCorners(),
      LauncherDesign.manifesto => BoxDecoration(
          color: tokens.onSurface,
          border: Border.all(color: tokens.onSurface, width: 1.5),
        ),
      // Instrument chip — square, thin phosphor outline.
      LauncherDesign.orbit => BoxDecoration(
          color: tokens.accent.withAlpha(16),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: tokens.accent.withAlpha(70)),
        ).withLauncherCorners(),
      LauncherDesign.windowsXp => BoxDecoration(
          color: WindowsXpTokens.paper,
          border: Border(
            left: BorderSide(color: WindowsXpTokens.controlLight),
            top: BorderSide(color: WindowsXpTokens.controlLight),
            right: const BorderSide(color: WindowsXpTokens.controlShadow),
            bottom: const BorderSide(color: WindowsXpTokens.controlShadow),
          ),
        ),
      LauncherDesign.windows98 => BoxDecoration(
          color: Windows98Tokens.face,
          border: Border(
            left: BorderSide(color: Windows98Tokens.light, width: 2),
            top: BorderSide(color: Windows98Tokens.light, width: 2),
            right: BorderSide(color: Windows98Tokens.dark, width: 2),
            bottom: BorderSide(color: Windows98Tokens.dark, width: 2),
          ),
        ),
      LauncherDesign.notion => BoxDecoration(
          color: NotionTokens.selection(tokens.isDark),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: NotionTokens.border(tokens.isDark)),
        ).withLauncherCorners(),
      LauncherDesign.switchboard => BoxDecoration(
          color: SwitchboardTokens.raised(tokens.isDark),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: SwitchboardTokens.border(tokens.isDark)),
        ).withLauncherCorners(),
      LauncherDesign.relay => BoxDecoration(
          color: RelayTokens.raised(tokens.isDark, accent),
          borderRadius: BorderRadius.circular(2),
          border: Border.all(color: RelayTokens.border(tokens.isDark, accent)),
        ).withLauncherCorners(),
      _ => BoxDecoration(
          color: accent.withAlpha(28),
          borderRadius: BorderRadius.circular(8),
        ).withLauncherCorners(),
    };
  }

  bool get _uppercaseVoice =>
      tokens.design == LauncherDesign.blueprint ||
      tokens.design == LauncherDesign.command ||
      tokens.design == LauncherDesign.terminal2 ||
      tokens.design == LauncherDesign.retro ||
      tokens.design == LauncherDesign.orbit ||
      tokens.design == LauncherDesign.manifesto ||
      tokens.design == LauncherDesign.switchboard ||
      tokens.design == LauncherDesign.relay;

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
              ).withLauncherCorners(),
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
      LauncherDesign.terminal2 => tokens.dim.withAlpha(72),
      LauncherDesign.retro => tokens.accent.withAlpha(100),
      LauncherDesign.blueprint => tokens.accent.withAlpha(80),
      LauncherDesign.transit => tokens.accent.withAlpha(90),
      LauncherDesign.orbit => tokens.accent.withAlpha(50),
      LauncherDesign.manifesto => tokens.onSurface,
      LauncherDesign.windowsXp => WindowsXpTokens.orange,
      LauncherDesign.windows98 => Windows98Tokens.shadow,
      LauncherDesign.notion => NotionTokens.border(tokens.isDark),
      LauncherDesign.switchboard => SwitchboardTokens.border(tokens.isDark),
      LauncherDesign.relay => RelayTokens.border(tokens.isDark, tokens.accent),
      _ => tokens.onSurface.withAlpha(16),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: tokens.design == LauncherDesign.terminal
            ? TerminalTokens.chrome(tokens.isDark)
            : tokens.design == LauncherDesign.terminal2
                ? Terminal2Tokens.chrome(tokens.isDark)
                : tokens.design == LauncherDesign.retro
                    ? RetroTokens.panel
                    : tokens.design == LauncherDesign.transit
                        ? TransitTokens.chrome(tokens.isDark)
                        : tokens.design == LauncherDesign.fluent
                            ? FluentTokens.chrome(tokens.isDark)
                            : tokens.design == LauncherDesign.orbit
                                ? OrbitTokens.chrome(tokens.isDark)
                                : tokens.design == LauncherDesign.notion
                                    ? NotionTokens.sidebar(tokens.isDark)
                                    : tokens.design == LauncherDesign.switchboard
                                        ? SwitchboardTokens.panel(tokens.isDark)
                                        : tokens.design == LauncherDesign.relay
                                            ? RelayTokens.panel(tokens.isDark, tokens.accent)
                                            : null,
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
    if (tokens.design == LauncherDesign.terminal || tokens.design == LauncherDesign.terminal2) {
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
            borderRadius: BorderRadius.circular(
              tokens.design == LauncherDesign.manifesto ? 0 : (tokens.design == LauncherDesign.blueprint ? 2 : 4),
            ),
            border: Border.all(
              color: tokens.outlinedControls ? tokens.accent.withAlpha(70) : onSurface.withAlpha(28),
            ),
          ).withLauncherCorners(),
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

class _ModalManifestoPainter extends CustomPainter {
  const _ModalManifestoPainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = ink
      ..strokeWidth = 0.5;
    for (double y = 18; y < size.height; y += 18) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
    final Paint mark = Paint()
      ..color = ink.withAlpha(120)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(6, 9), const Offset(18, 9), mark);
    canvas.drawLine(const Offset(12, 3), const Offset(12, 15), mark);
  }

  @override
  bool shouldRepaint(covariant _ModalManifestoPainter oldDelegate) => oldDelegate.ink != ink;
}

/// Faint range rings radiating from beyond the top-right corner, with bearing
/// ticks down the left edge (Orbit design) — a private copy of the launcher
/// frame's scope texture.
class _ModalOrbitPainter extends CustomPainter {
  const _ModalOrbitPainter({required this.ink, required this.isDark});

  final Color ink;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint ring = Paint()
      ..color = ink.withAlpha(isDark ? 11 : 14)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Offset origin = Offset(size.width * 1.02, -size.height * 0.08);
    for (double r = 42; r < size.width * 1.1; r += 42) {
      canvas.drawCircle(origin, r, ring);
    }

    final Paint cross = Paint()
      ..color = ink.withAlpha(isDark ? 36 : 42)
      ..strokeWidth = 1;
    canvas.drawLine(origin + const Offset(-5, 0), origin + const Offset(5, 0), cross);
    canvas.drawLine(origin + const Offset(0, -5), origin + const Offset(0, 5), cross);

    final Paint tick = Paint()
      ..color = ink.withAlpha(isDark ? 22 : 26)
      ..strokeWidth = 1;
    int i = 0;
    for (double y = 20; y < size.height; y += 20) {
      final double len = i % 4 == 0 ? 6 : 3;
      canvas.drawLine(Offset(0.5, y), Offset(0.5 + len, y), tick);
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _ModalOrbitPainter oldDelegate) =>
      oldDelegate.ink != ink || oldDelegate.isDark != isDark;
}
