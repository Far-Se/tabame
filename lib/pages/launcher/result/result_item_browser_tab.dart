import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart' show BrowserTab;

import 'result_row.dart';

class BrowserTabSearchListItem extends StatelessWidget {
  const BrowserTabSearchListItem({
    super.key,
    required this.browserTab,
    required this.isSelected,
    required this.isRepeating,
    required this.accent,
    required this.onSurface,
    required this.onTap,
    required this.onHover,
  });

  final BrowserTab browserTab;
  final bool isSelected;
  final bool isRepeating;
  final Color accent;
  final Color onSurface;
  final VoidCallback onTap;
  final VoidCallback onHover;

  @override
  Widget build(BuildContext context) {
    return LauncherResultRow(
      isSelected: isSelected,
      isRepeating: isRepeating,
      accent: accent,
      onSurface: onSurface,
      onTap: onTap,
      onHover: onHover,
      icon: const SizedBox(
        width: 20,
        height: 20,
        child: Icon(Icons.tab_rounded, size: 18),
      ),
      title: browserTab.title,
      subtitle: browserTab.browser,
      badge: LauncherKindBadge(
        icon: Icons.language_rounded,
        label: 'TAB',
        color: Colors.black45,
        accent: accent,
      ),
    );
  }
}
