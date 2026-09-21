part of '../result_row.dart';

extension _SereneResultRow on LauncherResultRow {
  Widget _buildSerene(BuildContext context) {
    return RepaintBoundary(
      child: _interactive(
        child: _SereneRowContainer(
          isSelected: isSelected,
          isRepeating: isRepeating,
          accent: accent,
          child: Row(
            children: <Widget>[
              _SereneIconWell(
                accent: accent,
                isSelected: isSelected,
                child: icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: content == null
                    ? Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          _titleText(TextStyle(
                            fontSize: _SereneTokens.titleSize,
                            fontWeight: FontWeight.w500,
                            color: isSelected ? onSurface : onSurface.withAlpha(210),
                            letterSpacing: -0.1,
                            height: 1.2,
                          )),
                          const SizedBox(height: 1),
                          _subtitleText(TextStyle(
                            fontSize: _SereneTokens.subtitleSize,
                            color: isSelected ? onSurface.withAlpha(160) : onSurface.withAlpha(110),
                            height: 1.2,
                          )),
                        ],
                      )
                    : content!,
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
    );
  }
}

class _SereneIconWell extends StatelessWidget {
  const _SereneIconWell({
    required this.child,
    required this.accent,
    this.isSelected = false,
  });

  final Widget child;
  final Color accent;
  final bool isSelected;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: _SereneTokens.iconWellSize,
      height: _SereneTokens.iconWellSize,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withAlpha(isSelected ? 36 : 20),
        borderRadius: BorderRadius.circular(_SereneTokens.iconWellRadius),
      ),
      child: child,
    );
  }
}

class _SereneRowContainer extends StatelessWidget {
  const _SereneRowContainer({
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.child,
  });

  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final Duration dur = isRepeating ? _SereneTokens.fastAnim : _SereneTokens.normalAnim;
    return AnimatedContainer(
      duration: dur,
      curve: _SereneTokens.animCurve,
      margin: const EdgeInsets.symmetric(horizontal: 6, vertical: _SereneTokens.rowVMargin),
      padding: const EdgeInsets.symmetric(
        horizontal: _SereneTokens.rowHPad,
        vertical: _SereneTokens.rowVPad,
      ),
      decoration: BoxDecoration(
        color: isSelected ? accent.withAlpha(_SereneTokens.selectionFillAlpha) : Colors.transparent,
        borderRadius: BorderRadius.circular(_SereneTokens.rowRadius),
      ),
      child: child,
    );
  }
}

class LauncherSereneBadge extends StatelessWidget {
  const LauncherSereneBadge({
    super.key,
    required this.icon,
    required this.label,
    required this.color,
  });

  final IconData icon;
  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(_SereneTokens.badgeRadius),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 9, color: color.withAlpha(180)),
          const SizedBox(width: 3),
          Text(
            label,
            style: TextStyle(
              fontSize: _SereneTokens.badgeFontSize,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.2,
              color: color.withAlpha(190),
            ),
          ),
        ],
      ),
    );
  }
}

abstract final class _SereneTokens {
  // Row geometry
  static const double rowHPad = 12;
  static const double rowVPad = 7;
  static const double rowRadius = 10.0;
  static const double rowVMargin = 1.5;

  // Icon well
  static const double iconWellSize = 30;
  static const double iconWellRadius = 7;

  // Typography
  static const double titleSize = 13;
  static const double subtitleSize = 11;

  // Badge
  static const double badgeFontSize = 9;
  static const double badgeRadius = 5;

  // Selection fill opacity (0-255)
  static const int selectionFillAlpha = 40;

  // Animation
  static const Duration fastAnim = Duration(milliseconds: 80);
  static const Duration normalAnim = Duration(milliseconds: 180);
  static const Curve animCurve = Curves.easeInOut;
}
