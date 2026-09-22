part of '../result_row.dart';

extension _ToonResultRow on LauncherResultRow {
  Widget _buildToon(BuildContext context) => _interactive(
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: Duration(milliseconds: isRepeating ? 40 : 120),
          curve: Curves.easeOutQuart,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.fromLTRB(9, 8, 10, 8),
          decoration: BoxDecoration(
            color: isSelected ? ToonTokens.selected : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isSelected ? ToonTokens.cream : ToonTokens.orange.withAlpha(80),
            ),
          ).withLauncherCorners(),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 20,
                child: Text(
                  isSelected ? '>' : '',
                  style: ToonTokens.font(size: 19, color: ToonTokens.orange, weight: FontWeight.w800),
                ),
              ),
              Container(
                width: 34,
                height: 34,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: const Color(0x7130281F),
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                    color: isSelected ? ToonTokens.orange : ToonTokens.red.withAlpha(150),
                  ),
                ).withLauncherCorners(),
                child: icon,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(ToonTokens.font(
                          size: 16,
                          color: isSelected ? ToonTokens.cream : ToonTokens.foreground,
                          weight: isSelected ? FontWeight.w700 : FontWeight.w600,
                        )),
                        if ((subtitle ?? '').isNotEmpty) ...<Widget>[
                          const SizedBox(height: 3),
                          _subtitleText(ToonTokens.font(size: 12, color: ToonTokens.dim)),
                        ],
                      ],
                    ),
              ),
              if (badge != null) Padding(padding: const EdgeInsets.only(left: 8), child: badge),
              if (isSelected)
                Padding(
                  padding: const EdgeInsets.only(left: 10),
                  child: Icon(Icons.keyboard_return_rounded, size: 16, color: ToonTokens.orange),
                ),
            ],
          ),
        ),
      );
}
