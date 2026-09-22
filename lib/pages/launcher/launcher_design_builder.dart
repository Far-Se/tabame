import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/design_settings.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/win32/win_utils.dart';
import '../../widgets/widgets/date_time_widget.dart';
import '../quickmenu_designs/design_backdrop_stable.dart';
import 'launcher_design.dart';
import 'widgets/capillary_surface.dart';
import 'widgets/crt_surface.dart';
import 'widgets/liquid_metal_surface.dart';
import 'widgets/thermal_surface.dart';
import 'widgets/satin_surface.dart';

part 'launcher_designs/anime_launcher_design.dart';
part 'launcher_designs/aurora_launcher_design.dart';
part 'launcher_designs/blueprint_launcher_design.dart';
part 'launcher_designs/capillary_launcher_design.dart';
part 'launcher_designs/classic_launcher_design.dart';
part 'launcher_designs/command_launcher_design.dart';
part 'launcher_designs/crt_launcher_design.dart';
part 'launcher_designs/cyber_launcher_design.dart';
part 'launcher_designs/fluent_launcher_design.dart';
part 'launcher_designs/glass_launcher_design.dart';
part 'launcher_designs/liquid_metal_launcher_design.dart';
part 'launcher_designs/manga_launcher_design.dart';
part 'launcher_designs/manifesto_launcher_design.dart';
part 'launcher_designs/matrix_launcher_design.dart';
part 'launcher_designs/newcast_launcher_design.dart';
part 'launcher_designs/notion_launcher_design.dart';
part 'launcher_designs/omarchy_launcher_design.dart';
part 'launcher_designs/optical_glass_launcher_design.dart';
part 'launcher_designs/orbit_launcher_design.dart';
part 'launcher_designs/outrun2_launcher_design.dart';
part 'launcher_designs/phosphor_launcher_design.dart';
part 'launcher_designs/relay_launcher_design.dart';
part 'launcher_designs/retro_launcher_design.dart';
part 'launcher_designs/serene_launcher_design.dart';
part 'launcher_designs/steam_launcher_design.dart';
part 'launcher_designs/strata_launcher_design.dart';
part 'launcher_designs/switchboard_launcher_design.dart';
part 'launcher_designs/tech_launcher_design.dart';
part 'launcher_designs/terminal2_launcher_design.dart';
part 'launcher_designs/terminal_launcher_design.dart';
part 'launcher_designs/thermal_launcher_design.dart';
part 'launcher_designs/satin_launcher_design.dart';
part 'launcher_designs/toon_launcher_design.dart';
part 'launcher_designs/transit_launcher_design.dart';
part 'launcher_designs/tui_launcher_design.dart';
part 'launcher_designs/vector_launcher_design.dart';
part 'launcher_designs/windows_98_launcher_design.dart';
part 'launcher_designs/windows_xp_launcher_design.dart';
part 'launcher_designs/zen_launcher_design.dart';
part 'widgets/launcher_animation.dart';
part 'widgets/launcher_search_field.dart';
part 'widgets/launcher_section_header.dart';

/// Design widgets inherit their palette from Theme and LauncherTheme.
extension LauncherDesignBuilder on LauncherDesign {
  /// Shared by launcher frames and action dialogs.
  BoxDecoration outerDecoration({required Color surface, required Color accent}) => switch (this) {
        LauncherDesign.anime => _animeOuterDecoration(surface, accent),
        LauncherDesign.aurora => _auroraOuterDecoration(),
        LauncherDesign.blueprint => _blueprintOuterDecoration(surface, accent),
        LauncherDesign.capillary => _capillaryOuterDecoration(surface),
        LauncherDesign.classic => _classicOuterDecoration(surface, accent),
        LauncherDesign.command => _commandOuterDecoration(surface, accent),
        LauncherDesign.crt => _crtOuterDecoration(),
        LauncherDesign.cyber => _cyberOuterDecoration(surface, accent),
        LauncherDesign.fluent => _fluentOuterDecoration(surface),
        LauncherDesign.glass => _glassOuterDecoration(accent),
        LauncherDesign.liquidMetal => _liquidMetalOuterDecoration(),
        LauncherDesign.manga => _mangaOuterDecoration(surface),
        LauncherDesign.manifesto => _manifestoOuterDecoration(surface),
        LauncherDesign.matrix => _matrixOuterDecoration(),
        LauncherDesign.newCast => _newCastOuterDecoration(surface),
        LauncherDesign.notion => _notionOuterDecoration(surface),
        LauncherDesign.omarchy => _omarchyOuterDecoration(surface),
        LauncherDesign.opticalGlass => _opticalGlassOuterDecoration(),
        LauncherDesign.orbit => _orbitOuterDecoration(surface, accent),
        LauncherDesign.outrun => _outrunOuterDecoration(surface, accent),
        LauncherDesign.phosphor => _phosphorOuterDecoration(),
        LauncherDesign.relay => _relayOuterDecoration(surface, accent),
        LauncherDesign.retro => _retroOuterDecoration(),
        LauncherDesign.serene => _sereneOuterDecoration(surface),
        LauncherDesign.steam => _steamOuterDecoration(surface),
        LauncherDesign.strata => _strataOuterDecoration(),
        LauncherDesign.switchboard => _switchboardOuterDecoration(surface),
        LauncherDesign.tech => _techOuterDecoration(surface, accent),
        LauncherDesign.terminal => _terminalOuterDecoration(surface, accent),
        LauncherDesign.terminal2 => _terminal2OuterDecoration(surface),
        LauncherDesign.satin => _satinOuterDecoration(),
        LauncherDesign.thermal => _thermalOuterDecoration(),
        LauncherDesign.toon => _toonOuterDecoration(),
        LauncherDesign.transit => _transitOuterDecoration(surface, accent),
        LauncherDesign.tui => _tuiOuterDecoration(surface),
        LauncherDesign.vector => _vectorOuterDecoration(surface),
        LauncherDesign.windows98 => _windows98OuterDecoration(),
        LauncherDesign.windowsXp => _windowsXpOuterDecoration(),
        LauncherDesign.zen => _zenOuterDecoration(surface, accent),
      };

  Widget buildSearchBar({
    required Widget dragHandle,
    required Widget textField,
    required Widget? trailingBadge,
    required bool isSearching,
  }) {
    final _LauncherSearchBarContent content = _LauncherSearchBarContent(
      dragHandle: dragHandle,
      textField: textField,
      trailingBadge: trailingBadge,
      isSearching: isSearching,
    );
    return switch (this) {
      LauncherDesign.anime => _AnimeSearchBar(content),
      LauncherDesign.aurora => _AuroraSearchBar(content),
      LauncherDesign.blueprint => _BlueprintSearchBar(content),
      LauncherDesign.capillary => _CapillarySearchBar(content),
      LauncherDesign.classic => _ClassicSearchBar(content),
      LauncherDesign.command => _CommandSearchBar(content),
      LauncherDesign.crt => _CrtSearchBar(content),
      LauncherDesign.cyber => _CyberLauncherSearchBar(content),
      LauncherDesign.fluent => _FluentSearchBar(content),
      LauncherDesign.glass => _GlassSearchBar(content),
      LauncherDesign.liquidMetal => _LiquidMetalSearchBar(content),
      LauncherDesign.manga => _MangaLauncherSearchBar(content),
      LauncherDesign.manifesto => _ManifestoSearchBar(content),
      LauncherDesign.matrix => _MatrixLauncherSearchBar(content),
      LauncherDesign.newCast => _RaycastSearchBar(content),
      LauncherDesign.notion => _NotionLauncherSearchBar(content),
      LauncherDesign.omarchy => _OmarchySearchBar(content),
      LauncherDesign.opticalGlass => _OpticalGlassSearchBar(content),
      LauncherDesign.orbit => _OrbitSearchBar(content),
      LauncherDesign.outrun => _Outrun2LauncherSearchBar(content),
      LauncherDesign.phosphor => _PhosphorSearchBar(content),
      LauncherDesign.relay => _RelaySearchBar(content),
      LauncherDesign.retro => _RetroSearchBar(content),
      LauncherDesign.serene => _SereneSearchBar(content),
      LauncherDesign.steam => _SteamLauncherSearchBar(content),
      LauncherDesign.strata => _StrataSearchBar(content),
      LauncherDesign.switchboard => _SwitchboardLauncherSearchBar(content),
      LauncherDesign.tech => _TechLauncherSearchBar(content),
      LauncherDesign.terminal => _TerminalSearchBar(content),
      LauncherDesign.terminal2 => _Terminal2SearchBar(content),
      LauncherDesign.satin => _SatinSearchBar(content),
      LauncherDesign.thermal => _ThermalSearchBar(content),
      LauncherDesign.toon => _ToonSearchBar(content),
      LauncherDesign.transit => _TransitSearchBar(content),
      LauncherDesign.tui => _TuiSearchBar(content),
      LauncherDesign.vector => _VectorLauncherSearchBar(content),
      LauncherDesign.windows98 => _Windows98LauncherSearchBar(content),
      LauncherDesign.windowsXp => _WindowsXpLauncherSearchBar(content),
      LauncherDesign.zen => _ZenSearchBar(content),
    };
  }

  Widget buildSectionHeader({required String label, Color? accent}) =>
      _LauncherSectionHeader(design: this, label: label, accent: accent);
}
