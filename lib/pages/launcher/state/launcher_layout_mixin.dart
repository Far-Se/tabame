part of '../../launcher.dart';

/// Assembles shared content while supplying special frame inputs only where used.
mixin _LauncherLayoutMixin on _LauncherStateMembersMixin {
  Widget _buildLauncherFrame(
      {required Widget searchContent, required Widget resultsContent, required Widget resizeHandle}) {
    final int resultCount = _results.length;
    final Widget resizeOverlay = Positioned(left: 0, right: 0, bottom: 0, child: resizeHandle);
    Widget buildBody() {
      final Widget layoutContent = Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          searchContent,
          if (_design == LauncherDesign.phosphor && _activePlugin == null)
            _PhosphorControls(
                query: _controller.text,
                results: _results,
                onQuery: (String value) {
                  _controller.text = value;
                  _controller.selection = TextSelection.collapsed(offset: value.length);
                  _onSearchChanged(value);
                  _searchFocusNode.requestFocus();
                }),
          if (_design == LauncherDesign.phosphor ||
              _design == LauncherDesign.crt ||
              _design == LauncherDesign.toon ||
              _design == LauncherDesign.retro)
            Flexible(
                fit: FlexFit.loose,
                child: Padding(padding: const EdgeInsets.fromLTRB(12, 0, 12, 12), child: resultsContent))
          else if (_design == LauncherDesign.strata)
            Flexible(
                fit: FlexFit.loose,
                child: Padding(padding: const EdgeInsets.fromLTRB(3, 0, 3, 6), child: resultsContent))
          else if (_design == LauncherDesign.aurora)
            Flexible(
              fit: FlexFit.loose,
              child: Container(
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                  decoration: BoxDecoration(
                      color: AuroraTokens.background.withAlpha(70),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: AuroraTokens.border)),
                  child: resultsContent),
            )
          else
            resultsContent,
        ],
      );
      return Stack(children: <Widget>[layoutContent, resizeOverlay]);
    }

    return switch (_design) {
      LauncherDesign.anime => AnimeLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.aurora => AuroraLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.blueprint => BlueprintLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.capillary =>
        CapillaryLauncherFrame(child: buildBody(), resultCount: resultCount, queryController: _controller),
      LauncherDesign.classic => ClassicLauncherFrame(child: buildBody()),
      LauncherDesign.command => CommandLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.crt => CrtLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.cyber => CyberLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.fluent => FluentLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.glass => GlassLauncherFrame(child: buildBody()),
      LauncherDesign.liquidMetal => LiquidMetalLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.manga => MangaLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.manifesto => ManifestoLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.newCast => RaycastLauncherFrame(child: buildBody()),
      LauncherDesign.notion => NotionLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.omarchy => OmarchyLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.opticalGlass => OpticalGlassLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.orbit => OrbitLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.outrun => Outrun2LauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.phosphor => PhosphorLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.relay => RelayLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.retro => RetroLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.serene => SereneLauncherFrame(child: buildBody()),
      LauncherDesign.steam => SteamLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.strata => StrataLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.switchboard => SwitchboardLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.tech => TechLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.terminal => TerminalLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.terminal2 => Terminal2LauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.thermal => ThermalLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.toon => ToonLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.transit => TransitLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.tui => TuiLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.vector => VectorLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.windows98 => Windows98LauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.windowsXp => WindowsXpLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.zen => ZenLauncherFrame(child: buildBody(), resultCount: resultCount),
      LauncherDesign.matrix => MatrixLauncherFrame(
          searchChild: searchContent,
          resultsChild: Stack(children: <Widget>[resultsContent, resizeOverlay]),
          resultCount: resultCount,
        ),
    };
  }
}
