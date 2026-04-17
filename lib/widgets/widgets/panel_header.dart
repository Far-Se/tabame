import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader(
      {required this.title,
      required this.accent,
      required this.boldFont,
      required this.icon,
      this.secondaryButtonPressed,
      this.secondaryButtonIcon,
      this.secondaryButtonTooltip,
      this.buttonPressed,
      this.buttonIcon,
      this.buttonTooltip});
  final Color accent;
  final String title;
  final bool boldFont;
  final IconData icon;
  final VoidCallback? secondaryButtonPressed;
  final IconData? secondaryButtonIcon;
  final String? secondaryButtonTooltip;
  final VoidCallback? buttonPressed;
  final IconData? buttonIcon;
  final String? buttonTooltip;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: accent.withAlpha(60),
            width: 1,
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (DragStartDetails details) {
              windowManager.startDragging();
            },
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: accent.withAlpha(30),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, size: 14, color: accent),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
              style: TextStyle(
                fontSize: 13,
                fontWeight: boldFont ? FontWeight.w600 : FontWeight.w400,
                letterSpacing: 0.3,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
          if (secondaryButtonPressed != null && secondaryButtonIcon != null) ...<Widget>[
            CustomTooltip(
              message: secondaryButtonTooltip ?? '',
              child: IconButton(
                onPressed: secondaryButtonPressed,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                iconSize: 14,
                icon: Icon(secondaryButtonIcon, color: accent),
              ),
            ),
          ],
          if (buttonPressed != null && buttonIcon != null) ...<Widget>[
            CustomTooltip(
              message: buttonTooltip ?? '',
              child: IconButton(
                onPressed: buttonPressed,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                iconSize: 14,
                icon: Icon(buttonIcon, color: accent),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
