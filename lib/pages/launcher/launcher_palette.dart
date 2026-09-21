part of 'launcher_design.dart';

/// Colors shared by the launcher and its dialogs. Brightness follows the
/// resolved background, including palettes supplied by the user.
@immutable
class LauncherPalette {
  LauncherPalette._({
    required this.surface,
    required this.onSurface,
    required this.accent,
    required this.dim,
    Color? primary,
    Color? highlightColor,
    Color? modalSurface,
    Color? modalAccent,
  })  : brightness = ThemeData.estimateBrightnessForColor(surface),
        primary = primary ?? accent,
        highlightColor = highlightColor ?? accent.withAlpha(30),
        modalSurface = modalSurface ?? surface,
        modalAccent = modalAccent ?? accent;

  final Brightness brightness;
  final Color surface;
  final Color onSurface;
  final Color accent;
  final Color dim;
  final Color highlightColor;

  /// Material primary and dialog chrome can intentionally differ from the
  /// launcher accent and canvas (for example Raycast and Windows XP).
  final Color primary;
  final Color modalSurface;
  final Color modalAccent;

  bool get isDark => brightness == Brightness.dark;

  factory LauncherPalette.resolve(LauncherDesign design, {required Brightness brightness}) {
    final bool isDark = brightness == Brightness.dark;
    final ThemeColors colors = user.launcherThemeColors;
    final CapillaryTokens capillary = CapillaryTokens.resolve(isDark);
    return switch (design) {
      LauncherDesign.thermal => LauncherPalette._(
          surface: ThermalTokens.background,
          accent: ThermalTokens.accent,
          onSurface: ThermalTokens.foreground,
          dim: ThermalTokens.dim,
          highlightColor: ThermalTokens.rust,
        ),
      LauncherDesign.capillary => LauncherPalette._(
          surface: capillary.background,
          accent: capillary.accent,
          onSurface: capillary.foreground,
          dim: capillary.dim,
        ),
      LauncherDesign.opticalGlass => LauncherPalette._(
          surface: OpticalGlassTokens.background,
          accent: OpticalGlassTokens.accent,
          onSurface: OpticalGlassTokens.foreground,
          dim: OpticalGlassTokens.dim,
        ),
      LauncherDesign.liquidMetal => LauncherPalette._(
          surface: LiquidMetalTokens.background,
          accent: LiquidMetalTokens.accent,
          onSurface: LiquidMetalTokens.foreground,
          dim: LiquidMetalTokens.dim,
        ),
      LauncherDesign.crt => LauncherPalette._(
          surface: CrtTokens.background,
          accent: CrtTokens.accent,
          onSurface: CrtTokens.foreground,
          dim: CrtTokens.dim,
        ),
      LauncherDesign.toon => LauncherPalette._(
          surface: ToonTokens.background,
          accent: ToonTokens.orange,
          onSurface: ToonTokens.foreground,
          dim: ToonTokens.dim,
          highlightColor: ToonTokens.orange.withAlpha(42),
        ),
      LauncherDesign.retro => LauncherPalette._(
          surface: RetroTokens.background,
          accent: RetroTokens.accent,
          onSurface: RetroTokens.foreground,
          dim: RetroTokens.dim,
        ),
      LauncherDesign.phosphor => LauncherPalette._(
          surface: PhosphorTokens.background,
          accent: PhosphorTokens.accent,
          onSurface: PhosphorTokens.foreground,
          dim: PhosphorTokens.dim,
        ),
      LauncherDesign.strata => LauncherPalette._(
          surface: StrataTokens.background,
          accent: StrataTokens.accent,
          onSurface: StrataTokens.foreground,
          dim: StrataTokens.dim,
        ),
      LauncherDesign.aurora => LauncherPalette._(
          surface: AuroraTokens.background,
          accent: AuroraTokens.accent,
          onSurface: AuroraTokens.foreground,
          dim: AuroraTokens.dim,
        ),
      LauncherDesign.tui => LauncherPalette._(
          surface: TuiTokens.background,
          accent: TuiTokens.accent,
          onSurface: TuiTokens.foreground,
          dim: TuiTokens.dim,
          highlightColor: TuiTokens.foreground,
        ),
      LauncherDesign.omarchy => LauncherPalette._(
          surface: OmarchyTokens.bg,
          accent: OmarchyTokens.accent,
          onSurface: OmarchyTokens.fg,
          dim: OmarchyTokens.dim,
          highlightColor: OmarchyTokens.selected,
        ),
      LauncherDesign.terminal => LauncherPalette._(
          surface: TerminalTokens.bg(isDark),
          accent: colors.accent,
          onSurface: TerminalTokens.fg(isDark),
          dim: TerminalTokens.dim(isDark),
          highlightColor: colors.accent.withAlpha(38),
        ),
      LauncherDesign.terminal2 => LauncherPalette._(
          surface: Terminal2Tokens.bg(isDark),
          accent: colors.accent,
          onSurface: Terminal2Tokens.fg(isDark),
          dim: Terminal2Tokens.dim(isDark),
          highlightColor: colors.accent.withAlpha(38),
        ),
      LauncherDesign.zen => LauncherPalette._(
          surface: ZenTokens.bg(isDark),
          accent: ZenTokens.accent(isDark),
          onSurface: ZenTokens.fg(isDark),
          dim: ZenTokens.dim(isDark),
          primary: colors.accent,
          highlightColor: ZenTokens.accent(isDark).withAlpha(isDark ? 42 : 30),
        ),
      LauncherDesign.blueprint => LauncherPalette._(
          surface: BlueprintTokens.bg(isDark),
          accent: BlueprintTokens.accent(isDark),
          onSurface: BlueprintTokens.fg(isDark),
          dim: BlueprintTokens.dim(isDark),
          primary: colors.accent,
          highlightColor: BlueprintTokens.accent(isDark).withAlpha(34),
        ),
      LauncherDesign.transit => LauncherPalette._(
          surface: TransitTokens.bg(isDark),
          accent: colors.accent,
          onSurface: TransitTokens.fg(isDark),
          dim: TransitTokens.dim(isDark),
        ),
      LauncherDesign.fluent => LauncherPalette._(
          surface: FluentTokens.bg(isDark),
          accent: colors.accent,
          onSurface: FluentTokens.fg(isDark),
          dim: FluentTokens.dim(isDark),
          highlightColor: colors.accent.withAlpha(28),
        ),
      LauncherDesign.manifesto => LauncherPalette._(
          surface: ManifestoTokens.bg(isDark),
          accent: ManifestoTokens.accent(isDark),
          onSurface: ManifestoTokens.fg(isDark),
          dim: ManifestoTokens.dim(isDark),
          primary: colors.accent,
          highlightColor: ManifestoTokens.accent(isDark).withAlpha(32),
        ),
      LauncherDesign.orbit => LauncherPalette._(
          surface: OrbitTokens.bg(isDark),
          accent: colors.accent,
          onSurface: OrbitTokens.fg(isDark),
          dim: OrbitTokens.dim(isDark),
        ),
      LauncherDesign.windowsXp => LauncherPalette._(
          surface: WindowsXpTokens.paper,
          accent: WindowsXpTokens.selection,
          onSurface: WindowsXpTokens.foreground,
          dim: WindowsXpTokens.dim,
          modalSurface: WindowsXpTokens.surface,
          highlightColor: WindowsXpTokens.selection.withAlpha(34),
        ),
      LauncherDesign.windows98 => LauncherPalette._(
          surface: Windows98Tokens.face,
          accent: Windows98Tokens.selection,
          onSurface: Windows98Tokens.foreground,
          dim: Windows98Tokens.dim,
          highlightColor: Windows98Tokens.selection.withAlpha(34),
        ),
      LauncherDesign.notion => LauncherPalette._(
          surface: NotionTokens.canvas(isDark),
          accent: NotionTokens.blue(isDark),
          onSurface: NotionTokens.foreground(isDark),
          dim: NotionTokens.dim(isDark),
          highlightColor: NotionTokens.selection(isDark),
        ),
      LauncherDesign.switchboard => LauncherPalette._(
          surface: SwitchboardTokens.canvas(isDark),
          accent: colors.accent,
          onSurface: SwitchboardTokens.foreground(isDark),
          dim: SwitchboardTokens.dim(isDark),
          modalSurface: SwitchboardTokens.panel(isDark),
          highlightColor: colors.accent.withAlpha(28),
        ),
      LauncherDesign.relay => LauncherPalette._(
          surface: RelayTokens.canvas(isDark, colors.accent),
          accent: colors.accent,
          onSurface: RelayTokens.foreground(isDark),
          dim: RelayTokens.dim(isDark),
          modalSurface: RelayTokens.panel(isDark, colors.accent),
        ),
      LauncherDesign.newCast => LauncherPalette._(
          surface: RaycastTokens.surface(isDark),
          accent: colors.accent,
          onSurface: RaycastTokens.primary(isDark),
          dim: RaycastTokens.dim(isDark),
          modalAccent: RaycastTokens.primary(isDark),
          primary: RaycastTokens.primary(isDark),
          highlightColor: RaycastTokens.selected(isDark),
        ),
      LauncherDesign.classic ||
      LauncherDesign.serene ||
      LauncherDesign.command ||
      LauncherDesign.glass ||
      LauncherDesign.anime ||
      LauncherDesign.tech ||
      LauncherDesign.vector ||
      LauncherDesign.outrun ||
      LauncherDesign.matrix ||
      LauncherDesign.steam ||
      LauncherDesign.cyber ||
      LauncherDesign.manga =>
        LauncherPalette._(
          surface: colors.background,
          onSurface: colors.text,
          accent: colors.accent,
          dim: colors.text.withAlpha(120),
        ),
    };
  }

  ThemeData applyTo(ThemeData baseTheme, {required TextTheme textTheme}) => baseTheme.copyWith(
        brightness: brightness,
        colorScheme: baseTheme.colorScheme.copyWith(
          brightness: brightness,
          surface: surface,
          onSurface: onSurface,
          primary: primary,
        ),
        highlightColor: highlightColor,
        textTheme: textTheme.apply(bodyColor: onSurface, displayColor: onSurface),
      );
}
