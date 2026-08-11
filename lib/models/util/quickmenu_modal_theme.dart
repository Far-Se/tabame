// ignore_for_file: unused_import, unused_element

import 'package:flutter/material.dart';
import 'dart:math' as math;

import '../../pages/launcher/launcher_modal_theme.dart';
import '../../pages/quickmenu_designs/design_family_guy.dart';
import '../../pages/quickmenu_designs/design_outrun2.dart';
import '../../pages/quickmenu_designs/design_winamp.dart';
import '../globals.dart';
import '../settings.dart';

/// Frame for QuickMenu modal popups (`showQuickMenuModal`) so they follow the
/// active QuickMenu design, the same way the launcher's Ctrl+K actions modal
/// follows the launcher design via [LauncherModalTokens]/[LauncherModalFrame].
///
/// The popup hosts arbitrary panel content, so only the frame is themed here —
/// each design's fill, border, corner radius and signature textures (matrix
/// grid, gazette page rules, player brushed metal, terminal accent border…)
/// are re-derived from the same `Design.*` theme values the design widgets in
/// `pages/quickmenu_designs/` use.

Color _lift(Color base, double amount) => Color.alphaBlend(Colors.white.withValues(alpha: amount), base);
Color _sink(Color base, double amount) => Color.alphaBlend(Colors.black.withValues(alpha: amount), base);

/// Mounts a decorative layer directly under the modal's [Stack].
///
/// Most layers paint edge-to-edge and receive a [Positioned.fill] wrapper.
/// A few designs intentionally provide their own [Positioned] geometry (for
/// example Outrun2's sunset band). Those must remain direct Stack children:
/// putting [IgnorePointer] between a Positioned widget and the Stack produces
/// an incompatible ParentData assertion.
Widget _mountModalLayer(Widget layer) {
  if (layer is Positioned) {
    return Positioned(
      left: layer.left,
      top: layer.top,
      right: layer.right,
      bottom: layer.bottom,
      width: layer.width,
      height: layer.height,
      child: IgnorePointer(child: layer.child),
    );
  }
  return Positioned.fill(child: IgnorePointer(child: layer));
}

ThemeData _legacyPopupTheme(ThemeData inherited, {required bool windowsXp}) {
  final bool isDark = Design.background.computeLuminance() < 0.5;
  final Color face = isDark
      ? Design.background
      : windowsXp
          ? const Color(0xFFECE9D8)
          : const Color(0xFFC0C0C0);
  final Color foreground = isDark ? Design.text : const Color(0xFF000000);
  final Color field = isDark ? Color.alphaBlend(Design.text.withAlpha(12), face) : const Color(0xFFFFFFFF);
  final Color primary = windowsXp ? const Color(0xFF245EDC) : const Color(0xFF000080);
  final Color shadow = windowsXp ? const Color(0xFFACA899) : const Color(0xFF808080);
  final String fontFamily = windowsXp ? 'Tahoma' : 'MS Sans Serif';
  final List<String> fallbacks =
      windowsXp ? const <String>['Verdana', 'Segoe UI'] : const <String>['Tahoma', 'Segoe UI'];
  final BorderRadius inputRadius = BorderRadius.circular(windowsXp ? 2 : 0);
  final ColorScheme scheme = (isDark ? ColorScheme.dark : ColorScheme.light)(
    primary: primary,
    onPrimary: const Color(0xFFFFFFFF),
    secondary: primary,
    onSecondary: const Color(0xFFFFFFFF),
    surface: face,
    onSurface: foreground,
    outline: shadow,
    outlineVariant: shadow.withAlpha(130),
  );
  final ThemeData base = isDark
      ? ThemeData.dark(useMaterial3: inherited.useMaterial3)
      : ThemeData.light(useMaterial3: inherited.useMaterial3);
  final TextTheme textTheme = base.textTheme.apply(
    fontFamily: fontFamily,
    fontFamilyFallback: fallbacks,
    bodyColor: foreground,
    displayColor: foreground,
  );
  final OutlineInputBorder fieldBorder = OutlineInputBorder(
    borderRadius: inputRadius,
    borderSide: BorderSide(color: shadow),
  );
  return base.copyWith(
    colorScheme: scheme,
    scaffoldBackgroundColor: face,
    canvasColor: face,
    cardColor: face,
    dividerColor: shadow,
    hoverColor: primary.withAlpha(18),
    highlightColor: primary.withAlpha(26),
    splashColor: primary.withAlpha(30),
    textTheme: textTheme,
    primaryTextTheme: textTheme,
    iconTheme: IconThemeData(color: foreground),
    primaryIconTheme: IconThemeData(color: foreground),
    dividerTheme: DividerThemeData(color: shadow, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: field,
      labelStyle: TextStyle(color: foreground),
      floatingLabelStyle: TextStyle(color: primary),
      hintStyle: TextStyle(color: foreground.withAlpha(150)),
      border: fieldBorder,
      enabledBorder: fieldBorder,
      focusedBorder: fieldBorder.copyWith(
        borderSide: BorderSide(color: primary, width: windowsXp ? 1.5 : 1),
      ),
    ),
    listTileTheme: ListTileThemeData(
      textColor: foreground,
      iconColor: foreground,
      selectedColor: const Color(0xFFFFFFFF),
      selectedTileColor: primary,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: isDark
            ? field
            : windowsXp
                ? const Color(0xFFFFFFE1)
                : face,
        border: Border.all(color: foreground),
        borderRadius: BorderRadius.circular(windowsXp ? 2 : 0),
      ),
      textStyle: TextStyle(color: foreground, fontSize: 11),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: primary,
      selectionColor: primary.withAlpha(70),
      selectionHandleColor: primary,
    ),
  );
}

class QuickMenuModalFrame extends StatelessWidget {
  const QuickMenuModalFrame({
    super.key,
    required this.width,
    required this.constraints,
    required this.child,
  });

  final double width;
  final BoxConstraints constraints;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ThemeData inheritedTheme = Theme.of(context);

    // Popups opened over the launcher page speak the launcher design instead —
    // the same frame the Ctrl+K actions modal uses.
    if (Globals.quickMenuPage == QuickMenuPage.launcher) {
      final LauncherDesign launcherDesign = user.launcherDesign;
      final Widget popupChild = launcherDesign == LauncherDesign.windowsXp || launcherDesign == LauncherDesign.windows98
          ? Theme(
              data: _legacyPopupTheme(
                inheritedTheme,
                windowsXp: launcherDesign == LauncherDesign.windowsXp,
              ),
              child: child,
            )
          : child;
      return LauncherModalFrame(
        tokens: LauncherModalTokens.of(context),
        width: width,
        margin: EdgeInsets.zero,
        constraints: constraints,
        child: popupChild,
      );
    }

    final QuickMenuDesigns design = QuickMenuDesigns.values[user.quickMenuDesign];
    final ThemeData theme = inheritedTheme;
    final Color surface = theme.colorScheme.surface;
    final Color onSurface = theme.colorScheme.onSurface;
    final Color bg = Design.background;
    final Color accent = Design.accent;
    final Color text = Design.text;
    final bool isDark = bg.computeLuminance() < 0.5;
    final double intensity = (Design.gradientAlpha.clamp(0, 255)) / 255.0;
    final double r = Design.borderRadius;
    final Widget popupChild = design == QuickMenuDesigns.windowsXp || design == QuickMenuDesigns.windows98
        ? Theme(
            data: _legacyPopupTheme(
              inheritedTheme,
              windowsXp: design == QuickMenuDesigns.windowsXp,
            ),
            child: child,
          )
        : child;

    // Aurora's signature asymmetric corners; every other design keeps its
    // regular panel radius.
    final BorderRadius radius = design == QuickMenuDesigns.aurora && r > 0
        ? BorderRadius.only(
            topLeft: Radius.circular(r),
            bottomRight: Radius.circular(r),
            topRight: Radius.circular((r * 0.3) + 3),
            bottomLeft: Radius.circular((r * 0.3) + 3),
          )
        : BorderRadius.circular(r);

    final _FrameSpec spec = switch (design) {
      QuickMenuDesigns.classic => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: surface.withValues(alpha: 0.88),
            border: Border.all(color: onSurface.withValues(alpha: 0.12), width: 0.5),
          ),
        ),
      QuickMenuDesigns.modern => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                surface.withValues(alpha: 0.95),
                Color.alphaBlend(accent.withAlpha((Design.gradientAlpha * 24 / 100).toInt()), surface)
                    .withValues(alpha: 0.95),
                Color.alphaBlend(accent.withAlpha((Design.gradientAlpha * 10 / 100).toInt()), surface)
                    .withValues(alpha: 0.95),
              ],
            ),
            border: Border.all(color: accent.withAlpha(28)),
          ),
          underlays: <Widget>[
            // Top sheen, same as the panel's inner gradient.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[Colors.white.withAlpha(14), Colors.transparent],
                ),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.interface => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: <Color>[
                Color.alphaBlend(
                        accent.withValues(alpha: 0.04 + ((Design.gradientAlpha.clamp(1, 100)) / 100) * 0.08), surface)
                    .withValues(alpha: 0.93),
                surface.withValues(alpha: 0.93),
              ],
            ),
            border: Border.all(color: onSurface.withValues(alpha: 0.08)),
          ),
        ),
      QuickMenuDesigns.matrix => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: Color.alphaBlend(accent.withValues(alpha: Design.gradientAlpha / 255.0), surface)
                .withValues(alpha: 0.95),
            border: Border.all(color: accent.withValues(alpha: 0.25), width: 0.8),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _GridPainter(accent.withValues(alpha: 0.07))),
          ],
        ),
      QuickMenuDesigns.serene => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: RadialGradient(
              center: const Alignment(-0.6, -0.7),
              radius: 1.4,
              colors: <Color>[
                Color.alphaBlend(accent.withValues(alpha: 0.10 + intensity * 0.14), surface).withValues(alpha: 0.93),
                surface.withValues(alpha: 0.93),
              ],
            ),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.70),
              width: 0.8,
            ),
          ),
        ),
      QuickMenuDesigns.aurora => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: surface.withValues(alpha: 0.96),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.07) : accent.withValues(alpha: 0.16),
              width: 0.8,
            ),
          ),
          underlays: _auroraBlobs(accent, intensity),
        ),
      QuickMenuDesigns.terminal => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.95),
            border: Border.all(color: accent.withAlpha(80)),
          ),
        ),
      QuickMenuDesigns.cassette => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _lift(bg, isDark ? 0.09 : 0.30).withValues(alpha: 0.96),
                bg.withValues(alpha: 0.96),
                _sink(bg, isDark ? 0.20 : 0.08).withValues(alpha: 0.96),
              ],
              stops: const <double>[0.0, 0.45, 1.0],
            ),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.14),
            ),
          ),
        ),
      QuickMenuDesigns.fluent => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.95),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.09) : Colors.black.withValues(alpha: 0.11),
            ),
          ),
          underlays: <Widget>[
            // Mica tint drifting in from the top.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    accent.withValues(alpha: (intensity * 0.10).clamp(0.0, 1.0)),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.gazette => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.96),
            border: Border.all(color: text.withValues(alpha: 0.45)),
          ),
          underlays: <Widget>[
            // Aged-paper vignette.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  radius: 1.25,
                  colors: <Color>[
                    Colors.transparent,
                    text.withValues(alpha: (0.03 + intensity * 0.07).clamp(0.0, 1.0)),
                  ],
                ),
              ),
            ),
          ],
          overlays: <Widget>[
            // Inner hairline of the double page frame.
            Container(
              margin: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                border: Border.all(color: text.withValues(alpha: 0.22), width: 0.8),
                borderRadius: BorderRadius.circular((r - 3).clamp(0.0, 100.0)),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.player => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: <Color>[
                _lift(bg, isDark ? 0.14 : 0.35).withValues(alpha: 0.97),
                bg.withValues(alpha: 0.97),
                _sink(bg, isDark ? 0.16 : 0.10).withValues(alpha: 0.97),
                bg.withValues(alpha: 0.97),
              ],
              stops: const <double>[0.0, 0.45, 0.9, 1.0],
            ),
          ),
          bevel: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              Colors.white.withValues(alpha: isDark ? 0.16 : 0.75),
              Colors.black.withValues(alpha: isDark ? 0.55 : 0.30),
            ],
          ),
          underlays: <Widget>[
            CustomPaint(painter: _BrushedPainter(isDark: isDark)),
          ],
        ),
      QuickMenuDesigns.steam => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.95),
            border: Border.all(
              color: isDark ? Colors.black.withValues(alpha: 0.5) : Colors.black.withValues(alpha: 0.12),
            ),
          ),
          underlays: <Widget>[
            // Library ambient glow drifting in from the top-left.
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: RadialGradient(
                  center: const Alignment(-0.6, -1.4),
                  radius: 1.6,
                  colors: <Color>[
                    accent.withValues(alpha: (0.05 + intensity * 0.18).clamp(0.0, 1.0)),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.manifesto => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.98),
            border: Border.all(color: text, width: 2),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _ManifestoRulePainter(text.withValues(alpha: isDark ? 0.10 : 0.075))),
          ],
          overlays: <Widget>[
            Align(
              alignment: Alignment.topRight,
              child: Container(width: 28, height: 6, color: accent),
            ),
          ],
        ),
      QuickMenuDesigns.vector => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.97),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.14 : 0.18), width: 0.5),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _VectorScanPainter(text.withValues(alpha: isDark ? 0.05 : 0.04))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _VectorBracketPainter(accent)),
          ],
        ),
      QuickMenuDesigns.ledger => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.98),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.16 : 0.2), width: 0.6),
          ),
          underlays: <Widget>[
            CustomPaint(
              painter: _LedgerMarginPainter(
                rule: text.withValues(alpha: isDark ? 0.16 : 0.2),
                holeRing: text.withValues(alpha: isDark ? 0.3 : 0.36),
              ),
            ),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _LedgerFoldPainter(text.withValues(alpha: isDark ? 0.22 : 0.26))),
          ],
        ),
      QuickMenuDesigns.console => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.97),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.20 : 0.24), width: 0.8),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _ConsoleBrushedPainter(isDark: isDark)),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _ConsoleRivetPainter(text.withValues(alpha: isDark ? 0.50 : 0.40))),
          ],
        ),
      QuickMenuDesigns.foundry => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.98),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.24 : 0.30), width: 0.8),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _FoundryGrainPainter(text.withValues(alpha: isDark ? 0.035 : 0.025))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _FoundryCornerMarkPainter(accent.withValues(alpha: 0.75))),
          ],
        ),
      QuickMenuDesigns.anime => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.97),
            border: Border.all(color: accent.withValues(alpha: isDark ? 0.30 : 0.22), width: 0.8),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _SparkleDustPainter(accent.withValues(alpha: isDark ? 0.16 : 0.14))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _RibbonCornerPainter(accent)),
          ],
        ),
      QuickMenuDesigns.cyber => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.92),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.7 : 0.5),
              width: 1.2,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.35 : 0.2),
                blurRadius: 16,
                spreadRadius: 1,
              ),
            ],
          ),
          underlays: <Widget>[
            CustomPaint(painter: _AnimeGridPainter(accent.withValues(alpha: isDark ? 0.08 : 0.05))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _AnimeFrameOverlayPainter(accent)),
          ],
        ),
      QuickMenuDesigns.tech => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.85), // Frosted glass feel
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.4 : 0.3),
              width: 1.0,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.5 : 0.15),
                blurRadius: 30,
                spreadRadius: 0,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          underlays: <Widget>[
            CustomPaint(painter: _TechBlueprintPainter(text.withValues(alpha: isDark ? 0.04 : 0.03))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _TechHUDOverlayPainter(accent)),
          ],
        ),
      QuickMenuDesigns.manga => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg,
            border: Border.all(color: text, width: 2.2),
          ),
          underlays: <Widget>[
            CustomPaint(painter: _HalftonePainter(text.withValues(alpha: isDark ? 0.04 : 0.02))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _MangaBurstLinesPainter(accent.withValues(alpha: isDark ? 0.10 : 0.07))),
            CustomPaint(painter: _MangaCornerTicksPainter(text)),
          ],
        ),
      // QuickMenuDesigns.impact => _FrameSpec(
      //     decoration: BoxDecoration(
      //       borderRadius: radius,
      //       color: bg.withValues(alpha: 0.97),
      //       border: Border.all(color: text.withValues(alpha: isDark ? 0.85 : 1), width: 2.5),
      //     ),
      //     underlays: <Widget>[
      //       CustomPaint(painter: _ImpactHalftonePainter(accent.withValues(alpha: isDark ? 0.09 : 0.07))),
      //     ],
      //     overlays: <Widget>[
      //       CustomPaint(painter: _ImpactSpeedlinePainter(accent: accent, ink: text)),
      //     ],
      //   ),
      QuickMenuDesigns.outrun => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.95),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.8 : 0.6),
              width: 1.5,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.4 : 0.25),
                blurRadius: 18,
                spreadRadius: 2,
              ),
            ],
          ),
          underlays: <Widget>[
            CustomPaint(painter: _OutrunGridPainter(accent.withValues(alpha: isDark ? 0.12 : 0.08))),
          ],
          overlays: <Widget>[
            CustomPaint(painter: _OutrunFramePainter(accent)),
          ],
        ),
      QuickMenuDesigns.anime2 => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.97),
            border: Border.all(
              color: accent.withValues(alpha: isDark ? 0.30 : 0.40),
              width: 1.0,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.18 : 0.12),
                blurRadius: 20,
                spreadRadius: -4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          underlays: <Widget>[
            // Soft floating dust / sparkles under the content
            CustomPaint(
              painter: _AnimeDustPainter(
                accent.withValues(alpha: isDark ? 0.20 : 0.28),
              ),
            ),
          ],
          overlays: <Widget>[
            // Star-shaped corner brackets
            CustomPaint(
              painter: _AnimeStarBracketPainter(
                accent: accent,
                tick: text.withValues(alpha: isDark ? 0.35 : 0.45),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.outrun2 => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.96),
            border: Border.all(
              color: accent,
              width: 1.5,
            ),
            boxShadow: <BoxShadow>[
              // Tight neon core glow
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.45 : 0.38),
                blurRadius: 12,
                spreadRadius: -2,
              ),
              // Diffuse atmospheric haze
              BoxShadow(
                color: accent.withValues(alpha: isDark ? 0.22 : 0.16),
                blurRadius: 32,
                spreadRadius: 4,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          underlays: <Widget>[
            // Sunset band at the top of the modal
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 50,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: <Color>[
                      const Color(0xFFFF00AA).withValues(alpha: isDark ? 0.28 : 0.22),
                      const Color(0xFFFF7700).withValues(alpha: isDark ? 0.12 : 0.08),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),
            // Perspective highway grid
            CustomPaint(
              painter: Outrun2GridPainter(
                color: accent.withValues(alpha: isDark ? 0.20 : 0.15),
                showHorizon: false,
              ),
              size: Size.infinite,
            ),
          ],
          overlays: <Widget>[
            // Neon corner brackets + CRT scanlines
            CustomPaint(
              painter: _OutrunNeonBracketPainter(
                accent: accent,
                secondary: text.withValues(alpha: isDark ? 0.50 : 0.60),
              ),
              size: Size.infinite,
            ),
            CustomPaint(
              painter: OutrunScanlinePainter(
                text.withValues(alpha: isDark ? 0.05 : 0.04),
              ),
              size: Size.infinite,
            ),
          ],
        ),
      QuickMenuDesigns.winamp => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.97),
            border: Border.all(
              color: text.withValues(alpha: isDark ? 0.16 : 0.28),
              width: 1,
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.20),
                blurRadius: 8,
                spreadRadius: 0,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          underlays: <Widget>[
            // Brushed metal grain
            CustomPaint(
              painter: WinampBrushedPainter(isDark: isDark),
              size: Size.infinite,
            ),
            // Cylindrical sheen
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: <Color>[
                    Colors.white.withValues(alpha: isDark ? 0.06 : 0.18),
                    Colors.transparent,
                    Colors.black.withValues(alpha: isDark ? 0.10 : 0.06),
                  ],
                  stops: const <double>[0.0, 0.5, 1.0],
                ),
              ),
            ),
          ],
          overlays: <Widget>[
            // 3D bevel frame
            CustomPaint(
              painter: _WinampFramePainter(
                hi: isDark ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.65),
                lo: isDark ? Colors.black.withValues(alpha: 0.55) : Colors.black.withValues(alpha: 0.32),
              ),
              size: Size.infinite,
            ),
            // LED accent corner ticks
            CustomPaint(
              painter: WinampLcdPainter(
                accent: accent,
                glow: (Design.gradientAlpha.clamp(0, 255)) / 255.0,
                isDark: isDark,
              ),
              size: Size.infinite,
            ),
          ],
        ),
      QuickMenuDesigns.windowsXp => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(7),
            color: const Color(0xFFECE9D8),
            border: Border.all(color: const Color(0xFF003399), width: 2),
            boxShadow: const <BoxShadow>[
              BoxShadow(color: Color(0x66000000), blurRadius: 12, offset: Offset(4, 7)),
              BoxShadow(color: Color(0xFF7AA5F7), offset: Offset(-1, -1)),
            ],
          ),
          underlays: const <Widget>[
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: 5,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: <Color>[
                      Color(0xFF5A8CF0),
                      Color(0xFF245EDC),
                      Color(0xFF003399),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      QuickMenuDesigns.windows98 => const _FrameSpec(
          decoration: BoxDecoration(
            color: Color(0xFFC0C0C0),
            border: Border(
              left: BorderSide(color: Color(0xFFFFFFFF), width: 2),
              top: BorderSide(color: Color(0xFFFFFFFF), width: 2),
              right: BorderSide(color: Color(0xFF000000), width: 2),
              bottom: BorderSide(color: Color(0xFF000000), width: 2),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(color: Color(0x66000000), offset: Offset(4, 5), blurRadius: 0),
            ],
          ),
          underlays: <Widget>[
            Positioned(
              top: 2,
              left: 2,
              right: 2,
              height: 4,
              child: ColoredBox(color: Color(0xFF000080)),
            ),
          ],
          overlays: <Widget>[
            CustomPaint(
              painter: _Windows98ModalBevelPainter(),
              size: Size.infinite,
            ),
          ],
        ),
      QuickMenuDesigns.notion => _FrameSpec(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF202020) : const Color(0xFFFFFFFF),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: (isDark ? const Color(0xFFE6E6E6) : const Color(0xFF37352F)).withAlpha(isDark ? 24 : 18),
            ),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withAlpha(isDark ? 95 : 30),
                blurRadius: 24,
                spreadRadius: -7,
                offset: const Offset(0, 11),
              ),
            ],
          ),
          underlays: <Widget>[
            // Positioned(
            //   left: 0,
            //   right: 0,
            //   bottom: 0,
            //   height: 34,
            //   child: ColoredBox(
            //     color: isDark ? const Color(0xFF191919) : const Color(0xFFF7F6F3),
            //   ),
            // ),
          ],
        ),
      QuickMenuDesigns.rundown => _FrameSpec(
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(Design.borderRadius),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.18 : 0.14), width: 0.8),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.24 : 0.12),
                blurRadius: 18,
                spreadRadius: -7,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          overlays: <Widget>[
            Positioned(
              left: 8,
              top: 8,
              width: 5,
              height: 5,
              child: ColoredBox(color: accent),
            ),
          ],
        ),
      QuickMenuDesigns.relay => _FrameSpec(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: bg.withValues(alpha: 0.96),
            border: Border.all(color: text.withValues(alpha: isDark ? 0.18 : 0.22), width: 0.8),
            boxShadow: <BoxShadow>[
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.28 : 0.10),
                blurRadius: 16,
                spreadRadius: -6,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          underlays: <Widget>[
            CustomPaint(
              painter: _RelayModalTracePainter(
                rail: accent.withValues(alpha: isDark ? 0.075 : 0.055),
                quiet: text.withValues(alpha: isDark ? 0.04 : 0.035),
              ),
            ),
          ],
          overlays: <Widget>[
            CustomPaint(
              painter: _RelayModalFramePainter(
                accent: accent,
                quiet: text.withValues(alpha: isDark ? 0.38 : 0.46),
              ),
            ),
          ],
        ),
      // QuickMenuDesigns.focusline => _FrameSpec(
      //     decoration: BoxDecoration(
      //       borderRadius: radius,
      //       color: bg.withValues(alpha: isDark ? 0.96 : 0.98),
      //       border: Border.all(
      //         color: text.withValues(alpha: isDark ? 0.18 : 0.22),
      //         width: 0.8,
      //       ),
      //       boxShadow: <BoxShadow>[
      //         BoxShadow(
      //           color: Colors.black.withValues(alpha: isDark ? 0.26 : 0.10),
      //           blurRadius: 15,
      //           spreadRadius: -7,
      //           offset: const Offset(0, 5),
      //         ),
      //       ],
      //     ),
      //     underlays: <Widget>[
      //       CustomPaint(
      //         painter: _FocuslineModalCalibrationPainter(
      //           rule: text.withValues(alpha: isDark ? 0.08 : 0.10),
      //           accent: accent.withValues(alpha: isDark ? 0.16 : 0.13),
      //         ),
      //       ),
      //     ],
      //     overlays: <Widget>[
      //       CustomPaint(
      //         painter: _FocuslineModalFramePainter(
      //           accent: accent,
      //           quiet: text.withValues(alpha: isDark ? 0.34 : 0.42),
      //         ),
      //       ),
      //     ],
      //   ),
      // QuickMenuDesigns.familyGuy => _FrameSpec(
      //     decoration: BoxDecoration(
      //       borderRadius: radius,
      //       color: bg.withValues(alpha: 0.98),
      //       border: Border.all(color: const Color(0xff1A1A1A), width: 3),
      //       boxShadow: <BoxShadow>[
      //         BoxShadow(
      //           color: Colors.black.withValues(alpha: isDark ? 0.50 : 0.25),
      //           blurRadius: 0,
      //           spreadRadius: 0,
      //           offset: const Offset(5, 5),
      //         ),
      //       ],
      //     ),
      //     underlays: <Widget>[
      //       // Living-room wallpaper crosshatch
      //       CustomPaint(
      //         painter: WallpaperPainter(
      //           color: text.withValues(alpha: isDark ? 0.04 : 0.06),
      //         ),
      //         size: Size.infinite,
      //       ),
      //     ],
      //     overlays: <Widget>[
      //       // Thick cartoon frame + character peeking from corner
      //       CustomPaint(
      //         painter: _FamilyGuyFramePainter(
      //           outline: const Color(0xff1A1A1A),
      //           shadow: isDark ? Colors.black.withValues(alpha: 0.45) : Colors.black.withValues(alpha: 0.20),
      //         ),
      //         size: Size.infinite,
      //       ),
      //       // Stewie peeking from bottom-left of modal
      //       const Positioned(
      //         bottom: -4,
      //         left: 4,
      //         width: 28,
      //         height: 32,
      //         child: IgnorePointer(
      //           child: CustomPaint(
      //             painter: StewieSilhouettePainter(
      //               color: Color(0xff1A1A1A),
      //             ),
      //           ),
      //         ),
      //       ),
      //     ],
      //   ),
    };

    final bool hasBevel = spec.bevel != null;
    Widget frame = Container(
      width: hasBevel ? null : width,
      constraints: hasBevel ? null : constraints,
      decoration: spec.decoration,
      child: ClipRRect(
        borderRadius: radius,
        child: Stack(
          fit: StackFit.passthrough,
          children: <Widget>[
            for (final Widget underlay in spec.underlays) _mountModalLayer(underlay),
            popupChild,
            for (final Widget overlay in spec.overlays) _mountModalLayer(overlay),
          ],
        ),
      ),
    );

    if (hasBevel) {
      // The classic skin emboss: a 1px frame that runs light on the top-left
      // and dark on the bottom-right (Player design).
      frame = Container(
        width: width,
        constraints: constraints,
        padding: const EdgeInsets.all(1),
        decoration: BoxDecoration(gradient: spec.bevel, borderRadius: radius),
        child: frame,
      );
    }
    return frame;
  }

  static List<Widget> _auroraBlobs(Color accent, double intensity) {
    final HSLColor accentHsl = HSLColor.fromColor(accent);
    final Color auroraB = accentHsl
        .withHue((accentHsl.hue + 58) % 360)
        .withSaturation((accentHsl.saturation * 0.92).clamp(0.0, 1.0))
        .toColor();
    return <Widget>[
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(-0.95, -1.1),
            radius: 1.25,
            colors: <Color>[
              accent.withValues(alpha: (0.10 + intensity * 0.26).clamp(0.0, 1.0)),
              accent.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
      DecoratedBox(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(1.15, 1.2),
            radius: 1.35,
            colors: <Color>[
              auroraB.withValues(alpha: (0.08 + intensity * 0.22).clamp(0.0, 1.0)),
              auroraB.withValues(alpha: 0.0),
            ],
          ),
        ),
      ),
    ];
  }
}

class _Windows98ModalBevelPainter extends CustomPainter {
  const _Windows98ModalBevelPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint highlight = Paint()
      ..color = const Color(0xFFDFDFDF)
      ..strokeWidth = 1;
    final Paint shadow = Paint()
      ..color = const Color(0xFF808080)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(2.5, 2.5), Offset(size.width - 2.5, 2.5), highlight);
    canvas.drawLine(const Offset(2.5, 2.5), Offset(2.5, size.height - 2.5), highlight);
    canvas.drawLine(
      Offset(size.width - 2.5, 2.5),
      Offset(size.width - 2.5, size.height - 2.5),
      shadow,
    );
    canvas.drawLine(
      Offset(2.5, size.height - 2.5),
      Offset(size.width - 2.5, size.height - 2.5),
      shadow,
    );
  }

  @override
  bool shouldRepaint(covariant _Windows98ModalBevelPainter oldDelegate) => false;
}

class _FrameSpec {
  const _FrameSpec({
    required this.decoration,
    this.bevel,
    this.underlays = const <Widget>[],
    this.overlays = const <Widget>[],
  });

  final BoxDecoration decoration;

  /// When set, the frame is wrapped in a 1px gradient emboss (Player design).
  final Gradient? bevel;
  final List<Widget> underlays;
  final List<Widget> overlays;
}

/// Faint square grid, same as the Matrix design's background.
class _GridPainter extends CustomPainter {
  const _GridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    const double step = 20;
    for (double i = 0; i < size.width; i += step) {
      canvas.drawLine(Offset(i, 0), Offset(i, size.height), paint);
    }
    for (double i = 0; i < size.height; i += step) {
      canvas.drawLine(Offset(0, i), Offset(size.width, i), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _GridPainter oldDelegate) => oldDelegate.color != color;
}

/// Horizontal brushed-metal hairlines, same as the Player design's body.
class _BrushedPainter extends CustomPainter {
  const _BrushedPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint light = Paint()..color = Colors.white.withValues(alpha: isDark ? 0.015 : 0.10);
    final Paint dark = Paint()..color = Colors.black.withValues(alpha: isDark ? 0.03 : 0.035);
    for (double y = 0; y < size.height; y += 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), dark);
      canvas.drawRect(Rect.fromLTWH(0, y + 1, size.width, 1), light);
    }
  }

  @override
  bool shouldRepaint(covariant _BrushedPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// Sparse editorial rules used by the Manifesto panel and its popups.
class _ManifestoRulePainter extends CustomPainter {
  const _ManifestoRulePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double y = 18; y < size.height; y += 18) {
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ManifestoRulePainter oldDelegate) => oldDelegate.color != color;
}

/// Soft CRT scanlines, same as the Vector design's background texture.
class _VectorScanPainter extends CustomPainter {
  const _VectorScanPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double y = 1.5; y < size.height; y += 3) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _VectorScanPainter oldDelegate) => oldDelegate.color != color;
}

/// Faint diagonal brushed-metal strokes, fixed-seed so they don't jitter
/// on rebuild. Cheap stand-in for the full widget's texture layer.
class _ConsoleBrushedPainter extends CustomPainter {
  _ConsoleBrushedPainter({required this.isDark});

  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final math.Random rnd = math.Random(7);
    final Color strokeColor = isDark ? Colors.white : Colors.black;
    final Paint paint = Paint()..strokeWidth = 1;
    final double diag = size.width + size.height;
    final int lineCount = (diag / 5).floor();

    for (int i = 0; i < lineCount; i++) {
      final double offset = i * 5.0 + rnd.nextDouble() * 2;
      paint.color = strokeColor.withValues(alpha: 0.012 + rnd.nextDouble() * 0.02);
      canvas.drawLine(Offset(offset - size.height, 0), Offset(offset, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _ConsoleBrushedPainter oldDelegate) => oldDelegate.isDark != isDark;
}

/// Four Phillips-head rivets pinning the corners of the frame, inset just
/// inside the border — the modal-preview version of the full widget's
/// `_Rivet` widgets, collapsed into one painter since there's no need for
/// separate widget/gesture handling here.
class _ConsoleRivetPainter extends CustomPainter {
  _ConsoleRivetPainter(this.color);

  final Color color;
  static const double _inset = 8;
  static const double _radius = 2.6;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color;
    final Paint slot = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..strokeWidth = 0.8;

    final List<Offset> corners = <Offset>[
      const Offset(_inset, _inset),
      Offset(size.width - _inset, _inset),
      Offset(_inset, size.height - _inset),
      Offset(size.width - _inset, size.height - _inset),
    ];

    for (final Offset c in corners) {
      canvas.drawCircle(c, _radius, fill);
      canvas.drawLine(Offset(c.dx - _radius + 0.6, c.dy), Offset(c.dx + _radius - 0.6, c.dy), slot);
    }
  }

  @override
  bool shouldRepaint(covariant _ConsoleRivetPainter oldDelegate) => oldDelegate.color != color;
}

/// Binder margin for the modal frame: a hairline rule down the left edge
/// with a short run of hollow punch-holes near the top. Same motif as the
/// QuickMenu panel, scaled to whatever size the modal ends up being.
class _LedgerMarginPainter extends CustomPainter {
  const _LedgerMarginPainter({required this.rule, required this.holeRing});

  final Color rule;
  final Color holeRing;

  static const double _marginX = 18;
  static const double _holeR = 2.3;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint rulePaint = Paint()
      ..color = rule
      ..strokeWidth = 0.6;
    canvas.drawLine(const Offset(_marginX, 8), Offset(_marginX, size.height - 8), rulePaint);

    final Paint ring = Paint()
      ..color = holeRing
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;

    const double holeX = _marginX / 2;
    double y = 16;
    while (y < size.height - 12) {
      canvas.drawCircle(Offset(holeX, y), _holeR, ring);
      y += 26;
    }
  }

  @override
  bool shouldRepaint(covariant _LedgerMarginPainter oldDelegate) =>
      oldDelegate.rule != rule || oldDelegate.holeRing != holeRing;
}

/// Folded page-corner, top right — two thin strokes standing in for a
/// dog-eared corner, kept as an overlay so it always sits above content.
class _LedgerFoldPainter extends CustomPainter {
  const _LedgerFoldPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint stroke = Paint()
      ..color = color
      ..strokeWidth = 0.6
      ..style = PaintingStyle.stroke;
    final Path fold = Path()
      ..moveTo(size.width - 14, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, 14)
      ..moveTo(size.width - 9, 0)
      ..lineTo(size.width, 9);
    canvas.drawPath(fold, stroke);
  }

  @override
  bool shouldRepaint(covariant _LedgerFoldPainter oldDelegate) => oldDelegate.color != color;
}

/// Corner reticle brackets used by the Vector design's panel and popups.
class _VectorBracketPainter extends CustomPainter {
  const _VectorBracketPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    const double inset = 3;
    const double len = 9;
    final double right = size.width - inset;
    final double bottom = size.height - inset;
    final Path corners = Path()
      ..moveTo(inset, inset + len)
      ..lineTo(inset, inset)
      ..lineTo(inset + len, inset)
      ..moveTo(right - len, inset)
      ..lineTo(right, inset)
      ..lineTo(right, inset + len)
      ..moveTo(right, bottom - len)
      ..lineTo(right, bottom)
      ..lineTo(right - len, bottom)
      ..moveTo(inset + len, bottom)
      ..lineTo(inset, bottom)
      ..lineTo(inset, bottom - len);
    canvas.drawPath(corners, paint);
  }

  @override
  bool shouldRepaint(covariant _VectorBracketPainter oldDelegate) => oldDelegate.color != color;
}

class _RelayModalTracePainter extends CustomPainter {
  const _RelayModalTracePainter({required this.rail, required this.quiet});

  final Color rail;
  final Color quiet;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint quietPaint = Paint()
      ..color = quiet
      ..strokeWidth = 0.5;
    final Paint railPaint = Paint()
      ..color = rail
      ..strokeWidth = 0.7
      ..style = PaintingStyle.stroke;

    for (double y = 16; y < size.height; y += 22) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), quietPaint);
    }

    final Path trace = Path()
      ..moveTo(0, 31)
      ..lineTo(size.width * 0.22, 31)
      ..lineTo(size.width * 0.25, 27)
      ..lineTo(size.width * 0.52, 27)
      ..lineTo(size.width * 0.55, 31)
      ..lineTo(size.width * 0.76, 31);
    canvas.drawPath(trace, railPaint);

    final Paint node = Paint()..color = rail;
    for (final Offset point in <Offset>[
      Offset(size.width * 0.25, 27),
      Offset(size.width * 0.55, 31),
    ]) {
      canvas.drawCircle(point, 1.4, node);
    }
  }

  @override
  bool shouldRepaint(covariant _RelayModalTracePainter oldDelegate) =>
      oldDelegate.rail != rail || oldDelegate.quiet != quiet;
}

class _RelayModalFramePainter extends CustomPainter {
  const _RelayModalFramePainter({required this.accent, required this.quiet});

  final Color accent;
  final Color quiet;

  @override
  void paint(Canvas canvas, Size size) {
    const double inset = 3;
    const double length = 9;
    final double right = size.width - inset;
    final double bottom = size.height - inset;
    final Paint bracket = Paint()
      ..color = accent
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final Path corners = Path()
      ..moveTo(inset, inset + length)
      ..lineTo(inset, inset)
      ..lineTo(inset + length, inset)
      ..moveTo(right - length, inset)
      ..lineTo(right, inset)
      ..lineTo(right, inset + length)
      ..moveTo(right, bottom - length)
      ..lineTo(right, bottom)
      ..lineTo(right - length, bottom)
      ..moveTo(inset + length, bottom)
      ..lineTo(inset, bottom)
      ..lineTo(inset, bottom - length);
    canvas.drawPath(corners, bracket);

    final Paint tick = Paint()
      ..color = quiet
      ..strokeWidth = 0.8;
    final double cx = size.width / 2;
    canvas.drawLine(Offset(cx, inset - 1), Offset(cx, inset + 4), tick);
    canvas.drawLine(Offset(cx, bottom - 4), Offset(cx, bottom + 1), tick);

    final Paint bus = Paint()
      ..color = accent.withValues(alpha: 0.55)
      ..strokeWidth = 0.8;
    const double x = 7;
    canvas.drawLine(const Offset(x, 20), Offset(x, size.height - 20), bus);
    for (final double y in <double>[26, size.height - 26]) {
      canvas.drawCircle(Offset(x, y), 1.3, Paint()..color = accent);
    }
  }

  @override
  bool shouldRepaint(covariant _RelayModalFramePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.quiet != quiet;
}

class _FocuslineModalCalibrationPainter extends CustomPainter {
  const _FocuslineModalCalibrationPainter({required this.rule, required this.accent});

  final Color rule;
  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint ticks = Paint()
      ..color = rule
      ..strokeWidth = 0.5;
    for (double y = 18; y < size.height; y += 28) {
      canvas.drawLine(Offset(0, y), Offset(6, y), ticks);
      canvas.drawLine(Offset(size.width - 6, y), Offset(size.width, y), ticks);
    }

    final Paint guide = Paint()
      ..color = accent
      ..strokeWidth = 0.6;
    final double center = size.width / 2;
    canvas.drawLine(Offset(center - 18, 14), Offset(center + 18, 14), guide);
    canvas.drawCircle(Offset(center, 14), 1.2, Paint()..color = accent);
  }

  @override
  bool shouldRepaint(covariant _FocuslineModalCalibrationPainter oldDelegate) {
    return oldDelegate.rule != rule || oldDelegate.accent != accent;
  }
}

class _FocuslineModalFramePainter extends CustomPainter {
  const _FocuslineModalFramePainter({required this.accent, required this.quiet});

  final Color accent;
  final Color quiet;

  @override
  void paint(Canvas canvas, Size size) {
    const double inset = 4;
    const double length = 11;
    final double right = size.width - inset;
    final double bottom = size.height - inset;

    final Paint bracket = Paint()
      ..color = accent
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;
    final Path corners = Path()
      ..moveTo(inset, inset + length)
      ..lineTo(inset, inset)
      ..lineTo(inset + length, inset)
      ..moveTo(right - length, inset)
      ..lineTo(right, inset)
      ..lineTo(right, inset + length)
      ..moveTo(right, bottom - length)
      ..lineTo(right, bottom)
      ..lineTo(right - length, bottom)
      ..moveTo(inset + length, bottom)
      ..lineTo(inset, bottom)
      ..lineTo(inset, bottom - length);
    canvas.drawPath(corners, bracket);

    final Paint tick = Paint()
      ..color = quiet
      ..strokeWidth = 0.7;
    final double center = size.width / 2;
    canvas.drawLine(Offset(center, inset - 1), Offset(center, inset + 4), tick);
    canvas.drawLine(Offset(center, bottom - 4), Offset(center, bottom + 1), tick);
  }

  @override
  bool shouldRepaint(covariant _FocuslineModalFramePainter oldDelegate) {
    return oldDelegate.accent != accent || oldDelegate.quiet != quiet;
  }
}

class _HalftonePainter extends CustomPainter {
  const _HalftonePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (color.a == 0) return;
    final Paint paint = Paint()..color = color;
    const double spacing = 5.5;
    const double dotRadius = 0.8;
    int row = 0;
    for (double y = spacing / 2; y < size.height; y += spacing) {
      final double offset = row.isEven ? 0.0 : spacing / 2;
      for (double x = spacing / 2 + offset; x < size.width; x += spacing) {
        canvas.drawCircle(Offset(x, y), dotRadius, paint);
      }
      row++;
    }
  }

  @override
  bool shouldRepaint(covariant _HalftonePainter oldDelegate) => oldDelegate.color != color;
}

/// Focus lines radiating from the popup's center — a manga "impact frame".
class _MangaBurstLinesPainter extends CustomPainter {
  const _MangaBurstLinesPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;
    final Offset c = Offset(size.width / 2, size.height / 2);
    final double len = math.max(size.width, size.height) * 0.7;
    const int lines = 24;
    for (int i = 0; i < lines; i++) {
      final double angle = (i * 2 * math.pi) / lines;
      final Offset end = Offset(c.dx + len * math.cos(angle), c.dy + len * math.sin(angle));
      canvas.drawLine(c, end, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _MangaBurstLinesPainter oldDelegate) => oldDelegate.color != color;
}

/// Bold ink corner brackets, like panel-corner marks on a comic page.
class _MangaCornerTicksPainter extends CustomPainter {
  const _MangaCornerTicksPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 2.4
      ..style = PaintingStyle.stroke;
    const double len = 10;
    const double pad = 4;
    // top-left
    canvas.drawLine(const Offset(pad, pad + len), const Offset(pad, pad), paint);
    canvas.drawLine(const Offset(pad, pad), const Offset(pad + len, pad), paint);
    // bottom-right
    canvas.drawLine(
        Offset(size.width - pad, size.height - pad - len), Offset(size.width - pad, size.height - pad), paint);
    canvas.drawLine(
        Offset(size.width - pad - len, size.height - pad), Offset(size.width - pad, size.height - pad), paint);
  }

  @override
  bool shouldRepaint(covariant _MangaCornerTicksPainter oldDelegate) => oldDelegate.color != color;
}

/// Ben-Day dot screen — the halftone shading manga uses instead of gradients.
/// Dot size grows slightly toward the bottom-right to fake a light source.
class _ImpactHalftonePainter extends CustomPainter {
  const _ImpactHalftonePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint dot = Paint()..color = color;
    const double spacing = 9;
    for (double y = 4; y < size.height; y += spacing) {
      for (double x = 4; x < size.width; x += spacing) {
        final double t = (x / size.width + y / size.height) / 2;
        final double r = 0.6 + t * 1.2;
        canvas.drawCircle(Offset(x, y), r, dot);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _ImpactHalftonePainter oldDelegate) => oldDelegate.color != color;
}

/// Speed-line burst from the top-left corner (manga "impact" panel convention),
/// plus a diagonal cut-corner tab top-right and a double inkline along the bottom.
class _ImpactSpeedlinePainter extends CustomPainter {
  const _ImpactSpeedlinePainter({required this.accent, required this.ink});

  final Color accent;
  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    // Radiating speed lines, corner burst.
    final Paint line = Paint()
      ..color = accent.withValues(alpha: 0.5)
      ..strokeWidth = 1.1;
    const Offset origin = Offset(-6, -6);
    const int rays = 9;
    const double spread = 1.3; // radians covered
    for (int i = 0; i < rays; i++) {
      final double angle = (i / (rays - 1)) * spread;
      final double len = 26 + (i.isEven ? 10 : 0);
      final Offset end = origin + Offset(len * _cos(angle), len * _sin(angle));
      canvas.drawLine(origin, end, line);
    }

    // Diagonal cut-corner tab, top-right — filled ink triangle with accent edge.
    final Path cut = Path()
      ..moveTo(size.width - 26, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width, 26)
      ..close();
    canvas.drawPath(cut, Paint()..color = ink);
    canvas.drawLine(
      Offset(size.width - 26, 0),
      Offset(size.width, 26),
      Paint()
        ..color = accent
        ..strokeWidth = 2,
    );

    // Double inkline along the bottom edge — manga panel gutter convention.
    final Paint gutter = Paint()
      ..color = ink.withValues(alpha: 0.85)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, size.height - 4), Offset(size.width, size.height - 4), gutter);
    canvas.drawLine(Offset(0, size.height - 1.5), Offset(size.width, size.height - 1.5), gutter);
  }

  double _cos(double a) => a == 0 ? 1 : (a > 1.5 ? -0.2 : 1 - a * a / 2);
  double _sin(double a) => a - a * a * a / 6;

  @override
  bool shouldRepaint(covariant _ImpactSpeedlinePainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.ink != ink;
}

/// Perspective wireframe grid for the modal background.
class _OutrunGridPainter extends CustomPainter {
  const _OutrunGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double horizon = size.height * 0.4;
    final double bottom = size.height;
    final double cx = size.width / 2;

    // Horizontal lines
    for (int i = 1; i <= 12; i++) {
      final double t = i / 12.0;
      final double y = horizon + (bottom - horizon) * (t * t);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Vertical lines converging to center
    for (int i = -10; i <= 10; i++) {
      if (i == 0) continue;
      final double xBottom = cx + (i * (size.width / 8.0));
      canvas.drawLine(Offset(xBottom, bottom), Offset(cx, horizon), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _OutrunGridPainter oldDelegate) => oldDelegate.color != color;
}

/// Neon corner brackets for the modal overlay.
class _OutrunFramePainter extends CustomPainter {
  const _OutrunFramePainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glowPaint = Paint()
      ..color = accent
      ..strokeWidth = 3.0
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 4);

    final Paint solidPaint = Paint()
      ..color = accent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(const Offset(0, 20), const Offset(0, 0), glowPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(20, 0), glowPaint);
    canvas.drawLine(const Offset(0, 20), const Offset(0, 0), solidPaint);
    canvas.drawLine(const Offset(0, 0), const Offset(20, 0), solidPaint);

    // Bottom-right
    canvas.drawLine(Offset(size.width, size.height - 20), Offset(size.width, size.height), glowPaint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - 20, size.height), glowPaint);
    canvas.drawLine(Offset(size.width, size.height - 20), Offset(size.width, size.height), solidPaint);
    canvas.drawLine(Offset(size.width, size.height), Offset(size.width - 20, size.height), solidPaint);
  }

  @override
  bool shouldRepaint(covariant _OutrunFramePainter oldDelegate) => oldDelegate.accent != accent;
}

/// Tiny floating dust motes — used as a modal underlay.
class _AnimeDustPainter extends CustomPainter {
  const _AnimeDustPainter(this.color);

  final Color color;

  static const List<Offset> _kDust = <Offset>[
    Offset(0.12, 0.10),
    Offset(0.88, 0.14),
    Offset(0.48, 0.08),
    Offset(0.06, 0.40),
    Offset(0.94, 0.44),
    Offset(0.28, 0.30),
    Offset(0.72, 0.34),
    Offset(0.18, 0.60),
    Offset(0.86, 0.64),
    Offset(0.52, 0.54),
    Offset(0.22, 0.80),
    Offset(0.78, 0.78),
    Offset(0.12, 0.92),
    Offset(0.90, 0.90),
    Offset(0.50, 0.96),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    for (final Offset rel in _kDust) {
      final double x = rel.dx * size.width;
      final double y = rel.dy * size.height;
      canvas.drawCircle(Offset(x, y), 1.2, paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimeDustPainter oldDelegate) => oldDelegate.color != color;
}

/// Star-shaped corner brackets — replaces sharp HUD lines with soft
/// 5-point stars in each corner.
class _AnimeStarBracketPainter extends CustomPainter {
  const _AnimeStarBracketPainter({required this.accent, required this.tick});

  final Color accent;
  final Color tick;

  static const double _inset = 5.0;
  static const double _starSize = 6.0;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint starPaint = Paint()..color = accent;
    final Paint tickPaint = Paint()
      ..color = tick
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    final double right = size.width - _inset;
    final double bottom = size.height - _inset;

    // Corner stars
    _drawStar(canvas, _inset, _inset, _starSize, starPaint);
    _drawStar(canvas, right, _inset, _starSize, starPaint);
    _drawStar(canvas, right, bottom, _starSize, starPaint);
    _drawStar(canvas, _inset, bottom, _starSize, starPaint);

    // Mid-edge ticks (small cross ticks, not full lines)
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    canvas.drawLine(Offset(cx, _inset - 2), Offset(cx, _inset + 3), tickPaint);
    canvas.drawLine(Offset(cx, bottom - 3), Offset(cx, bottom + 2), tickPaint);
    canvas.drawLine(Offset(_inset - 2, cy), Offset(_inset + 3, cy), tickPaint);
    canvas.drawLine(Offset(right - 3, cy), Offset(right + 2, cy), tickPaint);
  }

  void _drawStar(Canvas canvas, double cx, double cy, double r, Paint paint) {
    final double outer = r;
    final double inner = r * 0.45;
    final Path path = Path();
    for (int i = 0; i < 5; i++) {
      final double a1 = (i * 4 * math.pi / 5) - math.pi / 2;
      final double a2 = ((i * 4 + 2) * math.pi / 5) - math.pi / 2;
      if (i == 0) {
        path.moveTo(cx + math.cos(a1) * outer, cy + math.sin(a1) * outer);
      } else {
        path.lineTo(cx + math.cos(a1) * outer, cy + math.sin(a1) * outer);
      }
      path.lineTo(cx + math.cos(a2) * inner, cy + math.sin(a2) * inner);
    }
    path.close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _AnimeStarBracketPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.tick != tick;
}

/// Hard 3D bevel frame drawn around the modal edge.
class _WinampFramePainter extends CustomPainter {
  const _WinampFramePainter({required this.hi, required this.lo});

  final Color hi;
  final Color lo;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint hiPaint = Paint()
      ..color = hi
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Paint loPaint = Paint()
      ..color = lo
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    // Top & left (highlight)
    canvas.drawLine(Offset.zero, Offset(size.width, 0), hiPaint);
    canvas.drawLine(Offset.zero, Offset(0, size.height), hiPaint);

    // Bottom & right (shadow)
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      loPaint,
    );
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      loPaint,
    );
  }

  @override
  bool shouldRepaint(covariant _WinampFramePainter oldDelegate) => oldDelegate.hi != hi || oldDelegate.lo != lo;
}

/// Sharp neon corner brackets with a built-in glow effect (drawn thick+thin).
class _OutrunNeonBracketPainter extends CustomPainter {
  const _OutrunNeonBracketPainter({
    required this.accent,
    required this.secondary,
  });

  final Color accent;
  final Color secondary;

  static const double _inset = 6.0;
  static const double _len = 14.0;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glow = Paint()
      ..color = accent.withValues(alpha: 0.35)
      ..strokeWidth = 4.0
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final Paint core = Paint()
      ..color = accent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.square;

    final Paint tick = Paint()
      ..color = secondary
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    final double r = size.width - _inset;
    final double b = size.height - _inset;

    void drawBracket(double x1, double y1, double x2, double y2, double x3, double y3) {
      final Path path = Path()
        ..moveTo(x1, y1)
        ..lineTo(x2, y2)
        ..lineTo(x3, y3);
      canvas.drawPath(path, glow);
      canvas.drawPath(path, core);
    }

    // Four corners
    drawBracket(_inset, _inset + _len, _inset, _inset, _inset + _len, _inset);
    drawBracket(r - _len, _inset, r, _inset, r, _inset + _len);
    drawBracket(r, b - _len, r, b, r - _len, b);
    drawBracket(_inset + _len, b, _inset, b, _inset, b - _len);

    // Mid-edge alignment ticks
    final double cx = size.width / 2;
    final double cy = size.height / 2;
    canvas.drawLine(Offset(cx, _inset - 2), Offset(cx, _inset + 4), tick);
    canvas.drawLine(Offset(cx, b - 4), Offset(cx, b + 2), tick);
    canvas.drawLine(Offset(_inset - 2, cy), Offset(_inset + 4, cy), tick);
    canvas.drawLine(Offset(r - 4, cy), Offset(r + 2, cy), tick);
  }

  @override
  bool shouldRepaint(covariant _OutrunNeonBracketPainter oldDelegate) =>
      oldDelegate.accent != accent || oldDelegate.secondary != secondary;
}

/// A scatter of tiny fixed sparkles across the modal — same low-key dust
/// texture language as the QuickMenu panel's sparkle field, but static
/// (no timer) since the modal frame paints once per build.
class _SparkleDustPainter extends CustomPainter {
  const _SparkleDustPainter(this.color);
  final Color color;

  // Fixed, seeded-looking positions — deterministic so repaints don't jitter.
  static const List<Offset> _spots = <Offset>[
    Offset(0.08, 0.12),
    Offset(0.22, 0.30),
    Offset(0.40, 0.08),
    Offset(0.62, 0.22),
    Offset(0.80, 0.14),
    Offset(0.90, 0.34),
    Offset(0.15, 0.55),
    Offset(0.35, 0.68),
    Offset(0.58, 0.60),
    Offset(0.75, 0.72),
    Offset(0.90, 0.85),
    Offset(0.10, 0.88),
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final Paint p = Paint()..color = color;
    for (int i = 0; i < _spots.length; i++) {
      final double cx = _spots[i].dx * size.width;
      final double cy = _spots[i].dy * size.height;
      final double r = i.isEven ? 2.2 : 1.4;
      final Path diamond = Path()
        ..moveTo(cx, cy - r)
        ..lineTo(cx + r * 0.45, cy)
        ..lineTo(cx, cy + r)
        ..lineTo(cx - r * 0.45, cy)
        ..close();
      canvas.drawPath(diamond, p);
    }
  }

  @override
  bool shouldRepaint(covariant _SparkleDustPainter oldDelegate) => oldDelegate.color != color;
}

/// Fine digital grid pattern running under the whole modal panel.
class _AnimeGridPainter extends CustomPainter {
  const _AnimeGridPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;

    // Vertical lines
    for (double x = 0; x < size.width; x += 14) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    // Horizontal lines
    for (double y = 0; y < size.height; y += 14) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _AnimeGridPainter oldDelegate) => oldDelegate.color != color;
}

/// Glitchy reticle marks and status nodes overlaid on the modal edges.
class _AnimeFrameOverlayPainter extends CustomPainter {
  const _AnimeFrameOverlayPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glowPaint = Paint()
      ..color = accent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    final Paint solidPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;

    // Top-right reticle mark
    canvas.drawLine(
      Offset(size.width - 24, 6),
      Offset(size.width - 6, 6),
      glowPaint,
    );
    canvas.drawLine(
      Offset(size.width - 6, 6),
      Offset(size.width - 6, 24),
      glowPaint,
    );
    canvas.drawCircle(Offset(size.width - 6, 6), 2.5, solidPaint);

    // Bottom-left reticle mark
    canvas.drawLine(
      Offset(24, size.height - 6),
      Offset(6, size.height - 6),
      glowPaint,
    );
    canvas.drawLine(
      Offset(6, size.height - 6),
      Offset(6, size.height - 24),
      glowPaint,
    );
    canvas.drawCircle(Offset(6, size.height - 6), 2.5, solidPaint);
  }

  @override
  bool shouldRepaint(covariant _AnimeFrameOverlayPainter oldDelegate) => oldDelegate.accent != accent;
}

/// Fine dot-matrix blueprint pattern for the modal background.
class _TechBlueprintPainter extends CustomPainter {
  const _TechBlueprintPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color;
    const double step = 18.0;
    const double radius = 1.5;

    for (double x = step; x < size.width; x += step) {
      for (double y = step; y < size.height; y += step) {
        canvas.drawCircle(Offset(x, y), radius, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TechBlueprintPainter oldDelegate) => oldDelegate.color != color;
}

/// Soft glowing edge accents for the modal overlay.
class _TechHUDOverlayPainter extends CustomPainter {
  const _TechHUDOverlayPainter(this.accent);

  final Color accent;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint glowPaint = Paint()
      ..color = accent
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Top right soft bracket
    final Path topRight = Path()
      ..moveTo(size.width - 50, 6)
      ..lineTo(size.width - 6, 6)
      ..lineTo(size.width - 6, 50);
    canvas.drawPath(topRight, glowPaint);

    // Bottom left soft bracket
    final Path bottomLeft = Path()
      ..moveTo(50, size.height - 6)
      ..lineTo(6, size.height - 6)
      ..lineTo(6, size.height - 50);
    canvas.drawPath(bottomLeft, glowPaint);

    // Small accent pip at top right
    final Paint solidPaint = Paint()
      ..color = accent
      ..style = PaintingStyle.fill;
    canvas.drawCircle(Offset(size.width - 6, 6), 3, solidPaint);
  }

  @override
  bool shouldRepaint(covariant _TechHUDOverlayPainter oldDelegate) => oldDelegate.accent != accent;
}

/// A little bow tucked into the top-right corner, top right — two curved
/// ribbon tails and a knot. Same "corner accent" role the ledger design
/// gives its folded page-corner.
class _RibbonCornerPainter extends CustomPainter {
  const _RibbonCornerPainter(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint fill = Paint()..color = color.withValues(alpha: 0.85);
    final double cx = size.width - 14;
    const double cy = 12;

    // Two ribbon-tail triangles fanning out from the knot.
    final Path leftTail = Path()
      ..moveTo(cx, cy)
      ..lineTo(cx - 9, cy - 5)
      ..lineTo(cx - 6, cy + 2)
      ..close();
    final Path rightTail = Path()
      ..moveTo(cx, cy)
      ..lineTo(cx + 9, cy - 5)
      ..lineTo(cx + 6, cy + 2)
      ..close();
    canvas.drawPath(leftTail, fill);
    canvas.drawPath(rightTail, fill);

    // Knot.
    canvas.drawCircle(Offset(cx, cy), 2.6, fill);
  }

  @override
  bool shouldRepaint(covariant _RibbonCornerPainter oldDelegate) => oldDelegate.color != color;
}

//---
class _FoundryGrainPainter extends CustomPainter {
  const _FoundryGrainPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double y = 13; y < size.height; y += 13) {
      canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _FoundryGrainPainter oldDelegate) => oldDelegate.color != color;
}

class _FoundryCornerMarkPainter extends CustomPainter {
  const _FoundryCornerMarkPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const double inset = 5;
    const double length = 8;
    canvas.drawLine(const Offset(inset, inset), const Offset(inset + length, inset), paint);
    canvas.drawLine(const Offset(inset, inset), const Offset(inset, inset + length), paint);
    canvas.drawLine(Offset(size.width - inset - length, inset), Offset(size.width - inset, inset), paint);
    canvas.drawLine(Offset(size.width - inset, inset), Offset(size.width - inset, inset + length), paint);
  }

  @override
  bool shouldRepaint(covariant _FoundryCornerMarkPainter oldDelegate) => oldDelegate.color != color;
}

/// Thick cartoon frame with hard offset shadow (no blur — pure cutout).
class _FamilyGuyFramePainter extends CustomPainter {
  const _FamilyGuyFramePainter({required this.outline, required this.shadow});

  final Color outline;
  final Color shadow;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint outlinePaint = Paint()
      ..color = outline
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final Paint shadowPaint = Paint()
      ..color = shadow
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    final Rect rect = Rect.fromLTWH(1.5, 1.5, size.width - 3, size.height - 3);

    // Hard drop shadow (offset, no blur)
    canvas.drawRect(rect.translate(4, 4), shadowPaint);

    // Main outline
    canvas.drawRect(rect, outlinePaint);

    // Inner "cartoon" highlight line (white, inset 1px)
    canvas.drawRect(
      rect.deflate(2),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.15)
        ..strokeWidth = 1
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _FamilyGuyFramePainter oldDelegate) =>
      oldDelegate.outline != outline || oldDelegate.shadow != shadow;
}
