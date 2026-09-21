part of '../result_row.dart';

extension _WindowsXpResultRow on LauncherResultRow {
  Widget _buildWindowsXp(BuildContext context) {
    final int animMs = isRepeating ? 35 : 90;
    final Color rowText = isSelected ? const Color(0xFFFFFFFF) : WindowsXpTokens.foreground;
    final Color rowDim = isSelected ? const Color(0xFFE4EDFF) : WindowsXpTokens.dim;

    return RepaintBoundary(
      child: _interactive(
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          padding: const EdgeInsets.fromLTRB(7, 5, 7, 5),
          decoration: BoxDecoration(
            color: isSelected ? WindowsXpTokens.selection : Colors.transparent,
            border: isSelected ? Border.all(color: WindowsXpTokens.blueDark) : Border.all(color: Colors.transparent),
          ),
          child: Row(
            children: <Widget>[
              Container(
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: isSelected ? const Color(0x24FFFFFF) : WindowsXpTokens.paper,
                  border: Border.all(
                    color: isSelected ? const Color(0x66FFFFFF) : const Color(0xFFD6D2C2),
                  ),
                ),
                child: icon,
              ),
              const SizedBox(width: 9),
              Expanded(
                child: content ??
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        _titleText(WindowsXpTokens.tahoma(
                          fontSize: Design.baseFontSize + 2,
                          fontWeight: FontWeight.w400,
                          color: rowText,
                          height: 1.2,
                        )),
                        const SizedBox(height: 1),
                        _subtitleText(WindowsXpTokens.tahoma(
                          fontSize: Design.baseFontSize,
                          fontWeight: FontWeight.w400,
                          color: rowDim,
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
              if (isSelected)
                const Padding(
                  padding: EdgeInsets.only(left: 7),
                  child: Icon(Icons.arrow_forward_ios, size: 10, color: Color(0xFFFFFFFF)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
