part of '../launcher_design_builder.dart';

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
              if (!Globals.isLauncherPluginActive) const Spacer(),
              if (!Globals.isLauncherPluginActive)
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
