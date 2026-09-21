part of '../result_row.dart';

extension _ZenResultRow on LauncherResultRow {
  Widget _buildZen(BuildContext context) {
    // Deliberately unhurried — calm motion, never snappy (even on key-repeat).
    final Duration dur = Duration(milliseconds: isRepeating ? 120 : 300);
    const Curve curve = Curves.easeInOutSine;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: dur,
          curve: curve,
          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(30) : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: <Widget>[
              // Soft rounded "stem" that grows on selection.
              AnimatedContainer(
                duration: dur,
                curve: curve,
                width: isSelected ? 3 : 0,
                height: 20,
                margin: EdgeInsets.only(right: isSelected ? 10 : 0),
                decoration: BoxDecoration(
                  color: accent.withAlpha(180),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              // Soft squircle icon nest.
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: accent.withAlpha(isSelected ? 34 : 20),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: icon,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(ZenTokens.soft(
                          fontSize: Design.baseFontSize + 2,
                          fontWeight: FontWeight.w600,
                          color: isSelected ? onSurface : onSurface.withAlpha(225),
                          height: 1.25,
                          letterSpacing: 0.1,
                        )),
                        const SizedBox(height: 1),
                        _subtitleText(ZenTokens.soft(
                          fontSize: Design.baseFontSize,
                          fontWeight: FontWeight.w400,
                          color: onSurface.withAlpha(isSelected ? 150 : 115),
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
