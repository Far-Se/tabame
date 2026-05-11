import 'package:flutter/material.dart';

class StackyFackyPuliMaky extends StatefulWidget {
  final Widget child;
  const StackyFackyPuliMaky({super.key, required this.child});

  @override
  State<StackyFackyPuliMaky> createState() => _StackyFackyPuliMakyState();
}

class _StackyFackyPuliMakyState extends State<StackyFackyPuliMaky> {
  @override
  void initState() {
    super.initState();
    // WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) async {
    //   await Future<void>.delayed(const Duration(milliseconds: 100), () async {
    //     final Size value = await windowManager.getSize();
    //     await windowManager.setSize(Size(value.width + 1, value.height + 1));
    //     await windowManager.setSize(Size(value.width, value.height));
    //   });
    // });
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Scaffold(
          body: Material(type: MaterialType.transparency, child: widget.child),
          backgroundColor: Colors.black,
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: Container(
              decoration: BoxDecoration(
                border: Border.all(color: Colors.black, width: 1),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
