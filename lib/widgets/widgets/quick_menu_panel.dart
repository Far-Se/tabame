import 'package:flutter/material.dart';

import 'mouse_scroll_widget.dart';
import 'panel_header.dart';

class QuickMenuPanel extends StatelessWidget {
  const QuickMenuPanel({
    super.key,
    required this.title,
    required this.accent,
    required this.icon,
    required this.body,
    this.bodyPadding = EdgeInsets.zero,
    this.scrollable = false,
    this.useMouseScroll = false,
    this.materialBody = true,
    this.buttonPressed,
    this.buttonIcon,
    this.buttonTooltip,
    this.extraActions,
  });

  final String title;
  final Color accent;
  final IconData icon;
  final Widget body;
  final EdgeInsetsGeometry bodyPadding;
  final bool scrollable;
  final bool useMouseScroll;
  final bool materialBody;
  final VoidCallback? buttonPressed;
  final IconData? buttonIcon;
  final String? buttonTooltip;
  final List<Widget>? extraActions;

  @override
  Widget build(BuildContext context) {
    Widget content = body;

    if (bodyPadding != EdgeInsets.zero) {
      content = Padding(
        padding: bodyPadding,
        child: content,
      );
    }

    if (scrollable) {
      content = SingleChildScrollView(
        child: content,
      );
    }

    if (materialBody) {
      content = Material(
        type: MaterialType.transparency,
        child: content,
      );
    }

    if (useMouseScroll) {
      content = MouseScrollWidget(
        scrollDirection: Axis.vertical,
        child: content,
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: title,
          accent: accent,
          icon: icon,
          buttonPressed: buttonPressed,
          buttonIcon: buttonIcon,
          buttonTooltip: buttonTooltip,
          extraActions: extraActions,
        ),
        Flexible(child: content),
      ],
    );
  }
}
