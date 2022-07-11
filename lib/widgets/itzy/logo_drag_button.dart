import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

class LogoDragButton extends StatelessWidget {
  const LogoDragButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (DragStartDetails details) {
        windowManager.startDragging();
      },
      child: const InkWell(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 5),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Image(image: AssetImage("resources/logo.png"), width: 15),
          ),
        ),
      ),
    );
  }
}
