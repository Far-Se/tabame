import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/win32/win_utils.dart';
import '../../../widgets/widgets/custom_tooltip.dart';
import '../../launcher_search_models.dart';

class AppResultIcon extends StatelessWidget {
  const AppResultIcon({
    super.key,
    required this.app,
    this.size = 20,
  });

  final LauncherAppResult app;
  final double size;

  @override
  Widget build(BuildContext context) {
    final File file = File('${WinUtils.getTabameAppDataFolder()}/cache/icon_cache/app_${app.iconCacheKey}.png');
    if (file.existsSync()) {
      return Image.file(
        file,
        width: size,
        height: size,
        fit: BoxFit.contain,
        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => _fallback(),
      );
    }
    return _fallback();
  }

  Widget _fallback() {
    return Icon(
      Icons.apps_rounded,
      size: size,
      color: Colors.white70,
    );
  }
}

class LauncherAppListItem extends StatelessWidget {
  const LauncherAppListItem({
    super.key,
    required this.app,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
  });

  final LauncherAppResult app;
  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    final int animMs = isRepeating ? 50 : 200;
    final Curve animCurve = isRepeating ? Curves.linear : Curves.easeOutCubic;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onHover: (PointerHoverEvent event) {
        if (event.delta != Offset.zero) onHover();
      },
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: Duration(milliseconds: animMs),
          curve: animCurve,
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(55) : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Row(
              children: <Widget>[
                AnimatedContainer(
                  duration: Duration(milliseconds: animMs),
                  curve: animCurve,
                  width: isSelected ? 2.5 : 0,
                  height: 22,
                  margin: EdgeInsets.only(right: isSelected ? 7 : 0),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                AppResultIcon(app: app),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        app.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 12,
                          color: isSelected ? onSurface : onSurface.withAlpha(200),
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        app.subtitle,
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
                Padding(
                  padding: const EdgeInsets.only(left: 4),
                  child: CustomTooltip(
                    verticalOffset: 45,
                    message: 'Windows app\npress Enter to launch',
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
                          Icon(Icons.apps_rounded, size: 9, color: accent.withAlpha(180)),
                          const SizedBox(width: 2),
                          Text(
                            'APP',
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
