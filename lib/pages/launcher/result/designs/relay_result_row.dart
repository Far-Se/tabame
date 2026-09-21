part of '../result_row.dart';

extension _RelayResultRow on LauncherResultRow {
  Widget _buildRelay(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final bool reduceMotion = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final int animMs = reduceMotion || isRepeating ? 45 : 130;
    final Color foreground = RelayTokens.foreground(isDark);
    final Color dim = RelayTokens.dim(isDark);

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: Curves.easeOutQuart,
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: isSelected ? RelayTokens.raised(isDark, accent) : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
            border: Border.all(
              color: isSelected ? RelayTokens.border(isDark, accent) : Colors.transparent,
            ),
          ),
          child: CustomPaint(
            foregroundPainter: _RelayRowPainter(
              color: accent,
              selected: isSelected,
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              child: Row(
                children: <Widget>[
                  const SizedBox(width: 25),
                  AnimatedContainer(
                    duration: Duration(milliseconds: animMs),
                    curve: Curves.easeOutQuart,
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: isSelected ? RelayTokens.panel(isDark, accent) : RelayTokens.raised(isDark, accent),
                      borderRadius: BorderRadius.circular(2),
                      border: Border.all(
                        color: isSelected ? accent.withAlpha(120) : RelayTokens.border(isDark, accent),
                      ),
                    ),
                    child: icon,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: content ??
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _titleText(RelayTokens.body(
                              fontSize: Design.baseFontSize + 1.5,
                              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                              color: foreground,
                              height: 1.2,
                            )),
                            const SizedBox(height: 1),
                            _subtitleText(RelayTokens.body(
                              fontSize: Design.baseFontSize - 0.5,
                              fontWeight: FontWeight.w400,
                              color: isSelected ? foreground.withAlpha(175) : dim,
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
                  SizedBox(
                    width: 36,
                    child: AnimatedOpacity(
                      duration: Duration(milliseconds: animMs),
                      opacity: isSelected ? 1 : 0,
                      child: Text(
                        'LINK',
                        textAlign: TextAlign.right,
                        style: RelayTokens.channel(
                          fontSize: Design.baseFontSize + 1,
                          fontWeight: FontWeight.w600,
                          color: accent,
                          letterSpacing: 1.1,
                          height: 0.9,
                        ),
                      ),
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
}

class _RelayRowPainter extends CustomPainter {
  const _RelayRowPainter({required this.color, required this.selected});

  final Color color;
  final bool selected;

  @override
  void paint(Canvas canvas, Size size) {
    const double busX = 16;
    final double centerY = size.height / 2;
    final Paint bus = Paint()
      ..color = color.withAlpha(selected ? 160 : 56)
      ..strokeWidth = selected ? 1.5 : 1;
    canvas.drawLine(const Offset(busX, 0), Offset(busX, size.height), bus);

    final Paint lead = Paint()
      ..color = color.withAlpha(selected ? 220 : 85)
      ..strokeWidth = selected ? 1.5 : 1
      ..style = PaintingStyle.stroke;
    final Path path = Path()
      ..moveTo(busX, centerY)
      ..lineTo(busX + 6, centerY)
      ..lineTo(busX + 11, centerY - 5)
      ..lineTo(busX + 18, centerY - 5);
    canvas.drawPath(path, lead);

    final Rect port = Rect.fromCenter(
      center: Offset(busX, centerY),
      width: selected ? 9 : 6,
      height: selected ? 9 : 6,
    );
    canvas.drawRect(
      port,
      Paint()
        ..color = selected ? color : Colors.transparent
        ..style = selected ? PaintingStyle.fill : PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    if (selected) {
      canvas.drawRect(
        port.inflate(3),
        Paint()
          ..color = color.withAlpha(75)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _RelayRowPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.selected != selected;
}
