part of '../launcher_design_builder.dart';

class RetroSearchBar extends StatelessWidget {
  const RetroSearchBar({
    super.key,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 12, 12),
        decoration: BoxDecoration(
          color: RetroTokens.panel,
          border: Border(bottom: BorderSide(color: RetroTokens.border)),
        ),
        child: Row(
          children: <Widget>[
            dragHandle,
            const SizedBox(width: 12),
            Text('>', style: RetroTokens.label(size: 12, color: RetroTokens.accent)),
            const SizedBox(width: 10),
            Expanded(child: textField),
            if (trailingBadge != null) ...<Widget>[
              const SizedBox(width: 8),
              trailingBadge!,
            ],
            if (isSearching)
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                    strokeWidth: 1.5,
                    color: RetroTokens.accent,
                  ),
                ),
              ),
          ],
        ),
      );
}

class RetroLauncherFrame extends StatelessWidget {
  const RetroLauncherFrame({
    super.key,
    required this.surface,
    required this.accent,
    required this.onSurface,
    required this.resultCount,
    required this.child,
  });

  final Color surface;
  final Color accent;
  final Color onSurface;
  final int resultCount;
  final Widget child;

  @override
  Widget build(BuildContext context) => LauncherTheme(
        data: const LauncherThemeData(design: LauncherDesign.retro),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: LauncherDesign.retro.outerDecoration(surface: surface, accent: accent),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: RetroSurface(
              background: RetroTokens.background,
              accent: RetroTokens.accent,
              child: ColoredBox(
                color: RetroTokens.background,
                child: Stack(
                  fit: StackFit.passthrough,
                  children: <Widget>[
                    Positioned.fill(
                      child: IgnorePointer(
                        child: CustomPaint(
                          painter: _RetroBackdropPainter(
                            border: RetroTokens.border,
                            accent: RetroTokens.accent,
                            cyan: RetroTokens.cyan,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          SizedBox(
                            height: 30,
                            child: Row(
                              children: <Widget>[
                                Expanded(
                                  child: DragToMoveArea(
                                    child: Row(
                                      children: <Widget>[
                                        CustomPaint(
                                          size: Size(34, 22),
                                          painter: _RetroCabinetPainter(
                                            accent: RetroTokens.accent,
                                            cyan: RetroTokens.cyan,
                                          ),
                                        ),
                                        const SizedBox(width: 9),
                                        Flexible(
                                          child: Text(
                                            'TABAME // RETRO',
                                            overflow: TextOverflow.ellipsis,
                                            style: RetroTokens.label(
                                              size: 8,
                                              color: onSurface,
                                              spacing: 0.3,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Text('1P', style: RetroTokens.label(size: 7, color: RetroTokens.cyan)),
                                IconButton(
                                  tooltip: 'Hide launcher',
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                                  onPressed: windowManager.hide,
                                  icon: Text('X', style: RetroTokens.label(size: 8, color: RetroTokens.dim)),
                                ),
                              ],
                            ),
                          ),
                          Flexible(fit: FlexFit.loose, child: child),
                          Container(
                            padding: const EdgeInsets.fromLTRB(8, 10, 8, 3),
                            decoration: BoxDecoration(
                              border: Border(top: BorderSide(color: RetroTokens.border)),
                            ),
                            child: Row(
                              children: <Widget>[
                                Container(width: 7, height: 7, color: RetroTokens.cyan),
                                const SizedBox(width: 7),
                                Text('READY', style: RetroTokens.label(size: 7, color: RetroTokens.cyan)),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: SingleChildScrollView(
                                    scrollDirection: Axis.horizontal,
                                    child: Text(
                                      'UP/DN MOVE   ENTER SELECT   CTRL+P PREVIEW',
                                      style: RetroTokens.pixel(size: 15, color: RetroTokens.dim),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Text(
                                  '${resultCount.toString().padLeft(2, '0')} ITEMS',
                                  style: RetroTokens.label(size: 7, color: RetroTokens.yellow),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
}

class RetroSectionHeader extends StatelessWidget {
  const RetroSectionHeader({super.key, required this.label, required this.accent});

  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
        child: Row(
          children: <Widget>[
            Text('SECTOR //', style: RetroTokens.label(size: 7, color: accent)),
            const SizedBox(width: 8),
            Expanded(child: Divider(height: 1, color: accent.withAlpha(90))),
            const SizedBox(width: 8),
            Text(label.toUpperCase(), style: RetroTokens.pixel(size: 14, color: RetroTokens.dim)),
          ],
        ),
      );
}

class _RetroBackdropPainter extends CustomPainter {
  const _RetroBackdropPainter({required this.border, required this.accent, required this.cyan});

  final Color border;
  final Color accent;
  final Color cyan;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint grid = Paint()
      ..color = border.withAlpha(34)
      ..style = PaintingStyle.fill
      ..isAntiAlias = false;
    for (double x = 20; x < size.width; x += 32) {
      canvas.drawRect(Rect.fromLTWH(x, 0, 1, size.height), grid);
    }
    for (double y = 18; y < size.height; y += 24) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, 1), grid);
    }

    final Paint horizon = Paint()
      ..color = accent.withAlpha(18)
      ..isAntiAlias = false;
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.72, size.width, 2), horizon);
    canvas.drawRect(Rect.fromLTWH(0, size.height * 0.78, size.width, 1), horizon);

    final Paint pixels = Paint()
      ..color = cyan.withAlpha(90)
      ..isAntiAlias = false;
    for (final Offset point in <Offset>[
      const Offset(18, 14),
      const Offset(54, 44),
      const Offset(92, 22),
      const Offset(140, 66),
      const Offset(210, 18),
      const Offset(278, 52),
    ]) {
      if (point.dx < size.width - 3 && point.dy < size.height - 3) {
        canvas.drawRect(Rect.fromLTWH(point.dx, point.dy, 2, 2), pixels);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RetroBackdropPainter oldDelegate) =>
      border != oldDelegate.border || accent != oldDelegate.accent || cyan != oldDelegate.cyan;
}

class _RetroCabinetPainter extends CustomPainter {
  const _RetroCabinetPainter({required this.accent, required this.cyan});

  final Color accent;
  final Color cyan;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint pink = Paint()
      ..color = accent
      ..isAntiAlias = false;
    final Paint blue = Paint()
      ..color = cyan
      ..isAntiAlias = false;

    canvas.drawRect(const Rect.fromLTWH(2, 5, 5, 5), pink);
    canvas.drawRect(const Rect.fromLTWH(7, 2, 5, 5), pink);
    canvas.drawRect(const Rect.fromLTWH(12, 5, 5, 5), pink);
    canvas.drawRect(const Rect.fromLTWH(17, 8, 5, 5), blue);
    canvas.drawRect(const Rect.fromLTWH(22, 11, 5, 5), blue);
    canvas.drawRect(const Rect.fromLTWH(27, 14, 5, 5), blue);
    canvas.drawRect(const Rect.fromLTWH(7, 16, 5, 5), pink);
    canvas.drawRect(const Rect.fromLTWH(12, 13, 5, 5), pink);
  }

  @override
  bool shouldRepaint(covariant _RetroCabinetPainter oldDelegate) =>
      accent != oldDelegate.accent || cyan != oldDelegate.cyan;
}
