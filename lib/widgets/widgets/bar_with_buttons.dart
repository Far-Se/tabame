import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/globals.dart';

class BarWithButtons extends StatefulWidget {
  final List<Widget> children;
  final bool withScroll;
  final double height;
  const BarWithButtons({
    super.key,
    required this.children,
    this.withScroll = true,
    this.height = 30,
  });

  @override
  State<BarWithButtons> createState() => _BarWithButtonsState();
}

class _BarWithButtonsState extends State<BarWithButtons> with QuickMenuTriggers {
  final ScrollController _buttonBarScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    _buttonBarScrollController.dispose();
    super.dispose();
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (mounted) _buttonBarScrollController.animateTo(0, duration: const Duration(milliseconds: 50), curve: Curves.ease);
  }

  @override
  Widget build(BuildContext context) {
    double middleOffset = 0.93;
    Widget content = ListChildren(children: widget.children);

    if (!widget.withScroll) {
      return content;
    }

    return ShaderMask(
      shaderCallback: (Rect rect) {
        return LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: <Color>[Colors.transparent, Colors.transparent, const Color.fromARGB(255, 0, 0, 0)],
          stops: <double>[0.0, middleOffset, 1.0],
        ).createShader(rect);
      },
      blendMode: BlendMode.dstOut,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        controller: _buttonBarScrollController,
        child: Listener(
          onPointerSignal: (PointerSignalEvent pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              if (pointerSignal.scrollDelta.dy < 0) {
                _buttonBarScrollController.animateTo(_buttonBarScrollController.offset - 70, duration: const Duration(milliseconds: 200), curve: Curves.ease);
              } else {
                _buttonBarScrollController.animateTo(_buttonBarScrollController.offset + 70, duration: const Duration(milliseconds: 200), curve: Curves.ease);
              }
            }
          },
          child: content,
        ),
      ),
    );
  }
}

class ListChildren extends StatelessWidget {
  const ListChildren({
    super.key,
    required this.children,
  });

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.center,
        verticalDirection: VerticalDirection.down,
        spacing: 0,
        children: <Widget>[
          ...List<Widget>.generate(
            children.length,
            (int index) {
              return Flexible(
                flex: 1,
                fit: FlexFit.loose,
                child: children[index],
              );
            },
          ),
          const SizedBox(width: 6)
        ],
      ),
    );
  }
}
