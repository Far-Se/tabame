part of '../../launcher.dart';

mixin _LauncherThemeMixin on _LauncherStateMembersMixin {
  ThemeData _buildDesignTheme({required ThemeData baseTheme, required LauncherPalette palette}) {
    final TextTheme textTheme = switch (_design) {
      LauncherDesign.thermal => GoogleFonts.hankenGroteskTextTheme(baseTheme.textTheme),
      LauncherDesign.capillary => GoogleFonts.commissionerTextTheme(baseTheme.textTheme),
      LauncherDesign.opticalGlass => GoogleFonts.mulishTextTheme(baseTheme.textTheme),
      LauncherDesign.liquidMetal => GoogleFonts.barlowTextTheme(baseTheme.textTheme),
      LauncherDesign.crt => baseTheme.textTheme.apply(fontFamily: 'Consolas'),
      LauncherDesign.toon => baseTheme.textTheme.apply(
          fontFamily: 'Barlow Condensed',
          fontFamilyFallback: const <String>['Segoe UI'],
        ),
      LauncherDesign.retro => RetroTokens.resultTextTheme(baseTheme.textTheme),
      LauncherDesign.phosphor => baseTheme.textTheme.apply(fontFamily: 'Consolas'),
      LauncherDesign.strata => baseTheme.textTheme.apply(fontFamily: 'Segoe UI'),
      LauncherDesign.aurora => baseTheme.textTheme.apply(fontFamily: 'Segoe UI'),
      LauncherDesign.tui => baseTheme.textTheme.apply(
          fontFamily: 'Consolas',
          fontFamilyFallback: const <String>['Lucida Console', 'monospace'],
        ),
      LauncherDesign.omarchy => GoogleFonts.inconsolataTextTheme(baseTheme.textTheme),
      LauncherDesign.newCast => baseTheme.textTheme.apply(
          fontFamily: 'Segoe UI Variable Text',
          fontFamilyFallback: const <String>['Segoe UI', 'Arial'],
        ),
      LauncherDesign.windowsXp => baseTheme.textTheme.apply(
          fontFamily: 'Tahoma',
          fontFamilyFallback: const <String>['Verdana', 'Segoe UI'],
        ),
      LauncherDesign.windows98 => baseTheme.textTheme.apply(
          fontFamily: 'MS Sans Serif',
          fontFamilyFallback: const <String>['Tahoma', 'Segoe UI'],
        ),
      LauncherDesign.notion => baseTheme.textTheme.apply(
          fontFamily: 'Segoe UI Variable Text',
          fontFamilyFallback: const <String>['Segoe UI'],
        ),
      LauncherDesign.terminal => GoogleFonts.jetBrainsMonoTextTheme(baseTheme.textTheme),
      LauncherDesign.terminal2 => GoogleFonts.fragmentMonoTextTheme(baseTheme.textTheme),
      LauncherDesign.zen => GoogleFonts.quicksandTextTheme(baseTheme.textTheme),
      LauncherDesign.blueprint => GoogleFonts.chakraPetchTextTheme(baseTheme.textTheme),
      LauncherDesign.transit => GoogleFonts.overpassTextTheme(baseTheme.textTheme),
      LauncherDesign.fluent => baseTheme.textTheme.apply(
          fontFamily: 'Segoe UI Variable Text',
          fontFamilyFallback: const <String>['Segoe UI'],
        ),
      LauncherDesign.manifesto => baseTheme.textTheme.apply(
          fontFamily: 'Segoe UI Variable Text',
          fontFamilyFallback: const <String>['Segoe UI'],
        ),
      LauncherDesign.orbit => GoogleFonts.spaceGroteskTextTheme(baseTheme.textTheme),
      LauncherDesign.relay => GoogleFonts.encodeSansTextTheme(baseTheme.textTheme),
      LauncherDesign.switchboard => GoogleFonts.publicSansTextTheme(baseTheme.textTheme),
      LauncherDesign.glass => GoogleFonts.interTextTheme(baseTheme.textTheme),
      _ => baseTheme.textTheme,
    };
    return palette.applyTo(baseTheme, textTheme: textTheme);
  }
}
