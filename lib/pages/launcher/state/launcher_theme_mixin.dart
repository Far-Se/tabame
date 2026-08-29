part of '../../launcher.dart';

// ---------------------------------------------------------------------------
// Launcher theme construction
// ---------------------------------------------------------------------------

mixin _LauncherThemeMixin on _LauncherStateMembersMixin {
  ThemeData _buildDesignTheme({
    required ThemeData baseTheme,
    required bool isDark,
    required Color accent,
  }) {
    return switch (_design) {
      LauncherDesign.newCast => _copyDesignTheme(
          baseTheme,
          brightness: isDark ? Brightness.dark : Brightness.light,
          colorSchemeBrightness: isDark ? Brightness.dark : Brightness.light,
          surface: RaycastTokens.surface(isDark),
          onSurface: RaycastTokens.primary(isDark),
          primary: RaycastTokens.primary(isDark),
          highlightColor: RaycastTokens.selected(isDark),
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'Segoe UI Variable Text',
            fontFamilyFallback: const <String>['Segoe UI', 'Arial'],
            bodyColor: RaycastTokens.primary(isDark),
            displayColor: RaycastTokens.primary(isDark),
          ),
        ),
      LauncherDesign.windowsXp => _copyDesignTheme(
          baseTheme,
          surface: WindowsXpTokens.paper,
          onSurface: WindowsXpTokens.foreground,
          primary: WindowsXpTokens.selection,
          highlightColor: WindowsXpTokens.selection.withAlpha(34),
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'Tahoma',
            fontFamilyFallback: const <String>['Verdana', 'Segoe UI'],
            bodyColor: WindowsXpTokens.foreground,
            displayColor: WindowsXpTokens.foreground,
          ),
        ),
      LauncherDesign.windows98 => _copyDesignTheme(
          baseTheme,
          surface: Windows98Tokens.face,
          onSurface: Windows98Tokens.foreground,
          primary: Windows98Tokens.selection,
          highlightColor: Windows98Tokens.selection.withAlpha(34),
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'MS Sans Serif',
            fontFamilyFallback: const <String>['Tahoma', 'Segoe UI'],
            bodyColor: Windows98Tokens.foreground,
            displayColor: Windows98Tokens.foreground,
          ),
        ),
      LauncherDesign.notion => _copyDesignTheme(
          baseTheme,
          surface: NotionTokens.canvas(isDark),
          onSurface: NotionTokens.foreground(isDark),
          primary: NotionTokens.blue(isDark),
          highlightColor: NotionTokens.selection(isDark),
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'Segoe UI Variable Text',
            fontFamilyFallback: const <String>['Segoe UI'],
            bodyColor: NotionTokens.foreground(isDark),
            displayColor: NotionTokens.foreground(isDark),
          ),
        ),
      LauncherDesign.terminal => _copyDesignTheme(
          baseTheme,
          surface: TerminalTokens.bg(isDark),
          onSurface: TerminalTokens.fg(isDark),
          highlightColor: accent.withAlpha(38),
          textTheme: GoogleFonts.jetBrainsMonoTextTheme(baseTheme.textTheme).apply(
            bodyColor: TerminalTokens.fg(isDark),
            displayColor: TerminalTokens.fg(isDark),
          ),
        ),
      LauncherDesign.terminal2 => _copyDesignTheme(
          baseTheme,
          surface: Terminal2Tokens.bg(isDark),
          onSurface: Terminal2Tokens.fg(isDark),
          highlightColor: accent.withAlpha(38),
          textTheme: GoogleFonts.fragmentMonoTextTheme(baseTheme.textTheme).apply(
            bodyColor: Terminal2Tokens.fg(isDark),
            displayColor: Terminal2Tokens.fg(isDark),
          ),
        ),
      LauncherDesign.zen => _copyDesignTheme(
          baseTheme,
          surface: ZenTokens.bg(isDark),
          onSurface: ZenTokens.fg(isDark),
          highlightColor: accent.withAlpha(isDark ? 42 : 30),
          textTheme: GoogleFonts.quicksandTextTheme(baseTheme.textTheme).apply(
            bodyColor: ZenTokens.fg(isDark),
            displayColor: ZenTokens.fg(isDark),
          ),
        ),
      LauncherDesign.blueprint => _copyDesignTheme(
          baseTheme,
          surface: BlueprintTokens.bg(isDark),
          onSurface: BlueprintTokens.fg(isDark),
          highlightColor: accent.withAlpha(34),
          textTheme: GoogleFonts.chakraPetchTextTheme(baseTheme.textTheme).apply(
            bodyColor: BlueprintTokens.fg(isDark),
            displayColor: BlueprintTokens.fg(isDark),
          ),
        ),
      LauncherDesign.transit => _copyDesignTheme(
          baseTheme,
          surface: TransitTokens.bg(isDark),
          onSurface: TransitTokens.fg(isDark),
          highlightColor: accent.withAlpha(30),
          textTheme: GoogleFonts.overpassTextTheme(baseTheme.textTheme).apply(
            bodyColor: TransitTokens.fg(isDark),
            displayColor: TransitTokens.fg(isDark),
          ),
        ),
      LauncherDesign.fluent => _copyDesignTheme(
          baseTheme,
          surface: FluentTokens.bg(isDark),
          onSurface: FluentTokens.fg(isDark),
          highlightColor: accent.withAlpha(28),
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'Segoe UI Variable Text',
            fontFamilyFallback: const <String>['Segoe UI'],
            bodyColor: FluentTokens.fg(isDark),
            displayColor: FluentTokens.fg(isDark),
          ),
        ),
      LauncherDesign.manifesto => _copyDesignTheme(
          baseTheme,
          surface: ManifestoTokens.bg(isDark),
          onSurface: ManifestoTokens.fg(isDark),
          highlightColor: accent.withAlpha(32),
          textTheme: baseTheme.textTheme.apply(
            fontFamily: 'Segoe UI Variable Text',
            fontFamilyFallback: const <String>['Segoe UI'],
            bodyColor: ManifestoTokens.fg(isDark),
            displayColor: ManifestoTokens.fg(isDark),
          ),
        ),
      LauncherDesign.orbit => _copyDesignTheme(
          baseTheme,
          surface: OrbitTokens.bg(isDark),
          onSurface: OrbitTokens.fg(isDark),
          highlightColor: accent.withAlpha(30),
          textTheme: GoogleFonts.spaceGroteskTextTheme(baseTheme.textTheme).apply(
            bodyColor: OrbitTokens.fg(isDark),
            displayColor: OrbitTokens.fg(isDark),
          ),
        ),
      LauncherDesign.relay => _copyDesignTheme(
          baseTheme,
          surface: RelayTokens.canvas(isDark, accent),
          onSurface: RelayTokens.foreground(isDark),
          highlightColor: accent.withAlpha(30),
          textTheme: GoogleFonts.encodeSansTextTheme(baseTheme.textTheme).apply(
            bodyColor: RelayTokens.foreground(isDark),
            displayColor: RelayTokens.foreground(isDark),
          ),
        ),
      LauncherDesign.switchboard => _copyDesignTheme(
          baseTheme,
          surface: SwitchboardTokens.canvas(isDark),
          onSurface: SwitchboardTokens.foreground(isDark),
          highlightColor: accent.withAlpha(28),
          textTheme: GoogleFonts.publicSansTextTheme(baseTheme.textTheme).apply(
            bodyColor: SwitchboardTokens.foreground(isDark),
            displayColor: SwitchboardTokens.foreground(isDark),
          ),
        ),
      LauncherDesign.glass => baseTheme.copyWith(
          textTheme: GoogleFonts.interTextTheme(baseTheme.textTheme),
        ),
      _ => baseTheme,
    };
  }

  ThemeData _copyDesignTheme(
    ThemeData baseTheme, {
    required Color surface,
    required Color onSurface,
    required Color highlightColor,
    Color? primary,
    TextTheme? textTheme,
    Brightness? brightness,
    Brightness? colorSchemeBrightness,
  }) {
    return baseTheme.copyWith(
      brightness: brightness,
      colorScheme: baseTheme.colorScheme.copyWith(
        brightness: colorSchemeBrightness,
        surface: surface,
        onSurface: onSurface,
        primary: primary,
      ),
      highlightColor: highlightColor,
      textTheme: textTheme,
    );
  }
}
