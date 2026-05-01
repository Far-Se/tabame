import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/settings.dart';
import '../../models/win32/window.dart';
import '../../models/window_watcher.dart';

class WindowSearchListItem extends StatefulWidget {
  const WindowSearchListItem({
    super.key,
    required this.window,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
  });

  final Window window;
  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  State<WindowSearchListItem> createState() => _WindowSearchListItemState();
}

class _WindowSearchListItemState extends State<WindowSearchListItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final bool highlighted = _hovered || widget.isSelected;
    final Uint8List? iconBytes = WindowWatcher.icons[widget.window.hWnd];
    final String processName = widget.window.process.exe.replaceFirst('.exe', '');
    final int animMs = widget.isRepeating ? 50 : 200;

    return MouseRegion(
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) {
          setState(() => _hovered = true);
          widget.onHover();
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: AnimatedContainer(
        duration: Duration(milliseconds: animMs),
        curve: widget.isRepeating ? Curves.linear : Curves.easeIn,
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: highlighted ? globalSettings.themeColors.accentColor.withAlpha(60) : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: widget.onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: Duration(milliseconds: animMs),
                  width: highlighted ? 2.5 : 0,
                  height: 22,
                  margin: EdgeInsets.only(right: highlighted ? 7 : 0),
                  decoration: BoxDecoration(
                    color: globalSettings.themeColors.accentColor,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(
                  width: 20,
                  height: 20,
                  child: iconBytes != null && iconBytes.isNotEmpty
                      ? Image.memory(
                          iconBytes,
                          width: 20,
                          height: 20,
                          gaplessPlayback: true,
                          errorBuilder: (_, __, ___) => const Icon(Icons.web_asset_sharp, size: 18),
                        )
                      : const Icon(Icons.web_asset_sharp, size: 18),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        widget.window.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: highlighted ? widget.onSurface : widget.onSurface.withAlpha(200),
                          fontFamily: globalSettings.themeColors.entryFontFamily,
                          fontStyle: globalSettings.themeColors.entryFontItalic ? FontStyle.italic : FontStyle.normal,
                          fontWeight: FontWeight(globalSettings.themeColors.entryFontWeight),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        processName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: highlighted ? widget.onSurface.withAlpha(170) : widget.onSurface.withAlpha(130),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.window.isPinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 10,
                      color: globalSettings.themeColors.accentColor.withAlpha(200),
                    ),
                  ),
                // Window badge
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: _WindowKindBadge(
                    accent: globalSettings.themeColors.accentColor,
                    onSurface: widget.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _WindowKindBadge extends StatelessWidget {
  const _WindowKindBadge({
    required this.accent,
    required this.onSurface,
  });

  final Color accent;
  final Color onSurface;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.green.withAlpha(70),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: accent.withAlpha(40)),
      ),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: accent.withAlpha(22),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: accent.withAlpha(40)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(Icons.window_rounded, size: 9, color: accent.withAlpha(180)),
            const SizedBox(width: 2),
            Text(
              'WIN',
              style: TextStyle(
                fontSize: 8,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.3,
                color: accent.withAlpha(200),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
