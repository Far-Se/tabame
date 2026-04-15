import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class DragButton extends StatelessWidget {
  const DragButton({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (DragStartDetails details) {
        windowManager.startDragging();
      },
      child: child,
    );
  }
}
