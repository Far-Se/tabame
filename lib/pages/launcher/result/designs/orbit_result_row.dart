part of '../result_row.dart';

extension _OrbitResultRow on LauncherResultRow {
  Widget _buildOrbit(BuildContext context) {
    final int animMs = isRepeating ? 45 : 140;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOut;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: curve,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(18) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ).withLauncherCorners(),
          child: CustomPaint(
            foregroundPainter: isSelected ? _OrbitReticlePainter(color: accent) : null,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
              child: Row(
                children: <Widget>[
                  // Track marker — a dim cross that locks into a chevron.
                  SizedBox(
                    width: 15,
                    child: Text(
                      isSelected ? '▸' : '+',
                      textAlign: TextAlign.center,
                      style: OrbitTokens.tele(
                        fontSize: Design.baseFontSize + (isSelected ? 1 : 0),
                        color: isSelected ? accent : onSurface.withAlpha(70),
                        fontWeight: FontWeight.w700,
                        height: 1.0,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Instrument chip.
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: accent.withAlpha(isSelected ? 24 : 10),
                      borderRadius: BorderRadius.circular(3),
                      border: Border.all(color: accent.withAlpha(isSelected ? 90 : 36)),
                    ).withLauncherCorners(),
                    child: icon,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: content ??
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _titleText(OrbitTokens.disp(
                              fontSize: Design.baseFontSize + 2,
                              fontWeight: FontWeight.w600,
                              color: isSelected ? onSurface : onSurface.withAlpha(220),
                              letterSpacing: 0.1,
                              height: 1.2,
                            )),
                            const SizedBox(height: 1),
                            _subtitleText(OrbitTokens.tele(
                              fontSize: Design.baseFontSize + 0.5,
                              color: isSelected ? onSurface.withAlpha(180) : OrbitTokens.dim(isDark),
                              // letterSpacing: 0.1,
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
                  // Lock readout — only on the locked row.
                  AnimatedSize(
                    duration: Duration(milliseconds: animMs),
                    curve: curve,
                    child: isSelected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 8),
                            child: Text(
                              '[ LOCK ]',
                              style: OrbitTokens.tele(
                                fontSize: Design.baseFontSize - 2,
                                color: accent.withAlpha(220),
                                fontWeight: FontWeight.w700,
                                letterSpacing: 1.0,
                                height: 1.0,
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
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

class _OrbitReticlePainter extends CustomPainter {
  const _OrbitReticlePainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Rect rect = (Offset.zero & size).deflate(1);
    final Paint bracket = Paint()
      ..color = color.withAlpha(230)
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.square;
    const double arm = 8;
    // Top-left.
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(arm, 0), bracket);
    canvas.drawLine(rect.topLeft, rect.topLeft + const Offset(0, arm), bracket);
    // Top-right.
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(-arm, 0), bracket);
    canvas.drawLine(rect.topRight, rect.topRight + const Offset(0, arm), bracket);
    // Bottom-left.
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(arm, 0), bracket);
    canvas.drawLine(rect.bottomLeft, rect.bottomLeft + const Offset(0, -arm), bracket);
    // Bottom-right.
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(-arm, 0), bracket);
    canvas.drawLine(rect.bottomRight, rect.bottomRight + const Offset(0, -arm), bracket);
  }

  @override
  bool shouldRepaint(covariant _OrbitReticlePainter oldDelegate) => oldDelegate.color != color;
}
