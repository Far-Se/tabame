import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/globals.dart';
import '../../models/settings.dart';
import 'custom_tooltip.dart';
import 'mix_widgets.dart';

class PanelHeader extends StatefulWidget {
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
  State<PanelHeader> createState() => _PanelHeaderState();
}

class _PanelHeaderState extends State<PanelHeader> {
  @override
  Widget build(BuildContext context) {
    return !user.dragPopupsByIconOnly
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
            color: (widget.accent ?? Design.accent).withAlpha(60),
            width: 1,
          ),
        ),
      ),
      child: CancelTraversal(
        child: Theme(
          data: Theme.of(context).copyWith(
            iconTheme: IconThemeData(color: (widget.accent ?? Design.accent), size: 14),
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
              MouseRegion(
                cursor:
                    user.useCustomCursor ? Globals.customCursor ?? SystemMouseCursors.move : SystemMouseCursors.basic,
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onPanStart: (DragStartDetails details) {
                    windowManager.startDragging();
                  },
                  onSecondaryTapDown: (TapDownDetails details) {
                    user.keepPopupOpenOnDemand = !user.keepPopupOpenOnDemand;
                    setState(() {});
                  },
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: (widget.accent ?? Design.accent).withAlpha(30),
                      borderRadius: BorderRadius.circular(8),
                      border: user.keepPopupOpenOnDemand
                          ? Border.all(
                              color: (widget.accent ?? Design.accent).withAlpha(60),
                              width: 3,
                            )
                          : null,
                    ),
                    child: Icon(widget.icon, size: 14, color: (widget.accent ?? Design.accent)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.title,
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                  style: entryStyle(true, fontSize: 13, letterSpacing: 0.3, color: Design.text),
                ),
              ),
              const SizedBox(width: 10),
              if (widget.extraActions != null) ...widget.extraActions!,
              if (widget.buttonPressed != null && widget.buttonIcon != null) ...<Widget>[
                CustomTooltip(
                  message: widget.buttonTooltip ?? '',
                  child: IconButton(
                    onPressed: widget.buttonPressed,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                    iconSize: 14,
                    icon: Icon(widget.buttonIcon, color: (widget.accent ?? Design.accent)),
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
