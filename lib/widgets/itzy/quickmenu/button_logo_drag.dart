import 'dart:io';

import 'package:flutter/material.dart';
import 'package:window_manager/window_manager.dart';

import '../../../models/globals.dart';
import '../../../models/settings.dart';

class LogoDragButton extends StatefulWidget {
  const LogoDragButton({super.key});
  @override
  State<LogoDragButton> createState() => LogoDragButtonState();
}

class LogoDragButtonState extends State<LogoDragButton> {
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: Globals.themeChangeNotifier,
      builder: (_, bool refreshed, __) => GestureDetector(
        behavior: HitTestBehavior.translucent,
        onPanStart: (DragStartDetails details) {
          windowManager.startDragging();
        },
        onSecondaryTapDown: (TapDownDetails e) async {
          final Size value = await windowManager.getSize();
          await windowManager.setSize(Size(value.width + 2, value.height + 2));
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await windowManager.setSize(Size(value.width, value.height));
        },
        child: RepaintBoundary(
          child: InkWell(
            borderRadius: BorderRadius.circular(10),
            focusColor: Colors.transparent,
            hoverColor: Colors.transparent,
            splashColor: Colors.transparent,
            onTap: () {
              userSettings.hideTabameOnUnfocus = !userSettings.hideTabameOnUnfocus;
            },
            child: Stack(
              children: <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 0).copyWith(right: 2, top: 1),
                  child: Align(
                      alignment: Alignment.centerLeft,
                      child: userSettings.customLogo == ""
                          ? Image.asset(userSettings.logo, width: 15)
                          : Image.file(File(userSettings.customLogo), width: 15)),
                ),
                if (!userSettings.hideTabameOnUnfocus)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: CustomPaint(
                      size: const Size(6, 6),
                      painter: TrianglePainter(userSettings.themeColors.accentColor.withValues(alpha: 0.5)),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class TrianglePainter extends CustomPainter {
  final Color color;
  TrianglePainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()..color = color.withValues(alpha: 0.3);
    // final Path path = Path();
    // path.moveTo(0, 0);
    // path.lineTo(size.width, 0);
    // path.lineTo(size.width / 2, size.height);
    // path.close();
    // canvas.drawPath(path, paint);
    canvas.drawCircle(Offset(size.width - 2, 2), size.width / 2, paint);
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}
