import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/settings.dart';
import '../../../models/win32/window.dart';
import '../../../models/window_watcher.dart';
import '../../../widgets/widgets/extracted_icon.dart';

/// A single window result row in the launcher list.
///
/// Selection state is owned entirely by the parent via [isSelected].
/// This widget never holds its own hover/focus state — it simply renders
/// whatever the parent tells it and fires [onHover] so the parent can
/// update its selection index through [_selectResultFromPointerHover].
///
/// This eliminates the classic "typed selection vs mouse hover" split where
/// a local `_hovered` flag would visually override the keyboard-driven
/// `isSelected` prop.
class WindowSearchListItem extends StatelessWidget {
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

  /// Called when the pointer moves over this item with a non-zero delta.
  /// The parent is responsible for deciding whether to honour the hover
  /// (e.g. it may ignore it while [_mouseSelectionEnabled] is false).
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final int animMs = isRepeating ? 50 : 200;
    final Curve animCurve = isRepeating ? Curves.linear : Curves.easeOutCubic;

    return MouseRegion(
      // Only fire onHover when the pointer actually moves — this prevents
      // phantom "hover" events that fire on every rebuild when the cursor
      // happens to sit over the widget.
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) onHover();
      },
      // cursor gives a nice affordance that items are clickable
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: animCurve,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? userSettings.themeColors.accent.withAlpha(55) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                // Animated selection indicator bar
                AnimatedContainer(
                  duration: Duration(milliseconds: animMs),
                  curve: animCurve,
                  width: isSelected ? 2.5 : 0,
                  height: 22,
                  margin: EdgeInsets.only(right: isSelected ? 7 : 0),
                  decoration: BoxDecoration(
                    color: userSettings.themeColors.accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),

                // App icon
                SizedBox(
                  width: 20,
                  height: 20,
                  child: buildExtractedIcon(
                    WindowWatcher.icons[window.hWnd],
                    width: 20,
                    height: 20,
                    gaplessPlayback: true,
                    errorBuilder: (_, __, ___) => const Icon(Icons.web_asset_sharp, size: 18),
                    fallback: const Icon(Icons.web_asset_sharp, size: 18),
                  ),
                ),

                const SizedBox(width: 8),

                // Title + process name
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        window.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: entryStyle(isSelected),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        window.process.exe.replaceFirst('.exe', ''),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 10,
                          color: isSelected ? onSurface.withAlpha(170) : onSurface.withAlpha(130),
                        ),
                      ),
                    ],
                  ),
                ),

                // Pin indicator
                if (window.isPinned)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Icon(
                      Icons.push_pin_rounded,
                      size: 10,
                      color: userSettings.themeColors.accent.withAlpha(200),
                    ),
                  ),

                // WIN badge
                _WindowKindBadge(
                  accent: userSettings.themeColors.accent,
                  onSurface: onSurface,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------

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
    );
  }
}
