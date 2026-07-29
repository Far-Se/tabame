import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../quickmenu_designs/design_backdrop_stable.dart';
import 'launcher_design.dart';

part 'launcher_designs/manifesto_launcher_design.dart';
part 'launcher_designs/classic_launcher_design.dart';
part 'launcher_designs/serene_launcher_design.dart';
part 'launcher_designs/command_launcher_design.dart';
part 'launcher_designs/terminal_launcher_design.dart';
part 'launcher_designs/zen_launcher_design.dart';
part 'launcher_designs/glass_launcher_design.dart';
part 'launcher_designs/blueprint_launcher_design.dart';
part 'launcher_designs/transit_launcher_design.dart';
part 'launcher_designs/fluent_launcher_design.dart';
part 'launcher_designs/orbit_launcher_design.dart';
part 'launcher_designs/anime_launcher_design.dart';
part 'launcher_designs/tech_launcher_design.dart';
part 'launcher_designs/vector_launcher_design.dart';
part 'launcher_designs/outrun2_launcher_design.dart';
part 'launcher_designs/matrix_launcher_design.dart';
part 'launcher_designs/steam_launcher_design.dart';
part 'launcher_designs/cyber_launcher_design.dart';
part 'launcher_designs/manga_launcher_design.dart';

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
          borderRadius: BorderRadius.circular(Design.borderRadius),
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
          borderRadius: BorderRadius.circular(Design.borderRadius),
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
          borderRadius: BorderRadius.circular(Design.borderRadius),
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
          borderRadius: BorderRadius.circular(Design.borderRadius),
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
          borderRadius: BorderRadius.circular(Design.borderRadius),
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
          borderRadius: BorderRadius.circular(Design.borderRadius),
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
          borderRadius: BorderRadius.circular(Design.borderRadius),
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
          borderRadius: BorderRadius.circular(Design.borderRadius),
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
          borderRadius: BorderRadius.circular(Design.borderRadius),
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

      case LauncherDesign.manifesto:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          color: surface,
          border: Border.all(color: ManifestoTokens.fg(surface.computeLuminance() < 0.5), width: 2),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(110),
              blurRadius: 0,
              offset: const Offset(7, 7),
            ),
          ],
        );

      case LauncherDesign.orbit:
        // Guidance scope — [surface] is the forced HUD palette. A thin
        // phosphor edge, a deep instrument shadow, no glow.
        return BoxDecoration(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          color: surface,
          border: Border.all(color: accent.withAlpha(70)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(110),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 14),
            ),
          ],
        );
      case LauncherDesign.anime:
        return BoxDecoration(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          color: surface.withAlpha(245),
          border: Border.all(color: accent.withAlpha(65)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(70),
              blurRadius: 28,
              spreadRadius: -6,
              offset: const Offset(0, 14),
            ),
          ],
        );
      case LauncherDesign.tech:
        return techLauncherOuterDecoration(surface, accent);
      case LauncherDesign.vector:
        return vectorLauncherOuterDecoration(surface, accent);
      case LauncherDesign.outrun2:
        return outrun2LauncherOuterDecoration(surface, accent);
      case LauncherDesign.matrix:
        return matrixLauncherOuterDecoration(surface, accent);
      case LauncherDesign.steam:
        return steamLauncherOuterDecoration(surface, accent);
      case LauncherDesign.cyber:
        return cyberLauncherOuterDecoration(surface, accent);
      case LauncherDesign.manga:
        return mangaLauncherOuterDecoration(surface, accent);
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
      case LauncherDesign.manifesto:
        return _ManifestoSearchBar(
          accent: accent,
          onSurface: onSurface,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.orbit:
        return _OrbitSearchBar(
          accent: accent,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.anime:
        return _AnimeSearchBar(
          accent: accent,
          onSurface: onSurface,
          dragHandle: dragHandle,
          textField: textField,
          trailingBadge: trailingBadge,
          isSearching: isSearching,
        );
      case LauncherDesign.tech:
        return TechLauncherSearchBar(
            accent: accent,
            onSurface: onSurface,
            dragHandle: dragHandle,
            textField: textField,
            trailingBadge: trailingBadge,
            isSearching: isSearching);
      case LauncherDesign.vector:
        return VectorLauncherSearchBar(
            accent: accent,
            onSurface: onSurface,
            dragHandle: dragHandle,
            textField: textField,
            trailingBadge: trailingBadge,
            isSearching: isSearching);
      case LauncherDesign.outrun2:
        return Outrun2LauncherSearchBar(
            surface: surface,
            accent: accent,
            dragHandle: dragHandle,
            textField: textField,
            trailingBadge: trailingBadge,
            isSearching: isSearching);
      case LauncherDesign.matrix:
        return MatrixLauncherSearchBar(
            accent: accent,
            onSurface: onSurface,
            dragHandle: dragHandle,
            textField: textField,
            trailingBadge: trailingBadge,
            isSearching: isSearching);
      case LauncherDesign.steam:
        return SteamLauncherSearchBar(
            accent: accent,
            onSurface: onSurface,
            dragHandle: dragHandle,
            textField: textField,
            trailingBadge: trailingBadge,
            isSearching: isSearching);
      case LauncherDesign.cyber:
        return CyberLauncherSearchBar(
            accent: accent,
            onSurface: onSurface,
            dragHandle: dragHandle,
            textField: textField,
            trailingBadge: trailingBadge,
            isSearching: isSearching);
      case LauncherDesign.manga:
        return MangaLauncherSearchBar(
            surface: surface,
            accent: accent,
            onSurface: onSurface,
            dragHandle: dragHandle,
            textField: textField,
            trailingBadge: trailingBadge,
            isSearching: isSearching);
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
      case LauncherDesign.manifesto:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 9, 12, 3),
          child: Row(
            children: <Widget>[
              Container(width: 8, height: 8, color: accent),
              const SizedBox(width: 7),
              Text(
                label.toUpperCase(),
                style: ManifestoTokens.display(
                  fontSize: Design.baseFontSize,
                  color: accent,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 2.2,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(child: Container(height: 1, color: accent.withAlpha(100))),
              const SizedBox(width: 5),
              Text(
                'INDEX',
                style: ManifestoTokens.display(
                  fontSize: Design.baseFontSize - 1.5,
                  color: accent.withAlpha(170),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
        );
      case LauncherDesign.orbit:
        // A track readout: cross marker + label, then a dashed track line
        // running to the edge of the scope.
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 4),
          child: Row(
            children: <Widget>[
              Text(
                '+',
                style: OrbitTokens.tele(
                  fontSize: Design.baseFontSize + 1,
                  color: accent.withAlpha(220),
                  fontWeight: FontWeight.w700,
                  height: 1.0,
                ),
              ),
              const SizedBox(width: 7),
              Text(
                label.toUpperCase(),
                style: OrbitTokens.tele(
                  fontSize: Design.baseFontSize - 1,
                  color: accent.withAlpha(200),
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.0,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: SizedBox(
                  height: 7,
                  child: CustomPaint(painter: _OrbitTrackPainter(color: accent.withAlpha(110))),
                ),
              ),
            ],
          ),
        );
      case LauncherDesign.anime:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 11, 16, 4),
          child: Row(
            children: <Widget>[
              Icon(Icons.star_rounded, size: 13, color: accent.withAlpha(200)),
              const SizedBox(width: 6),
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: Design.baseFontSize - 0.5,
                  color: accent.withAlpha(210),
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),
            ],
          ),
        );
      case LauncherDesign.tech:
        return TechLauncherHeader(label: label, accent: accent);
      case LauncherDesign.vector:
        return VectorLauncherHeader(label: label, accent: accent);
      case LauncherDesign.outrun2:
        return Outrun2LauncherHeader(label: label, accent: accent);
      case LauncherDesign.matrix:
        return MatrixLauncherHeader(label: label, accent: accent);
      case LauncherDesign.steam:
        return SteamLauncherHeader(label: label, accent: accent);
      case LauncherDesign.cyber:
        return CyberLauncherHeader(label: label, accent: accent);
      case LauncherDesign.manga:
        return MangaLauncherHeader(label: label, accent: accent);
    }
  }
}

// ---------------------------------------------------------------------------
// Manifesto search bar
// ---------------------------------------------------------------------------
