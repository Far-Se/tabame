import 'package:flutter/material.dart';

import '../../../models/util/quickmenu_modal.dart';
import 'quick_actions_item.dart';

class ModalButton extends StatelessWidget {
  final String actionName;
  final Widget Function() child;
  final Widget icon;
  final double heightFactor;
  final bool backdropFilter;
  final VoidCallback? onSecondaryTap;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onLongPress;
  final GestureTapUpCallback? onTertiaryTapUp;
  final GestureDragStartCallback? onVerticalDragStart;
  final GestureDragUpdateCallback? onVerticalDragUpdate;
  final GestureDragEndCallback? onVerticalDragEnd;
  final GestureTapDownCallback? onTertiaryTapDown;
  const ModalButton({
    super.key,
    required this.actionName,
    required this.child,
    required this.icon,
    this.heightFactor = 0.9,
    this.backdropFilter = true,
    this.onSecondaryTap,
    this.onDoubleTap,
    this.onLongPress,
    this.onVerticalDragStart,
    this.onVerticalDragUpdate,
    this.onVerticalDragEnd,
    this.onTertiaryTapDown,
    this.onTertiaryTapUp,
  });

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: actionName,
      icon: icon,
      onSecondaryTap: onSecondaryTap,
      onDoubleTap: onDoubleTap,
      onLongPress: onLongPress,
      onVerticalDragStart: onVerticalDragStart,
      onVerticalDragUpdate: onVerticalDragUpdate,
      onVerticalDragEnd: onVerticalDragEnd,
      onTertiaryTapDown: onTertiaryTapDown,
      onTertiaryTapUp: onTertiaryTapUp,
      hoverColor: Theme.of(context).colorScheme.primary,
      onTap: () {
        showQuickMenuModal(
          context: context,
          heightFactor: heightFactor,
          child: child(),
          backdropFilter: backdropFilter,
        );
      },
    );
  }
}
