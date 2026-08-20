part of '../launcher_design_builder.dart';

class _Terminal2SearchBar extends StatelessWidget {
  const _Terminal2SearchBar({
    required this.accent,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dim = Terminal2Tokens.dim(isDark);

    return Container(
      margin: const EdgeInsets.fromLTRB(10, 8, 10, 6),
      decoration: BoxDecoration(
        color: Terminal2Tokens.chrome(isDark),
        border: Border.all(color: dim.withAlpha(75)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 5, 8, 4),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.fromLTRB(5, 3, 5, 2),
                  color: accent,
                  child: Text(
                    'QUERY',
                    style: Terminal2Tokens.label(
                      fontSize: Design.baseFontSize - 2,
                      fontWeight: FontWeight.w700,
                      color: Terminal2Tokens.bg(isDark),
                      letterSpacing: 1.1,
                      height: 1,
                    ),
                  ),
                ),
                Expanded(child: Container(height: 1, color: dim.withAlpha(60))),
                const SizedBox(width: 8),
                Text(
                  isSearching ? 'RESOLVING' : 'INSERT',
                  style: Terminal2Tokens.label(
                    fontSize: Design.baseFontSize - 2,
                    fontWeight: FontWeight.w600,
                    color: isSearching ? Terminal2Tokens.amber(isDark) : dim,
                    letterSpacing: 1,
                    height: 1,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 1, color: dim.withAlpha(48)),
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 5),
            child: Row(
              children: <Widget>[
                Tooltip(
                  message: 'Drag launcher',
                  child: SizedBox(width: 18, height: 22, child: Center(child: dragHandle)),
                ),
                Text(
                  'tabame@local',
                  style: Terminal2Tokens.mono(
                    fontSize: Design.baseFontSize,
                    fontWeight: FontWeight.w600,
                    color: accent,
                  ),
                ),
                Text(
                  ':~/launcher',
                  style: Terminal2Tokens.mono(
                    fontSize: Design.baseFontSize,
                    color: Terminal2Tokens.amber(isDark),
                  ),
                ),
                Text(
                  r'$ ',
                  style: Terminal2Tokens.mono(
                    fontSize: Design.baseFontSize + 1,
                    fontWeight: FontWeight.w600,
                    color: Terminal2Tokens.fg(isDark),
                  ),
                ),
                Expanded(
                  child: Stack(
                    alignment: Alignment.centerRight,
                    children: <Widget>[
                      textField,
                      if (trailingBadge != null)
                        Padding(padding: const EdgeInsets.only(right: 4), child: trailingBadge!),
                    ],
                  ),
                ),
                if (isSearching)
                  Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: _Terminal2Spinner(color: accent),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class Terminal2LauncherHeader extends StatelessWidget {
  const Terminal2LauncherHeader({super.key, required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dim = Terminal2Tokens.dim(isDark);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 4, 10, 2),
      child: Row(
        children: <Widget>[
          Text(
            '+--',
            style: Terminal2Tokens.mono(
              fontSize: Design.baseFontSize - 1,
              color: dim,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: Terminal2Tokens.label(
              fontSize: Design.baseFontSize - 1.5,
              color: Terminal2Tokens.amber(isDark),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(width: 7),
          Expanded(child: Container(height: 1, color: dim.withAlpha(65))),
          const SizedBox(width: 7),
          Text(
            'STDOUT',
            style: Terminal2Tokens.label(
              fontSize: Design.baseFontSize - 2,
              color: accent.withAlpha(190),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }
}

class _Terminal2Spinner extends StatefulWidget {
  const _Terminal2Spinner({required this.color});

  final Color color;

  @override
  State<_Terminal2Spinner> createState() => _Terminal2SpinnerState();
}

class _Terminal2SpinnerState extends State<_Terminal2Spinner> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (BuildContext context, Widget? child) {
        const List<String> frames = <String>['|', '/', '-', '\\'];
        return SizedBox(
          width: 10,
          child: Text(
            frames[(_controller.value * frames.length).floor() % frames.length],
            style: Terminal2Tokens.mono(
              fontSize: Design.baseFontSize + 1,
              fontWeight: FontWeight.w600,
              color: widget.color,
              height: 1,
            ),
          ),
        );
      },
    );
  }
}

/// The second-generation compact operator shell with flat panes and keyboard-first status chrome.
class Terminal2LauncherFrame extends StatelessWidget {
  const Terminal2LauncherFrame({
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
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.terminal2),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.terminal2.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(2),
          child: Stack(
            children: <Widget>[
              if (Design.hasBackdrop) const StableBackdrop(),
              ColoredBox(
                color: surface.withAlpha(Design.hasBackdrop ? 224 : 255),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    _Terminal2TitleBar(accent: accent, isDark: isDark),
                    child,
                    _Terminal2StatusBar(accent: accent, resultCount: resultCount, isDark: isDark),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Terminal2TitleBar extends StatelessWidget {
  const _Terminal2TitleBar({required this.accent, required this.isDark});

  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color dim = Terminal2Tokens.dim(isDark);
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (DragStartDetails _) => windowManager.startDragging(),
      child: Container(
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Terminal2Tokens.chrome(isDark),
          border: Border(bottom: BorderSide(color: dim.withAlpha(72))),
        ),
        child: Row(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 3),
              color: accent,
              child: Text(
                'TABAME',
                style: Terminal2Tokens.label(
                  fontSize: Design.baseFontSize - 1,
                  fontWeight: FontWeight.w700,
                  color: Terminal2Tokens.bg(isDark),
                  letterSpacing: 1.4,
                  height: 1,
                ),
              ),
            ),
            const SizedBox(width: 9),
            Text(
              '// COMMAND LAUNCHER',
              style: Terminal2Tokens.label(
                fontSize: Design.baseFontSize - 1.5,
                fontWeight: FontWeight.w500,
                color: dim,
                letterSpacing: 0.9,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: Container(height: 1, color: dim.withAlpha(55))),
            const SizedBox(width: 10),
            Container(width: 6, height: 6, color: accent),
            const SizedBox(width: 6),
            Text(
              'LOCAL / READY',
              style: Terminal2Tokens.label(
                fontSize: Design.baseFontSize - 2,
                fontWeight: FontWeight.w600,
                color: accent,
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(width: 10),
            _Terminal2CloseButton(isDark: isDark),
          ],
        ),
      ),
    );
  }
}

class _Terminal2CloseButton extends StatelessWidget {
  const _Terminal2CloseButton({required this.isDark});

  final bool isDark;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close launcher',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: QuickMenuFunctions.hideQuickMenu,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
            child: Text(
              '[x]',
              style: Terminal2Tokens.mono(
                fontSize: Design.baseFontSize - 1,
                fontWeight: FontWeight.w600,
                color: Terminal2Tokens.dim(isDark),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Terminal2StatusBar extends StatelessWidget {
  const _Terminal2StatusBar({required this.accent, required this.resultCount, required this.isDark});

  final Color accent;
  final int resultCount;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final Color dim = Terminal2Tokens.dim(isDark);
    final TextStyle key = Terminal2Tokens.mono(
      fontSize: Design.baseFontSize - 1.5,
      color: Terminal2Tokens.fg(isDark),
      fontWeight: FontWeight.w600,
    );
    final TextStyle label = Terminal2Tokens.mono(
      fontSize: Design.baseFontSize - 1.5,
      color: dim,
    );

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: Terminal2Tokens.chrome(isDark),
        border: Border(top: BorderSide(color: dim.withAlpha(72))),
      ),
      child: Row(
        children: <Widget>[
          Container(
            height: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            alignment: Alignment.center,
            color: accent,
            child: Text(
              Globals.isLauncherPluginActive ? 'PLUGIN' : 'NORMAL',
              style: Terminal2Tokens.label(
                fontSize: Design.baseFontSize - 2,
                fontWeight: FontWeight.w700,
                color: Terminal2Tokens.bg(isDark),
                letterSpacing: 0.9,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Text('up/dn', style: key),
          Text(' move  ', style: label),
          Text('enter', style: key),
          Text(' open  ', style: label),
          Text('ctrl+k', style: key),
          Text(' actions  ', style: label),
          Text('esc', style: key),
          Text(' close', style: label),
          const Spacer(),
          Text(
            '${resultCount.toString().padLeft(2, '0')} MATCHES',
            style: Terminal2Tokens.label(
              fontSize: Design.baseFontSize - 2,
              color: Terminal2Tokens.amber(isDark),
              fontWeight: FontWeight.w600,
              letterSpacing: 0.8,
            ),
          ),
          DateTimeWidget(
            padding: const EdgeInsets.only(left: 12, right: 10),
            style: Terminal2Tokens.mono(
              fontSize: Design.baseFontSize - 1.5,
              color: dim,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
