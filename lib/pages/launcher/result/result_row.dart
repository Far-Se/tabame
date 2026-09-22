import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/design_settings.dart';
import '../../../models/settings.dart';
import '../launcher_corners.dart';
import '../launcher_design.dart';
import '../widgets/capillary_surface.dart';
import '../widgets/thermal_surface.dart';
import '../widgets/radiant_surface.dart';
import '../widgets/liquid_metal_surface.dart';
import 'inline_markup.dart';

part 'designs/aurora_result_row.dart';
part 'designs/badges_result_row.dart';
part 'designs/blueprint_result_row.dart';
part 'designs/capillary_result_row.dart';
part 'designs/classic_result_row.dart';
part 'designs/command_result_row.dart';
part 'designs/crt_result_row.dart';
part 'designs/fluent_result_row.dart';
part 'designs/glass_result_row.dart';
part 'designs/liquid_metal_result_row.dart';
part 'designs/manifesto_result_row.dart';
part 'designs/notion_result_row.dart';
part 'designs/nouveau_result_row.dart';
part 'designs/radiant_result_row.dart';
part 'designs/omarchy_result_row.dart';
part 'designs/optical_glass_result_row.dart';
part 'designs/orbit_result_row.dart';
part 'designs/phosphor_result_row.dart';
part 'designs/raycast_result_row.dart';
part 'designs/relay_result_row.dart';
part 'designs/retro_result_row.dart';
part 'designs/serene_result_row.dart';
part 'designs/strata_result_row.dart';
part 'designs/switchboard_result_row.dart';
part 'designs/terminal_result_row.dart';
part 'designs/terminal2_result_row.dart';
part 'designs/thermal_result_row.dart';
part 'designs/satin_result_row.dart';
part 'designs/toon_result_row.dart';
part 'designs/transit_result_row.dart';
part 'designs/tui_result_row.dart';
part 'designs/windows98_result_row.dart';
part 'designs/windows_xp_result_row.dart';
part 'designs/zen_result_row.dart';

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
    final LauncherDesign design = LauncherTheme.maybeOf(context)?.design ?? user.launcherDesign;
    return switch (design) {
      LauncherDesign.radiant => _buildRadiant(context),
      LauncherDesign.nouveau => _buildNouveau(context),
      LauncherDesign.satin => _buildSatin(context),
      LauncherDesign.thermal => _buildThermal(context),
      LauncherDesign.capillary => _buildCapillary(context),
      LauncherDesign.liquidMetal => _buildLiquidMetal(context),
      LauncherDesign.opticalGlass => _buildOpticalGlass(context),
      LauncherDesign.aurora => _buildAurora(context),
      LauncherDesign.strata => _buildStrata(context),
      LauncherDesign.crt => _buildCrt(context),
      LauncherDesign.toon => _buildToon(context),
      LauncherDesign.retro => _buildRetro(context),
      LauncherDesign.phosphor => _buildPhosphor(context),
      LauncherDesign.serene => _buildSerene(context),
      LauncherDesign.command || LauncherDesign.cyber => _buildCommand(context),
      LauncherDesign.terminal || LauncherDesign.matrix => _buildTerminal(context),
      LauncherDesign.zen => _buildZen(context),
      LauncherDesign.glass || LauncherDesign.outrun => _buildGlass(context),
      LauncherDesign.classic || LauncherDesign.anime || LauncherDesign.tech => _buildClassic(context),
      LauncherDesign.blueprint => _buildBlueprint(context),
      LauncherDesign.transit => _buildTransit(context),
      LauncherDesign.fluent || LauncherDesign.steam => _buildFluent(context),
      LauncherDesign.manifesto || LauncherDesign.manga => _buildManifesto(context),
      LauncherDesign.orbit || LauncherDesign.vector => _buildOrbit(context),
      LauncherDesign.windowsXp => _buildWindowsXp(context),
      LauncherDesign.windows98 => _buildWindows98(context),
      LauncherDesign.notion => _buildNotion(context),
      LauncherDesign.switchboard => _buildSwitchboard(context),
      LauncherDesign.relay => _buildRelay(context),
      LauncherDesign.terminal2 => _buildTerminal2(context),
      LauncherDesign.newCast => _buildRaycast(context),
      LauncherDesign.omarchy => _buildOmarchy(),
      LauncherDesign.tui => _buildTui(context),
    };
  }

  /// Hover changes selection only when the pointer moves. Keep each renderer's
  /// hit-test behavior so its margins and embedded controls behave as before.
  Widget _interactive({required Widget child, HitTestBehavior behavior = HitTestBehavior.deferToChild}) => Semantics(
        selected: isSelected,
        button: true,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onHover: (PointerHoverEvent event) {
            if (event.delta != Offset.zero) onHover();
          },
          child: GestureDetector(behavior: behavior, onTap: onTap, child: child),
        ),
      );
}
