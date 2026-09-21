part of '../result_row.dart';

extension _BlueprintResultRow on LauncherResultRow {
  Widget _buildBlueprint(BuildContext context) {
    final int animMs = isRepeating ? 50 : 160;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOut;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: curve,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(18) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
          child: CustomPaint(
            foregroundPainter: isSelected ? _BlueprintCalloutPainter(color: accent) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              child: Row(
                children: <Widget>[
                  // Part-reference balloon.
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: isSelected ? accent.withAlpha(200) : onSurface.withAlpha(70),
                        width: 1.2,
                      ),
                    ),
                    child: icon,
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: content ??
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _titleText(BlueprintTokens.tech(
                              fontSize: Design.baseFontSize + 2,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? onSurface : onSurface.withAlpha(220),
                              letterSpacing: 0.4,
                              height: 1.2,
                            )),
                            _subtitleText(BlueprintTokens.tech(
                              fontSize: Design.baseFontSize - 0.5,
                              fontWeight: FontWeight.w400,
                              color: onSurface.withAlpha(isSelected ? 255 : 190),
                              letterSpacing: 0.3,
                              height: 1.2,
                            )),
                          ],
                        ),
                  ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: badge,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BlueprintCalloutPainter extends CustomPainter {
  const _BlueprintCalloutPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = (Offset.zero & size).deflate(0.5);

    // Dashed outline.
    final Paint dashPaint = Paint()
      ..color = color.withAlpha(150)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    const double dash = 5;
    const double gap = 4;
    final Path outline = Path()..addRect(rect);
    for (final ui.PathMetric metric in outline.computeMetrics()) {
      double d = 0;
      while (d < metric.length) {
        canvas.drawPath(metric.extractPath(d, d + dash), dashPaint);
        d += dash + gap;
      }
    }

    // Solid L-shaped ticks at the corners.
    final Paint tick = Paint()
      ..color = color.withAlpha(230)
      ..strokeWidth = 1.5;
    const double arm = 6;
    // Top-left.
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(arm, 0), tick);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, arm), tick);
    // Top-right.
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-arm, 0), tick);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, arm), tick);
    // Bottom-left.
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(arm, 0), tick);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -arm), tick);
    // Bottom-right.
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-arm, 0), tick);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -arm), tick);
  }

  @override
  bool shouldRepaint(covariant _BlueprintCalloutPainter oldDelegate) => oldDelegate.color != color;
}
