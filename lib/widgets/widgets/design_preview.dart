import 'package:flutter/material.dart';

/// Renders the real interface without input or its window-management lifecycle.
class DesignPreview extends StatelessWidget {
  const DesignPreview({super.key, required this.child});

  final Widget child;

  // A non-listening lookup also works during descendants' initState.
  static bool isActive(BuildContext context) => context.getInheritedWidgetOfExactType<_DesignPreviewScope>() != null;

  @override
  Widget build(BuildContext context) => _DesignPreviewScope(
        child: IgnorePointer(
          child: ExcludeFocus(child: ExcludeSemantics(child: child)),
        ),
      );
}

class _DesignPreviewScope extends InheritedWidget {
  const _DesignPreviewScope({required super.child});

  @override
  bool updateShouldNotify(_DesignPreviewScope oldWidget) => false;
}
