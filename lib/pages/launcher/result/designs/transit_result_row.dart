part of '../result_row.dart';

extension _TransitResultRow on LauncherResultRow {
  Widget _buildTransit(BuildContext context) {
    final int animMs = isRepeating ? 50 : 170;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutCubic;
    final Color surface = Theme.of(context).colorScheme.surface;

    // Route-line geometry: plate margin (6) + plate padding (8) + half of the
    // 26px marker slot centers the line under the station roundel.
    const double lineLeft = 6 + 8 + 13 - 1.5;

    return RepaintBoundary(
      child: _interactive(
        child: Stack(
          children: <Widget>[
            // The route line — runs edge-to-edge so neighbouring rows join
            // into one continuous metro line.
            Positioned(
              left: lineLeft,
              top: 0,
              bottom: 0,
              child: Container(width: 3, color: accent),
            ),
            AnimatedContainer(
              duration: Duration(milliseconds: animMs),
              curve: curve,
              margin: const EdgeInsets.symmetric(horizontal: 6),
              padding: const EdgeInsets.fromLTRB(8, 5, 10, 5),
              decoration: BoxDecoration(
                color: isSelected ? accent.withAlpha(26) : Colors.transparent,
                borderRadius: BorderRadius.circular(10),
              ).withLauncherCorners(),
              child: Row(
                children: <Widget>[
                  // Station marker — a stop dot that grows into an
                  // interchange roundel on selection.
                  SizedBox(
                    width: 26,
                    child: Center(
                      child: AnimatedContainer(
                        duration: Duration(milliseconds: animMs),
                        curve: curve,
                        width: isSelected ? 16 : 10,
                        height: isSelected ? 16 : 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: surface,
                          border: Border.all(color: accent, width: isSelected ? 3.4 : 2.4),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(width: 22, height: 22, child: Center(child: icon)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: content ??
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            _titleText(TransitTokens.sign(
                              fontSize: Design.baseFontSize + 2,
                              fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              color: isSelected ? onSurface : onSurface.withAlpha(225),
                              letterSpacing: 0.2,
                              height: 1.25,
                            )),
                            _subtitleText(TransitTokens.sign(
                              fontSize: Design.baseFontSize - 0.5,
                              fontWeight: FontWeight.w400,
                              color: onSurface.withAlpha(isSelected ? 165 : 125),
                              letterSpacing: 0.3,
                              height: 1.15,
                            )),
                          ],
                        ),
                  ),
                  if (badge != null)
                    Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: badge,
                    ),
                  // "You are here" pointer — only at the current stop.
                  AnimatedSize(
                    duration: Duration(milliseconds: animMs),
                    curve: curve,
                    child: isSelected
                        ? Padding(
                            padding: const EdgeInsets.only(left: 6),
                            child: Icon(Icons.play_arrow_rounded, size: 15, color: accent),
                          )
                        : const SizedBox.shrink(),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
