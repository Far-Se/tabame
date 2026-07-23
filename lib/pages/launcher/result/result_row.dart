import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';
import '../launcher_design.dart';
import 'inline_markup.dart';

/// Title/subtitle text that optionally renders the markdown-lite subset
/// (`**bold**`, `` `code` ``) plugins may embed. Plain strings take the cheap
/// [Text] path.
Widget _rowText(String value, TextStyle style, {required Color accent, required bool markup, int maxLines = 1}) {
  if (!markup || !hasInlineMarkup(value)) {
    return Text(value, maxLines: maxLines, overflow: TextOverflow.ellipsis, style: style);
  }
  return Text.rich(
    launcherInlineMarkup(value, style, accent),
    maxLines: maxLines,
    overflow: TextOverflow.ellipsis,
  );
}

abstract final class _SereneTokens {
  // Row geometry
  static const double rowHPad = 12;
  static const double rowVPad = 7;
  static const double rowRadius = 10.0;
  static const double rowVMargin = 1.5;

  // Icon well
  static const double iconWellSize = 30;
  static const double iconWellRadius = 7;

  // Typography
  static const double titleSize = 13;
  static const double subtitleSize = 11;

  // Badge
  static const double badgeFontSize = 9;
  static const double badgeRadius = 5;

  // Selection fill opacity (0-255)
  static const int selectionFillAlpha = 40;

  // Animation
  static const Duration fastAnim = Duration(milliseconds: 80);
  static const Duration normalAnim = Duration(milliseconds: 180);
  static const Curve animCurve = Curves.easeInOut;
}

// ---------------------------------------------------------------------------
// Serene private building blocks
// ---------------------------------------------------------------------------

class _SereneIconWell extends StatelessWidget {
  const _SereneIconWell({
    required this.child,
    required this.accent,
    this.isSelected = false,
  });

  final Widget child;
  final Color accent;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _SereneTokens.iconWellSize,
      height: _SereneTokens.iconWellSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(isSelected ? 36 : 20),
        borderRadius: BorderRadius.circular(_SereneTokens.iconWellRadius),
      ),
      child: child,
    );
  }
}

class _SereneRowContainer extends StatelessWidget {
  const _SereneRowContainer({
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.child,
  });

  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Duration dur = isRepeating ? _SereneTokens.fastAnim : _SereneTokens.normalAnim;
    return AnimatedContainer(
      duration: dur,
      curve: _SereneTokens.animCurve,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: _SereneTokens.rowVMargin),
      padding: const EdgeInsets.symmetric(
        horizontal: _SereneTokens.rowHPad,
        vertical: _SereneTokens.rowVPad,
      ),
      decoration: BoxDecoration(
        color: isSelected ? accent.withAlpha(_SereneTokens.selectionFillAlpha) : Colors.transparent,
        borderRadius: BorderRadius.circular(_SereneTokens.rowRadius),
      ),
      child: child,
    );
  }
}

// ---------------------------------------------------------------------------
// Public: LauncherResultRow  (Classic + Serene)
// ---------------------------------------------------------------------------

class LauncherResultRow extends StatelessWidget {
  const LauncherResultRow({
    super.key,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
    required this.icon,
    this.content,
    this.title,
    this.subtitle,
    this.badge,
    this.inlineMarkup = false,
    this.subtitleMaxLines = 1,
  });

  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  final Widget icon;
  final String? title;
  final String? subtitle;

  final Widget? content;
  final Widget? badge;

  /// Render `**bold**` / `` `code` `` spans in title/subtitle (plugin rows).
  final bool inlineMarkup;

  /// How many lines the subtitle may wrap to.
  final int subtitleMaxLines;

  Widget _titleText(TextStyle style) => _rowText(title ?? '', style, accent: accent, markup: inlineMarkup);

  Widget _subtitleText(TextStyle style) =>
      _rowText(subtitle ?? '', style, accent: accent, markup: inlineMarkup, maxLines: subtitleMaxLines);

  @override
  Widget build(BuildContext context) {
    return switch (user.launcherDesign) {
      LauncherDesign.serene => _buildSerene(context),
      LauncherDesign.command => _buildCommand(context),
      LauncherDesign.terminal => _buildTerminal(context),
      LauncherDesign.zen => _buildZen(context),
      LauncherDesign.glass => _buildGlass(context),
      LauncherDesign.classic => _buildClassic(context),
      LauncherDesign.blueprint => _buildBlueprint(context),
      LauncherDesign.transit => _buildTransit(context),
      LauncherDesign.fluent => _buildFluent(context),
      LauncherDesign.manifesto => _buildManifesto(context),
      LauncherDesign.orbit => _buildOrbit(context),
    };
  }

  // ── Orbit ────────────────────────────────────────────────────────────────
  // A guidance-computer track line: a dim `+` track marker that becomes an
  // accent lock chevron on the selected row, an instrument icon chip, and a
  // corner-bracket reticle + `[ LOCK ]` readout while the target is locked.

  Widget _buildOrbit(BuildContext context) {
    final int animMs = isRepeating ? 45 : 140;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOut;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: animMs),
            curve: curve,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? accent.withAlpha(18) : Colors.transparent,
              borderRadius: BorderRadius.circular(4),
            ),
            child: CustomPaint(
              foregroundPainter: isSelected ? _OrbitReticlePainter(color: accent) : null,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                child: Row(
                  children: <Widget>[
                    // Track marker — a dim cross that locks into a chevron.
                    SizedBox(
                      width: 15,
                      child: Text(
                        isSelected ? '▸' : '+',
                        textAlign: TextAlign.center,
                        style: OrbitTokens.tele(
                          fontSize: Design.baseFontSize + (isSelected ? 1 : 0),
                          color: isSelected ? accent : onSurface.withAlpha(70),
                          fontWeight: FontWeight.w700,
                          height: 1.0,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    // Instrument chip.
                    Container(
                      width: 28,
                      height: 28,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: accent.withAlpha(isSelected ? 24 : 10),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: accent.withAlpha(isSelected ? 90 : 36)),
                      ),
                      child: icon,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: content ??
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _titleText(OrbitTokens.disp(
                                fontSize: Design.baseFontSize + 1.5,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? onSurface : onSurface.withAlpha(220),
                                letterSpacing: 0.1,
                                height: 1.2,
                              )),
                              const SizedBox(height: 1),
                              _subtitleText(OrbitTokens.tele(
                                fontSize: Design.baseFontSize + 0.5,
                                color: isSelected ? onSurface.withAlpha(180) : OrbitTokens.dim(isDark),
                                // letterSpacing: 0.1,
                                height: 1.2,
                              )),
                            ],
                          ),
                    ),
                    if (badge != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: badge,
                      ),
                    // Lock readout — only on the locked row.
                    AnimatedSize(
                      duration: Duration(milliseconds: animMs),
                      curve: curve,
                      child: isSelected
                          ? Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: Text(
                                '[ LOCK ]',
                                style: OrbitTokens.tele(
                                  fontSize: Design.baseFontSize - 2,
                                  color: accent.withAlpha(220),
                                  fontWeight: FontWeight.w700,
                                  letterSpacing: 1.0,
                                  height: 1.0,
                                ),
                              ),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Manifesto ─────────────────────────────────────────────────────────────
  // Rows are index entries on a printed command sheet. Selection becomes a
  // complete outlined object with a square registration marker—never a pill.
  Widget _buildManifesto(BuildContext context) {
    final int animMs = isRepeating ? 45 : 130;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutQuart;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: animMs),
            curve: curve,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
            decoration: BoxDecoration(
              color: isSelected ? accent.withAlpha(30) : Colors.transparent,
              border: Border.all(
                color: isSelected ? onSurface : onSurface.withAlpha(28),
                width: isSelected ? 1.5 : 0.8,
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: isSelected ? onSurface : Colors.transparent,
                    border: Border.all(color: onSurface.withAlpha(isSelected ? 255 : 90)),
                  ),
                  child: isSelected
                      ? ColorFiltered(colorFilter: ColorFilter.mode(accent, BlendMode.srcIn), child: icon)
                      : icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: content ??
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(ManifestoTokens.body(
                            fontSize: Design.baseFontSize + 1.5,
                            fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                            color: onSurface,
                            height: 1.2,
                            letterSpacing: 0.1,
                          )),
                          _subtitleText(ManifestoTokens.body(
                            fontSize: Design.baseFontSize - 0.5,
                            fontWeight: FontWeight.w400,
                            color: ManifestoTokens.dim(Theme.of(context).brightness == Brightness.dark),
                            height: 1.2,
                          )),
                        ],
                      ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: badge,
                  ),
                AnimatedContainer(
                  duration: Duration(milliseconds: animMs),
                  curve: curve,
                  width: isSelected ? 10 : 4,
                  height: isSelected ? 10 : 4,
                  margin: const EdgeInsets.only(left: 8),
                  color: isSelected ? accent : onSurface.withAlpha(55),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Fluent (Windows 11) ────────────────────────────────────────────────────
  // A WinUI list item: a rounded neutral fill on the selected row plus the
  // signature accent "pill" indicator at the left edge. Icons sit plain (no
  // well), lettering is Segoe at regular weight — Windows never bolds a list.

  Widget _buildFluent(BuildContext context) {
    final int animMs = isRepeating ? 50 : 150;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutCubic;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: animMs),
            curve: curve,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
            decoration: BoxDecoration(
              color: isSelected ? onSurface.withAlpha(isDark ? 18 : 14) : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
            ),
            child: Stack(
              alignment: Alignment.centerLeft,
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  child: Row(
                    children: <Widget>[
                      SizedBox(width: 24, height: 24, child: Center(child: icon)),
                      const SizedBox(width: 12),
                      Expanded(
                        child: content ??
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                _titleText(FluentTokens.segoe(
                                  fontSize: Design.baseFontSize + 2,
                                  fontWeight: FontWeight.w400,
                                  color: isSelected ? onSurface : onSurface.withAlpha(225),
                                  height: 1.25,
                                )),
                                _subtitleText(FluentTokens.segoe(
                                  fontSize: Design.baseFontSize,
                                  fontWeight: FontWeight.w400,
                                  color: FluentTokens.dim(isDark).withAlpha(isSelected ? 255 : 210),
                                  height: 1.2,
                                )),
                              ],
                            ),
                      ),
                      if (badge != null)
                        Padding(
                          padding: const EdgeInsets.only(left: 6),
                          child: badge,
                        ),
                    ],
                  ),
                ),
                // Accent selection pill — the WinUI list indicator.
                AnimatedContainer(
                  duration: Duration(milliseconds: animMs),
                  curve: curve,
                  width: 3,
                  height: isSelected ? 16 : 0,
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Transit ────────────────────────────────────────────────────────────────
  // A metro-map stop: every row is a station on a continuous route line drawn
  // in the accent (rows keep zero vertical margin so the segments connect).
  // The selected row is the interchange — a bigger roundel, a sign-plate fill,
  // and a "you are here" pointer.

  Widget _buildTransit(BuildContext context) {
    final int animMs = isRepeating ? 50 : 170;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutCubic;
    final Color surface = Theme.of(context).colorScheme.surface;

    // Route-line geometry: plate margin (6) + plate padding (8) + half of the
    // 26px marker slot centers the line under the station roundel.
    const double lineLeft = 6 + 8 + 13 - 1.5;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: Stack(
            children: <Widget>[
              // The route line — runs edge-to-edge so neighbouring rows join
              // into one continuous metro line.
              Positioned(
                left: lineLeft,
                top: 0,
                bottom: 0,
                child: Container(width: 3, color: accent),
              ),
              AnimatedContainer(
                duration: Duration(milliseconds: animMs),
                curve: curve,
                margin: const EdgeInsets.symmetric(horizontal: 6),
                padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
                decoration: BoxDecoration(
                  color: isSelected ? accent.withAlpha(26) : Colors.transparent,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: <Widget>[
                    // Station marker — a stop dot that grows into an
                    // interchange roundel on selection.
                    SizedBox(
                      width: 26,
                      child: Center(
                        child: AnimatedContainer(
                          duration: Duration(milliseconds: animMs),
                          curve: curve,
                          width: isSelected ? 16 : 10,
                          height: isSelected ? 16 : 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: surface,
                            border: Border.all(color: accent, width: isSelected ? 3.4 : 2.4),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    SizedBox(width: 22, height: 22, child: Center(child: icon)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: content ??
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _titleText(TransitTokens.sign(
                                fontSize: Design.baseFontSize + 1.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                                color: isSelected ? onSurface : onSurface.withAlpha(225),
                                letterSpacing: 0.2,
                                height: 1.25,
                              )),
                              _subtitleText(TransitTokens.sign(
                                fontSize: Design.baseFontSize - 0.5,
                                fontWeight: FontWeight.w400,
                                color: onSurface.withAlpha(isSelected ? 165 : 125),
                                letterSpacing: 0.3,
                                height: 1.15,
                              )),
                            ],
                          ),
                    ),
                    if (badge != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: badge,
                      ),
                    // "You are here" pointer — only at the current stop.
                    AnimatedSize(
                      duration: Duration(milliseconds: animMs),
                      curve: curve,
                      child: isSelected
                          ? Padding(
                              padding: const EdgeInsets.only(left: 6),
                              child: Icon(Icons.play_arrow_rounded, size: 15, color: accent),
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Blueprint ──────────────────────────────────────────────────────────────
  // A drafting-sheet entry: the icon sits in a part-reference balloon (circled
  // callout), lettering is squared technical stencil, and the selected row is
  // outlined with a dashed "measured" callout plus solid corner ticks.

  Widget _buildBlueprint(BuildContext context) {
    final int animMs = isRepeating ? 50 : 160;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOut;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: animMs),
            curve: curve,
            margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? accent.withAlpha(18) : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
            ),
            child: CustomPaint(
              foregroundPainter: isSelected ? _BlueprintCalloutPainter(color: accent) : null,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  children: <Widget>[
                    // Part-reference balloon.
                    Container(
                      width: 30,
                      height: 30,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? accent.withAlpha(200) : onSurface.withAlpha(70),
                          width: 1.2,
                        ),
                      ),
                      child: icon,
                    ),
                    const SizedBox(width: 11),
                    Expanded(
                      child: content ??
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _titleText(BlueprintTokens.tech(
                                fontSize: Design.baseFontSize + 1.5,
                                fontWeight: FontWeight.w600,
                                color: isSelected ? onSurface : onSurface.withAlpha(220),
                                letterSpacing: 0.4,
                                height: 1.2,
                              )),
                              _subtitleText(BlueprintTokens.tech(
                                fontSize: Design.baseFontSize - 0.5,
                                fontWeight: FontWeight.w400,
                                color: onSurface.withAlpha(isSelected ? 255 : 190),
                                letterSpacing: 0.3,
                                height: 1.2,
                              )),
                            ],
                          ),
                    ),
                    if (badge != null)
                      Padding(
                        padding: const EdgeInsets.only(left: 6),
                        child: badge,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Glass (iOS Liquid Glass) ───────────────────────────────────────────────
  // The selected row becomes a floating glass lozenge — a translucent capsule
  // with a bright rim, accent tint, and a soft glow. Icons sit in frosted nests.

  Widget _buildGlass(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final int animMs = isRepeating ? 80 : 220;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutCubic;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: animMs),
            curve: curve,
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: isSelected
                ? BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: <Color>[
                        Color.alphaBlend(Colors.white.withAlpha(isDark ? 26 : 130), accent.withAlpha(isDark ? 44 : 26)),
                        accent.withAlpha(isDark ? 34 : 18),
                      ],
                    ),
                    border: Border.all(color: Colors.white.withAlpha(isDark ? 46 : 150), width: 1),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: accent.withAlpha(isDark ? 34 : 26),
                        blurRadius: 12,
                        spreadRadius: -2,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  )
                : null,
            child: Row(
              children: <Widget>[
                // Frosted icon nest.
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.white.withAlpha(isDark ? (isSelected ? 24 : 14) : (isSelected ? 150 : 100)),
                    border: Border.all(color: Colors.white.withAlpha(isDark ? 34 : 130), width: 0.8),
                  ),
                  child: icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: content ??
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(GlassTokens.font(
                            fontSize: Design.baseFontSize + 2,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? onSurface : onSurface.withAlpha(225),
                            height: 1.25,
                            letterSpacing: -0.1,
                          )),
                          const SizedBox(height: 1),
                          _subtitleText(GlassTokens.font(
                            fontSize: Design.baseFontSize,
                            fontWeight: FontWeight.w400,
                            color: onSurface.withAlpha(isSelected ? 165 : 120),
                            height: 1.2,
                          )),
                        ],
                      ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: badge,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Zen ──────────────────────────────────────────────────────────────────
  // Airy, low-contrast rows with generous breathing room. Selection is a soft
  // rounded "leaf pill" with a rounded stem — no hard edges, slow gentle motion.

  Widget _buildZen(BuildContext context) {
    // Deliberately unhurried — calm motion, never snappy (even on key-repeat).
    final Duration dur = Duration(milliseconds: isRepeating ? 120 : 300);
    const Curve curve = Curves.easeInOutSine;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: dur,
            curve: curve,
            margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
            decoration: BoxDecoration(
              color: isSelected ? accent.withAlpha(30) : Colors.transparent,
              borderRadius: BorderRadius.circular(18),
            ),
            child: Row(
              children: <Widget>[
                // Soft rounded "stem" that grows on selection.
                AnimatedContainer(
                  duration: dur,
                  curve: curve,
                  width: isSelected ? 3 : 0,
                  height: 20,
                  margin: EdgeInsets.only(right: isSelected ? 10 : 0),
                  decoration: BoxDecoration(
                    color: accent.withAlpha(180),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                // Soft squircle icon nest.
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: accent.withAlpha(isSelected ? 34 : 20),
                    borderRadius: BorderRadius.circular(13),
                  ),
                  child: icon,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: content ??
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(ZenTokens.soft(
                            fontSize: Design.baseFontSize + 2,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? onSurface : onSurface.withAlpha(225),
                            height: 1.25,
                            letterSpacing: 0.1,
                          )),
                          const SizedBox(height: 1),
                          _subtitleText(ZenTokens.soft(
                            fontSize: Design.baseFontSize,
                            fontWeight: FontWeight.w400,
                            color: onSurface.withAlpha(isSelected ? 150 : 115),
                            height: 1.2,
                          )),
                        ],
                      ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: badge,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Terminal ─────────────────────────────────────────────────────────────
  // A monospace console line: a `❯` caret + block-fill highlight on the active
  // row, phosphor-bright title, dimmed path. Colors are forced to the console
  // palette so it reads as a command prompt regardless of the active theme.

  Widget _buildTerminal(BuildContext context) {
    final int animMs = isRepeating ? 40 : 120;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOut;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: animMs),
            curve: curve,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            padding: const EdgeInsets.fromLTRB(6, 4, 8, 4),
            decoration: BoxDecoration(
              color: isSelected ? accent.withAlpha(36) : Colors.transparent,
              borderRadius: BorderRadius.circular(3),
              border: Border(
                left: BorderSide(
                  color: isSelected ? accent : Colors.transparent,
                  width: 2.5,
                ),
              ),
            ),
            child: Row(
              children: <Widget>[
                // Selection caret — the TUI line cursor.
                SizedBox(
                  width: 14,
                  child: Text(
                    isSelected ? '❯' : ' ',
                    style: TerminalTokens.mono(
                      fontSize: Design.baseFontSize + 1,
                      color: accent.withAlpha(230),
                      fontWeight: FontWeight.w700,
                      height: 1.0,
                    ),
                  ),
                ),
                SizedBox(width: 18, height: 18, child: Center(child: icon)),
                const SizedBox(width: 9),
                Expanded(
                  child: content ??
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(TerminalTokens.mono(
                            fontSize: Design.baseFontSize + 1,
                            fontWeight: FontWeight.w600,
                            color: isSelected ? accent : TerminalTokens.fg(isDark),
                            height: 1.25,
                          )),
                          _subtitleText(TerminalTokens.mono(
                            fontSize: Design.baseFontSize - 1,
                            color: isSelected ? TerminalTokens.fg(isDark).withAlpha(190) : TerminalTokens.dim(isDark),
                            height: 1.2,
                          )),
                        ],
                      ),
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: badge,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Command ──────────────────────────────────────────────────────────────
  // A dense console row: a bright left rail + faint accent fill on selection,
  // a bordered square icon chip, and a trailing ↵ key on the active row.

  Widget _buildCommand(BuildContext context) {
    final int animMs = isRepeating ? 50 : 160;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutCubic;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: animMs),
            curve: curve,
            margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              gradient: isSelected
                  ? LinearGradient(
                      colors: <Color>[accent.withAlpha(48), accent.withAlpha(14)],
                    )
                  : null,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 5, 8, 5),
              child: Row(
                children: <Widget>[
                  // Bright selection rail.
                  AnimatedContainer(
                    duration: Duration(milliseconds: animMs),
                    curve: curve,
                    width: isSelected ? 3 : 0,
                    height: 26,
                    margin: EdgeInsets.only(right: isSelected ? 7 : 0),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  // Bordered square icon chip.
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(isSelected ? 26 : 14),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: accent.withAlpha(isSelected ? 70 : 36)),
                    ),
                    child: icon,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: content ??
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _titleText(entryStyle(
                              isSelected,
                              fontSize: Design.baseFontSize + 1.5,
                              letterSpacing: 0.2,
                            )),
                            const SizedBox(height: 1),
                            _subtitleText(TextStyle(
                              fontSize: Design.baseFontSize - 0.5,
                              letterSpacing: 0.1,
                              color: isSelected ? onSurface.withAlpha(160) : onSurface.withAlpha(110),
                            )),
                          ],
                        ),
                  ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: badge,
                    ),
                  // Trailing enter key — only on the active row.
                  AnimatedSize(
                    duration: Duration(milliseconds: animMs),
                    curve: curve,
                    child: isSelected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              decoration: BoxDecoration(
                                color: accent.withAlpha(30),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: accent.withAlpha(80)),
                              ),
                              child: Text(
                                '↵',
                                style: TextStyle(
                                  fontSize: Design.baseFontSize + 1,
                                  height: 1.0,
                                  fontWeight: FontWeight.w700,
                                  color: accent.withAlpha(220),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Classic ────────────────────────────────────────────────────────────────

  Widget _buildClassic(BuildContext context) {
    final int animMs = isRepeating ? 50 : 200;
    final Curve animCurve = isRepeating ? Curves.linear : Curves.easeOutCubic;

    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: Duration(milliseconds: animMs),
            curve: animCurve,
            margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            decoration: BoxDecoration(
              color: isSelected ? accent.withAlpha(55) : Colors.transparent,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: Row(
                children: <Widget>[
                  AnimatedContainer(
                    duration: Duration(milliseconds: animMs),
                    curve: animCurve,
                    width: isSelected ? 2.5 : 0,
                    height: 22,
                    margin: EdgeInsets.only(right: isSelected ? 7 : 0),
                    decoration: BoxDecoration(
                      color: accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  icon,
                  const SizedBox(width: 8),
                  Expanded(
                    child: content == null
                        ? Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _titleText(entryStyle(isSelected, fontSize: Design.baseFontSize + 2)),
                              const SizedBox(height: 2),
                              _subtitleText(TextStyle(
                                fontSize: Design.baseFontSize,
                                color: isSelected ? onSurface.withAlpha(170) : onSurface.withAlpha(130),
                              )),
                            ],
                          )
                        : content!,
                  ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 4),
                      child: badge,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Serene ─────────────────────────────────────────────────────────────────

  Widget _buildSerene(BuildContext context) {
    return RepaintBoundary(
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onHover: (PointerHoverEvent event) {
          if (event.delta != Offset.zero) onHover();
        },
        child: GestureDetector(
          onTap: onTap,
          child: _SereneRowContainer(
            isSelected: isSelected,
            isRepeating: isRepeating,
            accent: accent,
            child: Row(
              children: <Widget>[
                _SereneIconWell(
                  accent: accent,
                  isSelected: isSelected,
                  child: icon,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: content == null
                      ? Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _titleText(TextStyle(
                              fontSize: _SereneTokens.titleSize,
                              fontWeight: FontWeight.w500,
                              color: isSelected ? onSurface : onSurface.withAlpha(210),
                              letterSpacing: -0.1,
                              height: 1.2,
                            )),
                            const SizedBox(height: 1),
                            _subtitleText(TextStyle(
                              fontSize: _SereneTokens.subtitleSize,
                              color: isSelected ? onSurface.withAlpha(160) : onSurface.withAlpha(110),
                              height: 1.2,
                            )),
                          ],
                        )
                      : content!,
                ),
                if (badge != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: badge,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Public: LauncherKindBadge  (Classic style)
// ---------------------------------------------------------------------------

class LauncherKindBadge extends StatelessWidget {
  const LauncherKindBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
      decoration: BoxDecoration(
        color: color.withAlpha(60),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withAlpha(40)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 9, color: accent.withAlpha(180)),
          const SizedBox(width: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 8,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
              color: accent.withAlpha(200),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Public: LauncherSereneBadge  (Serene style — no border, pure fill)
// ---------------------------------------------------------------------------

/// Dashed rectangle + solid corner ticks — the "measured callout" that marks
/// the selected Blueprint row.
class _BlueprintCalloutPainter extends CustomPainter {
  const _BlueprintCalloutPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = (Offset.zero & size).deflate(0.5);

    // Dashed outline.
    final Paint dashPaint = Paint()
      ..color = color.withAlpha(150)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const double dash = 5;
    const double gap = 4;
    final Path outline = Path()..addRect(rect);
    for (final ui.PathMetric metric in outline.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), dashPaint);
        d += dash + gap;
      }
    }

    // Solid L-shaped ticks at the corners.
    final Paint tick = Paint()
      ..color = color.withAlpha(230)
      ..strokeWidth = 1.5;
    const double arm = 6;
    // Top-left.
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(arm, 0), tick);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, arm), tick);
    // Top-right.
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-arm, 0), tick);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, arm), tick);
    // Bottom-left.
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(arm, 0), tick);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -arm), tick);
    // Bottom-right.
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-arm, 0), tick);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -arm), tick);
  }

  @override
  bool shouldRepaint(covariant _BlueprintCalloutPainter oldDelegate) => oldDelegate.color != color;
}

/// Corner-bracket target-lock reticle drawn around the selected Orbit row —
/// four L-shaped brackets, no outline: the row is "locked", not boxed in.
class _OrbitReticlePainter extends CustomPainter {
  const _OrbitReticlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = (Offset.zero & size).deflate(1);
    final Paint bracket = Paint()
      ..color = color.withAlpha(230)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square;
    const double arm = 8;
    // Top-left.
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(arm, 0), bracket);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, arm), bracket);
    // Top-right.
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-arm, 0), bracket);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, arm), bracket);
    // Bottom-left.
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(arm, 0), bracket);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -arm), bracket);
    // Bottom-right.
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-arm, 0), bracket);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -arm), bracket);
  }

  @override
  bool shouldRepaint(covariant _OrbitReticlePainter oldDelegate) => oldDelegate.color != color;
}

class LauncherSereneBadge extends StatelessWidget {
  const LauncherSereneBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(_SereneTokens.badgeRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 9, color: color.withAlpha(180)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: _SereneTokens.badgeFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: color.withAlpha(190),
            ),
          ),
        ],
      ),
    );
  }
}
