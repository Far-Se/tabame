import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/hotkeys.dart';
import '../../../models/win32/win32.dart';
import '../../widgets/checkbox_widget.dart';
import 'package:tabame/widgets/widgets/custom_tooltip.dart';

class MouseInfoWidget extends StatefulWidget {
  final Function(AnchorType anchor) onAnchorTypeChanged;
  const MouseInfoWidget({
    super.key,
    required this.onAnchorTypeChanged,
  });
  @override
  MouseInfoWidgetState createState() => MouseInfoWidgetState();
}

class MouseInfoWidgetState extends State<MouseInfoWidget> {
  Timer? timer;
  AnchorType anchor = AnchorType.topLeft;
  String mousePos = "";
  String windowExe = "";
  String windowTitle = "";
  String windowClass = "";
  String mouseAnchor = "";
  String mouseAnchorPercentage = "";
  bool tracking = true;
  int lastKey = 0;
  final Map<int, String> _cached = <int, String>{};

  bool trackingEnabled = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
      if (!trackingEnabled) return;
      final int state = GetKeyState(VK_MENU);
      if (state < 0) {
        if (lastKey != state) {
          lastKey = state;
          tracking = !tracking;
          setState(() {});
        }
      }
      if (!tracking) return;
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      mousePos = "X: ${lpPoint.ref.x} Y: ${lpPoint.ref.y}";
      int hWnd = WindowFromPoint(lpPoint.ref);
      hWnd = GetAncestor(hWnd, 2);
      if (hWnd > 0) {
        if (!_cached.containsKey(hWnd)) {
          _cached[hWnd] = Win32.getExe(Win32.getWindowExePath(hWnd));
        }
        Pointer<RECT> lpRect = calloc<RECT>();
        GetWindowRect(hWnd, lpRect);
        windowExe = _cached[hWnd]!;
        windowTitle = Win32.getTitle(hWnd);
        windowClass = Win32.getClass(hWnd);
        int x = 0, y = 0;
        final int yTop = lpPoint.ref.y - lpRect.ref.top;
        final int yBottom = lpPoint.ref.y - lpRect.ref.bottom;
        final int xLeft = lpPoint.ref.x - lpRect.ref.left;
        final int xRight = lpPoint.ref.x - lpRect.ref.right;
        final int width = lpRect.ref.right - lpRect.ref.left;
        final int height = lpRect.ref.bottom - lpRect.ref.top;
        if (anchor == AnchorType.topLeft) {
          x = xLeft;
          y = yTop;
        } else if (anchor == AnchorType.topRight) {
          x = xRight;
          y = yTop;
        } else if (anchor == AnchorType.bottomLeft) {
          x = xLeft;
          y = yBottom;
        } else if (anchor == AnchorType.bottomRight) {
          x = xRight;
          y = yBottom;
        }
        x = x.abs();
        y = y.abs();
        mouseAnchor = "X:$x Y:$y";
        final int percentageX = ((x / width) * 100).floor();
        final int percentageY = ((y / height) * 100).floor();
        mouseAnchorPercentage = "X:$percentageX Y:$percentageY";
        free(lpRect);
      }
      free(lpPoint);
      setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CheckBoxWidget(
          key: UniqueKey(),
          onChanged: (bool e) => setState(() => trackingEnabled = !trackingEnabled),
          value: trackingEnabled,
          padding: const EdgeInsets.symmetric(vertical: 5),
          text: "Track Mouse Info. Press ALT to pause (${tracking && trackingEnabled ? "Tracking" : "Paused"})",
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 100,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      CustomTooltip(
                          message: AnchorType.topLeft.name.toString(),
                          child: Checkbox(
                              value: anchor == AnchorType.topLeft,
                              onChanged: (bool? e) => onAnchorChanged(AnchorType.topLeft))),
                      CustomTooltip(
                          message: AnchorType.topRight.name.toString(),
                          child: Checkbox(
                              value: anchor == AnchorType.topRight,
                              onChanged: (bool? e) => onAnchorChanged(AnchorType.topRight))),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      CustomTooltip(
                          message: AnchorType.bottomLeft.name.toString(),
                          child: Checkbox(
                              value: anchor == AnchorType.bottomLeft,
                              onChanged: (bool? e) => onAnchorChanged(AnchorType.bottomLeft))),
                      CustomTooltip(
                          message: AnchorType.bottomRight.name.toString(),
                          child: Checkbox(
                              value: anchor == AnchorType.bottomRight,
                              onChanged: (bool? e) => onAnchorChanged(AnchorType.bottomRight))),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text("Mouse Position:"),
                  SelectableText(mousePos),
                  const Text("Position Anchored:"),
                  SelectableText(mouseAnchor),
                  const Text("As Percentage:"),
                  SelectableText(mouseAnchorPercentage),
                  const Text("Window exe:"),
                  SelectableText(windowExe, maxLines: null),
                  const Text("Window class:"),
                  SelectableText(windowClass, maxLines: null),
                  const Text("Window title:"),
                  SelectableText(windowTitle, maxLines: null),
                ],
              ),
            ),
          ],
        ),
        Markdown(
          shrinkWrap: true,
          selectable: true,
          data: '''
## Limit to a window:
You can limit to a specific window if you change "Any Window" to a filter you want. The match is regex aware.

## Info About Region:
You can can execute this hotkey if the mouse is in a specific rectangle, either in an window or on Screen.
You can anchor the points to a position of specific screen,
 for example if you want to execute this only if the mouse is in bottomCorner, 
 you set Anchor Point to BottomRight, then make an rectacle startX,startY:endX,endY as big as you want.

## Info about sendKeys:

You can send multiple hotkeys or keystrokes.Use # to hold a key and ^ to release.
All Special keys need to be put between {}.To release all previous keys use {|}.

```{#CTRL}{#SHIFT}{ESCAPE}{|}{#SHIFT}{TAB}{^SHIFT}{RIGHT}```

Will open Task Manager And move to Performance Tab.

[Here you can find all special keys name](here)

Aditionally, for mouse use {LMB} {MMB} {RMB} {MSU} {MSD}
''',
          onTapLink: (String e, String? e1, String e2) {
            WinUtils.open("https://github.com/Far-Se/tabame/blob/master/lib/models/keys.dart#L188");
          },
        )
      ],
    );
  }

  void onAnchorChanged(AnchorType newAnchor) {
    anchor = newAnchor;
    widget.onAnchorTypeChanged(newAnchor);
    setState(() {});
  }
}
