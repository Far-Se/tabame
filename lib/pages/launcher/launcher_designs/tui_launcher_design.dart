part of '../launcher_design_builder.dart';

class _TuiSearchBar extends StatelessWidget {
  const _TuiSearchBar({required this.textField, required this.trailingBadge, required this.isSearching});

  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: <Widget>[
          DragToMoveArea(child: Text(r'C:\Tabame>', style: TuiTokens.mono())),
          Expanded(child: textField),
          if (isSearching) const Padding(padding: EdgeInsets.only(left: 8), child: _TuiSearchSpinner()),
        ]),
        if (trailingBadge != null) Padding(padding: const EdgeInsets.only(top: 4), child: trailingBadge!),
      ]),
    );
  }
}

class _TuiSearchSpinner extends StatefulWidget {
  const _TuiSearchSpinner();

  @override
  State<_TuiSearchSpinner> createState() => _TuiSearchSpinnerState();
}

class _TuiSearchSpinnerState extends State<_TuiSearchSpinner> with SingleTickerProviderStateMixin {
  static const List<String> _frames = <String>['⣾', '⣽', '⣻', '⢿', '⡿', '⣟', '⣯', '⣷'];
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 480),
  );
  late final Animation<int> _frame = StepTween(begin: 0, end: _frames.length).animate(_controller);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) {
      _controller.stop();
      _controller.value = 0;
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      label: 'Searching...',
      child: ExcludeSemantics(
        child: SizedBox(
          width: 16,
          child: AnimatedBuilder(
            animation: _frame,
            builder: (BuildContext context, Widget? child) => Text(
              _frames[_frame.value % _frames.length],
              textAlign: TextAlign.center,
              style: TuiTokens.mono(color: TuiTokens.dim),
            ),
          ),
        ),
      ),
    );
  }
}

/// Console presentation only: input is still handled by the shared launcher.
class TuiLauncherFrame extends StatelessWidget {
  const TuiLauncherFrame(
      {super.key,
      required this.child,
      required this.surface,
      required this.accent,
      required this.onSurface,
      this.resultCount = 0});

  final Widget child;
  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.tui),
      child: Container(
        decoration: LauncherDesign.tui.outerDecoration(surface: surface, accent: accent),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Container(
              decoration: BoxDecoration(
                color: Color.alphaBlend(onSurface.withValues(alpha: 0.1), surface),
                border: Border(bottom: BorderSide(color: TuiTokens.border)),
              ),
              child: Row(children: <Widget>[
                Expanded(
                    child: DragToMoveArea(
                        child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
                  child: Row(children: <Widget>[
                    Text('>_', style: TuiTokens.mono(fontSize: 13)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: Text('Tabame - Command Prompt',
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontFamily: 'Segoe UI', fontSize: 12, color: onSurface))),
                  ]),
                ))),
                IconButton(
                  tooltip: 'Close (Esc)',
                  onPressed: QuickMenuFunctions.hideQuickMenu,
                  constraints: const BoxConstraints(minWidth: 40, minHeight: 30),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  icon: Text('×', style: TuiTokens.mono(fontSize: 18)),
                  style: IconButton.styleFrom(shape: const RoundedRectangleBorder()),
                ),
              ]),
            ),
            // Padding(
            //   padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
            //   child: Text('Tabame Launcher\nSearch applications, files, and commands.', style: TuiTokens.mono()),
            // ),
            const SizedBox(height: 10),
            child,
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                Text(Globals.isLauncherPluginActive ? "    PLUGIN" : '    $resultCount item(s)',
                    style: TuiTokens.mono()),
                const SizedBox(height: 8),
                Wrap(spacing: 16, runSpacing: 4, children: <Widget>[
                  for (final String hint in <String>[
                    '[Up/Down] Select',
                    '[Enter] Open',
                    '[Ctrl+K] Actions',
                    '[Esc] Close'
                  ])
                    Text(hint, style: TuiTokens.mono(fontSize: Design.baseFontSize + 3, color: TuiTokens.dim)),
                ]),
              ]),
            ),
          ],
        ),
      ),
    );
  }
}
