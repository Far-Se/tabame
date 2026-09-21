part of '../result_row.dart';

extension _ManifestoResultRow on LauncherResultRow {
  Widget _buildManifesto(BuildContext context) {
    final int animMs = isRepeating ? 45 : 130;
    final Curve curve = isRepeating ? Curves.linear : Curves.easeOutQuart;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: curve,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(30) : Colors.transparent,
            border: Border.all(
              color: isSelected ? onSurface : onSurface.withAlpha(28),
              width: isSelected ? 1.5 : 0.8,
            ),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? onSurface : Colors.transparent,
                  border: Border.all(color: onSurface.withAlpha(isSelected ? 255 : 90)),
                ),
                child: isSelected
                    ? ColorFiltered(colorFilter: ColorFilter.mode(accent, BlendMode.srcIn), child: icon)
                    : icon,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(ManifestoTokens.body(
                          fontSize: Design.baseFontSize + 2,
                          fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                          color: onSurface,
                          height: 1.2,
                          letterSpacing: 0.1,
                        )),
                        _subtitleText(ManifestoTokens.body(
                          fontSize: Design.baseFontSize - 0.5,
                          fontWeight: FontWeight.w400,
                          color: ManifestoTokens.dim(Theme.of(context).brightness == Brightness.dark),
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
              AnimatedContainer(
                duration: Duration(milliseconds: animMs),
                curve: curve,
                width: isSelected ? 10 : 4,
                height: isSelected ? 10 : 4,
                margin: const EdgeInsets.only(left: 8),
                color: isSelected ? accent : onSurface.withAlpha(55),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
