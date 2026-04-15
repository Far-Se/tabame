import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class MouseScrollWidget extends StatefulWidget {
  final Widget child;
  final Axis scrollDirection;
  final ScrollPhysics? physics;
  const MouseScrollWidget({
    super.key,
    required this.child,
    this.scrollDirection = Axis.vertical,
    this.physics,
  });

  @override
  MouseScrollWidgetState createState() => MouseScrollWidgetState();
}

class MouseScrollWidgetState extends State<MouseScrollWidget> {
  ScrollController controller = ScrollController();
  static String? _lastEventSignature;

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  double _target = 0;

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (PointerSignalEvent pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          // Use a unique signature for the event (Time + Global Position)
          // because child/parent localPositions differ, and object equality can fail.
          final String signature = "${pointerSignal.timeStamp.inMicroseconds}_${pointerSignal.position}";

          // If this specific event was already handled by a deeper child, skip
          if (_lastEventSignature == signature) return;

          // If we have no room to scroll, let the event pass to parent
          if (!controller.hasClients || controller.position.maxScrollExtent <= 0) return;

          final double delta = widget.scrollDirection == Axis.vertical 
              ? pointerSignal.scrollDelta.dy 
              : pointerSignal.scrollDelta.dx;
          if (delta == 0) return;

          // Claim the event fingerprint so parents don't handle it
          _lastEventSignature = signature;

          // Re-sync target with current offset if they drifted (e.g. scrollbar usage)
          if ((controller.offset - _target).abs() > 100) {
            _target = controller.offset;
          }

          _target += delta;
          _target = _target.clamp(0, controller.position.maxScrollExtent);

          controller.animateTo(
            _target,
            duration: const Duration(milliseconds: 400),
            curve: Curves.easeOutQuart,
          );
        }
      },
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(
          dragDevices: <PointerDeviceKind>{
            PointerDeviceKind.touch,
            PointerDeviceKind.mouse,
          },
          scrollbars: true,
        ),
        child: SingleChildScrollView(
          controller: controller,
          physics: widget.physics ?? const AlwaysScrollableScrollPhysics(parent: ClampingScrollPhysics()),
          scrollDirection: widget.scrollDirection,
          child: widget.child,
        ),
      ),
    );
  }
}
