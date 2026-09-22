part of '../result_row.dart';

extension _GlassResultRow on LauncherResultRow {
  Widget _buildGlass(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final int animMs = isRepeating ? 80 : 220;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutCubic;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: curve,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          decoration: isSelected
              ? BoxDecoration(
                  borderRadius: BorderRadius.circular(16),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: <Color>[
                      Color.alphaBlend(Colors.white.withAlpha(isDark ? 26 : 130), accent.withAlpha(isDark ? 44 : 26)),
                      accent.withAlpha(isDark ? 34 : 18),
                    ],
                  ),
                  border: Border.all(color: Colors.white.withAlpha(isDark ? 46 : 150), width: 1),
                  boxShadow: <BoxShadow>[
                    BoxShadow(
                      color: accent.withAlpha(isDark ? 34 : 26),
                      blurRadius: 12,
                      spreadRadius: -2,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ).withLauncherCorners()
              : null,
          child: Row(
            children: <Widget>[
              // Frosted icon nest.
              Container(
                width: 36,
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  color: Colors.white.withAlpha(isDark ? (isSelected ? 24 : 14) : (isSelected ? 150 : 100)),
                  border: Border.all(color: Colors.white.withAlpha(isDark ? 34 : 130), width: 0.8),
                ).withLauncherCorners(),
                child: icon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(GlassTokens.font(
                          fontSize: Design.baseFontSize + 2,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? onSurface : onSurface.withAlpha(225),
                          height: 1.25,
                          letterSpacing: -0.1,
                        )),
                        const SizedBox(height: 1),
                        _subtitleText(GlassTokens.font(
                          fontSize: Design.baseFontSize,
                          fontWeight: FontWeight.w400,
                          color: onSurface.withAlpha(isSelected ? 165 : 120),
                          height: 1.2,
                        )),
                      ],
                    ),
              ),
              if (badge != null)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: badge,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
