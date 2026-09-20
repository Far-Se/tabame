part of '../launcher_design_builder.dart';

BoxDecoration _commandOuterDecoration(Color surface, Color accent) {
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
}

class _CommandSearchBar extends StatelessWidget {
  const _CommandSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
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
                content.dragHandle,
                const SizedBox(width: 8),
                Expanded(
                  child: _LauncherSearchField(content),
                ),
                if (content.isSearching)
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

class CommandLauncherFrame extends StatelessWidget {
  const CommandLauncherFrame({super.key, required this.child, this.resultCount = 0});

  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color accent = LauncherTheme.accentOf(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 360),
      decoration: _commandOuterDecoration(surface, accent),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
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
                _CommandFooter(resultCount: resultCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CommandFooter extends StatelessWidget {
  const _CommandFooter({required this.resultCount});

  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Divider(height: 1, thickness: 1, color: onSurface.withAlpha(16)),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
          child: Row(
            children: <Widget>[
              const _KbdHint(label: '↵', action: 'open'),
              const SizedBox(width: 12),
              const _KbdHint(label: '→', action: 'actions'),
              const SizedBox(width: 12),
              const _KbdHint(label: 'esc', action: 'close'),
              const Spacer(),
              Text(
                Globals.isLauncherPluginActive ? "PLUGIN" : (resultCount == 1 ? '1 result' : '$resultCount results'),
                style: TextStyle(
                  fontSize: Design.baseFontSize - 1,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.4,
                  color: onSurface.withAlpha(120),
                ),
              ),
              DateTimeWidget(
                  padding: const EdgeInsets.only(left: 10),
                  style: TextStyle(
                    fontSize: Design.baseFontSize - 1,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.4,
                    color: onSurface.withAlpha(120),
                  )),
            ],
          ),
        ),
      ],
    );
  }
}

class _KbdHint extends StatelessWidget {
  const _KbdHint({required this.label, required this.action});

  final String label;
  final String action;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
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
