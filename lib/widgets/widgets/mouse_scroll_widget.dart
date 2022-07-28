import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MouseScrollWidget extends StatefulWidget {
  final Widget child;
  final Axis scrollDirection;
  const MouseScrollWidget({Key? key, required this.child, this.scrollDirection = Axis.horizontal}) : super(key: key);

  @override
  MouseScrollWidgetState createState() => MouseScrollWidgetState();
}

class MouseScrollWidgetState extends State<MouseScrollWidget> {
  ScrollController controller = ScrollController();
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (PointerSignalEvent pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          if (pointerSignal.scrollDelta.dy < 0) {
            controller.animateTo(controller.offset - 50, duration: const Duration(milliseconds: 200), curve: Curves.ease);
          } else {
            controller.animateTo(controller.offset + 50, duration: const Duration(milliseconds: 200), curve: Curves.ease);
          }
        }
      },
      child: SingleChildScrollView(
        controller: controller,
        scrollDirection: widget.scrollDirection,
        child: widget.child,
      ),
    );
  }
}
