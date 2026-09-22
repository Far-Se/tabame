part of '../result_row.dart';

extension _FluentResultRow on LauncherResultRow {
  Widget _buildFluent(BuildContext context) {
    final int animMs = isRepeating ? 50 : 150;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutCubic;
    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: curve,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
          decoration: BoxDecoration(
            color: isSelected ? onSurface.withAlpha(isDark ? 18 : 14) : Colors.transparent,
            borderRadius: BorderRadius.circular(5),
          ).withLauncherCorners(),
          child: Stack(
            alignment: Alignment.centerLeft,
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                child: Row(
                  children: <Widget>[
                    SizedBox(width: 24, height: 24, child: Center(child: icon)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: content ??
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              _titleText(FluentTokens.segoe(
                                fontSize: Design.baseFontSize + 2,
                                fontWeight: FontWeight.w400,
                                color: isSelected ? onSurface : onSurface.withAlpha(225),
                                height: 1.25,
                              )),
                              _subtitleText(FluentTokens.segoe(
                                fontSize: Design.baseFontSize,
                                fontWeight: FontWeight.w400,
                                color: FluentTokens.dim(isDark).withAlpha(isSelected ? 255 : 210),
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
              // Accent selection pill — the WinUI list indicator.
              AnimatedContainer(
                duration: Duration(milliseconds: animMs),
                curve: curve,
                width: 3,
                height: isSelected ? 16 : 0,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: BorderRadius.circular(2),
                ).withLauncherCorners(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
