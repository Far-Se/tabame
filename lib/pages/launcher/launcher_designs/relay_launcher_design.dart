part of '../launcher_design_builder.dart';

class _RelaySearchBar extends StatefulWidget {
  const _RelaySearchBar({
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
  State<_RelaySearchBar> createState() => _RelaySearchBarState();
}

class _RelaySearchBarState extends State<_RelaySearchBar> with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  void _syncAnimation() {
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (widget.isSearching && !reduceMotion) {
      if (!_controller.isAnimating) _controller.repeat();
    } else if (_controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncAnimation();
  }

  @override
  void didUpdateWidget(_RelaySearchBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncAnimation();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final Color dim = RelayTokens.dim(isDark);
    return Container(
      color: RelayTokens.panel(isDark, widget.accent),
      padding: const EdgeInsets.fromLTRB(14, 9, 14, 6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          DragToMoveArea(
            child: Row(
              children: <Widget>[
                Text(
                  'RELAY / INPUT 01',
                  style: RelayTokens.channel(
                    fontSize: Design.baseFontSize + 1,
                    fontWeight: FontWeight.w600,
                    color: dim,
                    letterSpacing: 1.5,
                    height: 0.9,
                  ),
                ),
                const Spacer(),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 120),
                  child: Text(
                    widget.isSearching ? 'ROUTING' : 'RX READY',
                    key: ValueKey<bool>(widget.isSearching),
                    style: RelayTokens.channel(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.w600,
                      color: widget.isSearching ? widget.accent : dim,
                      letterSpacing: 1.4,
                      height: 0.9,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 5),
          Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: RelayTokens.raised(isDark, widget.accent),
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(color: RelayTokens.border(isDark, widget.accent)),
                ),
                child: widget.dragHandle,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Stack(
                  alignment: Alignment.centerRight,
                  children: <Widget>[
                    widget.textField,
                    if (widget.trailingBadge != null)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: widget.trailingBadge!,
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          SizedBox(
            width: double.infinity,
            height: 9,
            child: AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                return CustomPaint(
                  painter: _RelaySignalPainter(
                    color: widget.accent,
                    progress: widget.isSearching ? _controller.value : null,
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _RelaySignalPainter extends CustomPainter {
  const _RelaySignalPainter({required this.color, required this.progress});

  final Color color;
  final double? progress;

  @override
  void paint(Canvas canvas, Size size) {
    final double y = size.height / 2;
    final Paint rail = Paint()
      ..color = color.withAlpha(70)
      ..strokeWidth = 1;
    canvas.drawLine(Offset.zero.translate(0, y), Offset(size.width, y), rail);

    final Paint branch = Paint()
      ..color = color.withAlpha(45)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final double branchX = size.width * 0.72;
    final Path branchPath = Path()
      ..moveTo(branchX, y)
      ..lineTo(branchX + 7, y)
      ..lineTo(branchX + 12, 0.5)
      ..lineTo(size.width - 1, 0.5);
    canvas.drawPath(branchPath, branch);

    for (final double x in <double>[0, size.width * 0.34, size.width * 0.72, size.width - 1]) {
      canvas.drawRect(
        Rect.fromCenter(center: Offset(x, y), width: 3.5, height: 3.5),
        Paint()
          ..color = color.withAlpha(125)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }

    final double? signalProgress = progress;
    if (signalProgress != null) {
      final double x = signalProgress * size.width;
      canvas.drawCircle(Offset(x, y), 3.8, Paint()..color = color.withAlpha(35));
      canvas.drawCircle(Offset(x, y), 1.8, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(covariant _RelaySignalPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.progress != progress;
}

class RelayLauncherFrame extends StatelessWidget {
  const RelayLauncherFrame({
    super.key,
    required this.child,
    required this.surface,
    required this.accent,
    this.resultCount = 0,
    Color? onSurface,
  });

  final Widget child;
  final Color surface;
  final Color accent;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return LauncherTheme(
      data: const LauncherThemeData(design: LauncherDesign.relay),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.relay.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              if (Design.hasBackdrop) const StableBackdrop(),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _RelayBackplanePainter(color: accent, isDark: isDark)),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  child,
                  _RelayFooter(accent: accent, resultCount: resultCount, isDark: isDark),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RelayBackplanePainter extends CustomPainter {
  const _RelayBackplanePainter({required this.color, required this.isDark});

  final Color color;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint trace = Paint()
      ..color = color.withAlpha(isDark ? 13 : 10)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Paint port = Paint()
      ..color = color.withAlpha(isDark ? 25 : 20)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;

    for (double y = 92; y < size.height - 42; y += 58) {
      final Path path = Path()
        ..moveTo(size.width - 8, y)
        ..lineTo(size.width - 42, y)
        ..lineTo(size.width - 52, y + 10)
        ..lineTo(size.width - 88, y + 10);
      canvas.drawPath(path, trace);
      canvas.drawRect(
        Rect.fromCenter(center: Offset(size.width - 90, y + 10), width: 4, height: 4),
        port,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RelayBackplanePainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.isDark != isDark;
}

class RelayLauncherHeader extends StatelessWidget {
  const RelayLauncherHeader({super.key, required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 14, 4),
      child: Row(
        children: <Widget>[
          SizedBox(
            width: 34,
            height: 10,
            child: CustomPaint(painter: _RelayHeaderTracePainter(color: accent)),
          ),
          const SizedBox(width: 7),
          Text(
            'BUS / ${label.toUpperCase()}',
            style: RelayTokens.channel(
              fontSize: Design.baseFontSize + 1,
              fontWeight: FontWeight.w600,
              color: RelayTokens.foreground(isDark).withAlpha(210),
              letterSpacing: 1.4,
              height: 0.9,
            ),
          ),
          const Spacer(),
          Text(
            'AUTO',
            style: RelayTokens.channel(
              fontSize: Design.baseFontSize,
              fontWeight: FontWeight.w500,
              color: RelayTokens.dim(isDark),
              letterSpacing: 1.3,
              height: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class _RelayHeaderTracePainter extends CustomPainter {
  const _RelayHeaderTracePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color.withAlpha(150)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final Path path = Path()
      ..moveTo(1, size.height - 1)
      ..lineTo(10, size.height - 1)
      ..lineTo(18, 1)
      ..lineTo(size.width - 1, 1);
    canvas.drawPath(path, paint);
    canvas.drawRect(const Rect.fromLTWH(0, 5, 4, 4), paint);
  }

  @override
  bool shouldRepaint(covariant _RelayHeaderTracePainter oldDelegate) => oldDelegate.color != color;
}

class _RelayFooter extends StatelessWidget {
  const _RelayFooter({required this.accent, required this.resultCount, required this.isDark});

  final Color accent;
  final int resultCount;
  final bool isDark;

  Widget _hint(String key, String caption) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          key,
          style: RelayTokens.channel(
            fontSize: Design.baseFontSize + 1,
            color: accent,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.7,
            height: 0.9,
          ),
        ),
        const SizedBox(width: 3),
        Text(
          caption,
          style: RelayTokens.channel(
            fontSize: Design.baseFontSize + 1,
            color: RelayTokens.dim(isDark),
            fontWeight: FontWeight.w500,
            letterSpacing: 1.0,
            height: 0.9,
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 7, 14, 7),
      decoration: BoxDecoration(
        color: RelayTokens.panel(isDark, accent),
        border: Border(top: BorderSide(color: RelayTokens.border(isDark, accent))),
      ),
      child: Row(
        children: <Widget>[
          Container(width: 5, height: 5, color: accent),
          const SizedBox(width: 8),
          _hint('↵', 'OPEN'),
          const SizedBox(width: 14),
          _hint('→', 'ACTIONS'),
          const SizedBox(width: 14),
          _hint('ESC', 'CLOSE'),
          const Spacer(),
          Text(
            Globals.isLauncherPluginActive ? 'REMOTE LINK' : '${resultCount.toString().padLeft(2, '0')} ROUTES',
            style: RelayTokens.channel(
              fontSize: Design.baseFontSize + 1,
              color: RelayTokens.dim(isDark),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              height: 0.9,
            ),
          ),
          DateTimeWidget(
            padding: const EdgeInsets.only(left: 10),
            style: RelayTokens.channel(
              fontSize: Design.baseFontSize + 1,
              color: RelayTokens.dim(isDark),
              fontWeight: FontWeight.w600,
              letterSpacing: 1.1,
              height: 0.9,
            ),
          ),
        ],
      ),
    );
  }
}

class RelayEmptyState extends StatelessWidget {
  const RelayEmptyState({
    super.key,
    required this.isSearching,
    required this.hasQuery,
    required this.accent,
  });

  final bool isSearching;
  final bool hasQuery;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final String title = isSearching
        ? 'ROUTING SIGNAL'
        : hasQuery
            ? 'NO SIGNAL RETURNED'
            : 'OPEN A CHANNEL';
    final String subtitle = isSearching
        ? 'Polling connected sources…'
        : hasQuery
            ? 'Try a shorter name, file path, or launcher keyword.'
            : 'Type an app, file, bookmark, command, or plugin keyword.';

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            SizedBox(
              width: 52,
              height: 40,
              child: CustomPaint(
                painter: _RelayEmptyPainter(color: accent, active: isSearching),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: RelayTokens.channel(
                fontSize: Design.baseFontSize + 5,
                fontWeight: FontWeight.w600,
                color: RelayTokens.foreground(isDark),
                letterSpacing: 1.7,
                height: 0.95,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: RelayTokens.body(
                fontSize: Design.baseFontSize,
                fontWeight: FontWeight.w400,
                color: RelayTokens.dim(isDark),
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RelayEmptyPainter extends CustomPainter {
  const _RelayEmptyPainter({required this.color, required this.active});

  final Color color;
  final bool active;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color.withAlpha(active ? 180 : 95)
      ..strokeWidth = 1.3
      ..style = PaintingStyle.stroke;
    final Path path = Path()
      ..moveTo(1, size.height / 2)
      ..lineTo(14, size.height / 2)
      ..lineTo(22, 7)
      ..lineTo(size.width - 10, 7)
      ..lineTo(size.width - 2, size.height / 2);
    canvas.drawPath(path, line);
    canvas.drawRect(Rect.fromCenter(center: Offset(1, size.height / 2), width: 5, height: 5), line);
    canvas.drawRect(
      Rect.fromCenter(center: Offset(size.width - 2, size.height / 2), width: active ? 9 : 6, height: active ? 9 : 6),
      line,
    );
  }

  @override
  bool shouldRepaint(covariant _RelayEmptyPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.active != active;
}
