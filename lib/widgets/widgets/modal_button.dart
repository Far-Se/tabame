import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/util/quickmenu_modal.dart';
import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/classes/hotkeys.dart';
import 'quick_actions_item.dart';

class ModalButton extends StatefulWidget {
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
    this.heightFactor = 0.85,
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
  ModalButtonState createState() => ModalButtonState();
}

class ModalButtonState extends State<ModalButton> with QuickMenuTriggers {
  bool _isSheetOpen = false;

  @override
  void initState() {
    super.initState();
    _registerAction(widget.actionName);
    QuickMenuFunctions.addListener(this);
  }

  @override
  void didUpdateWidget(ModalButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.actionName != widget.actionName) {
      _unregisterAction(oldWidget.actionName);
      _registerAction(widget.actionName);
    }
  }

  @override
  void dispose() {
    _unregisterAction(widget.actionName);
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  static final Map<String, int> _actionUsageCount = <String, int>{};

  void _registerAction(String name) {
    _actionUsageCount[name] = (_actionUsageCount[name] ?? 0) + 1;
    if (!HotKeyInfo.quickMenuPopups.contains(name)) {
      HotKeyInfo.quickMenuPopups.add(name);
      HotKeyInfo.quickMenuPopups.sort();
    }
  }

  void _unregisterAction(String name) {
    if (_actionUsageCount.containsKey(name)) {
      _actionUsageCount[name] = _actionUsageCount[name]! - 1;
      if (_actionUsageCount[name]! <= 0) {
        _actionUsageCount.remove(name);
        HotKeyInfo.quickMenuPopups.remove(name);
      }
    }
  }

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == widget.actionName) {
      _openPanel();
    }
  }

  Future<void> _openPanel() async {
    if (!mounted || _isSheetOpen) return;
    _isSheetOpen = true;
    await showQuickMenuModal(
      context: context,
      heightFactor: widget.heightFactor,
      child: widget.child(),
      backdropFilter: widget.backdropFilter,
    );
    _isSheetOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: widget.actionName,
      icon: widget.icon,
      onSecondaryTap: widget.onSecondaryTap,
      onDoubleTap: widget.onDoubleTap,
      onLongPress: widget.onLongPress,
      onVerticalDragStart: widget.onVerticalDragStart,
      onVerticalDragUpdate: widget.onVerticalDragUpdate,
      onVerticalDragEnd: widget.onVerticalDragEnd,
      onTertiaryTapDown: widget.onTertiaryTapDown,
      onTertiaryTapUp: widget.onTertiaryTapUp,
      hoverColor: Theme.of(context).colorScheme.primary,
      onTap: _openPanel,
    );
  }
}
