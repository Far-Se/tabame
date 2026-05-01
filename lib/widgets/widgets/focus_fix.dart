import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class FocusFix extends StatefulWidget {
  final Widget child;
  const FocusFix({required this.child});

  @override
  State<FocusFix> createState() => _FocusFixState();
}

class _FocusFixState extends State<FocusFix> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Forces Flutter to recalc hover states
      WidgetsBinding.instance.handlePointerEvent(
        const PointerHoverEvent(position: Offset(1, 1)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
