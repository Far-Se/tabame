import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:win32/win32.dart';

import '../../../models/classes/hotkeys.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';

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
    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // Tracker Control Bar and Anchor Split
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "LIVE TRACKING",
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: onSurface.withAlpha(150),
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  InkWell(
                    onTap: () => setState(() => trackingEnabled = !trackingEnabled),
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: (trackingEnabled && tracking) ? Colors.green.withAlpha(40) : Colors.orange.withAlpha(40),
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: (trackingEnabled && tracking)
                              ? Colors.green.withAlpha(100)
                              : Colors.orange.withAlpha(100),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Icon(
                            (trackingEnabled && tracking) ? Icons.play_arrow : Icons.pause,
                            size: 14,
                            color: (trackingEnabled && tracking) ? Colors.green : Colors.orange,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            (trackingEnabled && tracking) ? "ACTIVE" : "PAUSED",
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: (trackingEnabled && tracking) ? Colors.green : Colors.orange,
                              fontWeight: FontWeight.bold,
                              fontSize: Design.baseFontSize,
                              letterSpacing: 0.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "Press ALT to pause/resume",
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: onSurface.withAlpha(120),
                      fontSize: Design.baseFontSize,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),
            // Visual Anchor Selector
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "ANCHOR",
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: onSurface.withAlpha(150),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(height: 8),
                _buildAnchorSelector(theme, accent),
              ],
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Textual Dashboard
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              "TELEMETRY",
              style: theme.textTheme.labelSmall?.copyWith(
                color: onSurface.withAlpha(150),
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withAlpha(60),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: onSurface.withAlpha(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  _buildDataRow("Screen Pos", mousePos, theme),
                  _buildDataRow("Anchored Pos", mouseAnchor, theme),
                  _buildDataRow("Percentage", mouseAnchorPercentage, theme),
                  Divider(height: 16, thickness: 1, color: onSurface.withAlpha(20)),
                  _buildDataRow("Window Title", windowTitle, theme),
                  _buildDataRow("Executable", windowExe, theme),
                  _buildDataRow("Win Class", windowClass, theme),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Expandable Documentation
        Theme(
          data: theme.copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: Row(
              children: <Widget>[
                Icon(Icons.help_outline, size: 18, color: onSurface.withAlpha(150)),
                const SizedBox(width: 8),
                Text(
                  "Documentation & Shortcuts",
                  style: theme.textTheme.titleSmall?.copyWith(color: onSurface.withAlpha(200)),
                ),
              ],
            ),
            children: <Widget>[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface.withAlpha(50),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: onSurface.withAlpha(20)),
                ),
                child: MarkdownBody(
                  selectable: true,
                  data: '''
**Limit to a window:**
You can limit the execution to a specific window by setting "Any Window" to your desired filter. Regex is supported.

**Region Targeting:**
Trigger actions only when the mouse is inside a specific rectangle (on-screen or inside window bounds).
Anchor to a screen position: For example, to target the bottom corner, set the Anchor Point to `BottomRight` and define a rectangle via `startX,startY:endX,endY`.

**Keystroke Commands:**
Send multiple key presses in a sequence.
- Use `#` to hold a key.
- Use `^` to release a key.
- Use `{}` to wrap special keys.
- Use `{|}` to forcibly release all previously held keys.

*Example:* `{#CTRL}{#SHIFT}{ESCAPE}{|}{#SHIFT}{TAB}{^SHIFT}{RIGHT}`
Will open Task Manager and navigate tabs.

[View all supported special keys](here)

*Mouse Commands:* `{LMB}`, `{MMB}`, `{RMB}`, `{MSU}`, `{MSD}`
''',
                  onTapLink: (String text, String? href, String title) {
                    WinUtils.open("https://github.com/Far-Se/tabame/blob/master/lib/models/win32/keys.dart#L188");
                  },
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAnchorSelector(ThemeData theme, Color accent) {
    return Container(
      width: 70,
      height: 70,
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(80),
        border: Border.all(color: theme.colorScheme.onSurface.withAlpha(40)),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: <Widget>[
          Expanded(
            child: Row(
              children: <Widget>[
                _buildAnchorQuadrant(AnchorType.topLeft, accent, const BorderRadius.only(topLeft: Radius.circular(7))),
                Container(width: 1, color: theme.colorScheme.onSurface.withAlpha(40)),
                _buildAnchorQuadrant(
                    AnchorType.topRight, accent, const BorderRadius.only(topRight: Radius.circular(7))),
              ],
            ),
          ),
          Container(height: 1, color: theme.colorScheme.onSurface.withAlpha(40)),
          Expanded(
            child: Row(
              children: <Widget>[
                _buildAnchorQuadrant(
                    AnchorType.bottomLeft, accent, const BorderRadius.only(bottomLeft: Radius.circular(7))),
                Container(width: 1, color: theme.colorScheme.onSurface.withAlpha(40)),
                _buildAnchorQuadrant(
                    AnchorType.bottomRight, accent, const BorderRadius.only(bottomRight: Radius.circular(7))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAnchorQuadrant(AnchorType type, Color accent, BorderRadius radius) {
    final bool isSelected = anchor == type;
    return Expanded(
      child: InkWell(
        onTap: () => onAnchorChanged(type),
        borderRadius: radius,
        child: Container(
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(70) : Colors.transparent,
            borderRadius: radius,
          ),
          child: Center(
            child: isSelected ? Icon(Icons.my_location, size: 16, color: accent) : const SizedBox(),
          ),
        ),
      ),
    );
  }

  Widget _buildDataRow(String label, String value, ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label.toUpperCase(),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(130),
              fontWeight: FontWeight.w700,
              fontSize: 9,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 2),
          SelectableText(
            value.isEmpty ? "—" : value,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withAlpha(240),
              fontFamily: 'Consolas',
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  void onAnchorChanged(AnchorType newAnchor) {
    anchor = newAnchor;
    widget.onAnchorTypeChanged(newAnchor);
    setState(() {});
  }
}
