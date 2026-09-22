part of '../launcher_design_builder.dart';

class _LauncherSectionHeader extends StatelessWidget {
  const _LauncherSectionHeader({required this.design, required this.label, this.accent});

  final LauncherDesign design;
  final String label;

  // Action dialogs have their own resolved palette outside LauncherTheme.
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final Color accent = this.accent ?? LauncherTheme.accentOf(context);
    switch (design) {
      case LauncherDesign.satin:
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 6),
          child: Text(label, style: SatinTokens.font(size: 11, color: SatinTokens.dim, weight: FontWeight.w600)),
        );
      case LauncherDesign.thermal:
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 6),
          child: Text(label, style: ThermalTokens.font(size: 11, color: ThermalTokens.dim)),
        );
      case LauncherDesign.capillary:
        final CapillaryTokens capillary = CapillaryTokens.of(context);
        return Padding(
          padding: const EdgeInsets.fromLTRB(18, 10, 18, 5),
          child: Text(label, style: capillary.font(size: 11, color: capillary.dim, weight: FontWeight.w600)),
        );
      case LauncherDesign.opticalGlass:
        return Padding(
            padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
            child: Text(label,
                style: OpticalGlassTokens.font(size: 11, weight: FontWeight.w600, color: OpticalGlassTokens.dim)));
      case LauncherDesign.liquidMetal:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
          child: Text(label.toUpperCase(),
              style: LiquidMetalTokens.font(size: 10, color: LiquidMetalTokens.dim, spacing: 1.5)),
        );
      case LauncherDesign.crt:
      case LauncherDesign.phosphor:
        return const SizedBox.shrink();
      case LauncherDesign.toon:
        return Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 16, 5),
          child: Row(
            children: <Widget>[
              Icon(Icons.bolt_rounded, size: 15, color: ToonTokens.orange),
              const SizedBox(width: 7),
              Text(
                label.toUpperCase(),
                style: ToonTokens.font(size: 11, color: ToonTokens.cream, spacing: 1.4, weight: FontWeight.w700),
              ),
              const SizedBox(width: 10),
              Expanded(child: Container(height: 2, color: ToonTokens.orange.withAlpha(90))),
              const SizedBox(width: 8),
              Text('INK', style: ToonTokens.font(size: 10, color: ToonTokens.red, spacing: 1.1)),
            ],
          ),
        );
      case LauncherDesign.retro:
        return RetroSectionHeader(label: label, accent: accent);
      case LauncherDesign.strata:
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Text(label, style: StrataTokens.font(color: StrataTokens.dim)));
      case LauncherDesign.aurora:
        return Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 5),
            child: Row(children: <Widget>[
              Text(label.toUpperCase(), style: AuroraTokens.font(size: 11, color: AuroraTokens.dim, spacing: 1.8)),
              const SizedBox(width: 12),
              const Expanded(child: Divider(color: AuroraTokens.border, height: 1)),
            ]));

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
      case LauncherDesign.outrun:
        return Outrun2LauncherHeader(label: label, accent: accent);
      case LauncherDesign.matrix:
        return MatrixLauncherHeader(label: label, accent: accent);
      case LauncherDesign.steam:
        return SteamLauncherHeader(label: label, accent: accent);
      case LauncherDesign.cyber:
        return CyberLauncherHeader(label: label, accent: accent);
      case LauncherDesign.manga:
        return MangaLauncherHeader(label: label, accent: accent);
      case LauncherDesign.windowsXp:
        return WindowsXpLauncherHeader(label: label);
      case LauncherDesign.windows98:
        return Windows98LauncherHeader(label: label);
      case LauncherDesign.notion:
        return NotionLauncherHeader(label: label);
      case LauncherDesign.switchboard:
        return SwitchboardLauncherHeader(label: label, accent: accent);
      case LauncherDesign.relay:
        return RelayLauncherHeader(label: label, accent: accent);
      case LauncherDesign.newCast:
        final bool isDark = Theme.of(context).brightness == Brightness.dark;
        return Padding(
          padding: const EdgeInsets.only(left: 16, top: 8, bottom: 6),
          child: Text(
            (label == 'Results' ? 'Suggestions' : label).toUpperCase(),
            style: RaycastTokens.ui(
              fontSize: 11,
              color: RaycastTokens.dim(isDark),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.25,
              height: 1.1,
            ),
          ),
        );
      case LauncherDesign.terminal2:
        return Terminal2LauncherHeader(label: label, accent: accent);
      case LauncherDesign.omarchy:
        return OmarchyLauncherHeader(label: label, accent: accent);
      case LauncherDesign.tui:
        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
          child: Text(' $label', style: TuiTokens.mono(color: TuiTokens.dim)),
        );
    }
  }
}
