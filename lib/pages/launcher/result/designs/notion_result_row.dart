part of '../result_row.dart';

extension _NotionResultRow on LauncherResultRow {
  Widget _buildNotion(BuildContext context) {
    final bool isDark = Theme.of(context).brightness == Brightness.dark;
    final int animMs = isRepeating ? 35 : 90;
    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
          decoration: BoxDecoration(
            color: isSelected ? NotionTokens.selection(isDark) : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 27,
                height: 27,
                child: Center(child: icon),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(NotionTokens.ui(
                          fontSize: Design.baseFontSize + 2,
                          fontWeight: FontWeight.w500,
                          color: NotionTokens.foreground(isDark),
                          height: 1.2,
                        )),
                        const SizedBox(height: 1),
                        _subtitleText(NotionTokens.ui(
                          fontSize: Design.baseFontSize,
                          fontWeight: FontWeight.w400,
                          color: NotionTokens.dim(isDark),
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
              AnimatedOpacity(
                duration: Duration(milliseconds: animMs),
                opacity: isSelected ? 1 : 0,
                child: Padding(
                  padding: const EdgeInsets.only(left: 7),
                  child: Icon(
                    Icons.keyboard_return_rounded,
                    size: 14,
                    color: NotionTokens.dim(isDark),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
