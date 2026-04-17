import 'dart:async';
import 'package:flutter/material.dart';
import '../../../models/util/quickmenu_modal.dart';
import '../../models/classes/boxes/quick_menu_box.dart';
import 'quick_actions_item.dart';

class ModalButton extends StatefulWidget {
  final String actionName;
  final Widget child;
  final Widget icon;
  final double? heightFactor;
  const ModalButton({super.key, required this.actionName, required this.child, required this.icon, this.heightFactor});
  @override
  ModalButtonState createState() => ModalButtonState();
}

class ModalButtonState extends State<ModalButton> with QuickMenuTriggers {
  bool _isSheetOpen = false;

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
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
    if (widget.heightFactor != null) {
      await showQuickMenuModal(context: context, heightFactor: widget.heightFactor!, child: widget.child);
    } else {
      await showQuickMenuModal(context: context, child: widget.child);
    }
    _isSheetOpen = false;
  }

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: widget.actionName,
      icon: widget.icon,
      onTap: () => _openPanel(),
    );
  }
}
