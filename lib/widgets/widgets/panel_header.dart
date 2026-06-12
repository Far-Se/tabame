import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/settings.dart';
import 'custom_tooltip.dart';
import 'mix_widgets.dart';

class PanelHeader extends StatelessWidget {
  const PanelHeader({
    required this.title,
    required this.icon,
    this.accent,
    this.buttonPressed,
    this.buttonIcon,
    this.buttonTooltip,
    this.extraActions,
  });

  final Color? accent;
  final String title;
  final IconData icon;
  final VoidCallback? buttonPressed;
  final IconData? buttonIcon;
  final String? buttonTooltip;
  final List<Widget>? extraActions;

  @override
  Widget build(BuildContext context) {
    return !userSettings.dragPopupsByIconOnly
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
            color: (accent ?? Design.accent).withAlpha(60),
            width: 1,
          ),
        ),
      ),
      child: CancelTraversal(
        child: Theme(
          data: Theme.of(context).copyWith(
            iconTheme: IconThemeData(color: (accent ?? Design.accent), size: 14),
            iconButtonTheme: IconButtonThemeData(
              style: ButtonStyle(
                padding: WidgetStateProperty.all(
                  const EdgeInsets.all(0), // <- default padding here
                ),
                minimumSize: WidgetStateProperty.all(const Size(30, 30)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
                    color: (accent ?? Design.accent).withAlpha(30),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 14, color: (accent ?? Design.accent)),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: entryStyle(true, fontSize: 13, letterSpacing: 0.3),
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
                    icon: Icon(buttonIcon, color: (accent ?? Design.accent)),
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
