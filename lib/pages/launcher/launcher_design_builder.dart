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
