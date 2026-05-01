import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/settings.dart';
import 'custom_tooltip.dart';
import 'mix_widgets.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader({
    required this.title,
    required this.accent,
    required this.icon,
    this.buttonPressed,
    this.buttonIcon,
    this.buttonTooltip,
    this.extraActions,
  });

  final Color accent;
  final String title;
  final IconData icon;
  final VoidCallback? buttonPressed;
  final IconData? buttonIcon;
  final String? buttonTooltip;
  final List<Widget>? extraActions;

  @override
  Widget build(BuildContext context) {
    return !globalSettings.dragPopupsByIconOnly
        ? GestureDetector(
            behavior: HitTestBehavior.translucent,
            onPanStart: (DragStartDetails details) => windowManager.startDragging(),
            child: _panelWidget(context))
        : _panelWidget(context);
  }

  Container _panelWidget(BuildContext context) {
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
      child: CancelTraversal(
        child: Theme(
          data: Theme.of(context).copyWith(iconTheme: IconThemeData(color: accent)),
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
                    letterSpacing: 0.3,
                    color: Theme.of(context).colorScheme.onSurface,
                    fontFamily: globalSettings.theme.entryFontFamily,
                    fontStyle: globalSettings.theme.entryFontItalic ? FontStyle.italic : FontStyle.normal,
                    fontWeight: FontWeight(globalSettings.theme.entryFontWeight),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              if (extraActions != null) ...extraActions!,
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
        ),
      ),
    );
  }
}
