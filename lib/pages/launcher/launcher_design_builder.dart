import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../quickmenu_designs/design_backdrop_stable.dart';
import 'launcher_design.dart';

// ---------------------------------------------------------------------------
// Extension: per-design widget factories used by LauncherState
// ---------------------------------------------------------------------------

extension LauncherDesignBuilder on LauncherDesign {
  /// Returns the outer window decoration for the given design.
  BoxDecoration outerDecoration({
    required Color surface,
    required Color accent,
  }) {
    switch (this) {
      case LauncherDesign.classic:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(18),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: <Color>[
              surface.withAlpha(245),
              Color.alphaBlend(accent.withAlpha(24), surface),
              Color.alphaBlend(accent.withAlpha(10), surface),
            ],
          ),
          border: Border.all(color: accent.withAlpha(28)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(18),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        );

      case LauncherDesign.serene:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: surface.withAlpha(230),
          border: Border.all(color: Colors.white.withAlpha(18)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(60),
              blurRadius: 40,
              spreadRadius: -4,
              offset: const Offset(0, 16),
            ),
            BoxShadow(
              color: Colors.black.withAlpha(14),
              blurRadius: 6,
              offset: const Offset(0, 2),
            ),
          ],
        );

      case LauncherDesign.command:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: surface.withAlpha(244),
          border: Border.all(color: accent.withAlpha(56)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(70),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
          ],
        );

      case LauncherDesign.terminal:
        // Console screen — [surface] is the forced terminal palette background
        // (light or dark) supplied by the launcher theme.
        return BoxDecoration(
          borderRadius: BorderRadius.circular(6),
          color: surface,
          border: Border.all(color: accent.withAlpha(60)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(120),
              blurRadius: 30,
              spreadRadius: -4,
              offset: const Offset(0, 14),
            ),
          ],
        );

      case LauncherDesign.zen:
        // Soft "dawn" wash over the forced sage surface; big, diffuse shadow.
        return BoxDecoration(
          borderRadius: BorderRadius.circular(26),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Color.alphaBlend(Colors.white.withAlpha(22), surface),
              surface,
            ],
          ),
          border: Border.all(color: accent.withAlpha(40)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(28),
              blurRadius: 48,
              spreadRadius: -8,
              offset: const Offset(0, 20),
            ),
          ],
        );

      case LauncherDesign.glass:
        // Just the floating-glass shadow + accent refraction glow; the glassy
        // fill, border and specular highlights live inside [GlassLauncherFrame].
        return BoxDecoration(
          borderRadius: BorderRadius.circular(28),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: accent.withAlpha(100),
              blurRadius: 30,
              spreadRadius: -19,
              offset: const Offset(0, 18),
            ),
            BoxShadow(
              color: Colors.black.withAlpha(70),
              blurRadius: 30,
              spreadRadius: -8,
              offset: const Offset(0, 12),
            ),
          ],
        );

      case LauncherDesign.blueprint:
        // Drafting sheet — [surface] is the forced blueprint palette. Sharp
        // corners, a crisp ink edge, and a flat paper shadow (no glow).
        return BoxDecoration(
          borderRadius: BorderRadius.circular(3),
          color: surface,
          border: Border.all(color: accent.withAlpha(110)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(90),
              blurRadius: 26,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
          ],
        );

      case LauncherDesign.transit:
        // Station sign — [surface] is the forced signage palette. Soft signage
        // rounding, an enamel-plate edge, and a flat drop shadow.
        return BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          color: surface,
          border: Border.all(color: accent.withAlpha(120), width: 1.4),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(90),
              blurRadius: 26,
              spreadRadius: -6,
              offset: const Offset(0, 12),
            ),
          ],
        );

      case LauncherDesign.fluent:
        // Mica window — [surface] is the forced Win11 neutral. The 8px corner,
        // a hairline stroke, and the broad soft shadow Windows 11 puts under
        // every flyout.
        final bool fluentDark = surface.computeLuminance() < 0.5;
        return BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: surface,
          border: Border.all(color: fluentDark ? Colors.white.withAlpha(24) : Colors.black.withAlpha(20)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(80),
              blurRadius: 34,
              spreadRadius: -8,
              offset: const Offset(0, 16),
            ),
          ],
        );
    }
  }

  /// Builds the search bar for this design variant.
  Widget buildSearchBar({
    required Color surface,
    required Color accent,
    required Color onSurface,
    required Widget dragHandle,
    required Widget textField,
    required Widget? trailingBadge,
    required bool isSearching,
  }) {
    switch (this) {
      case LauncherDesign.classic:
        return _ClassicSearchBar(
          surface: surface,
          accent: accent,
          onSurface: onSurface,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.serene:
        return _SereneSearchBar(
          surface: surface,
          accent: accent,
          onSurface: onSurface,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.command:
        return _CommandSearchBar(
          surface: surface,
          accent: accent,
          onSurface: onSurface,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.terminal:
        return _TerminalSearchBar(
          accent: accent,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.zen:
        return _ZenSearchBar(
          accent: accent,
          onSurface: onSurface,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.glass:
        return _GlassSearchBar(
          surface: surface,
          accent: accent,
          onSurface: onSurface,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.blueprint:
        return _BlueprintSearchBar(
          accent: accent,
          onSurface: onSurface,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.transit:
        return _TransitSearchBar(
          accent: accent,
          onSurface: onSurface,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.fluent:
        return _FluentSearchBar(
          accent: accent,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
    }
  }

  /// Returns the section-header label widget.
  Widget buildSectionHeader({required String label, required Color accent}) {
    switch (this) {
      case LauncherDesign.classic:
        return Padding(
          padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: Design.baseFontSize,
              color: accent.withAlpha(180),
              fontWeight: FontWeight.w800,
              letterSpacing: 1.0,
            ),
          ),
        );
      case LauncherDesign.serene:
        return Padding(
          padding: const EdgeInsets.only(left: 18, top: 10, bottom: 2),
          child: Text(
            label,
            style: TextStyle(
              fontSize: Design.baseFontSize + 1,
              color: accent.withAlpha(160),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        );
      case LauncherDesign.command:
        return Padding(
          padding: const EdgeInsets.only(left: 14, top: 12, bottom: 4),
          child: Row(
            children: <Widget>[
              Text(
                '//',
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  color: accent.withAlpha(150),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: Design.baseFontSize,
                  color: accent.withAlpha(170),
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.6,
                ),
              ),
            ],
          ),
        );
      case LauncherDesign.terminal:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 2, 12, 3),
          child: Text(
            ':: ${label.toLowerCase()} ${'─' * 24}',
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: TerminalTokens.mono(
              fontSize: Design.baseFontSize - 0.5,
              color: accent.withAlpha(100),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        );
      case LauncherDesign.zen:
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 20, 4),
          child: Row(
            children: <Widget>[
              Icon(Icons.spa_rounded, size: Design.baseFontSize + 1, color: accent.withAlpha(150)),
              const SizedBox(width: 8),
              Text(
                label.toLowerCase(),
                style: ZenTokens.soft(
                  fontSize: Design.baseFontSize + 1,
                  color: accent.withAlpha(190),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                ),
              ),
            ],
          ),
        );
      case LauncherDesign.glass:
        return Padding(
          padding: const EdgeInsets.fromLTRB(22, 14, 20, 4),
          child: Text(
            label.toUpperCase(),
            style: GlassTokens.font(
              fontSize: Design.baseFontSize - 0.5,
              color: accent.withAlpha(150),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.8,
            ),
          ),
        );
      case LauncherDesign.blueprint:
        // A dimension line: |◄──── LABEL ────►| with solid end ticks.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: <Widget>[
              Container(width: 1, height: 9, color: accent.withAlpha(140)),
              Text('◄', style: TextStyle(fontSize: 7, color: accent.withAlpha(140), height: 1.0)),
              Expanded(child: Container(height: 1, color: accent.withAlpha(70))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Text(
                  label.toUpperCase(),
                  style: BlueprintTokens.tech(
                    fontSize: Design.baseFontSize - 1,
                    color: accent.withAlpha(200),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 2.4,
                  ),
                ),
              ),
              Expanded(child: Container(height: 1, color: accent.withAlpha(70))),
              Text('►', style: TextStyle(fontSize: 7, color: accent.withAlpha(140), height: 1.0)),
              Container(width: 1, height: 9, color: accent.withAlpha(140)),
            ],
          ),
        );
      case LauncherDesign.transit:
        // A fare-zone boundary: a small zone pill, then a dashed border line
        // running to the sign's edge.
        return Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
          child: Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.fromLTRB(8, 2, 8, 1),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(9),
                  border: Border.all(color: accent.withAlpha(150), width: 1.2),
                ),
                child: Text(
                  'ZONE · ${label.toUpperCase()}',
                  style: TransitTokens.sign(
                    fontSize: Design.baseFontSize - 1.5,
                    color: accent.withAlpha(220),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.6,
                    height: 1.1,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: SizedBox(
                  height: 1,
                  child: CustomPaint(painter: _TransitZonePainter(color: accent.withAlpha(110))),
                ),
              ),
            ],
          ),
        );
      case LauncherDesign.fluent:
        // A "Best match" group label: plain semibold Segoe in the foreground
        // color — Windows 11 search never decorates its headers.
        return Builder(builder: (BuildContext context) {
          final Color fg = Theme.of(context).colorScheme.onSurface;
          return Padding(
            padding: const EdgeInsets.only(left: 16, top: 12, bottom: 4),
            child: Text(
              label,
              style: FluentTokens.segoe(
                fontSize: Design.baseFontSize + 1,
                color: fg.withAlpha(210),
                fontWeight: FontWeight.w600,
                letterSpacing: 0.1,
              ),
            ),
          );
        });
    }
  }
}

// ---------------------------------------------------------------------------
// Classic search bar
// ---------------------------------------------------------------------------

class _ClassicSearchBar extends StatelessWidget {
  const _ClassicSearchBar({
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color surface;
  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: surface.withAlpha(100),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withAlpha(32)),
      ),
      child: Row(
        children: <Widget>[
          dragHandle,
          const SizedBox(width: 10),
          Expanded(
            child: Stack(
              alignment: Alignment.centerRight,
              children: <Widget>[
                textField,
                if (trailingBadge != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: trailingBadge!,
                  ),
              ],
            ),
          ),
          if (isSearching)
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: accent.withAlpha(100),
              ),
            ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Serene search bar
// ---------------------------------------------------------------------------

class _SereneSearchBar extends StatelessWidget {
  const _SereneSearchBar({
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color surface;
  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: surface.withAlpha(70),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            child: Row(
              children: <Widget>[
                dragHandle,
                const SizedBox(width: 10),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: <Widget>[
                      textField,
                      if (trailingBadge != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: trailingBadge!,
                        ),
                    ],
                  ),
                ),
                if (isSearching)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: onSurface.withAlpha(80),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Hairline separator — replaces the boxy card border
          Divider(
            height: 1,
            thickness: 1,
            indent: 0,
            endIndent: 0,
            color: onSurface.withAlpha(18),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// SereneLauncherFrame
// ---------------------------------------------------------------------------

/// The frosted-glass outer frame used by the Serene design.
///
/// This widget:
/// 1. Applies backdrop blur + frosted surface.
/// 2. Injects a [LauncherTheme] with [LauncherDesign.serene] so that all
///    descendant result-item widgets automatically inherit the Serene variant
///    without needing an explicit parameter.
class SereneLauncherFrame extends StatelessWidget {
  const SereneLauncherFrame({
    super.key,
    required this.child,
    required this.accent,
  });

  final Widget child;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final bool hasBackdrop = Design.backdropType.isNotEmpty && user.activeBackdropPath.isNotEmpty;

    // Wrap in LauncherTheme so descendants can read the design without a
    // parameter chain.
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.serene),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            constraints: const BoxConstraints(minHeight: 360),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              color: surface.withAlpha(hasBackdrop ? 180 : 240),
              border: Border.all(color: Colors.white.withAlpha(18)),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: Colors.black.withAlpha(60),
                  blurRadius: 40,
                  spreadRadius: -4,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Design.backdropLauncher
                ? Stack(
                    children: <Widget>[
                      const StableBackdrop(),
                      child,
                    ],
                  )
                : child,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// ClassicLauncherFrame
// ---------------------------------------------------------------------------

/// The glass-card outer frame used by the Classic design.
///
/// Mirrors [SereneLauncherFrame]: wraps [child] in a [LauncherTheme] with
/// [LauncherDesign.classic] so descendants inherit the correct variant.
class ClassicLauncherFrame extends StatelessWidget {
  const ClassicLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
  });

  final Widget child;
  final Color surface;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.classic),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.classic.outerDecoration(
          surface: surface,
          accent: accent,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            children: <Widget>[
              if (Design.backdropLauncher) const StableBackdrop(),
              child,
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Command search bar — a terminal input line with a chevron prompt.
// ---------------------------------------------------------------------------

class _CommandSearchBar extends StatelessWidget {
  const _CommandSearchBar({
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color surface;
  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: <Color>[accent.withAlpha(20), accent.withAlpha(8)],
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 13, 14, 11),
            child: Row(
              children: <Widget>[
                // Chevron prompt (also the window drag handle).
                dragHandle,
                const SizedBox(width: 8),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: <Widget>[
                      textField,
                      if (trailingBadge != null)
                        Padding(
                          padding: const EdgeInsets.only(right: 4),
                          child: trailingBadge!,
                        ),
                    ],
                  ),
                ),
                if (isSearching)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: SizedBox(
                      width: 13,
                      height: 13,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: accent.withAlpha(150),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // Bright prompt underline — the blinking-cursor line of the console.
          Container(
            height: 1.5,
            // margin: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(1),
              gradient: LinearGradient(
                colors: <Color>[accent.withAlpha(100), accent.withAlpha(30)],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// CommandLauncherFrame — a crisp console window with a top accent rail and a
// keyboard-hint footer strip.
// ---------------------------------------------------------------------------

class CommandLauncherFrame extends StatelessWidget {
  const CommandLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    this.resultCount = 0,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.command),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.command.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Stack(
            children: <Widget>[
              if (Design.backdropLauncher) const StableBackdrop(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  // Top accent rail.
                  Container(
                    height: 2,
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
                  child,
                  _CommandFooter(accent: accent, onSurface: onSurface, resultCount: resultCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandFooter extends StatelessWidget {
  const _CommandFooter({
    required this.accent,
    required this.onSurface,
    required this.resultCount,
  });

  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Divider(height: 1, thickness: 1, color: onSurface.withAlpha(16)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
          child: Row(
            children: <Widget>[
              _KbdHint(label: '↵', action: 'open', accent: accent, onSurface: onSurface),
              const SizedBox(width: 12),
              _KbdHint(label: '→', action: 'actions', accent: accent, onSurface: onSurface),
              const SizedBox(width: 12),
              _KbdHint(label: 'esc', action: 'close', accent: accent, onSurface: onSurface),
              const Spacer(),
              Text(
                resultCount == 1 ? '1 result' : '$resultCount results',
                style: TextStyle(
                  fontSize: Design.baseFontSize - 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: onSurface.withAlpha(120),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _KbdHint extends StatelessWidget {
  const _KbdHint({
    required this.label,
    required this.action,
    required this.accent,
    required this.onSurface,
  });

  final String label;
  final String action;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(minWidth: 16),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onSurface.withAlpha(12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: onSurface.withAlpha(28)),
          ),
          child: Text(
            label,
            style: TextStyle(
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w700,
              color: onSurface.withAlpha(170),
              height: 1.1,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          action,
          style: TextStyle(
            fontSize: Design.baseFontSize - 1,
            fontWeight: FontWeight.w500,
            color: onSurface.withAlpha(110),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Terminal (CLI) — search bar, frame, chrome, and CRT scanline overlay.
// ---------------------------------------------------------------------------

class _TerminalSearchBar extends StatelessWidget {
  const _TerminalSearchBar({
    required this.accent,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 9),
      child: Row(
        children: <Widget>[
          // Prompt chevron (also the window drag handle).
          dragHandle,
          const SizedBox(width: 6),
          Expanded(
            child: Stack(
              alignment: Alignment.centerRight,
              children: <Widget>[
                textField,
                if (trailingBadge != null)
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: trailingBadge!,
                  ),
              ],
            ),
          ),
          // Blinking-style block cursor that runs while a query resolves.
          if (isSearching)
            Padding(
              padding: const EdgeInsets.only(left: 8),
              child: SizedBox(
                width: 13,
                height: 13,
                child: CircularProgressIndicator(strokeWidth: 1.5, color: accent.withAlpha(170)),
              ),
            )
          else
            _TerminalBlinkCursor(color: accent),
        ],
      ),
    );
  }
}

/// A small blinking block — the idle terminal cursor.
class _TerminalBlinkCursor extends StatefulWidget {
  const _TerminalBlinkCursor({required this.color});

  final Color color;

  @override
  State<_TerminalBlinkCursor> createState() => _TerminalBlinkCursorState();
}

class _TerminalBlinkCursorState extends State<_TerminalBlinkCursor> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1060),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: AnimatedBuilder(
        animation: _controller,
        builder: (BuildContext context, Widget? child) {
          // On half the cycle the block is lit, off the other half.
          final bool lit = _controller.value < 0.5;
          return Container(
            width: 8,
            height: 15,
            decoration: BoxDecoration(
              color: lit ? widget.color.withAlpha(90) : widget.color.withAlpha(0),
              borderRadius: BorderRadius.circular(1),
            ),
          );
        },
      ),
    );
  }
}

/// The console window — a forced-dark screen with a faux title bar, a
/// keyboard status line, and a subtle CRT scanline overlay.
class TerminalLauncherFrame extends StatelessWidget {
  const TerminalLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    this.resultCount = 0,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.terminal),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.terminal.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(6),
          child: Stack(
            children: <Widget>[
              if (Design.backdropLauncher) const StableBackdrop(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  _TerminalTitleBar(accent: accent, isDark: isDark),
                  child,
                  _TerminalStatusBar(accent: accent, resultCount: resultCount, isDark: isDark),
                ],
              ),
              // CRT scanlines.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _ScanlinePainter(isDark: isDark)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TerminalTitleBar extends StatelessWidget {
  const _TerminalTitleBar({required this.accent, required this.isDark});

  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onPanStart: (DragStartDetails _) {
        windowManager.startDragging();
      },
      child: Container(
        height: 24,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: TerminalTokens.chrome(isDark),
          border: Border(bottom: BorderSide(color: accent.withAlpha(40))),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: accent.withAlpha(220), shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
            Text(
              'QuickLaunch',
              style: TerminalTokens.mono(
                fontSize: Design.baseFontSize - 1,
                color: TerminalTokens.dim(isDark),
                letterSpacing: 0.3,
              ),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () {
                QuickMenuFunctions.hideQuickMenu();
              },
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child: Text(
                  '─  ✕',
                  style: TerminalTokens.mono(
                    fontSize: Design.baseFontSize - 1,
                    color: TerminalTokens.dim(isDark),
                    letterSpacing: 1.5,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TerminalStatusBar extends StatelessWidget {
  const _TerminalStatusBar({required this.accent, required this.resultCount, required this.isDark});

  final Color accent;
  final int resultCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final TextStyle key = TerminalTokens.mono(
      fontSize: Design.baseFontSize - 1.5,
      color: accent.withAlpha(210),
      fontWeight: FontWeight.w700,
    );
    final TextStyle label = TerminalTokens.mono(
      fontSize: Design.baseFontSize - 1.5,
      color: TerminalTokens.dim(isDark),
    );
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      decoration: BoxDecoration(
        color: TerminalTokens.chrome(isDark),
        border: Border(top: BorderSide(color: accent.withAlpha(40))),
      ),
      child: Row(
        children: <Widget>[
          Text('↵', style: key),
          Text(' run   ', style: label),
          Text('→', style: key),
          Text(' Ctrl+K   ', style: label),
          Text('esc', style: key),
          Text(' quit', style: label),
          const Spacer(),
          Text(
            '[ ${resultCount.toString().padLeft(2, '0')} ]',
            style: TerminalTokens.mono(
              fontSize: Design.baseFontSize - 1.5,
              color: accent.withAlpha(180),
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// Very subtle horizontal scanlines for a CRT feel. Light phosphor lines on the
/// dark screen; faint ink lines on the light "paper console".
class _ScanlinePainter extends CustomPainter {
  const _ScanlinePainter({required this.isDark});

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
  bool shouldRepaint(covariant _ScanlinePainter oldDelegate) => oldDelegate.isDark != isDark;
}

// ---------------------------------------------------------------------------
// Zen (nature) — a calm, airy search field, frame, and rolling-hills footer.
// ---------------------------------------------------------------------------

class _ZenSearchBar extends StatelessWidget {
  const _ZenSearchBar({
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    // A soft floating pill with generous margin — room to breathe.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: accent.withAlpha(18),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: accent.withAlpha(36)),
        ),
        child: Row(
          children: <Widget>[
            dragHandle,
            const SizedBox(width: 12),
            Expanded(
              child: Stack(
                alignment: Alignment.centerRight,
                children: <Widget>[
                  textField,
                  if (trailingBadge != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: trailingBadge!,
                    ),
                ],
              ),
            ),
            if (isSearching)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.6, color: accent.withAlpha(140)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The calm outer frame — soft dawn wash, big rounding, and a faint
/// rolling-hills horizon footer.
class ZenLauncherFrame extends StatelessWidget {
  const ZenLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    this.resultCount = 0,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.zen),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.zen.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(26),
          child: Stack(
            children: <Widget>[
              if (Design.backdropLauncher) const StableBackdrop(),
              // Soft dawn glow drifting in from the top-left.
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
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  child,
                  _ZenFooter(accent: accent, onSurface: onSurface, resultCount: resultCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZenFooter extends StatelessWidget {
  const _ZenFooter({required this.accent, required this.onSurface, required this.resultCount});

  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: Stack(
        alignment: Alignment.bottomCenter,
        children: <Widget>[
          // Rolling-hills horizon.
          Positioned.fill(
            child: IgnorePointer(
              child: CustomPaint(painter: _ZenHillsPainter(accent)),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                resultCount == 0 ? 'breathe' : '$resultCount found',
                style: ZenTokens.soft(
                  fontSize: Design.baseFontSize - 1,
                  color: onSurface.withAlpha(120),
                  fontWeight: FontWeight.w500,
                  letterSpacing: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Two soft overlapping hills along the bottom edge — a quiet horizon.
class _ZenHillsPainter extends CustomPainter {
  const _ZenHillsPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final double h = size.height;
    final double w = size.width;

    final Paint back = Paint()
      ..color = color.withAlpha(24)
      ..style = PaintingStyle.fill;
    final Path backHill = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.62)
      ..quadraticBezierTo(w * 0.28, h * 0.22, w * 0.55, h * 0.55)
      ..quadraticBezierTo(w * 0.8, h * 0.85, w, h * 0.45)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(backHill, back);

    final Paint front = Paint()
      ..color = color.withAlpha(40)
      ..style = PaintingStyle.fill;
    final Path frontHill = Path()
      ..moveTo(0, h)
      ..lineTo(0, h * 0.82)
      ..quadraticBezierTo(w * 0.4, h * 0.5, w * 0.7, h * 0.78)
      ..quadraticBezierTo(w * 0.88, h * 0.92, w, h * 0.72)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(frontHill, front);
  }

  @override
  bool shouldRepaint(covariant _ZenHillsPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Glass (iOS Liquid Glass) — translucent capsule search field + layered glass
// frame with specular highlights and an accent refraction glow.
// ---------------------------------------------------------------------------

class _GlassSearchBar extends StatelessWidget {
  const _GlassSearchBar({
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color surface;
  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // A bright floating glass capsule.
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(22),
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              Colors.white.withAlpha(isDark ? 24 : 150),
              Colors.white.withAlpha(isDark ? 8 : 80),
            ],
          ),
          border: Border.all(color: Colors.white.withAlpha(isDark ? 44 : 180), width: 1),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(isDark ? 46 : 18),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          children: <Widget>[
            dragHandle,
            const SizedBox(width: 12),
            Expanded(
              child: Stack(
                alignment: Alignment.centerRight,
                children: <Widget>[
                  textField,
                  if (trailingBadge != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: trailingBadge!,
                    ),
                ],
              ),
            ),
            if (isSearching)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 1.8, color: accent.withAlpha(170)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class GlassLauncherFrame extends StatelessWidget {
  const GlassLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool hasBackdrop = Design.backdropType.isNotEmpty && user.activeBackdropPath.isNotEmpty;
    final Color baseFill = surface.withAlpha(hasBackdrop ? (isDark ? 150 : 170) : (isDark ? 188 : 212));

    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.glass),
      // Outer container carries the (un-clipped) floating shadow + accent glow.
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.glass.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 30, sigmaY: 30),
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(28),
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    Color.alphaBlend(Colors.white.withAlpha(isDark ? 60 : 92), baseFill),
                    baseFill,
                    Color.alphaBlend(accent.withAlpha(isDark ? 46 : 30), baseFill),
                  ],
                ),
                border: Border.all(color: Colors.white.withAlpha(isDark ? 40 : 120), width: 1.2),
              ),
              child: Stack(
                children: <Widget>[
                  if (Design.backdropLauncher) const StableBackdrop(),
                  // Accent refraction glow drifting from the bottom-right.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: const Alignment(1.1, 1.2),
                            radius: 1.4,
                            colors: <Color>[accent.withAlpha(isDark ? 48 : 34), accent.withAlpha(0)],
                          ),
                        ),
                      ),
                    ),
                  ),
                  // Specular sheen — the glass shine from the top-left.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.center,
                            colors: <Color>[Colors.white.withAlpha(isDark ? 26 : 96), Colors.transparent],
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
                              Colors.white.withAlpha(isDark ? 70 : 200),
                              Colors.transparent,
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[child],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Blueprint (drafting sheet) — search field with a drafting-ruler underline,
// grid-paper frame with sheet border + registration marks, and an engineering
// title block as the footer.
// ---------------------------------------------------------------------------

class _BlueprintSearchBar extends StatelessWidget {
  const _BlueprintSearchBar({
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final TextStyle microLabel = BlueprintTokens.tech(
      fontSize: Design.baseFontSize - 3.5,
      color: onSurface.withAlpha(110),
      fontWeight: FontWeight.w600,
      letterSpacing: 1.8,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Micro title-block labels above the field.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 0),
          child: Row(
            children: <Widget>[
              Text('DWG NO. TB-001', style: microLabel),
              const Spacer(),
              Text('SEARCH FIELD', style: microLabel),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 3, 14, 0),
          child: Row(
            children: <Widget>[
              dragHandle,
              const SizedBox(width: 10),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: <Widget>[
                    textField,
                    if (trailingBadge != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: trailingBadge!,
                      ),
                  ],
                ),
              ),
              if (isSearching)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: accent.withAlpha(170)),
                  ),
                ),
            ],
          ),
        ),
        // Drafting ruler — the measured underline of the input.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: SizedBox(
            height: 9,
            width: double.infinity,
            child: CustomPaint(painter: _BlueprintRulerPainter(color: accent)),
          ),
        ),
      ],
    );
  }
}

/// A ruler edge: a baseline with graduation ticks — taller every 5th, tallest
/// every 10th — like the scale printed along a drafting rule.
class _BlueprintRulerPainter extends CustomPainter {
  const _BlueprintRulerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color.withAlpha(150)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), line);

    final Paint tick = Paint()
      ..color = color.withAlpha(110)
      ..strokeWidth = 1;
    int i = 0;
    for (double x = 0.5; x <= size.width; x += 6) {
      final double h = i % 10 == 0 ? 7 : (i % 5 == 0 ? 5 : 3);
      canvas.drawLine(Offset(x, 1), Offset(x, 1 + h), tick);
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintRulerPainter oldDelegate) => oldDelegate.color != color;
}

/// The drafting sheet — grid paper, an inner sheet border with corner
/// registration crosses, and an engineering title block along the bottom.
class BlueprintLauncherFrame extends StatelessWidget {
  const BlueprintLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    this.resultCount = 0,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.blueprint),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.blueprint.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(3),
          child: Stack(
            children: <Widget>[
              if (Design.backdropLauncher) const StableBackdrop(),
              // Grid paper + inner sheet border + corner registration marks.
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _BlueprintSheetPainter(ink: accent)),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  child,
                  _BlueprintTitleBlock(accent: accent, onSurface: onSurface, resultCount: resultCount),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grid paper with a heavier line every 5th cell, an inner sheet border, and
/// small "+" registration crosses at its corners.
class _BlueprintSheetPainter extends CustomPainter {
  const _BlueprintSheetPainter({required this.ink});

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

    // Inner sheet border.
    const double inset = 5;
    final Paint border = Paint()
      ..color = ink.withAlpha(80)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Rect sheet = Rect.fromLTWH(inset + 0.5, inset + 0.5, size.width - 2 * inset - 1, size.height - 2 * inset - 1);
    canvas.drawRect(sheet, border);

    // Registration crosses at the sheet corners.
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
  bool shouldRepaint(covariant _BlueprintSheetPainter oldDelegate) => oldDelegate.ink != ink;
}

/// The engineering title block: labeled cells separated by ruled dividers.
class _BlueprintTitleBlock extends StatelessWidget {
  const _BlueprintTitleBlock({
    required this.accent,
    required this.onSurface,
    required this.resultCount,
  });

  final Color accent;
  final Color onSurface;
  final int resultCount;

  Widget _cell(String label, String value, {bool expand = false}) {
    final Widget content = Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 9),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: BlueprintTokens.tech(
              fontSize: Design.baseFontSize - 4,
              color: onSurface.withAlpha(110),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.6,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 1),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.clip,
            style: BlueprintTokens.tech(
              fontSize: Design.baseFontSize - 1.5,
              color: onSurface.withAlpha(220),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
              height: 1.1,
            ),
          ),
        ],
      ),
    );
    return expand ? Expanded(child: content) : content;
  }

  @override
  Widget build(BuildContext context) {
    final Widget divider = Container(width: 1, color: accent.withAlpha(80));
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: accent.withAlpha(80))),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            _cell('DRAWING', 'TABAME — QUICK LAUNCH', expand: true),
            divider,
            _cell('ENTER', 'OPEN'),
            divider,
            _cell('ESC', 'CLOSE'),
            divider,
            _cell('QTY', resultCount.toString().padLeft(2, '0')),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transit (metro map) — destination-sign search bar topped by the line-color
// band, a station-sign frame, and a platform-strip footer. Results render as
// stations on a continuous route line (see LauncherResultRow._buildTransit).
// ---------------------------------------------------------------------------

class _TransitSearchBar extends StatelessWidget {
  const _TransitSearchBar({
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 11, 14, 9),
          child: Row(
            children: <Widget>[
              // Line roundel — the metro-line bullet (also the drag handle).
              Container(
                width: 30,
                height: 30,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent, width: 2.4),
                ),
                child: dragHandle,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: <Widget>[
                    textField,
                    if (trailingBadge != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: trailingBadge!,
                      ),
                  ],
                ),
              ),
              if (isSearching)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.6, color: accent.withAlpha(170)),
                  ),
                ),
            ],
          ),
        ),
        // The line-color band — the identity stripe of a station sign.
        Container(height: 5, color: accent),
      ],
    );
  }
}

/// Dashed fare-zone boundary line used by the Transit section header.
class _TransitZonePainter extends CustomPainter {
  const _TransitZonePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 1.2;
    const double dash = 5;
    const double gap = 5;
    final double y = size.height / 2;
    for (double x = 0; x < size.width; x += dash + gap) {
      canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), paint);
    }
  }

  @override
  bool shouldRepaint(covariant _TransitZonePainter oldDelegate) => oldDelegate.color != color;
}

/// The station sign — forced signage palette, a flat enamel plate with the
/// accent as the metro-line color, and a platform strip along the bottom.
class TransitLauncherFrame extends StatelessWidget {
  const TransitLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    this.resultCount = 0,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.transit),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.transit.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: <Widget>[
              if (Design.backdropLauncher) const StableBackdrop(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  child,
                  _TransitFooter(accent: accent, resultCount: resultCount, isDark: isDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The platform strip: boarding hints on the left, the stop count on the
/// right — all in signage lettering.
class _TransitFooter extends StatelessWidget {
  const _TransitFooter({required this.accent, required this.resultCount, required this.isDark});

  final Color accent;
  final int resultCount;
  final bool isDark;

  Widget _hint(String key, String caption) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          key,
          style: TransitTokens.sign(
            fontSize: Design.baseFontSize - 1,
            color: accent,
            fontWeight: FontWeight.w800,
            letterSpacing: 0.6,
          ),
        ),
        Text(
          ' $caption',
          style: TransitTokens.sign(
            fontSize: Design.baseFontSize - 1,
            color: TransitTokens.dim(isDark),
            fontWeight: FontWeight.w600,
            letterSpacing: 1.0,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      decoration: BoxDecoration(
        color: TransitTokens.chrome(isDark),
        border: Border(top: BorderSide(color: accent.withAlpha(90))),
      ),
      child: Row(
        children: <Widget>[
          _hint('↵', 'BOARD'),
          const SizedBox(width: 14),
          _hint('→', 'LINES'),
          const SizedBox(width: 14),
          _hint('ESC', 'EXIT'),
          const Spacer(),
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: accent, width: 2),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            resultCount == 1 ? '1 STOP' : '$resultCount STOPS',
            style: TransitTokens.sign(
              fontSize: Design.baseFontSize - 1,
              color: TransitTokens.dim(isDark),
              fontWeight: FontWeight.w700,
              letterSpacing: 1.2,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Fluent (Windows 11) — a WinUI text box with the accent focus underline, a
// mica frame, and a Start-menu-style footer strip. Results render as WinUI
// list items with the accent selection pill (see LauncherResultRow._buildFluent).
// ---------------------------------------------------------------------------

class _FluentSearchBar extends StatelessWidget {
  const _FluentSearchBar({
    required this.accent,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    // A WinUI AutoSuggestBox: faint layer fill, hairline stroke, and — since
    // the launcher input is always focused — the 2px accent bottom underline.
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
      child: Container(
        decoration: BoxDecoration(
          color: FluentTokens.fill(isDark),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: FluentTokens.stroke(isDark)),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 8, 10, 7),
                child: Row(
                  children: <Widget>[
                    dragHandle,
                    const SizedBox(width: 10),
                    Expanded(
                      child: Stack(
                        alignment: Alignment.centerRight,
                        children: <Widget>[
                          textField,
                          if (trailingBadge != null)
                            Padding(
                              padding: const EdgeInsets.only(right: 4),
                              child: trailingBadge!,
                            ),
                        ],
                      ),
                    ),
                    if (isSearching)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                        ),
                      ),
                  ],
                ),
              ),
              // Focus underline — the accent bottom stroke of a focused text box.
              Container(height: 2, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

/// The mica window — forced Win11 neutrals, 8px corners, and a footer strip in
/// the shifted chrome shade, like the Start menu's bottom bar.
class FluentLauncherFrame extends StatelessWidget {
  const FluentLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    required this.onSurface,
    this.resultCount = 0,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.fluent),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.fluent.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Stack(
            children: <Widget>[
              if (Design.backdropLauncher) const StableBackdrop(),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  child,
                  _FluentFooter(onSurface: onSurface, resultCount: resultCount, isDark: isDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FluentFooter extends StatelessWidget {
  const _FluentFooter({required this.onSurface, required this.resultCount, required this.isDark});

  final Color onSurface;
  final int resultCount;
  final bool isDark;

  Widget _kbd(String keyLabel, String caption) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          constraints: const BoxConstraints(minWidth: 18),
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: onSurface.withAlpha(12),
            borderRadius: BorderRadius.circular(4),
            border: Border.all(color: FluentTokens.stroke(isDark)),
          ),
          child: Text(
            keyLabel,
            style: FluentTokens.segoe(
              fontSize: Design.baseFontSize - 1,
              fontWeight: FontWeight.w600,
              color: onSurface.withAlpha(180),
              height: 1.2,
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          caption,
          style: FluentTokens.segoe(
            fontSize: Design.baseFontSize - 1,
            color: FluentTokens.dim(isDark),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      decoration: BoxDecoration(
        color: FluentTokens.chrome(isDark),
        border: Border(top: BorderSide(color: FluentTokens.stroke(isDark))),
      ),
      child: Row(
        children: <Widget>[
          _kbd('↵', 'Open'),
          const SizedBox(width: 12),
          _kbd('→', 'Actions'),
          const SizedBox(width: 12),
          _kbd('Esc', 'Dismiss'),
          const Spacer(),
          Text(
            resultCount == 1 ? '1 result' : '$resultCount results',
            style: FluentTokens.segoe(
              fontSize: Design.baseFontSize - 1,
              color: FluentTokens.dim(isDark),
              fontWeight: FontWeight.w400,
            ),
          ),
        ],
      ),
    );
  }
}
