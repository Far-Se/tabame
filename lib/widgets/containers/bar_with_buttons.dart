import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

class BarWithButtons extends StatefulWidget {
  final List<Widget> children;
  final bool withScroll;
  final double height;
  const BarWithButtons({
    Key? key,
    required this.children,
    this.withScroll = true,
    this.height = 30,
  }) : super(key: key);

  @override
  State<BarWithButtons> createState() => _BarWithButtonsState();
}

class _BarWithButtonsState extends State<BarWithButtons> {
  final ScrollController _buttonBarScrollController = ScrollController();

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      controller: _buttonBarScrollController,
      child: !widget.withScroll
          ? ListChildren(children: widget.children)
          : Listener(
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent) {
                  if (pointerSignal.scrollDelta.dy < 0) {
                    _buttonBarScrollController.animateTo(_buttonBarScrollController.offset - 50, duration: const Duration(milliseconds: 200), curve: Curves.ease);
                  } else {
                    _buttonBarScrollController.animateTo(_buttonBarScrollController.offset + 50, duration: const Duration(milliseconds: 200), curve: Curves.ease);
                  }
                }
              },
              child: ListChildren(children: widget.children),
            ),
    );
  }
}

class ListChildren extends StatelessWidget {
  const ListChildren({
    Key? key,
    required this.children,
  }) : super(key: key);

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        verticalDirection: VerticalDirection.down,
        children: List<Widget>.generate(
          children.length,
          (index) {
            return Flexible(
              flex: 1,
              fit: FlexFit.loose,
              child: children[index],
            );
          },
        ),
      ),
    );
  }
}
