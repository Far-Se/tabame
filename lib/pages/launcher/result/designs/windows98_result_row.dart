part of '../result_row.dart';

extension _Windows98ResultRow on LauncherResultRow {
  Widget _buildWindows98(BuildContext context) {
    final Color rowText = isSelected ? Windows98Tokens.light : Windows98Tokens.foreground;
    final Color rowDim = isSelected ? const Color(0xFFE0E0FF) : Windows98Tokens.dim;

    return RepaintBoundary(
      child: _interactive(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          color: isSelected ? Windows98Tokens.selection : Colors.transparent,
          child: CustomPaint(
            foregroundPainter: isSelected ? const _Windows98FocusPainter() : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(6, 4, 6, 4),
              child: Row(
                children: <Widget>[
                  SizedBox(width: 30, height: 30, child: Center(child: icon)),
                  const SizedBox(width: 7),
                  Expanded(
                    child: content ??
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _titleText(Windows98Tokens.system(
                              fontSize: Design.baseFontSize + 1,
                              fontWeight: FontWeight.w400,
                              color: rowText,
                              height: 1.15,
                            )),
                            const SizedBox(height: 1),
                            _subtitleText(Windows98Tokens.system(
                              fontSize: Design.baseFontSize - 0.5,
                              color: rowDim,
                              height: 1.15,
                            )),
                          ],
                        ),
                  ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: badge,
                    ),
                  if (isSelected)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Icon(Icons.arrow_right, size: 16, color: Windows98Tokens.light),
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

class _Windows98FocusPainter extends CustomPainter {
  const _Windows98FocusPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Windows98Tokens.light
      ..strokeWidth = 1;
    const double inset = 2.5;
    const double dash = 2;
    const double gap = 2;

    for (double x = inset; x < size.width - inset; x += dash + gap) {
      canvas.drawLine(
        Offset(x, inset),
        Offset(math.min(x + dash, size.width - inset), inset),
        paint,
      );
      canvas.drawLine(
        Offset(x, size.height - inset),
        Offset(math.min(x + dash, size.width - inset), size.height - inset),
        paint,
      );
    }
    for (double y = inset; y < size.height - inset; y += dash + gap) {
      canvas.drawLine(
        Offset(inset, y),
        Offset(inset, math.min(y + dash, size.height - inset)),
        paint,
      );
      canvas.drawLine(
        Offset(size.width - inset, y),
        Offset(size.width - inset, math.min(y + dash, size.height - inset)),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _Windows98FocusPainter oldDelegate) => false;
}
