part of '../launcher_design_builder.dart';

BoxDecoration _blueprintOuterDecoration(Color surface, Color accent) {
  // Drafting sheet — [surface] is the forced blueprint palette. Sharp
  // corners, a crisp ink edge, and a flat paper shadow (no glow).
  return BoxDecoration(
    borderRadius: BorderRadius.circular(Design.borderRadius),
    color: surface,
    border: Border.all(color: accent.withAlpha(110)),
    boxShadow: <BoxShadow>[
      BoxShadow(
        color: Colors.black.withAlpha(90),
        blurRadius: 26,
        spreadRadius: -6,
        offset: const Offset(0, 12),
      ),
    ],
  );
}

class _BlueprintSearchBar extends StatelessWidget {
  const _BlueprintSearchBar(this.content);

  final _LauncherSearchBarContent content;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final TextStyle microLabel = BlueprintTokens.tech(
      fontSize: Design.baseFontSize - 3.5,
      color: onSurface.withAlpha(110),
      fontWeight: FontWeight.w600,
      letterSpacing: 1.8,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        if (user.launcherShowTitlebar)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 9, 16, 0),
            child: Row(
              children: <Widget>[
                Text('DWG NO. TB-001', style: microLabel),
                const Spacer(),
                Text('SEARCH FIELD', style: microLabel),
              ],
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 3, 14, 0),
          child: Row(
            children: <Widget>[
              content.dragHandle,
              const SizedBox(width: 10),
              Expanded(
                child: _LauncherSearchField(content),
              ),
              if (content.isSearching)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: SizedBox(
                    width: 13,
                    height: 13,
                    child: CircularProgressIndicator(strokeWidth: 1.5, color: accent.withAlpha(170)),
                  ),
                ),
            ],
          ),
        ),
        // Drafting ruler — the measured underline of the input.
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 2, 14, 6),
          child: SizedBox(
            height: 9,
            width: double.infinity,
            child: CustomPaint(painter: _BlueprintRulerPainter(color: accent)),
          ),
        ),
      ],
    );
  }
}

/// A ruler edge: a baseline with graduation ticks — taller every 5th, tallest
/// every 10th — like the scale printed along a drafting rule.
class _BlueprintRulerPainter extends CustomPainter {
  const _BlueprintRulerPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint line = Paint()
      ..color = color.withAlpha(150)
      ..strokeWidth = 1;
    canvas.drawLine(const Offset(0, 0.5), Offset(size.width, 0.5), line);

    final Paint tick = Paint()
      ..color = color.withAlpha(110)
      ..strokeWidth = 1;
    int i = 0;
    for (double x = 0.5; x <= size.width; x += 6) {
      final double h = i % 10 == 0 ? 7 : (i % 5 == 0 ? 5 : 3);
      canvas.drawLine(Offset(x, 1), Offset(x, 1 + h), tick);
      i++;
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintRulerPainter oldDelegate) => oldDelegate.color != color;
}

/// The drafting sheet — grid paper, an inner sheet border with corner
/// registration crosses, and an engineering title block along the bottom.
class BlueprintLauncherFrame extends StatelessWidget {
  const BlueprintLauncherFrame({super.key, required this.child, this.resultCount = 0});

  final Widget child;
  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color surface = Theme.of(context).colorScheme.surface;
    final Color accent = LauncherTheme.accentOf(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 360),
      decoration: _blueprintOuterDecoration(surface, accent),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Design.borderRadius),
        child: Stack(
          children: <Widget>[
            if (Design.hasBackdrop) const StableBackdrop(),
            // Grid paper + inner sheet border + corner registration marks.
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(painter: _BlueprintSheetPainter(ink: accent)),
              ),
            ),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                child,
                _BlueprintTitleBlock(resultCount: resultCount),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Grid paper with a heavier line every 5th cell, an inner sheet border, and
/// small "+" registration crosses at its corners.
class _BlueprintSheetPainter extends CustomPainter {
  const _BlueprintSheetPainter({required this.ink});

  final Color ink;

  @override
  void paint(Canvas canvas, Size size) {
    const double cell = 14;
    final Paint minor = Paint()
      ..color = ink.withAlpha(14)
      ..strokeWidth = 1;
    final Paint major = Paint()
      ..color = ink.withAlpha(26)
      ..strokeWidth = 1;

    int i = 0;
    for (double x = 0.5; x <= size.width; x += cell) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), i % 5 == 0 ? major : minor);
      i++;
    }
    i = 0;
    for (double y = 0.5; y <= size.height; y += cell) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), i % 5 == 0 ? major : minor);
      i++;
    }

    // Inner sheet border.
    const double inset = 5;
    final Paint border = Paint()
      ..color = ink.withAlpha(80)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final Rect sheet = Rect.fromLTWH(inset + 0.5, inset + 0.5, size.width - 2 * inset - 1, size.height - 2 * inset - 1);
    canvas.drawRect(sheet, border);

    // Registration crosses at the sheet corners.
    final Paint cross = Paint()
      ..color = ink.withAlpha(140)
      ..strokeWidth = 1;
    const double arm = 4;
    for (final Offset c in <Offset>[sheet.topLeft, sheet.topRight, sheet.bottomLeft, sheet.bottomRight]) {
      canvas.drawLine(Offset(c.dx - arm, c.dy), Offset(c.dx + arm, c.dy), cross);
      canvas.drawLine(Offset(c.dx, c.dy - arm), Offset(c.dx, c.dy + arm), cross);
    }
  }

  @override
  bool shouldRepaint(covariant _BlueprintSheetPainter oldDelegate) => oldDelegate.ink != ink;
}

/// The engineering title block: labeled cells separated by ruled dividers.
class _BlueprintTitleBlock extends StatelessWidget {
  const _BlueprintTitleBlock({required this.resultCount});

  final int resultCount;

  @override
  Widget build(BuildContext context) {
    final Color accent = LauncherTheme.accentOf(context);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    Widget buildCell(String label, String value, {bool expand = false}) {
      final Widget content = Padding(
        padding: const EdgeInsets.fromLTRB(10, 4, 10, 9),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              label,
              style: BlueprintTokens.tech(
                fontSize: Design.baseFontSize - 4,
                color: onSurface.withAlpha(110),
                fontWeight: FontWeight.w600,
                letterSpacing: 1.6,
                height: 1.1,
              ),
            ),
            const SizedBox(height: 1),
            value == "TIME"
                ? DateTimeWidget(
                    style: BlueprintTokens.tech(
                    fontSize: Design.baseFontSize - 1.5,
                    color: onSurface.withAlpha(220),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.8,
                    height: 1.1,
                  ))
                : Text(
                    value,
                    maxLines: 1,
                    overflow: TextOverflow.clip,
                    style: BlueprintTokens.tech(
                      fontSize: Design.baseFontSize - 1.5,
                      color: onSurface.withAlpha(220),
                      fontWeight: FontWeight.w600,
                      letterSpacing: 0.8,
                      height: 1.1,
                    ),
                  ),
          ],
        ),
      );
      return expand ? Expanded(child: content) : content;
    }

    final Widget divider = Container(width: 1, color: accent.withAlpha(80));
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: accent.withAlpha(80))),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            buildCell('DRAWING', 'TABAME — QUICK LAUNCH', expand: true),
            divider,
            buildCell('ENTER', 'OPEN'),
            divider,
            buildCell('ESC', 'CLOSE'),
            divider,
            Globals.isLauncherPluginActive
                ? buildCell('TPY', "PLUGIN")
                : buildCell('QTY', resultCount.toString().padLeft(2, '0')),
            divider,
            buildCell('TIME', 'TIME'),
          ],
        ),
      ),
    );
  }
}
