import '../globals.dart';
import '../win32/mixed.dart';
import '../win32/win32.dart';
import 'saved_maps.dart';

/// Shared snap math used by the drag-triggered QuickSnap overlay, the
/// middle-click QuickSnap picker, and the standalone QuickSnap view — so all
/// three move/resize windows identically (DPI + invisible-border aware).
class QuickSnapApply {
  QuickSnapApply._();

  /// Moves/resizes [hWnd] into [zone] (a fractional 0..1 rect) on the monitor
  /// identified by [monitorId], leaving [gap] screen pixels between zones.
  ///
  /// [topInsetPhysical] reserves that many physical pixels at the top of the
  /// zone (e.g. for the standalone view's per-region taskbar strip) so the
  /// window is pushed below it instead of being covered by it.
  static void apply(int hWnd, QuickGridRect zone, int gap, int monitorId, {double topInsetPhysical = 0}) {
    final Square? monSize = Monitor.monitorSizes[monitorId];
    if (monSize == null) return;
    final Dpi? dpi = Monitor.dpi[monitorId];
    final double scaleX = dpi != null ? dpi.x / 96.0 : 1.0;
    final double scaleY = dpi != null ? dpi.y / 96.0 : 1.0;

    final double mx = monSize.x / scaleX;
    final double my = monSize.y / scaleY;
    final double mw = monSize.width / scaleX;
    final double mh = monSize.height / scaleY;

    Win32.restoreIfMaximized(hWnd);

    if (!Globals.snappedWindowOriginalSizes.containsKey(hWnd)) {
      final ({int height, int width}) size = Win32.getSize(hwnd: hWnd);
      Globals.snappedWindowOriginalSizes[hWnd] = <int>[size.width, size.height];
    }

    final ({int bottom, int left, int right, int top}) border = Win32.getInvisibleBorder(hWnd);
    final double borderLeft = border.left / scaleX;
    final double borderTop = border.top / scaleY;
    final double borderRight = border.right / scaleX;
    final double borderBottom = border.bottom / scaleY;

    final double g = gap / scaleX;
    final double half = g / 2;

    final double topInset = topInsetPhysical / scaleY;

    final double zx = mx + zone.left * mw;
    final double zy = my + zone.top * mh + topInset;
    final double zw = (zone.right - zone.left) * mw;
    final double zh = (zone.bottom - zone.top) * mh - topInset;

    final int x = (zx - borderLeft + half).round();
    final int y = (zy - borderTop + half).round();
    final int w = (zw + borderLeft + borderRight - g).round().clamp(100, mw.round());
    final int h = (zh + borderTop + borderBottom - g).round().clamp(60, mh.round());

    Win32.setPosDPI(hWnd, PointXY(X: x, Y: y), logicalWidth: w, logicalHeight: h);
  }
}
