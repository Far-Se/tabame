part of '../launcher_design_builder.dart';

class _BlueprintSearchBar extends StatelessWidget {
  const _BlueprintSearchBar({
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
    final TextStyle microLabel = BlueprintTokens.tech(
      fontSize: Design.baseFontSize - 3.5,
      color: onSurface.withAlpha(110),
      fontWeight: FontWeight.w600,
      letterSpacing: 1.8,
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        // Micro title-block labels above the field.
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
              dragHandle,
              const SizedBox(width: 10),
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
  const BlueprintLauncherFrame({
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
      data: const LauncherThemeData(design: LauncherDesign.blueprint),
      child: Container(
        constraints: const BoxConstraints(minHeight: 360),
        decoration: LauncherDesign.blueprint.outerDecoration(surface: surface, accent: accent),
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
                  _BlueprintTitleBlock(accent: accent, onSurface: onSurface, resultCount: resultCount),
                ],
              ),
            ],
          ),
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
  const _BlueprintTitleBlock({
    required this.accent,
    required this.onSurface,
    required this.resultCount,
  });

  final Color accent;
  final Color onSurface;
  final int resultCount;

  Widget _cell(String label, String value, {bool expand = false}) {
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
                  // padding: const EdgeInsets.only(left: 10),
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

  @override
  Widget build(BuildContext context) {
    final Widget divider = Container(width: 1, color: accent.withAlpha(80));
    return Container(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: accent.withAlpha(80))),
      ),
      child: IntrinsicHeight(
        child: Row(
          children: <Widget>[
            _cell('DRAWING', 'TABAME — QUICK LAUNCH', expand: true),
            divider,
            _cell('ENTER', 'OPEN'),
            divider,
            _cell('ESC', 'CLOSE'),
            divider,
            Globals.isLauncherPluginActive
                ? _cell('TPY', "PLUGIN")
                : _cell('QTY', resultCount.toString().padLeft(2, '0')),
            divider,
            _cell('TIME', 'TIME'),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Transit (metro map) — destination-sign search bar topped by the line-color
// band, a station-sign frame, and a platform-strip footer. Results render as
// stations on a continuous route line (see LauncherResultRow._buildTransit).
// ---------------------------------------------------------------------------
