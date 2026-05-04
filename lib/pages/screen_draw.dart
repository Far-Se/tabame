// main.dart
// Flutter Windows Screen Annotation Overlay
// Uses: win32 (pre-v6), ffi, dart:isolate, dart:ffi
//
// HWND discovery: FindWindowEx by class name 'FLUTTER_RUNNER_WIN32_WINDOW'
// Global hotkeys: RegisterHotKey with HWND=0 in a background isolate message pump
// Click-through: WS_EX_LAYERED | WS_EX_TRANSPARENT via SetWindowLongPtr
// No native runner changes required.

// ignore_for_file: unused_element, dead_code

import 'dart:async';
import 'dart:ffi' hide Size;
import 'dart:math';
import 'dart:ui' as ui;

import 'package:emoji_selector/emoji_selector.dart';
import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../models/classes/boxes.dart';
import '../models/classes/hotkeys.dart';
import '../models/classes/screen_draw_hotkeys.dart';
import '../models/win32/keys.dart';
import '../models/win32/mixed.dart';
import '../widgets/widgets/color_picker.dart';
import '../widgets/widgets/custom_tooltip.dart';

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> startScreenDraw() async {
  // Load settings and themes only, without
  WidgetsFlutterBinding.ensureInitialized();
  await Boxes.registerBoxes(justLoad: true);

  const WindowOptions windowOptions = WindowOptions(
    size: Size(1920, 1080),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: false,
    title: 'Tabame Screen Draw',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
    Win32Window._hwnd = GetAncestor(GetActiveWindow(), 2);
  });

  runApp(const AnnotationApp());
}

// ---------------------------------------------------------------------------
// Win32 helpers
// ---------------------------------------------------------------------------

class Win32Window {
  static int _hwnd = 0;

  /// Finds the Flutter window HWND by the known class name.
  static int getHwnd() {
    if (_hwnd != 0) return _hwnd;
    _hwnd = GetAncestor(GetActiveWindow(), 2);
    return _hwnd;
  }

  /// Make the window borderless, topmost, and full-screen.
  static void setupOverlay() {
    final int hwnd = getHwnd();
    if (hwnd == 0) return;

    // Remove title bar and borders
    final int style = GetWindowLongPtr(hwnd, GWL_STYLE);
    SetWindowLongPtr(
      hwnd,
      GWL_STYLE,
      style & ~(WS_CAPTION | WS_THICKFRAME | WS_MINIMIZEBOX | WS_MAXIMIZEBOX | WS_SYSMENU),
    );

    // Add layered + topmost extended styles
    final int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);
    SetWindowLongPtr(
      hwnd,
      GWL_EXSTYLE,
      exStyle | WS_EX_LAYERED | WS_EX_TOPMOST | WS_EX_TOOLWINDOW,
    );

    // Layered window: full opacity, color key unused
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    // Cover full primary monitor
    final int screenW = GetSystemMetrics(SM_CXSCREEN);
    final int screenH = GetSystemMetrics(SM_CYSCREEN);
    SetWindowPos(
      hwnd,
      HWND_TOPMOST,
      0,
      0,
      screenW,
      screenH,
      SWP_NOACTIVATE | SWP_FRAMECHANGED | SWP_SHOWWINDOW,
    );
  }

  /// Enable click-through: window stays visible but mouse passes through.
  static void enableClickThrough() {
    final int hwnd = getHwnd();
    if (hwnd == 0) return;

    final int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);

    SetWindowLongPtr(
      hwnd,
      GWL_EXSTYLE,
      exStyle | WS_EX_LAYERED | WS_EX_TRANSPARENT | WS_EX_NOACTIVATE,
    );

    // SetLayeredWindowAttributes(hwnd, 0, 220, LWA_ALPHA);

    // Important: refresh cached window styles
    SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_NOACTIVATE | SWP_FRAMECHANGED);
  }

  /// Disable click-through: window captures mouse again.
  static void disableClickThrough() {
    final int hwnd = getHwnd();
    if (hwnd == 0) return;

    final int exStyle = GetWindowLongPtr(hwnd, GWL_EXSTYLE);

    SetWindowLongPtr(hwnd, GWL_EXSTYLE, exStyle & ~WS_EX_TRANSPARENT & ~WS_EX_LAYERED & ~WS_EX_NOACTIVATE);

    // Restore full opacity (or whatever you prefer)
    SetLayeredWindowAttributes(hwnd, 0, 255, LWA_ALPHA);

    // Refresh style cache (same as before)
    SetWindowPos(hwnd, 0, 0, 0, 0, 0, SWP_NOMOVE | SWP_NOSIZE | SWP_NOZORDER | SWP_FRAMECHANGED);
  }

  /// Show/hide the overlay window.
  static void setVisible(bool visible) {
    final int hwnd = getHwnd();
    if (hwnd == 0) return;
    ShowWindow(hwnd, visible ? SW_SHOW : SW_HIDE);
    if (visible) {
      SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
    }
  }
}

class ScreenDrawCapture {
  static Future<void> copyRegionToClipboard(Rect screenRect) async {
    final int x = screenRect.left.round();
    final int y = screenRect.top.round();
    final int w = screenRect.width.round().clamp(1, 1000000);
    final int h = screenRect.height.round().clamp(1, 1000000);

    final int screenDc = GetDC(NULL);
    final int memDc = CreateCompatibleDC(screenDc);
    final int bmp = CreateCompatibleBitmap(screenDc, w, h);
    SelectObject(memDc, bmp);

    BitBlt(memDc, 0, 0, w, h, screenDc, x, y, SRCCOPY | CAPTUREBLT);

    final Pointer<BITMAPINFO> bmi = calloc<BITMAPINFO>();
    bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
    bmi.ref.bmiHeader.biWidth = w;
    bmi.ref.bmiHeader.biHeight = -h;
    bmi.ref.bmiHeader.biPlanes = 1;
    bmi.ref.bmiHeader.biBitCount = 32;
    bmi.ref.bmiHeader.biCompression = BI_RGB;

    final Pointer<Uint8> bgra = calloc<Uint8>(w * h * 4);
    GetDIBits(memDc, bmp, 0, h, bgra.cast(), bmi, DIB_RGB_COLORS);

    final Uint8List rgba = Uint8List(w * h * 4);
    final Uint8List src = bgra.asTypedList(w * h * 4);
    for (int i = 0; i < src.length; i += 4) {
      rgba[i] = src[i + 2];
      rgba[i + 1] = src[i + 1];
      rgba[i + 2] = src[i];
      rgba[i + 3] = 255;
    }

    DeleteObject(bmp);
    DeleteDC(memDc);
    ReleaseDC(NULL, screenDc);
    calloc.free(bgra);
    calloc.free(bmi);

    final img.Image image = img.Image.fromBytes(
      width: w,
      height: h,
      bytes: rgba.buffer,
      numChannels: 4,
      order: img.ChannelOrder.rgba,
    );
    await _copyPngToClipboard(Uint8List.fromList(img.encodePng(image)));
  }

  static Future<void> _copyPngToClipboard(Uint8List pngBytes) async {
    ClipboardExtended.copyImage(pngBytes);
    return;
  }
}
// ---------------------------------------------------------------------------
// Shape data model
// ---------------------------------------------------------------------------

enum DrawTool {
  select,
  screenCapture,
  pen,
  highlight,
  line,
  rect,
  ellipse,
  arrow,
  ruler,
  sizebox,
  guide,
  // New tools
  text,
  emoji,
  stepCounter,
  infoBalloon,
  magnifier,
  blur,
  pixelate,
  smartDelete,
  spotlight,
  imageDraw,
}

enum GuideOrientation { horizontal, vertical }

@immutable
class AppColor {
  static const List<Color> palette = <ui.Color>[
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Color(0xFF00FF00),
    Colors.cyan,
    Colors.blue,
    Colors.purple,
    Colors.white,
    Colors.black,
  ];
}

class DrawShape {
  final DrawTool tool;
  final List<Offset> points; // for pen: all points; for others: [start, end]
  final Color color;
  final double strokeWidth;
  final double opacity;
  bool selected;

  // Extra data for specialised tools
  final String? text; // text, infoBalloon
  final bool textBackground; // text: show background pill
  final Color? textColor; // explicit text color (nullable = use stroke color)
  final double? fontSize; // text: font size override
  final int? stepNumber; // stepCounter: which number
  /// Raw RGBA pixels captured from screen (blur/pixelate/smartDelete/spotlight/imageDraw/magnifier)
  final Uint8List? imageBytes;
  final int? imageW;
  final int? imageH;

  /// For smartDelete: the fill color sampled from the first pixel
  final Color? fillColor;

  DrawShape({
    required this.tool,
    required this.points,
    required this.color,
    required this.strokeWidth,
    required this.opacity,
    this.selected = false,
    this.text,
    this.textBackground = true,
    this.textColor,
    this.fontSize,
    this.stepNumber,
    this.imageBytes,
    this.imageW,
    this.imageH,
    this.fillColor,
  });

  DrawShape copyWith({
    List<Offset>? points,
    bool? selected,
    String? text,
    bool? textBackground,
    Color? textColor,
    double? fontSize,
    int? stepNumber,
    Uint8List? imageBytes,
    int? imageW,
    int? imageH,
    Color? fillColor,
  }) {
    return DrawShape(
      tool: tool,
      points: points ?? this.points,
      color: color,
      strokeWidth: strokeWidth,
      opacity: opacity,
      selected: selected ?? this.selected,
      text: text ?? this.text,
      textBackground: textBackground ?? this.textBackground,
      textColor: textColor ?? this.textColor,
      fontSize: fontSize ?? this.fontSize,
      stepNumber: stepNumber ?? this.stepNumber,
      imageBytes: imageBytes ?? this.imageBytes,
      imageW: imageW ?? this.imageW,
      imageH: imageH ?? this.imageH,
      fillColor: fillColor ?? this.fillColor,
    );
  }
}

class GuideLineModel {
  final GuideOrientation orientation;
  final Color color;
  double position; // screen coordinate (x for vertical, y for horizontal)
  bool locked;
  bool selected;

  GuideLineModel({
    required this.orientation,
    required this.color,
    required this.position,
    this.locked = false,
    this.selected = false,
  });
}

// ---------------------------------------------------------------------------
// Annotation state / controller
// ---------------------------------------------------------------------------

class AnnotationController extends ChangeNotifier {
  // Mode
  bool drawingModeActive = true;
  bool overlayVisible = true;

  // Tool
  DrawTool activeTool = DrawTool.pen;

  // Style
  Color strokeColor = Colors.red;
  double strokeWidth = 2.0;
  double opacity = 1.0;

  // Grid
  bool gridVisible = false;
  double gridSpacing = 50.0;

  // Magnifier
  bool magnifierVisible = false;

  // Text tool options
  bool textBackground = true;
  double fontSize = 16.0;
  Color? textColor; // null = use strokeColor

  // Step counter: auto-incrementing number
  int _stepCount = 1;
  int get nextStepNumber => _stepCount;
  void resetStepCounter() {
    _stepCount = 1;
    notifyListeners();
  }

  // Pending text/balloon callback (set by overlay, consumed here)
  String? pendingText;

  // Shapes
  final List<DrawShape> _shapes = <DrawShape>[];
  final List<DrawShape> _redoStack = <DrawShape>[];
  final List<GuideLineModel> _guides = <GuideLineModel>[];

  List<DrawShape> get shapes => List<DrawShape>.unmodifiable(_shapes);
  List<GuideLineModel> get guides => List<GuideLineModel>.unmodifiable(_guides);

  // Current in-progress shape
  DrawShape? currentShape;
  Offset? currentEnd;

  // Guide being dragged
  GuideLineModel? _draggingGuide;
  GuideLineModel? get draggingGuide => _draggingGuide;

  void toggleGrid() {
    gridVisible = !gridVisible;
    notifyListeners(); // This is allowed here because it's inside the class
  }

  // Selected shape index
  int? selectedShapeIndex;
  DrawShape? get selectedShape {
    final int? index = selectedShapeIndex;
    if (index == null || index < 0 || index >= _shapes.length) return null;
    return _shapes[index];
  }

  void toggleDrawingMode({bool? activated}) {
    drawingModeActive = activated ?? !drawingModeActive;
    if (drawingModeActive) {
      Win32Window.disableClickThrough();
      Future<void>.delayed(const Duration(milliseconds: 100), () async {
        await windowManager.show();
        await WindowManager.instance.focus();
      });
    } else {
      Win32Window.enableClickThrough();
    }
    notifyListeners();
  }

  void toggleVisibility() {
    overlayVisible = !overlayVisible;
    if (overlayVisible) WindowManager.instance.focus();
    Win32Window.setVisible(overlayVisible);
    notifyListeners();
  }

  void setTool(DrawTool t) {
    if (t == DrawTool.select) {
      selectMode = true;
    } else {
      selectMode = false;
    }
    activeTool = t;
    notifyListeners();
  }

  void toggleTextBackground() {
    textBackground = !textBackground;
    notifyListeners();
  }

  void setFontSize(double s) {
    fontSize = s;
    notifyListeners();
  }

  void setTextColor(Color? c) {
    textColor = c;
    notifyListeners();
  }

  void setColor(Color c) {
    strokeColor = c;
    notifyListeners();
  }

  void setStrokeWidth(double w) {
    strokeWidth = w;
    notifyListeners();
  }

  void setOpacity(double o) {
    opacity = o;
    notifyListeners();
  }

  // ── Drawing lifecycle ──────────────────────────────────────────────────────

  void startShape(Offset pos) {
    if (activeTool == DrawTool.guide) {
      // Guide creation handled separately
      return;
    }
    // These tools are committed on tap/drag-end; skip buffering a currentShape for single-point tools
    _redoStack.clear();
    currentShape = DrawShape(
      tool: activeTool,
      points: <ui.Offset>[pos],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      textBackground: textBackground,
      stepNumber: activeTool == DrawTool.stepCounter ? _stepCount : null,
    );
    currentEnd = pos;
    notifyListeners();
  }

  void updateShape(Offset pos, {bool shiftHeld = false}) {
    if (currentShape == null) return;
    if (activeTool == DrawTool.pen) {
      currentShape = currentShape!.copyWith(
        points: <ui.Offset>[...currentShape!.points, pos],
      );
    } else if (activeTool == DrawTool.highlight) {
      final ui.Offset start = currentShape!.points.first;

      if (shiftHeld) {
        currentEnd = _snap45(start, pos);
      } else {
        currentEnd = null;
        currentShape = currentShape!.copyWith(
          points: <ui.Offset>[...currentShape!.points, pos],
        );
      }
    } else {
      final ui.Offset start = currentShape!.points.first;
      currentEnd = shiftHeld ? _snap45(start, pos) : pos;
    }

    notifyListeners();
  }

  void endShape() {
    if (currentShape == null) return;

    DrawShape finished;

    if (activeTool == DrawTool.pen) {
      finished = currentShape!;
    } // endShape()
    else if (activeTool == DrawTool.highlight) {
      finished = currentEnd == null
          ? currentShape!
          : currentShape!.copyWith(
              points: <ui.Offset>[
                currentShape!.points.first,
                currentEnd!,
              ],
            );
    } else {
      finished = currentShape!.copyWith(
        points: <ui.Offset>[
          currentShape!.points.first,
          currentEnd ?? currentShape!.points.last,
        ],
      );
    }

    _shapes.add(finished);

    // Increment step counter after committing
    if (activeTool == DrawTool.stepCounter) _stepCount++;

    currentShape = null;
    currentEnd = null;
    notifyListeners();
  }

  /// Called by overlay after user types text-like content.
  void commitTextShape(Offset pos, String text) {
    if (text.isEmpty) return;
    _redoStack.clear();
    _shapes.add(DrawShape(
      tool: activeTool,
      points: <ui.Offset>[pos, pos],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      text: text,
      textBackground: activeTool == DrawTool.emoji ? false : textBackground,
      textColor: textColor,
      fontSize: fontSize,
    ));
    notifyListeners();
  }

  /// Called by overlay after a screen region is captured (blur/pixelate/smartDelete/spotlight/imageDraw/magnifier).
  void commitImageShape(DrawTool tool, Rect region, Uint8List bytes, int w, int h, {Color? fillColor}) {
    _redoStack.clear();
    _shapes.add(DrawShape(
      tool: tool,
      points: <ui.Offset>[region.topLeft, region.bottomRight],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      imageBytes: bytes,
      imageW: w,
      imageH: h,
      fillColor: fillColor,
    ));
    notifyListeners();
  }

  // ── Guide lines ────────────────────────────────────────────────────────────

  void addGuide(GuideOrientation orientation, double position) {
    _clearGuideSelection(notify: false);
    _guides.add(GuideLineModel(
      orientation: orientation,
      color: strokeColor,
      position: position,
      selected: true,
    ));
    notifyListeners();
  }

  void startDragGuide(GuideLineModel g) {
    selectGuide(g, notify: false);
    _draggingGuide = g;
    notifyListeners();
  }

  void dragGuide(Offset pos) {
    if (_draggingGuide == null) return;
    if (_draggingGuide!.locked) return;
    _draggingGuide!.position = _draggingGuide!.orientation == GuideOrientation.horizontal ? pos.dy : pos.dx;
    notifyListeners();
  }

  void endDragGuide() {
    _draggingGuide = null;
    notifyListeners();
  }

  void selectGuide(GuideLineModel guide, {bool notify = true}) {
    for (final GuideLineModel item in _guides) {
      item.selected = identical(item, guide);
    }
    for (final DrawShape shape in _shapes) {
      shape.selected = false;
    }
    selectedShapeIndex = null;
    if (notify) notifyListeners();
  }

  void clearGuideSelection({bool notify = true}) {
    _clearGuideSelection(notify: notify);
  }

  void _clearGuideSelection({bool notify = true}) {
    bool changed = false;
    for (final GuideLineModel guide in _guides) {
      if (guide.selected) {
        guide.selected = false;
        changed = true;
      }
    }
    if (notify && changed) notifyListeners();
  }

  bool deleteSelectedGuide() {
    final int index = _guides.indexWhere((GuideLineModel guide) => guide.selected);
    if (index == -1) return false;
    if (identical(_draggingGuide, _guides[index])) _draggingGuide = null;
    _guides.removeAt(index);
    notifyListeners();
    return true;
  }

  bool deleteGuideAt(Offset pos, {double tolerance = 8}) {
    for (int i = _guides.length - 1; i >= 0; i--) {
      final GuideLineModel guide = _guides[i];
      final double distance = guide.orientation == GuideOrientation.horizontal
          ? (pos.dy - guide.position).abs()
          : (pos.dx - guide.position).abs();
      if (distance >= tolerance) continue;
      if (identical(_draggingGuide, guide)) _draggingGuide = null;
      _guides.removeAt(i);
      notifyListeners();
      return true;
    }
    return false;
  }

  // ── Undo / redo ────────────────────────────────────────────────────────────

  void undo() {
    if (_shapes.isEmpty) return;
    _redoStack.add(_shapes.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redoStack.isEmpty) return;
    _shapes.add(_redoStack.removeLast());
    notifyListeners();
  }

  void clearAll() {
    _shapes.clear();
    _guides.clear();
    _redoStack.clear();
    currentShape = null;
    currentEnd = null;
    notifyListeners();
  }

  void deleteSelected() {
    if (selectedShapeIndex != null) {
      _shapes.removeAt(selectedShapeIndex!);
      selectedShapeIndex = null;
      notifyListeners();
      return;
    }
    deleteSelectedGuide();
  }

  bool deleteShapeAt(Offset pos) {
    for (int i = _shapes.length - 1; i >= 0; i--) {
      if (_hitTest(_shapes[i], pos)) {
        _shapes.removeAt(i);
        selectedShapeIndex = null;
        _clearGuideSelection(notify: false);
        _redoStack.clear();
        notifyListeners();
        return true;
      }
    }
    return false;
  }

  void selectShapeAt(Offset pos) {
    _clearGuideSelection(notify: false);
    for (int i = _shapes.length - 1; i >= 0; i--) {
      if (_hitTest(_shapes[i], pos)) {
        for (DrawShape s in _shapes) {
          s.selected = false;
        }
        _shapes[i].selected = true;
        selectedShapeIndex = i;
        notifyListeners();
        return;
      }
    }
    for (DrawShape s in _shapes) {
      s.selected = false;
    }
    selectedShapeIndex = null;
    notifyListeners();
  }

  void moveSelected(Offset delta) {
    if (selectedShapeIndex == null) return;
    final DrawShape s = _shapes[selectedShapeIndex!];
    _shapes[selectedShapeIndex!] = s.copyWith(
      points: s.points.map((ui.Offset p) => p + delta).toList(),
    );
    notifyListeners();
  }

  void updateSelectedImage(Uint8List bytes, int w, int h) {
    final int? index = selectedShapeIndex;
    if (index == null || index < 0 || index >= _shapes.length) return;
    _shapes[index] = _shapes[index].copyWith(imageBytes: bytes, imageW: w, imageH: h);
    notifyListeners();
  }

  bool _hitTest(DrawShape s, Offset pos) {
    if (s.tool == DrawTool.pen || s.tool == DrawTool.highlight) {
      return s.points.any((ui.Offset p) => (p - pos).distance < 8);
    }
    if (s.points.length < 2) return false;
    final ui.Offset a = s.points.first;
    final ui.Offset b = s.points.last;
    // All rect-based and region tools: hit inside rect
    if (s.tool == DrawTool.rect ||
        s.tool == DrawTool.sizebox ||
        s.tool == DrawTool.blur ||
        s.tool == DrawTool.pixelate ||
        s.tool == DrawTool.smartDelete ||
        s.tool == DrawTool.spotlight ||
        s.tool == DrawTool.imageDraw ||
        s.tool == DrawTool.magnifier) {
      return Rect.fromPoints(a, b).inflate(6).contains(pos);
    }
    // Text-like tools: hit their actual painted bounds, not only the anchor.
    if (s.tool == DrawTool.text || s.tool == DrawTool.emoji) {
      return _textHitRect(s, a).contains(pos);
    }
    if (s.tool == DrawTool.infoBalloon) {
      return _infoBalloonHitPath(s, a).contains(pos);
    }
    if (s.tool == DrawTool.stepCounter) {
      return Rect.fromCircle(center: a, radius: 22).contains(pos);
    }
    // line/ruler/arrow/ellipse: proximity to center
    final ui.Offset center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    return (center - pos).distance < 24;
  }

  Rect _textHitRect(DrawShape s, Offset pos) {
    final String text = s.text ?? '';
    if (text.isEmpty) return Rect.fromCircle(center: pos, radius: 24);
    final double fs = s.fontSize ?? (s.strokeWidth * 8 + 12);
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: fs, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    return Rect.fromLTWH(pos.dx - 6, pos.dy - 6, tp.width + 12, tp.height + 12).inflate(6);
  }

  Path _infoBalloonHitPath(DrawShape s, Offset pos) {
    final String text = s.text ?? '';
    if (text.isEmpty) return Path()..addOval(Rect.fromCircle(center: pos, radius: 24));
    const double padding = 10.0;
    const double tailH = 14.0;
    const double radius = 8.0;
    final double fs = s.fontSize ?? (s.strokeWidth * 6 + 12);
    final TextPainter tp = TextPainter(
      text: TextSpan(text: text, style: TextStyle(fontSize: fs)),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 280);
    final double bw = tp.width + padding * 2;
    final double bh = tp.height + padding * 2;
    final Rect bubble = Rect.fromLTWH(pos.dx - bw / 2, pos.dy - bh - tailH, bw, bh);
    return Path()
      ..addRRect(RRect.fromRectAndRadius(bubble.inflate(6), const Radius.circular(radius)))
      ..addPolygon(<Offset>[
        Offset(pos.dx - 12, pos.dy - tailH - 6),
        Offset(pos.dx + 12, pos.dy - tailH - 6),
        Offset(pos.dx, pos.dy + 6),
      ], true);
  }

  // ── Snap helper ──────────────────────────────────────────────────────────

  Offset _snap45(Offset start, Offset end) {
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    final double angle = atan2(dy, dx);
    final double len = sqrt(dx * dx + dy * dy);
    // Snap to nearest 45°
    final double snapped = (angle / (pi / 4)).round() * (pi / 4);
    return Offset(start.dx + cos(snapped) * len, start.dy + sin(snapped) * len);
  }
}

// ---------------------------------------------------------------------------
// App root
// ---------------------------------------------------------------------------

class AnnotationApp extends StatelessWidget {
  const AnnotationApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: const AnnotationShell(),
    );
  }
}

// ---------------------------------------------------------------------------
// Shell: sets up Win32, wires hotkeys, owns the controller
// ---------------------------------------------------------------------------

class AnnotationShell extends StatefulWidget {
  const AnnotationShell({super.key});

  @override
  State<AnnotationShell> createState() => _AnnotationShellState();
}

class _AnnotationShellState extends State<AnnotationShell> with TabameListener {
  final AnnotationController _ctrl = AnnotationController();
  Timer? _timer;
  int _sizeIncrement = 1;
  @override
  void initState() {
    super.initState();
    NativeHooks.registerCallHandler();
    NativeHooks.addListener(this);
    // Defer Win32 setup until after the window is rendered
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Win32Window.setupOverlay();
      _ctrl.toggleDrawingMode(activated: true);
      unawaited(_registerScreenDrawHotkeys());
    });
    Monitor.fetchMonitors();
    checkResize();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _ticker());
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 300));
      if (!mounted) return;

      final Size size = await windowManager.getSize();
      await windowManager.setSize(Size(size.width + _sizeIncrement, size.height + _sizeIncrement));
      _sizeIncrement = _sizeIncrement == 1 ? -1 : 1;
    });
  }

  int currentMonitor = 0;
  Square monitorData = Square(x: 0, y: 0, width: 0, height: 0);
  final bool _shouldResize = true;
  Future<void> checkResize() async {
    if (!_shouldResize || !_ctrl.drawingModeActive) return;
    final Pointer<POINT> lpPoint = calloc<POINT>();
    GetCursorPos(lpPoint);
    final int monitor = MonitorFromPoint(lpPoint.ref, 0);
    free(lpPoint);

    if (monitor != currentMonitor) {
      currentMonitor = monitor;
      monitorData = Monitor.monitorSizes[monitor]!;
      await WindowManager.instance.setPosition(
        Offset(monitorData.x.toDouble(), monitorData.y.toDouble()),
      );
      await WindowManager.instance.setSize(
        Size(monitorData.width.toDouble(), monitorData.height.toDouble()),
      );
    }
  }

  void _ticker() {
    checkResize();
  }

  Future<void> _registerScreenDrawHotkeys() async {
    final List<Map<String, dynamic>> hotkeys = <Map<String, dynamic>>[];
    for (final ScreenDrawHotkeyBinding binding in Boxes.screenDrawHotkeys) {
      if (!binding.enabled || !binding.isScreenDraw) continue;
      final int? keyVk = keyMap["VK_${binding.key.toUpperCase()}"];
      if (keyVk == null) continue;
      hotkeys.add(<String, dynamic>{
        "name": binding.actionId,
        "hotkey": binding.hotkey.toUpperCase(),
        "keyVK": keyVk,
        "modifisers":
            binding.modifiers.isNotEmpty ? Hotkeys.normalizeModifiers(binding.modifiers).join('+') : "noModifiers",
        "listenToMovement": false,
        "matchWindowBy": "",
        "matchWindowText": "",
        "activateWindowUnderCursor": false,
        "noopScreenBusy": false,
        "prohibitedWindows": "",
        "regionasPercentage": false,
        "regionOnScreen": false,
        "regionX1": 0,
        "regionX2": 0,
        "regionY1": 0,
        "regionY2": 0,
        "anchorType": 0,
      });
    }
    await NativeHooks.runHotkeys(hotkeys);
  }

  @override
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) {
    if (hotkeyInfo.action != "releaseKbd") return;
    final ScreenDrawHotkeyBinding? binding = Boxes.screenDrawHotkeys.cast<ScreenDrawHotkeyBinding?>().firstWhere(
          (ScreenDrawHotkeyBinding? item) => item != null && item.isScreenDraw && item.hotkey == hotkeyInfo.hotkey,
          orElse: () => null,
        );
    switch (binding?.action) {
      case ScreenDrawHotkeyAction.toggleDrawing:
        _ctrl.toggleDrawingMode();
      case ScreenDrawHotkeyAction.toggleVisibility:
        _ctrl.toggleVisibility();
      case ScreenDrawHotkeyAction.closeScreenDraw:
        unawaited(windowManager.close());
      case ScreenDrawHotkeyAction.spotlightEnable:
      case ScreenDrawHotkeyAction.spotlightSetActiveWindow:
      case ScreenDrawHotkeyAction.spotlightRaiseBlurSigma:
      case ScreenDrawHotkeyAction.spotlightDecreaseBlurSigma:
      case ScreenDrawHotkeyAction.spotlightRaiseDimOpacity:
      case ScreenDrawHotkeyAction.spotlightDecreaseDimOpacity:
      case ScreenDrawHotkeyAction.spotlightClose:
        return;
      case null:
        return;
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    NativeHooks.removeListener(this);
    unawaited(NativeHooks.unHook());
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ListenableBuilder(
        listenable: _ctrl,
        builder: (_, __) => AnnotationOverlay(controller: _ctrl),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main overlay widget
// ---------------------------------------------------------------------------

class AnnotationOverlay extends StatefulWidget {
  final AnnotationController controller;
  const AnnotationOverlay({super.key, required this.controller});

  @override
  State<AnnotationOverlay> createState() => _AnnotationOverlayState();
}

bool selectMode = false;

class _AnnotationOverlayState extends State<AnnotationOverlay> {
  AnnotationController get ctrl => widget.controller;

  bool _shiftHeld = false;
  Offset? _lastSelectPos;
  Offset? _captureStart;
  Offset? _captureCurrent;

  // Live screen-captured region shapes (refetch on drag): blur, pixelate, smartDelete, spotlight, magnifier
  // Key = tool, value = shape being previewed
  DrawShape? _liveRegionShape; // current in-progress region preview (with fetched pixels)

  // imageDraw: no live drag — committed on pan-end, moveable only via Select
  // (nothing extra needed here since imageDraw goes through the normal shape commit path)

  // Magnifier: live circle lens from screen capture
  Offset? _magnifierCenter;
  DrawShape? _magnifierShape; // fetched pixels for the magnifier circle

  Timer? _liveRegionFetchDebounce;
  int _selectedImageRefreshToken = 0;

  // One frozen background per drawing-mode activation / monitor.
  // Region tools crop from this buffer instead of BitBlt-ing the live overlay.
  Uint8List? _monitorSnapshotBytes;
  Rect? _monitorSnapshotScreenRect;
  int? _monitorSnapshotW;
  int? _monitorSnapshotH;
  int? _monitorSnapshotMonitor;
  bool _snapshotInProgress = false;
  Uint8List? _captureMonitorSnapshotBytes;
  Rect? _captureMonitorSnapshotScreenRect;
  int? _captureMonitorSnapshotW;
  int? _captureMonitorSnapshotH;
  int? _captureMonitorSnapshotMonitor;
  bool _captureMonitorSnapshotInProgress = false;
  bool _lastDrawingModeActive = false;

  @override
  void initState() {
    super.initState();
    _lastDrawingModeActive = ctrl.drawingModeActive;
    ctrl.addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _liveRegionFetchDebounce?.cancel();
    ctrl.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (ctrl.drawingModeActive && !_lastDrawingModeActive) {
      _discardMonitorSnapshot();
    }
    _lastDrawingModeActive = ctrl.drawingModeActive;
  }

  void _discardMonitorSnapshot() {
    _monitorSnapshotBytes = null;
    _monitorSnapshotScreenRect = null;
    _monitorSnapshotW = null;
    _monitorSnapshotH = null;
    _monitorSnapshotMonitor = null;
    _captureMonitorSnapshotBytes = null;
    _captureMonitorSnapshotScreenRect = null;
    _captureMonitorSnapshotW = null;
    _captureMonitorSnapshotH = null;
    _captureMonitorSnapshotMonitor = null;
  }

  // For guide dragging hit-test
  GuideLineModel? _hitGuide(Offset pos) {
    for (final GuideLineModel g in ctrl.guides) {
      if (g.orientation == GuideOrientation.horizontal) {
        if ((pos.dy - g.position).abs() < 8) return g;
      } else {
        if ((pos.dx - g.position).abs() < 8) return g;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final ui.Size size = MediaQuery.of(context).size;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Stack(
        children: <Widget>[
          // Spotlight is below the annotation painter so existing drawn
          // elements stay visible over the blurred outside area.
          ListenableBuilder(
            listenable: ctrl,
            builder: (_, __) => Stack(
              children: ctrl.shapes
                  .where((DrawShape s) => s.imageBytes != null && s.tool == DrawTool.spotlight)
                  .map((DrawShape s) => _CommittedImageShape(shape: s))
                  .toList(),
            ),
          ),
          // Transparent canvas background
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onPanStart: _onPanStart,
              onPanUpdate: _onPanUpdate,
              onPanEnd: _onPanEnd,
              onTapDown: _onTapDown,
              onSecondaryTapDown: _onSecondaryTapDown,
              child: CustomPaint(
                size: size,
                painter: AnnotationPainter(
                  shapes: ctrl.shapes,
                  currentShape: ctrl.currentShape,
                  currentEnd: ctrl.currentEnd,
                  guides: ctrl.guides,
                  gridVisible: ctrl.gridVisible,
                  gridSpacing: ctrl.gridSpacing,
                  drawingMode: ctrl.drawingModeActive,
                ),
              ),
            ),
          ),
          // Other committed image-backed shapes stay above the base painter.
          ListenableBuilder(
            listenable: ctrl,
            builder: (_, __) => Stack(
              children: ctrl.shapes
                  .where((DrawShape s) =>
                      s.imageBytes != null &&
                      (s.tool == DrawTool.blur ||
                          s.tool == DrawTool.pixelate ||
                          s.tool == DrawTool.smartDelete ||
                          s.tool == DrawTool.imageDraw ||
                          s.tool == DrawTool.magnifier))
                  .map((DrawShape s) => _CommittedImageShape(shape: s))
                  .toList(),
            ),
          ),
          if (_liveRegionShape != null && _captureStart != null && _captureCurrent != null)
            _LiveRegionWidget(
              shape: _liveRegionShape!,
              rect: Rect.fromPoints(_captureStart!, _captureCurrent!),
            ),
          // Magnifier lens (circular zoom from live screen capture)
          if (false &&
              ctrl.drawingModeActive &&
              ctrl.activeTool == DrawTool.magnifier &&
              _magnifierShape != null &&
              _magnifierCenter != null)
            _MagnifierLens(center: _magnifierCenter!, shape: _magnifierShape!),
          // Toolbar (only in drawing mode)
          if (ctrl.drawingModeActive)
            Positioned(
              left: 8,
              top: 8,
              child: AnnotationToolbar(controller: ctrl),
            ),
          // Status bar
          if (ctrl.drawingModeActive)
            Positioned(
              bottom: 8,
              left: 8,
              child: _StatusBar(controller: ctrl),
            ),
          // Cursor crosshair hint
          if (ctrl.drawingModeActive && !selectMode)
            const Positioned.fill(
              child: _CrosshairLayer(
                onHover: null,
              ),
            ),
          if (_captureStart != null &&
              _captureCurrent != null &&
              !_isLiveRegionTool(ctrl.activeTool) &&
              ctrl.activeTool != DrawTool.magnifier)
            Positioned.fill(
              child: IgnorePointer(
                child: CustomPaint(
                  painter: _CaptureSelectionPainter(Rect.fromPoints(_captureStart!, _captureCurrent!)),
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onKeyEvent(KeyEvent e) {
    _shiftHeld = HardwareKeyboard.instance.isShiftPressed;

    if (e is KeyDownEvent) {
      final bool lCtrl = HardwareKeyboard.instance.isControlPressed;
      // In-app shortcuts (focus required)
      if (lCtrl) {
        if (e.logicalKey == LogicalKeyboardKey.keyZ) ctrl.undo();
        if (e.logicalKey == LogicalKeyboardKey.keyY) ctrl.redo();
        if (e.logicalKey == LogicalKeyboardKey.keyG) {
          // ctrl.gridVisible = !ctrl.gridVisible;
          // ctrl.notifyListeners();
          ctrl.toggleGrid();
        }
      }
      if (e.logicalKey == LogicalKeyboardKey.delete) ctrl.deleteSelected();
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        // ctrl.currentShape = null;
        // ctrl.notifyListeners();
        ctrl.toggleVisibility();
      }
      // Tool shortcuts
      final Map<LogicalKeyboardKey, DrawTool> toolKeys = <LogicalKeyboardKey, DrawTool>{
        LogicalKeyboardKey.keyS: DrawTool.select,
        LogicalKeyboardKey.keyP: DrawTool.pen,
        LogicalKeyboardKey.keyH: DrawTool.highlight,
        LogicalKeyboardKey.keyL: DrawTool.line,
        LogicalKeyboardKey.keyR: DrawTool.rect,
        LogicalKeyboardKey.keyE: DrawTool.ellipse,
        LogicalKeyboardKey.keyA: DrawTool.arrow,
        LogicalKeyboardKey.keyM: DrawTool.ruler,
        LogicalKeyboardKey.keyB: DrawTool.sizebox,
        LogicalKeyboardKey.keyU: DrawTool.guide,
        LogicalKeyboardKey.keyC: DrawTool.screenCapture,
        LogicalKeyboardKey.keyT: DrawTool.text,
        LogicalKeyboardKey.keyJ: DrawTool.emoji,
        LogicalKeyboardKey.keyN: DrawTool.stepCounter,
        LogicalKeyboardKey.keyI: DrawTool.infoBalloon,
        LogicalKeyboardKey.keyZ: DrawTool.magnifier,
        LogicalKeyboardKey.keyF: DrawTool.blur,
        LogicalKeyboardKey.keyX: DrawTool.pixelate,
        LogicalKeyboardKey.keyD: DrawTool.smartDelete,
        LogicalKeyboardKey.keyO: DrawTool.spotlight,
        LogicalKeyboardKey.keyW: DrawTool.imageDraw,
      };
      if (toolKeys.containsKey(e.logicalKey)) {
        ctrl.setTool(toolKeys[e.logicalKey]!);
      }

      if (e.logicalKey == LogicalKeyboardKey.keyS && lCtrl) {
        selectMode = !selectMode;
        setState(() {});
      }
    }
  }

  bool _addingGuide = false;

  bool _isLiveRegionTool(DrawTool t) =>
      t == DrawTool.blur || t == DrawTool.pixelate || t == DrawTool.smartDelete || t == DrawTool.spotlight;

  bool _isRegionTool(DrawTool t) => _isLiveRegionTool(t) || t == DrawTool.imageDraw;

  bool _usesCaptureMonitorTool(DrawTool t) => t == DrawTool.magnifier || t == DrawTool.blur || t == DrawTool.pixelate;

  void _onPanStart(DragStartDetails d) {
    if (!ctrl.drawingModeActive) return;
    final ui.Offset pos = d.localPosition;

    if (ctrl.activeTool == DrawTool.screenCapture) {
      setState(() {
        _captureStart = pos;
        _captureCurrent = pos;
      });
      return;
    }
    if (ctrl.activeTool == DrawTool.magnifier) return;

    final GuideLineModel? hit = _hitGuide(pos);
    if (hit != null) {
      ctrl.startDragGuide(hit);
      return;
    }
    if (ctrl.activeTool == DrawTool.guide) {
      _addingGuide = true;
      return;
    }

    if (selectMode) {
      ctrl.selectShapeAt(pos);
      _lastSelectPos = pos;
      unawaited(_refreshSelectedCaptureMonitorShape(force: true));
      return;
    }

    if (_isRegionTool(ctrl.activeTool)) {
      setState(() {
        _captureStart = pos;
        _captureCurrent = pos;
      });
      // Freeze the monitor once for this drawing-mode activation / monitor.
      // The preview and commit below crop from this cache; they do not capture
      // the live overlay while the mouse moves.
      unawaited(_ensureRegionToolSnapshot(ctrl.activeTool).then((_) {
        if (!mounted || !_isLiveRegionTool(ctrl.activeTool)) return;
        unawaited(_fetchLiveRegion(Rect.fromPoints(pos, pos)));
      }));
      return;
    }
    ctrl.startShape(pos);
  }

  void _onPanUpdate(DragUpdateDetails d) {
    if (!ctrl.drawingModeActive) return;
    final ui.Offset pos = d.localPosition;

    if (ctrl.activeTool == DrawTool.magnifier) return;

    if (ctrl.activeTool == DrawTool.screenCapture && _captureStart != null) {
      setState(() => _captureCurrent = pos);
      return;
    }
    if (_isRegionTool(ctrl.activeTool) && _captureStart != null) {
      setState(() => _captureCurrent = pos);
      if (_isLiveRegionTool(ctrl.activeTool)) {
        final Rect region = Rect.fromPoints(_captureStart!, pos);
        if (_usesCaptureMonitorTool(ctrl.activeTool)) {
          _debounceLiveRegionFetch(region);
        } else {
          unawaited(_fetchLiveRegion(region));
        }
      }
      return;
    }
    if (ctrl.activeTool == DrawTool.guide && _addingGuide) {
      _addingGuide = false;
      final GuideOrientation ori =
          d.delta.dx.abs() < d.delta.dy.abs() ? GuideOrientation.vertical : GuideOrientation.horizontal;
      ctrl.addGuide(ori, ori == GuideOrientation.horizontal ? pos.dy : pos.dx);
      return;
    }
    if (ctrl.draggingGuide != null) {
      ctrl.dragGuide(pos);
      return;
    }
    if (selectMode && _lastSelectPos != null) {
      ctrl.moveSelected(pos - _lastSelectPos!);
      _lastSelectPos = pos;
      return;
    }
    ctrl.updateShape(pos, shiftHeld: _shiftHeld);
  }

  void _onPanEnd(DragEndDetails d) {
    if (!ctrl.drawingModeActive) return;

    if (ctrl.activeTool == DrawTool.screenCapture) {
      unawaited(_copyCaptureSelection());
      return;
    }

    if (_isLiveRegionTool(ctrl.activeTool) && _captureStart != null && _captureCurrent != null) {
      _liveRegionFetchDebounce?.cancel();
      final Rect region = Rect.fromPoints(_captureStart!, _captureCurrent!);
      if (region.width > 4 && region.height > 4) unawaited(_commitLiveRegion(region));
      setState(() {
        _captureStart = null;
        _captureCurrent = null;
        _liveRegionShape = null;
      });
      return;
    }
    if (ctrl.activeTool == DrawTool.imageDraw && _captureStart != null && _captureCurrent != null) {
      final Rect region = Rect.fromPoints(_captureStart!, _captureCurrent!);
      if (region.width > 4 && region.height > 4) unawaited(_captureAndCommitImageDraw(region));
      setState(() {
        _captureStart = null;
        _captureCurrent = null;
      });
      return;
    }
    ctrl.endDragGuide();
    if (!selectMode) ctrl.endShape();
    _lastSelectPos = null;
  }

  void _onSecondaryTapDown(TapDownDetails d) {
    if (!ctrl.drawingModeActive) return;
    if (ctrl.deleteGuideAt(d.localPosition)) return;
    ctrl.deleteShapeAt(d.localPosition);
  }

  void _onTapDown(TapDownDetails d) {
    if (!ctrl.drawingModeActive) return;
    final ui.Offset pos = d.localPosition;
    final GuideLineModel? hitGuide = _hitGuide(pos);
    if (selectMode) {
      if (hitGuide != null) {
        ctrl.selectGuide(hitGuide);
        return;
      }
      ctrl.selectShapeAt(pos);
      return;
    }
    if (ctrl.activeTool == DrawTool.magnifier) {
      unawaited(_commitMagnifierAt(pos));
      return;
    }
    if (ctrl.activeTool == DrawTool.text || ctrl.activeTool == DrawTool.infoBalloon) {
      unawaited(_showTextDialog(pos));
      return;
    }
    if (ctrl.activeTool == DrawTool.emoji) {
      unawaited(_showEmojiDialog(pos));
      return;
    }
    if (ctrl.activeTool == DrawTool.stepCounter) {
      ctrl.startShape(pos);
      ctrl.endShape();
      return;
    }
  }

  // ── Magnifier hover ────────────────────────────────────────────────────────

  DateTime _lastMagnifierFetch = DateTime(0);

  void _onMagnifierHover(Offset pos) {
    setState(() => _magnifierCenter = pos);
    final DateTime now = DateTime.now();
    if (now.difference(_lastMagnifierFetch).inMilliseconds < 80) return;
    _lastMagnifierFetch = now;
    unawaited(_fetchMagnifierRegion(pos));
  }

  Future<void> _fetchMagnifierRegion(Offset center) async {
    const double radius = 80.0;
    final Rect localRect = Rect.fromCenter(center: center, width: radius * 2, height: radius * 2);
    final Uint8List? bytes = await _captureMonitorRegion(localRect, force: true);
    if (bytes == null || !mounted) return;
    setState(() {
      _magnifierShape = DrawShape(
        tool: DrawTool.magnifier,
        points: <Offset>[localRect.topLeft, localRect.bottomRight],
        color: ctrl.strokeColor,
        strokeWidth: ctrl.strokeWidth,
        opacity: ctrl.opacity,
        imageBytes: bytes,
        imageW: (radius * 2).round(),
        imageH: (radius * 2).round(),
      );
    });
  }

  Future<void> _commitMagnifierAt(Offset center) async {
    const double radius = 90.0;
    final Rect localRect = Rect.fromCenter(center: center, width: radius * 2, height: radius * 2);
    final Uint8List? bytes = await _captureMonitorRegion(localRect, force: true);
    if (bytes == null || !mounted) return;
    ctrl.commitImageShape(
      DrawTool.magnifier,
      localRect,
      bytes,
      (radius * 2).round(),
      (radius * 2).round(),
    );
  }

  // ── Live region fetch/commit ───────────────────────────────────────────────

  Future<void> _fetchLiveRegion(Rect localRect) async {
    if (localRect.width < 4 || localRect.height < 4) return;
    Uint8List? bytes;
    int w;
    int h;
    if (ctrl.activeTool == DrawTool.spotlight) {
      final Size screenSize = MediaQuery.of(context).size;
      final Rect fullRect = Offset.zero & screenSize;
      bytes = await _captureScreenRegion(fullRect);
      w = screenSize.width.round().clamp(1, 100000);
      h = screenSize.height.round().clamp(1, 100000);
    } else if (ctrl.activeTool == DrawTool.blur || ctrl.activeTool == DrawTool.pixelate) {
      bytes = await _captureMonitorRegion(localRect, force: true);
      w = localRect.width.round().clamp(1, 100000);
      h = localRect.height.round().clamp(1, 100000);
    } else {
      bytes = await _captureScreenRegion(localRect);
      w = localRect.width.round().clamp(1, 100000);
      h = localRect.height.round().clamp(1, 100000);
    }
    if (bytes == null || !mounted) return;
    Color? fillColor;
    if (ctrl.activeTool == DrawTool.smartDelete && bytes.length >= 4) {
      fillColor = Color.fromARGB(255, bytes[0], bytes[1], bytes[2]);
    }
    setState(() {
      _liveRegionShape = DrawShape(
        tool: ctrl.activeTool,
        points: <Offset>[localRect.topLeft, localRect.bottomRight],
        color: ctrl.strokeColor,
        strokeWidth: ctrl.strokeWidth,
        opacity: ctrl.opacity,
        imageBytes: bytes,
        imageW: w,
        imageH: h,
        fillColor: fillColor,
      );
    });
  }

  Future<void> _commitLiveRegion(Rect region) async {
    Uint8List? bytes;
    int w, h;

    if (ctrl.activeTool == DrawTool.spotlight) {
      // Capture the full window for spotlight so we can blur the whole background
      final Size screenSize = MediaQuery.of(context).size;
      final Rect fullRect = Offset.zero & screenSize;
      bytes = await _captureScreenRegion(fullRect);
      w = screenSize.width.round().clamp(1, 100000);
      h = screenSize.height.round().clamp(1, 100000);
    } else if (ctrl.activeTool == DrawTool.blur || ctrl.activeTool == DrawTool.pixelate) {
      bytes = await _captureMonitorRegion(region, force: true);
      w = region.width.round().clamp(1, 100000);
      h = region.height.round().clamp(1, 100000);
    } else {
      bytes = await _captureScreenRegion(region);
      w = region.width.round().clamp(1, 100000);
      h = region.height.round().clamp(1, 100000);
    }

    if (bytes == null) return;

    Color? fillColor;
    if (ctrl.activeTool == DrawTool.smartDelete && bytes.length >= 4) {
      fillColor = Color.fromARGB(255, bytes[0], bytes[1], bytes[2]);
    }
    ctrl.commitImageShape(ctrl.activeTool, region, bytes, w, h, fillColor: fillColor);
  }

  Future<void> _captureAndCommitImageDraw(Rect localRect) async {
    final Uint8List? bytes = await _captureScreenRegion(localRect);
    if (bytes == null) return;
    final int w = localRect.width.round().clamp(1, 100000);
    final int h = localRect.height.round().clamp(1, 100000);
    ctrl.commitImageShape(DrawTool.imageDraw, localRect, bytes, w, h);
  }

  // ── Frozen monitor capture helper ──────────────────────────────────────────

  Future<bool> _ensureRegionToolSnapshot(DrawTool tool) {
    if (_usesCaptureMonitorTool(tool)) return _ensureCaptureMonitorSnapshot();
    return _ensureMonitorSnapshot();
  }

  void _debounceLiveRegionFetch(Rect region) {
    _liveRegionFetchDebounce?.cancel();
    _liveRegionFetchDebounce = Timer(const Duration(milliseconds: 30), () {
      unawaited(_fetchLiveRegion(region));
    });
  }

  Future<bool> _ensureCaptureMonitorSnapshot({bool force = false}) async {
    if (_captureMonitorSnapshotInProgress) {
      while (_captureMonitorSnapshotInProgress && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return _captureMonitorSnapshotBytes != null;
    }

    final int hwnd = Win32Window.getHwnd();
    if (hwnd == 0) return false;

    Monitor.fetchMonitors();
    final int monitor = Monitor.getWindowMonitor(hwnd);
    if (!force &&
        _captureMonitorSnapshotBytes != null &&
        _captureMonitorSnapshotMonitor == monitor &&
        _captureMonitorSnapshotScreenRect != null) {
      return true;
    }

    final Square? m = Monitor.monitorSizes[monitor];
    if (m == null) return false;

    _captureMonitorSnapshotInProgress = true;
    try {
      final int monitorIndex = ((Monitor.monitorIds[monitor] ?? 1) - 1).clamp(0, 100000);
      await excludeWindowFromCapture(hwnd);
      final MonitorCapture? capture = await captureMonitor(monitorIndex: monitorIndex);
      if (capture == null || capture.width <= 0 || capture.height <= 0 || capture.pixels.isEmpty) return false;

      _captureMonitorSnapshotBytes = _bgraToRgba(capture.pixels);
      _captureMonitorSnapshotScreenRect = Rect.fromLTWH(
        m.x.toDouble(),
        m.y.toDouble(),
        m.width.toDouble(),
        m.height.toDouble(),
      );
      _captureMonitorSnapshotW = capture.width;
      _captureMonitorSnapshotH = capture.height;
      _captureMonitorSnapshotMonitor = monitor;
      return true;
    } finally {
      _captureMonitorSnapshotInProgress = false;
    }
  }

  Future<void> _refreshSelectedCaptureMonitorShape({bool force = false}) async {
    final DrawShape? shape = ctrl.selectedShape;
    if (shape == null || !_usesCaptureMonitorTool(shape.tool) || shape.points.length < 2) return;

    final int token = ++_selectedImageRefreshToken;
    final Rect rect = Rect.fromPoints(shape.points.first, shape.points.last).normalized();
    if (rect.width < 2 || rect.height < 2) return;

    final Uint8List? bytes = await _captureMonitorRegion(rect, force: true);
    if (!mounted || bytes == null || token != _selectedImageRefreshToken) return;

    ctrl.updateSelectedImage(
      bytes,
      rect.width.round().clamp(1, 100000),
      rect.height.round().clamp(1, 100000),
    );
  }

  Uint8List _bgraToRgba(Uint8List bgra) {
    final Uint8List rgba = Uint8List(bgra.length);
    for (int i = 0; i < bgra.length; i += 4) {
      rgba[i] = bgra[i + 2];
      rgba[i + 1] = bgra[i + 1];
      rgba[i + 2] = bgra[i];
      rgba[i + 3] = 255;
    }
    return rgba;
  }

  Future<bool> _ensureMonitorSnapshot({bool force = false}) async {
    if (_snapshotInProgress) {
      while (_snapshotInProgress && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return _monitorSnapshotBytes != null;
    }

    final int hwnd = Win32Window.getHwnd();
    if (hwnd == 0) return false;

    final int monitor = Monitor.getWindowMonitor(hwnd);
    if (!force &&
        _monitorSnapshotBytes != null &&
        _monitorSnapshotMonitor == monitor &&
        _monitorSnapshotScreenRect != null) {
      return true;
    }

    _snapshotInProgress = true;
    try {
      Monitor.fetchMonitors();
      final Square? m = Monitor.monitorSizes[monitor];
      if (m == null) return false;

      final Rect monitorRect = Rect.fromLTWH(
        m.x.toDouble(),
        m.y.toDouble(),
        m.width.toDouble(),
        m.height.toDouble(),
      );

      // Hide the overlay for the one real capture so CAPTUREBLT cannot include
      // our own blur/pixelate/spotlight pixels. This capture happens only when
      // the overlay opens / drawing mode becomes active / monitor changes.
      ShowWindow(hwnd, SW_HIDE);
      await Future<void>.delayed(const Duration(milliseconds: 60));

      final Uint8List? bytes = _captureScreenRectRgba(monitorRect);

      ShowWindow(hwnd, SW_SHOW);
      SetWindowPos(hwnd, HWND_TOPMOST, 0, 0, 0, 0, SWP_NOSIZE | SWP_NOMOVE | SWP_NOACTIVATE | SWP_SHOWWINDOW);
      await WindowManager.instance.focus();

      if (bytes == null) return false;
      _monitorSnapshotBytes = bytes;
      _monitorSnapshotScreenRect = monitorRect;
      _monitorSnapshotW = monitorRect.width.round();
      _monitorSnapshotH = monitorRect.height.round();
      _monitorSnapshotMonitor = monitor;
      return true;
    } finally {
      // In case an early return happened while hidden, make the overlay visible again.
      ShowWindow(hwnd, SW_SHOW);
      _snapshotInProgress = false;
    }
  }

  Uint8List? _captureScreenRectRgba(Rect screenRect) {
    final int x = screenRect.left.round();
    final int y = screenRect.top.round();
    final int w = screenRect.width.round().clamp(1, 100000);
    final int h = screenRect.height.round().clamp(1, 100000);

    final int screenDc = GetDC(NULL);
    final int memDc = CreateCompatibleDC(screenDc);
    final int bmp = CreateCompatibleBitmap(screenDc, w, h);
    SelectObject(memDc, bmp);
    BitBlt(memDc, 0, 0, w, h, screenDc, x, y, SRCCOPY | CAPTUREBLT);

    final Pointer<BITMAPINFO> bmi = calloc<BITMAPINFO>();
    final Pointer<Uint8> bgra = calloc<Uint8>(w * h * 4);
    try {
      bmi.ref.bmiHeader.biSize = sizeOf<BITMAPINFOHEADER>();
      bmi.ref.bmiHeader.biWidth = w;
      bmi.ref.bmiHeader.biHeight = -h;
      bmi.ref.bmiHeader.biPlanes = 1;
      bmi.ref.bmiHeader.biBitCount = 32;
      bmi.ref.bmiHeader.biCompression = BI_RGB;

      if (GetDIBits(memDc, bmp, 0, h, bgra.cast(), bmi, DIB_RGB_COLORS) == 0) return null;

      final Uint8List rgba = Uint8List(w * h * 4);
      final Uint8List src = bgra.asTypedList(w * h * 4);
      for (int i = 0; i < src.length; i += 4) {
        rgba[i] = src[i + 2];
        rgba[i + 1] = src[i + 1];
        rgba[i + 2] = src[i];
        rgba[i + 3] = 255;
      }
      return rgba;
    } finally {
      DeleteObject(bmp);
      DeleteDC(memDc);
      ReleaseDC(NULL, screenDc);
      calloc.free(bgra);
      calloc.free(bmi);
    }
  }

  Future<Uint8List?> _captureScreenRegion(Rect localRect) async {
    if (!await _ensureMonitorSnapshot()) return null;

    final Uint8List? snapshot = _monitorSnapshotBytes;
    final Rect? snapshotRect = _monitorSnapshotScreenRect;
    final int? snapshotW = _monitorSnapshotW;
    final int? snapshotH = _monitorSnapshotH;
    if (snapshot == null || snapshotRect == null || snapshotW == null || snapshotH == null) return null;

    final Pointer<RECT> windowRect = calloc<RECT>();
    try {
      final int hwnd = Win32Window.getHwnd();
      if (hwnd == 0 || GetWindowRect(hwnd, windowRect) == 0) return null;

      final Rect r = localRect.normalized();
      final int outW = r.width.round().clamp(1, 100000);
      final int outH = r.height.round().clamp(1, 100000);
      final int screenLeft = (windowRect.ref.left + r.left).round();
      final int screenTop = (windowRect.ref.top + r.top).round();

      final Uint8List out = Uint8List(outW * outH * 4);
      for (int row = 0; row < outH; row++) {
        final int sy = screenTop + row - snapshotRect.top.round();
        if (sy < 0 || sy >= snapshotH) continue;
        for (int col = 0; col < outW; col++) {
          final int sx = screenLeft + col - snapshotRect.left.round();
          if (sx < 0 || sx >= snapshotW) continue;
          final int srcI = (sy * snapshotW + sx) * 4;
          final int dstI = (row * outW + col) * 4;
          out[dstI] = snapshot[srcI];
          out[dstI + 1] = snapshot[srcI + 1];
          out[dstI + 2] = snapshot[srcI + 2];
          out[dstI + 3] = snapshot[srcI + 3];
        }
      }
      return out;
    } finally {
      calloc.free(windowRect);
    }
  }

  // ── Text dialog ────────────────────────────────────────────────────────────

  Future<Uint8List?> _captureMonitorRegion(Rect localRect, {bool force = false}) async {
    if (!await _ensureCaptureMonitorSnapshot(force: force)) return null;

    final Uint8List? snapshot = _captureMonitorSnapshotBytes;
    final Rect? snapshotRect = _captureMonitorSnapshotScreenRect;
    final int? snapshotW = _captureMonitorSnapshotW;
    final int? snapshotH = _captureMonitorSnapshotH;
    if (snapshot == null || snapshotRect == null || snapshotW == null || snapshotH == null) return null;

    final Pointer<RECT> windowRect = calloc<RECT>();
    try {
      final int hwnd = Win32Window.getHwnd();
      if (hwnd == 0 || GetWindowRect(hwnd, windowRect) == 0) return null;

      final Rect r = localRect.normalized();
      final int outW = r.width.round().clamp(1, 100000);
      final int outH = r.height.round().clamp(1, 100000);
      final double screenLeft = windowRect.ref.left + r.left;
      final double screenTop = windowRect.ref.top + r.top;
      final double scaleX = snapshotW / snapshotRect.width;
      final double scaleY = snapshotH / snapshotRect.height;

      final Uint8List out = Uint8List(outW * outH * 4);
      for (int row = 0; row < outH; row++) {
        final int sy = ((screenTop + row - snapshotRect.top) * scaleY).floor();
        if (sy < 0 || sy >= snapshotH) continue;
        for (int col = 0; col < outW; col++) {
          final int sx = ((screenLeft + col - snapshotRect.left) * scaleX).floor();
          if (sx < 0 || sx >= snapshotW) continue;
          final int srcI = (sy * snapshotW + sx) * 4;
          final int dstI = (row * outW + col) * 4;
          out[dstI] = snapshot[srcI];
          out[dstI + 1] = snapshot[srcI + 1];
          out[dstI + 2] = snapshot[srcI + 2];
          out[dstI + 3] = snapshot[srcI + 3];
        }
      }
      return out;
    } finally {
      calloc.free(windowRect);
    }
  }

  Future<void> _showTextDialog(Offset pos) async {
    final TextEditingController tc = TextEditingController();
    bool localBg = ctrl.textBackground;
    Color localColor = ctrl.textColor ?? ctrl.strokeColor;
    double localSize = ctrl.fontSize;

    final String? result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black38,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setSt) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: Text(
            ctrl.activeTool == DrawTool.infoBalloon ? 'Info Balloon Text' : 'Enter Text',
            style: const TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 340,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                TextField(
                  controller: tc,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    hintText: 'Type here…',
                    hintStyle: TextStyle(color: Colors.white38),
                    enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                    focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent)),
                  ),
                  onSubmitted: (String v) {
                    ctrl.textBackground = localBg;
                    ctrl.textColor = localColor;
                    ctrl.fontSize = localSize;
                    Navigator.pop(ctx, v);
                  },
                ),
                const SizedBox(height: 12),
                // Font size slider
                Row(children: <Widget>[
                  const Text('Size:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: SliderTheme(
                      data: SliderTheme.of(ctx2).copyWith(
                        activeTrackColor: Colors.yellowAccent,
                        thumbColor: Colors.yellowAccent,
                        inactiveTrackColor: Colors.white24,
                      ),
                      child: Slider(
                        value: localSize,
                        min: 8,
                        max: 72,
                        onChanged: (double v) => setSt(() => localSize = v),
                      ),
                    ),
                  ),
                  Text('${localSize.round()}pt', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                ]),
                const SizedBox(height: 8),
                // Background toggle + color palette row
                Row(children: <Widget>[
                  GestureDetector(
                    onTap: () => setSt(() => localBg = !localBg),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: localBg ? Colors.white24 : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.white38),
                      ),
                      child: Row(children: <Widget>[
                        Icon(localBg ? Icons.check_box : Icons.check_box_outline_blank,
                            color: Colors.white70, size: 16),
                        const SizedBox(width: 4),
                        const Text('BG', style: TextStyle(color: Colors.white70, fontSize: 11)),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Color picker placeholder (palette)
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: AppColor.palette
                            .map((Color c) => GestureDetector(
                                  onTap: () => setSt(() => localColor = c),
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    margin: const EdgeInsets.only(right: 4),
                                    decoration: BoxDecoration(
                                      color: c,
                                      shape: BoxShape.circle,
                                      border: localColor == c
                                          ? Border.all(color: Colors.white, width: 2)
                                          : Border.all(color: Colors.transparent),
                                    ),
                                  ),
                                ))
                            .toList(),
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () {
                ctrl.textBackground = localBg;
                ctrl.textColor = localColor;
                ctrl.fontSize = localSize;
                Navigator.pop(ctx, tc.text);
              },
              child: const Text('OK'),
            ),
          ],
        ),
      ),
    );
    if (result != null && result.isNotEmpty) ctrl.commitTextShape(pos, result);
  }

  Future<void> _showEmojiDialog(Offset pos) async {
    String? selectedEmoji;
    double localSize = ctrl.fontSize.clamp(24.0, 160.0);

    final String? result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black38,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext ctx2, StateSetter setSt) => AlertDialog(
          backgroundColor: Colors.grey[900],
          title: const Text(
            'Pick Emoji',
            style: TextStyle(color: Colors.white),
          ),
          content: SizedBox(
            width: 440,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: Colors.black26,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Text(
                    selectedEmoji ?? '🙂',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: localSize),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: <Widget>[
                    const Text('Size:', style: TextStyle(color: Colors.white70, fontSize: 12)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: SliderTheme(
                        data: SliderTheme.of(ctx2).copyWith(
                          activeTrackColor: Colors.yellowAccent,
                          thumbColor: Colors.yellowAccent,
                          inactiveTrackColor: Colors.white24,
                        ),
                        child: Slider(
                          value: localSize,
                          min: 24,
                          max: 160,
                          onChanged: (double v) => setSt(() => localSize = v),
                        ),
                      ),
                    ),
                    Text('${localSize.round()}pt', style: const TextStyle(color: Colors.white70, fontSize: 11)),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  height: 320,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: Material(
                      color: Colors.white,
                      child: EmojiSelector(
                        rows: 5,
                        columns: 8,
                        onSelected: (EmojiData emoji) => setSt(() => selectedEmoji = emoji.char),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: <Widget>[
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: selectedEmoji == null
                  ? null
                  : () {
                      ctrl.fontSize = localSize;
                      Navigator.pop(ctx, selectedEmoji);
                    },
              child: const Text('Place'),
            ),
          ],
        ),
      ),
    );

    if (result != null && result.isNotEmpty) ctrl.commitTextShape(pos, result);
  }

  Future<void> _copyCaptureSelection() async {
    final Offset? start = _captureStart;
    final Offset? current = _captureCurrent;
    setState(() {
      _captureStart = null;
      _captureCurrent = null;
    });
    if (start == null || current == null) return;
    final Rect localRect = Rect.fromPoints(start, current);
    if (localRect.width < 2 || localRect.height < 2) return;
    final Pointer<RECT> windowRect = calloc<RECT>();
    try {
      final int hwnd = Win32Window.getHwnd();
      if (hwnd == 0 || GetWindowRect(hwnd, windowRect) == 0) return;
      final Rect screenRect = Rect.fromLTWH(
        windowRect.ref.left + localRect.left,
        windowRect.ref.top + localRect.top,
        localRect.width,
        localRect.height,
      );
      await Future<void>.delayed(const Duration(milliseconds: 90));
      await ScreenDrawCapture.copyRegionToClipboard(screenRect);
      await WindowManager.instance.focus();
    } finally {
      calloc.free(windowRect);
    }
  }
}

// ---------------------------------------------------------------------------
// Crosshair overlay
// ---------------------------------------------------------------------------

class _CrosshairLayer extends StatefulWidget {
  final void Function(Offset)? onHover;
  const _CrosshairLayer({this.onHover});
  @override
  State<_CrosshairLayer> createState() => _CrosshairLayerState();
}

class _CrosshairLayerState extends State<_CrosshairLayer> {
  Offset _cursor = Offset.zero;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (PointerHoverEvent e) {
        setState(() => _cursor = e.localPosition);
        widget.onHover?.call(e.localPosition);
      },
      child: IgnorePointer(
        ignoring: true,
        child: CustomPaint(
          painter: _CrosshairPainter(_cursor),
        ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  final Offset pos;
  _CrosshairPainter(this.pos);

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, pos.dy), Offset(size.width, pos.dy), paint);
    canvas.drawLine(Offset(pos.dx, 0), Offset(pos.dx, size.height), paint);

    // Coordinate label
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '${pos.dx.round()}, ${pos.dy.round()}',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
          backgroundColor: Colors.black.withValues(alpha: 0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos + const Offset(8, 8));
  }

  @override
  bool shouldRepaint(_CrosshairPainter old) => old.pos != pos;
}

void _paintPixelatedRgba(
  Canvas canvas,
  Rect bounds,
  Uint8List? rgba,
  int? imageW,
  int? imageH, {
  double blockSize = 14,
}) {
  if (rgba == null || imageW == null || imageH == null || imageW <= 0 || imageH <= 0) {
    canvas.drawRect(bounds, Paint()..color = Colors.black.withValues(alpha: 0.20));
    return;
  }

  final int cols = (bounds.width / blockSize).ceil().clamp(1, 1000000).toInt();
  final int rows = (bounds.height / blockSize).ceil().clamp(1, 1000000).toInt();

  for (int row = 0; row < rows; row++) {
    for (int col = 0; col < cols; col++) {
      final Rect dst = Rect.fromLTWH(
        bounds.left + col * blockSize,
        bounds.top + row * blockSize,
        blockSize,
        blockSize,
      ).intersect(bounds);
      if (dst.isEmpty) continue;

      final int sx0 = ((dst.left - bounds.left) / bounds.width * imageW).floor().clamp(0, imageW - 1).toInt();
      final int sy0 = ((dst.top - bounds.top) / bounds.height * imageH).floor().clamp(0, imageH - 1).toInt();
      final int sx1 = ((dst.right - bounds.left) / bounds.width * imageW).ceil().clamp(sx0 + 1, imageW).toInt();
      final int sy1 = ((dst.bottom - bounds.top) / bounds.height * imageH).ceil().clamp(sy0 + 1, imageH).toInt();

      int r = 0, g = 0, b = 0, a = 0, count = 0;
      final int stepX = max(1, ((sx1 - sx0) / 4).floor());
      final int stepY = max(1, ((sy1 - sy0) / 4).floor());
      for (int y = sy0; y < sy1; y += stepY) {
        for (int x = sx0; x < sx1; x += stepX) {
          final int i = (y * imageW + x) * 4;
          if (i + 3 >= rgba.length) continue;
          r += rgba[i];
          g += rgba[i + 1];
          b += rgba[i + 2];
          a += rgba[i + 3];
          count++;
        }
      }
      if (count == 0) continue;
      canvas.drawRect(
        dst,
        Paint()
          ..color = Color.fromARGB(
            (a / count).round().clamp(0, 255).toInt(),
            (r / count).round().clamp(0, 255).toInt(),
            (g / count).round().clamp(0, 255).toInt(),
            (b / count).round().clamp(0, 255).toInt(),
          ),
      );
    }
  }
}

// ---------------------------------------------------------------------------
// Committed image-backed shape widget (blur/pixelate/smartDelete/spotlight/imageDraw)
// ---------------------------------------------------------------------------

class _CommittedImageShape extends StatefulWidget {
  final DrawShape shape;
  const _CommittedImageShape({required this.shape});
  @override
  State<_CommittedImageShape> createState() => _CommittedImageShapeState();
}

class _CommittedImageShapeState extends State<_CommittedImageShape> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_CommittedImageShape old) {
    super.didUpdateWidget(old);
    if (old.shape.imageBytes != widget.shape.imageBytes) _decode();
  }

  Future<void> _decode() async {
    final DrawShape s = widget.shape;
    if (s.imageBytes == null || s.imageW == null || s.imageH == null) return;
    final ui.ImmutableBuffer buf = await ui.ImmutableBuffer.fromUint8List(s.imageBytes!);
    final ui.ImageDescriptor desc =
        ui.ImageDescriptor.raw(buf, width: s.imageW!, height: s.imageH!, pixelFormat: ui.PixelFormat.rgba8888);
    final ui.Codec codec = await desc.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  @override
  Widget build(BuildContext context) {
    final DrawShape s = widget.shape;
    final Offset tl = s.points.first;
    final Offset br = s.points.last;
    final Rect rect = Rect.fromPoints(tl, br).normalized();

    if (s.tool == DrawTool.spotlight) {
      // Full-screen widget: blurred outside, clear inside
      return Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _SpotlightCommittedPainter(_image, rect, s),
          ),
        ),
      );
    }

    return Positioned(
      left: rect.left,
      top: rect.top,
      width: rect.width,
      height: rect.height,
      child: IgnorePointer(
        child: ClipRect(
          child: CustomPaint(
            painter: _CommittedRegionPainter(s, _image),
          ),
        ),
      ),
    );
  }
}

class _CommittedRegionPainter extends CustomPainter {
  final DrawShape shape;
  final ui.Image? image;
  _CommittedRegionPainter(this.shape, this.image);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    if (image == null) return;

    switch (shape.tool) {
      case DrawTool.blur:
        _paintBlur(canvas, bounds);
      case DrawTool.pixelate:
        _paintPixelate(canvas, bounds);
      case DrawTool.smartDelete:
        canvas.drawRect(bounds, Paint()..color = shape.fillColor ?? Colors.white);
      case DrawTool.imageDraw:
        canvas.drawImageRect(image!, Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()), bounds,
            Paint()..color = Colors.black.withValues(alpha: shape.opacity));
        if (shape.selected) {
          canvas.drawRect(
              bounds,
              Paint()
                ..color = Colors.lightBlueAccent
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
        }
      case DrawTool.magnifier:
        _paintMagnifier(canvas, bounds);
      default:
        break;
    }
  }

  void _paintBlur(Canvas canvas, Rect bounds) {
    final Rect src = Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble());
    canvas.save();
    canvas.clipRect(bounds);
    canvas.saveLayer(
      bounds,
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
    );
    canvas.drawImageRect(image!, src, bounds.inflate(16), Paint()..filterQuality = FilterQuality.high);
    canvas.restore();
    canvas.drawRect(bounds, Paint()..color = Colors.white.withValues(alpha: 0.10));
    canvas.restore();
  }

  void _paintPixelate(Canvas canvas, Rect bounds) {
    _paintPixelatedRgba(canvas, bounds, shape.imageBytes, shape.imageW, shape.imageH, blockSize: 14);
  }

  void _paintMagnifier(Canvas canvas, Rect bounds) {
    final Rect src = Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble());
    canvas.save();
    canvas.clipPath(Path()..addOval(bounds));
    final Rect zoomed = bounds.inflate(bounds.width * 0.28);
    canvas.drawImageRect(image!, src, zoomed, Paint()..filterQuality = FilterQuality.high);
    canvas.restore();
    canvas.drawOval(
      bounds.deflate(1),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.90)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
    canvas.drawOval(
      bounds.deflate(4),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(_CommittedRegionPainter old) => old.image != image || old.shape != shape;
}

class _SpotlightCommittedPainter extends CustomPainter {
  final ui.Image? bgImage;
  final Rect spotRect;
  final DrawShape shape;
  _SpotlightCommittedPainter(this.bgImage, this.spotRect, this.shape);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect full = Offset.zero & size;
    final Path outside = Path()
      ..addRect(full)
      ..addRect(spotRect)
      ..fillType = PathFillType.evenOdd;

    if (bgImage != null) {
      final Rect src = Rect.fromLTWH(0, 0, bgImage!.width.toDouble(), bgImage!.height.toDouble());

      // Outside: draw the frozen screen capture through a real blur filter.
      // Inside: draw the frozen screen capture sharp. This whole layer is
      // underneath AnnotationPainter, so existing drawings remain visible.
      canvas.save();
      canvas.clipPath(outside);
      canvas.saveLayer(
        full,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      );
      canvas.drawImageRect(bgImage!, src, full.inflate(28), Paint()..filterQuality = FilterQuality.high);
      canvas.restore();
      canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.28));
      canvas.restore();

      canvas.save();
      canvas.clipRect(spotRect);
      // canvas.drawImageRect(bgImage!, src, full, Paint()..filterQuality = FilterQuality.high); <- this commented for live preview.
      canvas.restore();
    } else {
      canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    }

    canvas.drawRect(
        spotRect,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.55)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(_SpotlightCommittedPainter old) =>
      old.bgImage != bgImage || old.spotRect != spotRect || old.shape != shape;
}

// ---------------------------------------------------------------------------
// Magnifier lens widget — renders a real screen-captured circular zoom lens
// ---------------------------------------------------------------------------

class _MagnifierLens extends StatefulWidget {
  final Offset center;
  final DrawShape shape;
  const _MagnifierLens({required this.center, required this.shape});
  @override
  State<_MagnifierLens> createState() => _MagnifierLensState();
}

class _MagnifierLensState extends State<_MagnifierLens> {
  ui.Image? _image;
  Uint8List? _lastBytes;

  @override
  void didUpdateWidget(_MagnifierLens old) {
    super.didUpdateWidget(old);
    if (widget.shape.imageBytes != _lastBytes) _decode();
  }

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final DrawShape s = widget.shape;
    if (s.imageBytes == null || s.imageW == null || s.imageH == null) return;
    _lastBytes = s.imageBytes;
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(s.imageBytes!);
    final ui.ImageDescriptor desc =
        ui.ImageDescriptor.raw(buffer, width: s.imageW!, height: s.imageH!, pixelFormat: ui.PixelFormat.rgba8888);
    final ui.Codec codec = await desc.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  @override
  Widget build(BuildContext context) {
    const double radius = 90.0;
    const double zoom = 1.55;
    final Offset center = widget.center;

    return Positioned(
      left: center.dx - radius,
      top: center.dy - radius * 2.4,
      child: IgnorePointer(
        child: ClipOval(
          child: Container(
            width: radius * 2,
            height: radius * 2,
            decoration: const BoxDecoration(shape: BoxShape.circle),
            child: CustomPaint(
              painter: _MagnifierPainter(_image, zoom),
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white70, width: 2),
                  boxShadow: <BoxShadow>[BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 8)],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MagnifierPainter extends CustomPainter {
  final ui.Image? image;
  final double zoom;
  _MagnifierPainter(this.image, this.zoom);

  @override
  void paint(Canvas canvas, Size size) {
    if (image == null) {
      canvas.drawOval(Offset.zero & size, Paint()..color = Colors.black.withValues(alpha: 0.5));
      return;
    }
    // Scale image up (zoom) centered in the circular lens
    final double scale = size.width / image!.width * zoom;
    final double dx = (size.width - image!.width * scale) / 2;
    final double dy = (size.height - image!.height * scale) / 2;
    canvas.save();
    canvas.clipPath(Path()..addOval(Offset.zero & size));
    canvas.drawImageRect(
      image!,
      Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble()),
      Rect.fromLTWH(dx, dy, image!.width * scale, image!.height * scale),
      Paint(),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_MagnifierPainter old) => old.image != image;
}

// ---------------------------------------------------------------------------
// Live region widget — renders blur/pixelate/smartDelete/spotlight live preview
// ---------------------------------------------------------------------------

class _LiveRegionWidget extends StatefulWidget {
  final DrawShape shape;
  final Rect rect;
  const _LiveRegionWidget({required this.shape, required this.rect});
  @override
  State<_LiveRegionWidget> createState() => _LiveRegionWidgetState();
}

class _LiveRegionWidgetState extends State<_LiveRegionWidget> {
  ui.Image? _image;
  Uint8List? _lastBytes;

  @override
  void didUpdateWidget(_LiveRegionWidget old) {
    super.didUpdateWidget(old);
    if (widget.shape.imageBytes != _lastBytes) _decode();
  }

  @override
  void initState() {
    super.initState();
    _decode();
  }

  Future<void> _decode() async {
    final DrawShape s = widget.shape;
    if (s.imageBytes == null || s.imageW == null || s.imageH == null) return;
    _lastBytes = s.imageBytes;
    final ui.ImmutableBuffer buf = await ui.ImmutableBuffer.fromUint8List(s.imageBytes!);
    final ui.ImageDescriptor desc =
        ui.ImageDescriptor.raw(buf, width: s.imageW!, height: s.imageH!, pixelFormat: ui.PixelFormat.rgba8888);
    final ui.Codec codec = await desc.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  @override
  Widget build(BuildContext context) {
    final Rect r = widget.rect.normalized();
    if (widget.shape.tool == DrawTool.spotlight) {
      return Positioned.fill(
        child: IgnorePointer(
          child: CustomPaint(
            painter: _SpotlightCommittedPainter(_image, r, widget.shape),
          ),
        ),
      );
    }
    return Positioned(
      left: r.left,
      top: r.top,
      width: r.width,
      height: r.height,
      child: IgnorePointer(
        child: ClipRect(
          child: CustomPaint(
            painter: _RegionEffectPainter(widget.shape, _image, r),
          ),
        ),
      ),
    );
  }
}

extension _RectNorm on Rect {
  Rect normalized() => Rect.fromLTRB(
        left < right ? left : right,
        top < bottom ? top : bottom,
        left < right ? right : left,
        top < bottom ? bottom : top,
      );
}

class _RegionEffectPainter extends CustomPainter {
  final DrawShape shape;
  final ui.Image? image;
  final Rect screenRect;
  _RegionEffectPainter(this.shape, this.image, this.screenRect);

  @override
  void paint(Canvas canvas, Size size) {
    final Rect bounds = Offset.zero & size;
    switch (shape.tool) {
      case DrawTool.blur:
        _paintBlur(canvas, bounds);
      case DrawTool.pixelate:
        _paintPixelate(canvas, bounds);
      case DrawTool.smartDelete:
        _paintSmartDelete(canvas, bounds);
      case DrawTool.spotlight:
        _paintSpotlight(canvas, size);
      default:
        break;
    }
  }

  void _paintBlur(Canvas canvas, Rect bounds) {
    if (image != null) {
      final Rect src = Rect.fromLTWH(0, 0, image!.width.toDouble(), image!.height.toDouble());
      canvas.save();
      canvas.clipRect(bounds);
      canvas.saveLayer(
        bounds,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      );
      canvas.drawImageRect(image!, src, bounds.inflate(16), Paint()..filterQuality = FilterQuality.high);
      canvas.restore();
      canvas.drawRect(bounds, Paint()..color = Colors.white.withValues(alpha: 0.10));
      canvas.restore();
    } else {
      canvas.drawRect(bounds, Paint()..color = Colors.white.withValues(alpha: 0.18));
    }
    _drawDashedBorder(canvas, bounds, Colors.white60);
  }

  void _paintPixelate(Canvas canvas, Rect bounds) {
    if (image == null) {
      _drawCheckerboard(canvas, bounds);
    } else {
      _paintPixelatedRgba(canvas, bounds, shape.imageBytes, shape.imageW, shape.imageH, blockSize: 14);
    }
    _drawDashedBorder(canvas, bounds, Colors.orangeAccent);
  }

  void _drawCheckerboard(Canvas canvas, Rect bounds) {
    const double bs = 10.0;
    final int cols = (bounds.width / bs).ceil();
    final int rows = (bounds.height / bs).ceil();
    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final Rect cell = Rect.fromLTWH(bounds.left + c * bs, bounds.top + r * bs, bs, bs).intersect(bounds);
        canvas.drawRect(
            cell,
            Paint()
              ..color = ((r + c) % 2 == 0
                  ? Colors.grey.withValues(alpha: 0.5)
                  : Colors.grey.shade700.withValues(alpha: 0.5)));
      }
    }
  }

  void _paintSmartDelete(Canvas canvas, Rect bounds) {
    final Color fill = shape.fillColor ?? Colors.white;
    canvas.drawRect(bounds, Paint()..color = fill);
    _drawDashedBorder(canvas, bounds, Colors.redAccent);
  }

  void _paintSpotlight(Canvas canvas, Size size) {
    // We need to darken the entire screen *outside* the spotlight rect.
    // Since this widget only covers the spotlight rect, we can't darken outside here.
    // Instead we draw a bright border to indicate the spotlight region.
    // The actual darkened-outside effect is handled in AnnotationPainter for committed shapes.
    final Rect bounds = Offset.zero & size;
    canvas.drawRect(bounds, Paint()..color = Colors.white.withValues(alpha: 0.05));
    canvas.drawRect(
        bounds,
        Paint()
          ..color = Colors.white.withValues(alpha: 0.4)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2.5);
  }

  void _drawDashedBorder(Canvas canvas, Rect r, Color color) {
    final Paint p = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const double dash = 6, gap = 4;
    void line(Offset a, Offset b) {
      final double len = (b - a).distance;
      final Offset dir = (b - a) / len;
      double pos = 0;
      bool draw = true;
      while (pos < len) {
        final double end = (pos + (draw ? dash : gap)).clamp(0.0, len);
        if (draw) canvas.drawLine(a + dir * pos, a + dir * end, p);
        pos = end;
        draw = !draw;
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  @override
  bool shouldRepaint(_RegionEffectPainter old) =>
      old.image != image || old.shape.tool != shape.tool || old.screenRect != screenRect;
}

// ---------------------------------------------------------------------------
// Raw image decode widget (shared)
// ---------------------------------------------------------------------------

class _RawImageWidget extends StatefulWidget {
  final Uint8List bytes;
  final int width;
  final int height;
  const _RawImageWidget({required this.bytes, required this.width, required this.height});

  @override
  State<_RawImageWidget> createState() => _RawImageWidgetState();
}

class _RawImageWidgetState extends State<_RawImageWidget> {
  ui.Image? _image;

  @override
  void initState() {
    super.initState();
    _decode();
  }

  @override
  void didUpdateWidget(_RawImageWidget old) {
    super.didUpdateWidget(old);
    if (old.bytes != widget.bytes) _decode();
  }

  Future<void> _decode() async {
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(widget.bytes);
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: widget.width,
      height: widget.height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (mounted) setState(() => _image = frame.image);
  }

  @override
  Widget build(BuildContext context) {
    if (_image == null) return const SizedBox.shrink();
    return CustomPaint(painter: _ImagePainter(_image!));
  }
}

class _ImagePainter extends CustomPainter {
  final ui.Image image;
  _ImagePainter(this.image);
  @override
  void paint(Canvas canvas, Size size) =>
      paintImage(canvas: canvas, rect: Offset.zero & size, image: image, fit: BoxFit.fill);
  @override
  bool shouldRepaint(_ImagePainter old) => old.image != image;
}

// ---------------------------------------------------------------------------
// Capture selection overlay painter
// ---------------------------------------------------------------------------

class _CaptureSelectionPainter extends CustomPainter {
  final Rect rect;
  _CaptureSelectionPainter(this.rect);

  @override
  void paint(Canvas canvas, Size size) {
    final Paint shade = Paint()..color = Colors.black.withValues(alpha: 0.28);
    final Path overlay = Path()
      ..addRect(Offset.zero & size)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(overlay, shade);

    final Paint border = Paint()
      ..color = Colors.lightBlueAccent
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    canvas.drawRect(rect, border);

    final TextPainter label = TextPainter(
      text: TextSpan(
        text: '${rect.width.abs().round()} x ${rect.height.abs().round()}',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
          backgroundColor: Colors.black.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    label.paint(canvas, rect.topLeft + const Offset(6, 6));
  }

  @override
  bool shouldRepaint(_CaptureSelectionPainter oldDelegate) => oldDelegate.rect != rect;
}

// ---------------------------------------------------------------------------
// Status bar
// ---------------------------------------------------------------------------

class _StatusBar extends StatelessWidget {
  final AnnotationController controller;
  const _StatusBar({required this.controller});

  String get _hotkeyHelp {
    String labelFor(ScreenDrawHotkeyAction action) {
      final ScreenDrawHotkeyBinding? binding = Boxes.screenDrawHotkeys.cast<ScreenDrawHotkeyBinding?>().firstWhere(
            (ScreenDrawHotkeyBinding? binding) => binding?.action == action && binding?.enabled == true,
            orElse: () => null,
          );
      return binding?.displayHotkey ?? "Off";
    }

    return 'Draw: ${labelFor(ScreenDrawHotkeyAction.toggleDrawing)}  '
        'Show/hide: ${labelFor(ScreenDrawHotkeyAction.toggleVisibility)} | Close: ${labelFor(ScreenDrawHotkeyAction.closeScreenDraw)}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListenableBuilder(
        listenable: controller,
        builder: (_, __) => Text(
          'Tool: ${controller.activeTool.name.toUpperCase()}  '
          '| Shapes: ${controller.shapes.length}  '
          '| Guides: ${controller.guides.length}  '
          '| ${controller.drawingModeActive ? "DRAW" : "PASS-THROUGH"}  '
          '| $_hotkeyHelp',
          style: const TextStyle(
              color: Colors.white,
              fontSize: 13,
              fontWeight: FontWeight.bold,
              shadows: <ui.Shadow>[Shadow(blurRadius: 1, color: Colors.black, offset: Offset(1, 1))]),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toolbar
// ---------------------------------------------------------------------------

class AnnotationToolbar extends StatelessWidget {
  final AnnotationController controller;
  const AnnotationToolbar({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20.0),
      child: Container(
        width: 52,
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.75),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white24),
        ),
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              _ToolBtn(Icons.mouse_rounded, DrawTool.select, controller, 'Select (S)'),
              _ToolBtn(Icons.screenshot_monitor_rounded, DrawTool.screenCapture, controller, 'Screen Capture (C)'),
              const Divider(color: Colors.white24, height: 10),
              _ToolBtn(Icons.edit, DrawTool.pen, controller, 'Pen (P)'),
              _ToolBtn(Icons.highlight, DrawTool.highlight, controller, 'Highlight (H)'),
              _ToolBtn(Icons.remove, DrawTool.line, controller, 'Line (L)'),
              _ToolBtn(Icons.crop_square, DrawTool.rect, controller, 'Rect (R)'),
              _ToolBtn(Icons.circle_outlined, DrawTool.ellipse, controller, 'Ellipse (E)'),
              _ToolBtn(Icons.arrow_forward, DrawTool.arrow, controller, 'Arrow (A)'),
              const Divider(color: Colors.white24, height: 10),
              _ToolBtn(Icons.text_fields, DrawTool.text, controller, 'Text (T)'),
              _ToolBtn(Icons.emoji_emotions_outlined, DrawTool.emoji, controller, 'Emoji (J)'),
              _ToolBtn(Icons.format_list_numbered, DrawTool.stepCounter, controller, 'Step Counter (N)'),
              _ToolBtn(Icons.chat_bubble_outline, DrawTool.infoBalloon, controller, 'Info Balloon (I)'),
              const Divider(color: Colors.white24, height: 10),
              _ToolBtn(Icons.search, DrawTool.magnifier, controller, 'Magnifier (Z)'),
              _ToolBtn(Icons.blur_on, DrawTool.blur, controller, 'Blur Region (F)'),
              _ToolBtn(Icons.grid_3x3, DrawTool.pixelate, controller, 'Pixelate Region (X)'),
              _ToolBtn(Icons.auto_fix_high, DrawTool.smartDelete, controller, 'Smart Delete (D)'),
              _ToolBtn(Icons.highlight_alt, DrawTool.spotlight, controller, 'Spotlight (O)'),
              _ToolBtn(Icons.content_cut, DrawTool.imageDraw, controller, 'Image Draw (W)'),
              const Divider(color: Colors.white24, height: 10),
              _ToolBtn(Icons.straighten, DrawTool.ruler, controller, 'Ruler (M)'),
              _ToolBtn(Icons.aspect_ratio, DrawTool.sizebox, controller, 'Size Box (B)'),
              _ToolBtn(Icons.linear_scale, DrawTool.guide, controller, 'Guide (U)'),
              const Divider(color: Colors.white24, height: 10),
              // Color: shows current color dot; hover reveals popup palette to the right
              _ColorPopupBtn(controller),
              // Stroke width: shows current width bar; hover reveals popup
              _WidthPopupBtn(controller),
              const Divider(color: Colors.white24, height: 10),
              _ActionBtn(Icons.undo, 'Undo (Ctrl+Z)', () => controller.undo()),
              _ActionBtn(Icons.redo, 'Redo (Ctrl+Y)', () => controller.redo()),
              _ActionBtn(Icons.delete_sweep, 'Clear All', () => controller.clearAll()),
              _ActionBtn(Icons.grid_on, 'Grid (Ctrl+G)', () => controller.toggleGrid()),
              _ActionBtn(Icons.exposure_zero, 'Reset Steps', () => controller.resetStepCounter()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Shows the current stroke color as a small dot.
/// On hover, a popup panel slides out to the right showing the full palette.
class _ColorPopupBtn extends StatefulWidget {
  final AnnotationController ctrl;
  const _ColorPopupBtn(this.ctrl);
  @override
  State<_ColorPopupBtn> createState() => _ColorPopupBtnState();
}

class _ColorPopupBtnState extends State<_ColorPopupBtn> {
  Timer? _closeTimer;
  OverlayEntry? _overlayEntry;
  OverlayEntry? _pickerOverlayEntry;
  final LayerLink _layerLink = LayerLink();
  final LayerLink _pickerLayerLink = LayerLink();
  bool _pickerOpen = false;

  void _show() {
    _closeTimer?.cancel();
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: 300,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(40, -4),
          child: MouseRegion(
            onEnter: (_) => _show(),
            onExit: (_) => _scheduleHide(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    // Palette swatches
                    ...AppColor.palette.map(
                      (Color c) => GestureDetector(
                        onTap: () {
                          widget.ctrl.setColor(c);
                          _overlayEntry?.markNeedsBuild();
                        },
                        child: ListenableBuilder(
                          listenable: widget.ctrl,
                          builder: (_, __) => Container(
                            width: 22,
                            height: 22,
                            margin: const EdgeInsets.only(right: 5),
                            decoration: BoxDecoration(
                              color: c,
                              shape: BoxShape.circle,
                              border: widget.ctrl.strokeColor == c
                                  ? Border.all(color: Colors.white, width: 2.5)
                                  : Border.all(color: Colors.white24, width: 1),
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Divider
                    Container(
                      width: 1,
                      height: 22,
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      color: Colors.white24,
                    ),

                    // Custom color picker trigger
                    CompositedTransformTarget(
                      link: _pickerLayerLink,
                      child: GestureDetector(
                        onTap: _togglePicker,
                        child: ListenableBuilder(
                          listenable: widget.ctrl,
                          builder: (_, __) => Container(
                            width: 26,
                            height: 26,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: const SweepGradient(
                                colors: <ui.Color>[
                                  Colors.red,
                                  Colors.yellow,
                                  Colors.green,
                                  Colors.cyan,
                                  Colors.blue,
                                  Colors.purple,
                                  Colors.red,
                                ],
                              ),
                              border: _pickerOpen
                                  ? Border.all(color: Colors.white, width: 2.5)
                                  : Border.all(color: Colors.white38, width: 1.5),
                            ),
                            child: const Icon(
                              Icons.colorize,
                              size: 14,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _togglePicker() {
    if (_pickerOpen) {
      _closePicker();
    } else {
      _openPicker();
    }
  }

  void _openPicker() {
    if (_pickerOverlayEntry != null) return;
    _pickerOpen = true;
    _overlayEntry?.markNeedsBuild();

    Color pendingColor = widget.ctrl.strokeColor;

    _pickerOverlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: 320,
        child: CompositedTransformFollower(
          link: _pickerLayerLink,
          showWhenUnlinked: false,
          offset: const Offset(0, 36),
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.92),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
                boxShadow: <BoxShadow>[
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  CustomColorPicker(
                    startColor: widget.ctrl.strokeColor,
                    themeOptions: <List<int>>[<int>[]],
                    colorIndex: 0,
                    onColorChanged: (Color color) {
                      pendingColor = color;
                    },
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: <Widget>[
                      // Cancel
                      GestureDetector(
                        onTap: _closePicker,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Cancel',
                            style: TextStyle(color: Colors.white70, fontSize: 13),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // Apply
                      GestureDetector(
                        onTap: () {
                          widget.ctrl.setColor(pendingColor);
                          _closePicker();
                          _overlayEntry?.markNeedsBuild();
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white24,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: const Text(
                            'Apply',
                            style: TextStyle(color: Colors.white, fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_pickerOverlayEntry!);
  }

  void _closePicker() {
    _pickerOverlayEntry?.remove();
    _pickerOverlayEntry = null;
    _pickerOpen = false;
    _overlayEntry?.markNeedsBuild();
  }

  void _scheduleHide() {
    // Don't hide if the picker is open
    if (_pickerOpen) return;
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 220), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _closePicker();
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: ListenableBuilder(
        listenable: widget.ctrl,
        builder: (_, __) => MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _scheduleHide(),
          child: CustomTooltip(
            message: 'Color',
            child: Container(
              width: 36,
              height: 28,
              margin: const EdgeInsets.symmetric(vertical: 2),
              alignment: Alignment.center,
              child: Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  color: widget.ctrl.strokeColor,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white54, width: 1.5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Shows the current stroke width as a small line.
/// On hover, a popup panel slides out to the right with width options.
class _WidthPopupBtn extends StatefulWidget {
  final AnnotationController ctrl;
  const _WidthPopupBtn(this.ctrl);
  @override
  State<_WidthPopupBtn> createState() => _WidthPopupBtnState();
}

class _WidthPopupBtnState extends State<_WidthPopupBtn> {
  Timer? _closeTimer;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  static const List<double> _widths = <double>[1, 2, 4, 8];

  void _show() {
    _closeTimer?.cancel();
    if (_overlayEntry != null) return; // already shown

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: 200, // large enough, won't clip
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(40, -4), // same as your original left/top
          child: MouseRegion(
            onEnter: (_) => _show(),
            onExit: (_) => _scheduleHide(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.85),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: _widths
                      .map((double w) => GestureDetector(
                            onTap: () {
                              widget.ctrl.setStrokeWidth(w);
                              _overlayEntry?.markNeedsBuild(); // refresh highlight
                            },
                            child: ListenableBuilder(
                              listenable: widget.ctrl,
                              builder: (_, __) => Container(
                                width: 36,
                                height: 32,
                                margin: const EdgeInsets.only(right: 6),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(4),
                                  color: widget.ctrl.strokeWidth == w ? Colors.white24 : Colors.transparent,
                                ),
                                child: Container(
                                  width: 24,
                                  height: w,
                                  decoration: BoxDecoration(
                                    color: widget.ctrl.strokeColor,
                                    borderRadius: BorderRadius.circular(2),
                                  ),
                                ),
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }

  void _scheduleHide() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 220), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  @override
  void dispose() {
    _closeTimer?.cancel();
    _overlayEntry?.remove();
    _overlayEntry = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: ListenableBuilder(
        listenable: widget.ctrl,
        builder: (_, __) => MouseRegion(
          onEnter: (_) => _show(),
          onExit: (_) => _scheduleHide(),
          child: CustomTooltip(
            message: 'Stroke Width',
            child: Container(
              width: 36,
              height: 28,
              margin: const EdgeInsets.symmetric(vertical: 2),
              alignment: Alignment.center,
              child: Container(
                width: 24,
                height: widget.ctrl.strokeWidth.clamp(1.0, 8.0),
                decoration: BoxDecoration(
                  color: widget.ctrl.strokeColor,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToolBtn extends StatelessWidget {
  final IconData icon;
  final DrawTool tool;
  final AnnotationController ctrl;
  final String tooltip;
  const _ToolBtn(this.icon, this.tool, this.ctrl, this.tooltip);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: ctrl,
      builder: (_, __) {
        final bool active = ctrl.activeTool == tool;
        return CustomTooltip(
          message: tooltip,
          child: IconButton(
            icon: Icon(icon, size: 18),
            color: active ? Colors.yellowAccent : Colors.white70,
            onPressed: () => ctrl.setTool(tool),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
        );
      },
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  const _ActionBtn(this.icon, this.tooltip, this.onTap);

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: Colors.white70,
        onPressed: onTap,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Annotation painter
// ---------------------------------------------------------------------------

class AnnotationPainter extends CustomPainter {
  final List<DrawShape> shapes;
  final DrawShape? currentShape;
  final Offset? currentEnd;
  final List<GuideLineModel> guides;
  final bool gridVisible;
  final double gridSpacing;
  final bool drawingMode;

  AnnotationPainter({
    required this.shapes,
    required this.currentShape,
    required this.currentEnd,
    required this.guides,
    required this.gridVisible,
    required this.gridSpacing,
    required this.drawingMode,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Grid
    if (gridVisible) _paintGrid(canvas, size);

    // Committed shapes
    for (final DrawShape s in shapes) {
      _paintShape(canvas, s, null);
    }

    // In-progress shape
    if (currentShape != null) {
      _paintShape(canvas, currentShape!, currentEnd);
    }

    // Guide lines
    _paintGuides(canvas, size);
  }

  Paint _makePaint(DrawShape s) => Paint()
    ..color = s.color.withValues(alpha: s.opacity)
    ..strokeWidth = s.strokeWidth
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void _paintShape(Canvas canvas, DrawShape s, Offset? liveEnd) {
    final ui.Paint paint = _makePaint(s);
    final ui.Offset start = s.points.isNotEmpty ? s.points.first : Offset.zero;
    final ui.Offset end = liveEnd ?? (s.points.length > 1 ? s.points.last : start);

    // Selection highlight
    if (s.selected) {
      final ui.Paint selPaint = Paint()
        ..color = Colors.blue.withValues(alpha: 0.3)
        ..strokeWidth = s.strokeWidth + 4
        ..style = PaintingStyle.stroke;
      _drawShape(canvas, s.tool, start, end, s.points, selPaint, s.color, s.strokeWidth);
    }

    // Dispatch new specialised tools first
    switch (s.tool) {
      case DrawTool.text:
      case DrawTool.emoji:
        _drawText(canvas, s, start);
        return;
      case DrawTool.infoBalloon:
        _drawInfoBalloon(canvas, s, start);
        return;
      case DrawTool.stepCounter:
        _drawStepCounter(canvas, s, start);
        return;
      case DrawTool.blur:
        _drawBlurRegion(canvas, Rect.fromPoints(start, end), s.opacity);
        return;
      case DrawTool.pixelate:
        _drawPixelateRegion(canvas, Rect.fromPoints(start, end));
        return;
      case DrawTool.smartDelete:
        _drawSmartDelete(canvas, Rect.fromPoints(start, end));
        return;
      case DrawTool.spotlight:
        _drawSpotlight(canvas, Rect.fromPoints(start, end));
        return;
      case DrawTool.imageDraw:
        _drawImageShape(canvas, s, Rect.fromPoints(start, end));
        return;
      case DrawTool.magnifier:
        return; // magnifier is a live widget, not a committed shape
      default:
        break;
    }

    _drawShape(canvas, s.tool, start, end, s.points, paint, s.color, s.strokeWidth);

    // Measurement labels for ruler / sizebox / line
    if (s.tool == DrawTool.ruler || s.tool == DrawTool.line || s.tool == DrawTool.sizebox || s.tool == DrawTool.arrow) {
      _paintMeasurement(canvas, s.tool, start, end, s.color);
    }
  }

  // ── New tool painters ────────────────────────────────────────────────────

  void _drawText(Canvas canvas, DrawShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    final double fs = s.fontSize ?? (s.strokeWidth * 8 + 12);
    final Color tc = s.textColor ?? s.color;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: TextStyle(
          color: tc,
          fontSize: fs,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (s.textBackground) {
      final Rect bg = Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4);
      canvas.drawRRect(
          RRect.fromRectAndRadius(bg, const Radius.circular(4)), Paint()..color = Colors.black.withValues(alpha: 0.72));
    }
    tp.paint(canvas, pos);
  }

  void _drawInfoBalloon(Canvas canvas, DrawShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    const double padding = 10.0;
    const double tailH = 14.0;
    const double radius = 8.0;
    final double fs = s.fontSize ?? (s.strokeWidth * 6 + 12);
    final Color tc = s.textColor ?? Colors.white;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: TextStyle(color: tc, fontSize: fs),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 280);

    final double bw = tp.width + padding * 2;
    final double bh = tp.height + padding * 2;
    // Bubble rect (above pos)
    final Rect bubble = Rect.fromLTWH(pos.dx - bw / 2, pos.dy - bh - tailH, bw, bh);

    final ui.Path path = Path()
      ..addRRect(RRect.fromRectAndRadius(bubble, const Radius.circular(radius)))
      ..moveTo(pos.dx - 8, bubble.bottom)
      ..lineTo(pos.dx, pos.dy)
      ..lineTo(pos.dx + 8, bubble.bottom)
      ..close();

    canvas.drawPath(path, Paint()..color = s.color.withValues(alpha: 0.9));
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    tp.paint(canvas, Offset(bubble.left + padding, bubble.top + padding));
  }

  void _drawStepCounter(Canvas canvas, DrawShape s, Offset pos) {
    const double r = 14.0;
    final int num = s.stepNumber ?? 1;
    canvas.drawCircle(pos, r, Paint()..color = s.color);
    canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = Colors.black38
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '$num',
        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  // For blur/pixelate/smartDelete/spotlight/imageDraw: actual pixels are rendered
  // by the _CommittedImageShape widget overlay. The painter only draws selection handles.
  void _drawBlurRegion(Canvas canvas, Rect rect, double opacity) {
    if (true) return; // rendered by widget layer
  }

  void _drawPixelateRegion(Canvas canvas, Rect rect) {
    // rendered by widget layer
  }

  void _drawSmartDelete(Canvas canvas, Rect rect) {
    // rendered by widget layer
  }

  void _drawSpotlight(Canvas canvas, Rect spotRect) {
    // rendered by widget layer (_SpotlightCommittedPainter handles full-screen)
  }

  void _drawImageShape(Canvas canvas, DrawShape s, Rect rect) {
    // rendered by widget layer; draw selection border if selected
    if (s.selected) {
      canvas.drawRect(
          rect.inflate(2),
          Paint()
            ..color = Colors.lightBlueAccent
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2);
    }
  }

  void _drawDashedRect(Canvas canvas, Rect rect, Color color) {
    final ui.Paint p = Paint()
      ..color = color
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    const double dash = 6, gap = 4;
    void drawDashedLine(Offset a, Offset b) {
      final double len = (b - a).distance;
      final Offset dir = (b - a) / len;
      double pos = 0;
      bool drawing = true;
      while (pos < len) {
        final double end = (pos + (drawing ? dash : gap)).clamp(0, len);
        if (drawing) canvas.drawLine(a + dir * pos, a + dir * end, p);
        pos = end;
        drawing = !drawing;
      }
    }

    drawDashedLine(rect.topLeft, rect.topRight);
    drawDashedLine(rect.topRight, rect.bottomRight);
    drawDashedLine(rect.bottomRight, rect.bottomLeft);
    drawDashedLine(rect.bottomLeft, rect.topLeft);
  }

  void _drawShape(Canvas canvas, DrawTool tool, Offset start, Offset end, List<Offset> points, Paint paint, Color color,
      double sw) {
    switch (tool) {
      case DrawTool.select:
        break;
      case DrawTool.pen:
        if (points.length < 2) return;
        final ui.Path path = Path()..moveTo(points.first.dx, points.first.dy);
        for (int i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        canvas.drawPath(path, paint);
// _drawShape() highlight case
      case DrawTool.highlight:
        const double averageLineHeight = 16.0;

        final ui.Paint highlightPaint = Paint()
          ..color = color.withValues(alpha: 0.27)
          ..strokeWidth = sw * averageLineHeight
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;

        // Shift mode: live straight line
        if (points.length == 1 || points.length == 2) {
          canvas.drawLine(start, end, highlightPaint);
          break;
        }

        // Normal mode: freehand
        final ui.Path path = Path()..moveTo(points.first.dx, points.first.dy);
        for (int i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        canvas.drawPath(path, highlightPaint);
        break;
      case DrawTool.line:
        canvas.drawLine(start, end, paint);

      case DrawTool.rect:
        canvas.drawRect(Rect.fromPoints(start, end), paint);

      case DrawTool.sizebox:
        canvas.drawRect(Rect.fromPoints(start, end), paint);

      case DrawTool.ellipse:
        canvas.drawOval(Rect.fromPoints(start, end), paint);

      case DrawTool.arrow:
        _drawArrow(canvas, start, end, paint);

      case DrawTool.ruler:
        _drawRuler(canvas, start, end, paint);

      case DrawTool.guide:
        break; // guides drawn separately

      default:
        break;
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final double angle = atan2(end.dy - start.dy, end.dx - start.dx);
    const double headLen = 14.0;
    const double headAngle = 0.45; // radians
    final ui.Offset p1 = Offset(
      end.dx - headLen * cos(angle - headAngle),
      end.dy - headLen * sin(angle - headAngle),
    );
    final ui.Offset p2 = Offset(
      end.dx - headLen * cos(angle + headAngle),
      end.dy - headLen * sin(angle + headAngle),
    );
    canvas.drawLine(end, p1, paint);
    canvas.drawLine(end, p2, paint);
  }

  void _drawRuler(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    // Tick marks at start/end
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    final double len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final double nx = -dy / len;
    final double ny = dx / len;
    const double tick = 6.0;
    canvas.drawLine(
      Offset(start.dx + nx * tick, start.dy + ny * tick),
      Offset(start.dx - nx * tick, start.dy - ny * tick),
      paint,
    );
    canvas.drawLine(
      Offset(end.dx + nx * tick, end.dy + ny * tick),
      Offset(end.dx - nx * tick, end.dy - ny * tick),
      paint,
    );
  }

  void _paintMeasurement(Canvas canvas, DrawTool tool, Offset start, Offset end, Color color) {
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    final double dist = sqrt(dx * dx + dy * dy);
    final double angleDeg = atan2(dy, dx) * 180 / pi;

    String label;
    if (tool == DrawTool.sizebox) {
      final ui.Rect r = Rect.fromPoints(start, end);
      label = 'X:${r.left.round()} Y:${r.top.round()} '
          'W:${r.width.round()} H:${r.height.round()}';
    } else {
      label = '${dist.round()}px  Δ${dx.round()},${dy.round()}  ${angleDeg.toStringAsFixed(1)}°';
    }

    final ui.Offset mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    _drawLabel(canvas, label, mid + const Offset(6, -14), color);
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 11,
          backgroundColor: Colors.black.withValues(alpha: 0.95),
          fontFamily: 'monospace',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  void _paintGuideDistance(Canvas canvas, Offset start, Offset end, Color color, {required Axis axis}) {
    final double distance = (end - start).distance;
    if (distance < 2) return;

    final Offset offset = axis == Axis.horizontal ? const Offset(0, -12) : const Offset(12, 0);
    final Offset lineStart = start + offset;
    final Offset lineEnd = end + offset;
    final Paint paint = Paint()
      ..color = color.withValues(alpha: 0.9)
      ..strokeWidth = 1.0;

    canvas.drawLine(lineStart, lineEnd, paint);
    const double tick = 4.0;
    if (axis == Axis.horizontal) {
      canvas.drawLine(lineStart + const Offset(0, -tick), lineStart + const Offset(0, tick), paint);
      canvas.drawLine(lineEnd + const Offset(0, -tick), lineEnd + const Offset(0, tick), paint);
      _drawLabel(
          canvas, '${distance.round()}px', Offset((lineStart.dx + lineEnd.dx) / 2 - 20, lineStart.dy - 14), color);
    } else {
      canvas.drawLine(lineStart + const Offset(-tick, 0), lineStart + const Offset(tick, 0), paint);
      canvas.drawLine(lineEnd + const Offset(-tick, 0), lineEnd + const Offset(tick, 0), paint);
      _drawLabel(canvas, '${distance.round()}px', Offset(lineStart.dx + 6, (lineStart.dy + lineEnd.dy) / 2 - 8), color);
    }
  }

  void _paintGuides(Canvas canvas, Size size) {
    // Collect all guide positions for intersection detection
    final List<GuideLineModel> hGuides = guides
        .where((GuideLineModel g) => g.orientation == GuideOrientation.horizontal)
        .toList()
      ..sort((GuideLineModel a, GuideLineModel b) => a.position.compareTo(b.position));
    final List<GuideLineModel> vGuides = guides
        .where((GuideLineModel g) => g.orientation == GuideOrientation.vertical)
        .toList()
      ..sort((GuideLineModel a, GuideLineModel b) => a.position.compareTo(b.position));

    for (final GuideLineModel g in hGuides) {
      final ui.Paint paint = Paint()
        ..color = g.color.withValues(alpha: g.selected ? 0.95 : 0.72)
        ..strokeWidth = g.selected ? 2 : 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(0, g.position), Offset(size.width, g.position), paint);
      _drawLabel(canvas, 'y: ${g.position.round()}', Offset(size.width - 54, g.position + 3), g.color);
    }

    for (final GuideLineModel g in vGuides) {
      final ui.Paint paint = Paint()
        ..color = g.color.withValues(alpha: g.selected ? 0.95 : 0.72)
        ..strokeWidth = g.selected ? 2 : 1
        ..style = PaintingStyle.stroke;
      canvas.drawLine(Offset(g.position, 0), Offset(g.position, size.height), paint);
      _drawLabel(canvas, 'x: ${g.position.round()}', Offset(g.position + 3, 4), g.color);
    }

    // Intersection highlights
    for (final GuideLineModel h in hGuides) {
      for (final GuideLineModel v in vGuides) {
        final ui.Offset pt = Offset(v.position, h.position);
        final ui.Paint highlightPaint = Paint()
          ..color = Color.lerp(h.color, v.color, 0.5)!.withValues(alpha: 0.95)
          ..style = PaintingStyle.fill;
        canvas.drawCircle(pt, 5, highlightPaint);
      }
    }

    if (vGuides.length > 1) {
      for (final GuideLineModel h in hGuides) {
        for (int i = 0; i < vGuides.length - 1; i++) {
          _paintGuideDistance(
            canvas,
            Offset(vGuides[i].position, h.position),
            Offset(vGuides[i + 1].position, h.position),
            h.color,
            axis: Axis.horizontal,
          );
        }
      }
    }

    if (hGuides.length > 1) {
      for (final GuideLineModel v in vGuides) {
        for (int i = 0; i < hGuides.length - 1; i++) {
          _paintGuideDistance(
            canvas,
            Offset(v.position, hGuides[i].position),
            Offset(v.position, hGuides[i + 1].position),
            v.color,
            axis: Axis.vertical,
          );
        }
      }
    }
  }

  void _paintGrid(Canvas canvas, Size size) {
    final ui.Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += gridSpacing) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += gridSpacing) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(AnnotationPainter old) => true;
}
