import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import 'launcher_design.dart';

// ---------------------------------------------------------------------------
// Public helpers that the LauncherState uses to switch designs
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
    }
  }

  /// Returns the search-bar widget for the given design.
  ///
  /// [dragHandle] is the GestureDetector wrapping the drag affordance.
  /// [textField] is the already-constructed TextField.
  /// [trailingBadge] is the optional info badge (e.g. "File Copied").
  /// [isSearching] drives the spinner.
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
              fontSize: 10,
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
              fontSize: 11,
              color: accent.withAlpha(160),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
            ),
          ),
        );
    }
  }
}

// ---------------------------------------------------------------------------
// Classic search bar (extracted from launcher.dart for parity)
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
        color: surface.withAlpha(210),
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

/// The Spotlight-inspired search bar: no card border, just a subtle
/// separator below, larger search icon, and a slightly heavier input font.
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
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          child: Row(
            children: <Widget>[
              // The drag handle widget already wraps the search icon in the
              // parent; we just render it.
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
    );
  }
}

// ---------------------------------------------------------------------------
// Serene launcher outer frame
//
// The LauncherState.build() method wraps its content in one of these so the
// backdrop blur and rounded corners are consistent.
// ---------------------------------------------------------------------------

/// Wraps [child] in the Serene-design frosted-glass container.
///
/// Use this instead of a plain [Container] when [LauncherDesign.serene] is
/// active.  For [LauncherDesign.classic] the existing [Container] in
/// `launcher.dart` is kept unchanged.
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

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: BackdropFilter(
        filter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28),
        child: Container(
          constraints: const BoxConstraints(minHeight: 360),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: surface.withAlpha(240),
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
          child: child,
        ),
      ),
    );
  }
}
