part of '../launcher_design_builder.dart';

class _ManifestoSearchBar extends StatelessWidget {
  const _ManifestoSearchBar({
    required this.accent,
    required this.onSurface,
    required this.dragHandle,
    required this.textField,
    required this.trailingBadge,
    required this.isSearching,
  });

  final Color accent;
  final Color onSurface;
  final Widget dragHandle;
  final Widget textField;
  final Widget? trailingBadge;
  final bool isSearching;

  @override
  Widget build(BuildContext context) {
    final Color paper = Theme.of(context).colorScheme.surface;
    return Container(
      height: 56,
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: onSurface, width: 2))),
      child: Row(
        children: <Widget>[
          Container(
            width: 72,
            color: onSurface,
            child: Stack(
              children: <Widget>[
                Positioned(
                  left: 8,
                  top: 7,
                  child: Text(
                    'RUN',
                    style: ManifestoTokens.display(
                      fontSize: Design.baseFontSize + 7,
                      fontWeight: FontWeight.w700,
                      color: paper,
                      letterSpacing: -0.5,
                      height: 1,
                    ),
                  ),
                ),
                Positioned(
                  left: 8,
                  bottom: 5,
                  child: Text(
                    'TABAME / 02',
                    style: ManifestoTokens.display(
                      fontSize: Design.baseFontSize - 2.5,
                      fontWeight: FontWeight.w600,
                      color: paper.withAlpha(170),
                      letterSpacing: 1,
                    ),
                  ),
                ),
                Positioned(
                    right: 6,
                    top: 7,
                    child: ColorFiltered(colorFilter: ColorFilter.mode(paper, BlendMode.srcIn), child: dragHandle)),
              ],
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 3, 6, 3),
              child: Stack(
                alignment: Alignment.centerRight,
                children: <Widget>[
                  textField,
                  if (trailingBadge != null) trailingBadge!,
                ],
              ),
            ),
          ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutQuart,
            width: isSearching ? 18 : 10,
            height: double.infinity,
            color: accent,
            alignment: Alignment.center,
            child: isSearching
                ? SizedBox(
                    width: 8,
                    height: 8,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: onSurface),
                  )
                : null,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Classic search bar
// ---------------------------------------------------------------------------

class ManifestoLauncherFrame extends StatelessWidget {
  const ManifestoLauncherFrame({
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
      data: const LauncherThemeData(design: LauncherDesign.manifesto),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.manifesto.outerDecoration(surface: surface, accent: accent),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(Design.borderRadius),
          child: Stack(
            children: <Widget>[
              if (Design.hasBackdrop) const StableBackdrop(),
              Positioned.fill(
                child: IgnorePointer(
                  child: CustomPaint(painter: _ManifestoGridPainter(color: onSurface.withAlpha(18))),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 22),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    child,
                    _ManifestoFooter(
                      paper: surface,
                      ink: onSurface,
                      accent: accent,
                      resultCount: resultCount,
                    ),
                  ],
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                bottom: 0,
                width: 22,
                child: _ManifestoIssueRail(paper: surface, ink: onSurface, accent: accent),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ManifestoIssueRail extends StatelessWidget {
  const _ManifestoIssueRail({required this.paper, required this.ink, required this.accent});

  final Color paper;
  final Color ink;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: accent,
      child: Column(
        children: <Widget>[
          const SizedBox(height: 9),
          RotatedBox(
            quarterTurns: 1,
            child: Text(
              'TABAME / SEARCH MANIFESTO / ISSUE 02',
              style: ManifestoTokens.display(
                fontSize: Design.baseFontSize - 2,
                fontWeight: FontWeight.w700,
                color: accent.computeLuminance() > 0.55 ? ink : paper,
                letterSpacing: 1.4,
              ),
            ),
          ),
          const Spacer(),
          Container(width: 8, height: 8, color: ink),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

class _ManifestoFooter extends StatelessWidget {
  const _ManifestoFooter({
    required this.paper,
    required this.ink,
    required this.accent,
    required this.resultCount,
  });

  final Color paper;
  final Color ink;
  final Color accent;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    Text key(String glyph, String label) {
      return Text.rich(
        TextSpan(
          children: <InlineSpan>[
            TextSpan(text: '$glyph ', style: const TextStyle(fontWeight: FontWeight.w700)),
            TextSpan(text: label),
          ],
        ),
        style: ManifestoTokens.body(
          fontSize: Design.baseFontSize - 1,
          color: paper,
          letterSpacing: 0.3,
        ),
      );
    }

    return Container(
      height: 30,
      color: ink,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: Row(
        children: <Widget>[
          Container(width: 7, height: 7, color: accent),
          const SizedBox(width: 8),
          key('↵', 'OPEN'),
          const SizedBox(width: 14),
          key('→', 'ACTIONS'),
          const SizedBox(width: 14),
          key('ESC', 'CLOSE'),
          const Spacer(),
          Text(
            Globals.isLauncherPluginActive ? "PLUGIN" : '${resultCount.toString().padLeft(2, '0')} ENTRIES',
            style: ManifestoTokens.display(
              fontSize: Design.baseFontSize - 0.5,
              fontWeight: FontWeight.w700,
              color: paper,
              letterSpacing: 1.4,
            ),
          ),
          DateTimeWidget(
            padding: const EdgeInsets.only(left: 10),
            style: ManifestoTokens.display(
              fontSize: Design.baseFontSize - 0.5,
              fontWeight: FontWeight.w700,
              color: paper,
              letterSpacing: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

class _ManifestoGridPainter extends CustomPainter {
  const _ManifestoGridPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..strokeWidth = 0.5;
    for (double y = 56; y < size.height; y += 20) {
      canvas.drawLine(Offset(22, y), Offset(size.width, y), paint);
    }
    for (double x = 98; x < size.width; x += 116) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    final Paint mark = Paint()
      ..color = color.withAlpha(110)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(5, 8), const Offset(17, 8), mark);
    canvas.drawLine(const Offset(11, 2), const Offset(11, 14), mark);
  }

  @override
  bool shouldRepaint(covariant _ManifestoGridPainter oldDelegate) => oldDelegate.color != color;
}

// ---------------------------------------------------------------------------
// Orbit (spacecraft guidance HUD) — telemetry-labelled search field with an
// animated acquisition scope, a graduation-tick underline, a range-ring frame,
// and a telemetry strip as the footer. Results render as track lines with a
// corner-bracket lock reticle (see LauncherResultRow._buildOrbit).
// ---------------------------------------------------------------------------
