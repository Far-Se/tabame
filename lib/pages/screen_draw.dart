import 'dart:async';
import 'dart:convert';
import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../logic/app_startup.dart';
import '../models/classes/boxes.dart';
import '../models/classes/hotkeys.dart';
import '../models/classes/screen_draw_hotkeys.dart';
import '../models/screen_utils.dart';
import '../models/settings.dart';
import '../models/win32/mixed.dart';
import '../models/win32/win_utils.dart';
import '../widgets/widgets/color_picker.dart';
import '../widgets/widgets/custom_tooltip.dart';
import '../widgets/widgets/emoji_picker_modal.dart';
import '../widgets/interface/fancyshot.dart';
import '../widgets/widgets/font_picker/models/picker_font.dart';
import '../widgets/widgets/font_picker/ui/font_picker.dart';

// ---------------------------------------------------------------------------
// Screen-Draw post-capture action enum
// ---------------------------------------------------------------------------

enum ScreenDrawCaptureAction {
  copyImage,
  copyFile,
  upload,
  copyTextOcr,
}

enum ScreenDrawOcrCaptureType {
  bitBlt,
  directX,
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------

Future<void> startScreenDraw() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStartup.initialize();
  await Boxes.registerBoxes(justLoad: true);

  // Use virtual desktop size so the initial window is large enough for all monitors.
  // setupOverlay() will reposition it precisely after HWND is known.
  final int vWidth = GetSystemMetrics(SM_CXVIRTUALSCREEN);
  final int vHeight = GetSystemMetrics(SM_CYVIRTUALSCREEN);

  final WindowOptions windowOptions = WindowOptions(
    size: Size(vWidth.toDouble(), vHeight.toDouble()),
    center: false,
    backgroundColor: Colors.transparent,
    skipTaskbar: true,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: false,
    title: 'Tabame Screen Draw',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.show();
    await windowManager.focus();
    Win32Window.hwnd = GetAncestor(GetActiveWindow(), 2);
  });

  runApp(const AnnotationApp());
}

// ---------------------------------------------------------------------------
// Win32 helpers
// ---------------------------------------------------------------------------
class Settings {
  static String get _path => '${WinUtils.getTabameAppDataFolder(settings: true)}\\screen_draw.json';
  static Map<String, dynamic> _data = <String, dynamic>{};

  static void load() {
    try {
      final File file = File(_path);
      if (file.existsSync()) {
        final String content = file.readAsStringSync();
        _data = jsonDecode(content) as Map<String, dynamic>;
      }
    } catch (e) {
      // ignore
    }
  }

  static void save() {
    try {
      final File file = File(_path);
      file.writeAsStringSync(jsonEncode(_data));
    } catch (e) {
      // ignore
    }
  }

  // --- String Getters / Setters ---
  static String? getString(String key) => _data[key] as String?;

  static void setString(String key, String? value) {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    save();
  }

  // --- Boolean Getters / Setters ---
  static bool? getBool(String key) => _data[key] as bool?;

  static void setBool(String key, bool value) {
    _data[key] = value;
    save();
  }

  // --- Integer Getters / Setters ---
  static int? getInt(String key) => _data[key] as int?;

  static void setInt(String key, int value) {
    _data[key] = value;
    save();
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
  imageFile,
  measureDistance,
}

enum GuideOrientation { horizontal, vertical }

@immutable
class AppColor {
  static const List<Color> palette = <ui.Color>[
    Colors.black,
    Colors.red,
    Colors.orange,
    Colors.yellow,
    Color(0xFF00FF00),
    Colors.cyan,
    Colors.blue,
    Colors.purple,
    Colors.white,
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
  final String? fontFamily; // text: font family override
  final int? stepNumber; // stepCounter: which number
  /// Raw RGBA pixels captured from screen (blur/pixelate/smartDelete/spotlight/imageDraw/magnifier)
  final Uint8List? imageBytes;
  final int? imageW;
  final int? imageH;

  /// For smartDelete: the fill color sampled from the first pixel
  final Color? fillColor;

  /// For text/infoBalloon: explicit background color (null = default black/shape color)
  final Color? textBgColor;

  /// For rect / ellipse: draw filled instead of stroked
  final bool filled;

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
    this.fontFamily,
    this.stepNumber,
    this.imageBytes,
    this.imageW,
    this.imageH,
    this.fillColor,
    this.textBgColor,
    this.filled = false,
  });

  DrawShape copyWith({
    List<Offset>? points,
    Color? color,
    double? strokeWidth,
    double? opacity,
    bool? selected,
    String? text,
    bool? textBackground,
    Color? textColor,
    double? fontSize,
    String? fontFamily,
    int? stepNumber,
    Uint8List? imageBytes,
    int? imageW,
    int? imageH,
    Color? fillColor,
    Color? textBgColor,
    bool? filled,
  }) {
    return DrawShape(
      tool: tool,
      points: points ?? this.points,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
      opacity: opacity ?? this.opacity,
      selected: selected ?? this.selected,
      text: text ?? this.text,
      textBackground: textBackground ?? this.textBackground,
      textColor: textColor ?? this.textColor,
      fontSize: fontSize ?? this.fontSize,
      fontFamily: fontFamily ?? this.fontFamily,
      stepNumber: stepNumber ?? this.stepNumber,
      imageBytes: imageBytes ?? this.imageBytes,
      imageW: imageW ?? this.imageW,
      imageH: imageH ?? this.imageH,
      fillColor: fillColor ?? this.fillColor,
      textBgColor: textBgColor ?? this.textBgColor,
      filled: filled ?? this.filled,
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

  // Crosshair
  bool crosshairVisible = true;
  void toggleCrosshair() {
    crosshairVisible = !crosshairVisible;
    notifyListeners();
  }

  // Magnifier
  bool magnifierVisible = false;

  // Shape fill option (rect / ellipse)
  bool shapeFilled = false;
  void toggleShapeFilled() {
    shapeFilled = !shapeFilled;
    notifyListeners();
  }

  // Text tool options
  bool textBackground = true;
  double fontSize = 16.0;
  String? textFontFamily; // null = system default
  Color? textColor; // null = use strokeColor
  Color? textBgColor; // null = black

  // Step counter: auto-incrementing number
  int _stepCount = 1;
  int get nextStepNumber => _stepCount;
  void resetStepCounter() {
    _stepCount = 1;
    notifyListeners();
  }

  // Pending text/balloon callback (set by overlay, consumed here)
  String? pendingText;

  /// When true, the overlay will close the app after the next screen capture.
  bool captureAndClose = false;

  // ── Screen-capture post-action settings ────────────────────────────────────
  /// If non-null, apply this FancyShot profile before saving/uploading.
  String? captureSelectedFancyShotProfile;

  /// After capture: copy image, copy file, upload via host, or null (just save).
  /// null means copy image to clipboard (legacy / default behaviour).
  ScreenDrawCaptureAction capturePostAction = ScreenDrawCaptureAction.copyImage;
  ScreenDrawOcrCaptureType ocrCaptureType = ScreenDrawOcrCaptureType.bitBlt;

  /// If [capturePostAction] is [ScreenDrawCaptureAction.upload], which host.
  ScreenCaptureUploadHost? captureUploadHost;

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
      activeTool = DrawTool.select;
      selectMode = true;
      Win32Window.disableClickThrough();
      Future<void>.delayed(const Duration(milliseconds: 100), () async {
        await windowManager.show();
        await WindowManager.instance.focus();
        await Future<void>.delayed(const Duration(milliseconds: 100));
        final Pointer<INPUT> inputs = calloc<INPUT>(2);

        // Left button down
        inputs[0]
          ..type = INPUT_MOUSE
          ..mi.dx = 0
          ..mi.dy = 0
          ..mi.mouseData = 0
          ..mi.dwFlags = MOUSEEVENTF_LEFTDOWN
          ..mi.time = 0
          ..mi.dwExtraInfo = 0;

        // Left button up
        inputs[1]
          ..type = INPUT_MOUSE
          ..mi.dx = 0
          ..mi.dy = 0
          ..mi.mouseData = 0
          ..mi.dwFlags = MOUSEEVENTF_LEFTUP
          ..mi.time = 0
          ..mi.dwExtraInfo = 0;

        SendInput(2, inputs, sizeOf<INPUT>());

        calloc.free(inputs);
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
    Future<void>.delayed(const Duration(milliseconds: 100), () {
      // Win32.activeWindowUnderCursor();
    });
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
    Settings.setInt('strokeColor', c.toARGB32());
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
      filled: (activeTool == DrawTool.rect || activeTool == DrawTool.ellipse) ? shapeFilled : false,
    );
    currentEnd = pos;
    notifyListeners();
  }

  void updateShape(Offset pos, {bool shiftHeld = false}) {
    if (currentShape == null) return;
    if (activeTool == DrawTool.pen) {
      // Distance-gate: only record a new point if it moved at least 3px from the last.
      // This removes micro-jitter from raw mouse events without losing real direction changes.
      final List<Offset> existing = currentShape!.points;
      if (existing.isNotEmpty && (existing.last - pos).distance < 3.0) return;
      currentShape = currentShape!.copyWith(
        points: <ui.Offset>[...existing, pos],
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
      // Apply iterative Laplacian smoothing to the raw pen points before committing.
      // Each interior point is pulled toward the average of its neighbours.
      // We run 3 passes with alpha=0.5 — smooths jitter while preserving shape.
      List<Offset> pts = List<Offset>.from(currentShape!.points);
      const int passes = 3;
      const double alpha = 0.5;
      for (int pass = 0; pass < passes; pass++) {
        final List<Offset> next = List<Offset>.from(pts);
        for (int i = 1; i < pts.length - 1; i++) {
          final Offset avg = (pts[i - 1] + pts[i + 1]) / 2.0;
          next[i] = pts[i] + (avg - pts[i]) * alpha;
        }
        pts = next;
      }
      finished = currentShape!.copyWith(points: pts);
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
      textBgColor: textBgColor,
      fontSize: fontSize,
      fontFamily: textFontFamily,
    ));
    notifyListeners();
  }

  /// Called by overlay after a screen region is captured (blur/pixelate/smartDelete/spotlight/imageDraw/magnifier).
  void commitImageShape(DrawTool tool, Rect region, Uint8List bytes, int w, int h, {Color? fillColor}) {
    _redoStack.clear();
    _shapes.add(DrawShape(
      tool: tool,
      points: tool == DrawTool.imageDraw
          ? <ui.Offset>[region.topLeft + const Offset(10, 10), region.bottomRight + const Offset(10, 10)]
          : <ui.Offset>[region.topLeft, region.bottomRight],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      imageBytes: bytes,
      imageW: w,
      imageH: h,
      fillColor: fillColor,
    ));
    if (tool == DrawTool.imageDraw) {
      //selectSelecting mode
      setTool(DrawTool.select);
      selectShapeAt(region.center);
    }
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

  /// Remove all committed shapes of [tool]. Used to enforce single-spotlight.
  void removeShapesOfTool(DrawTool tool) {
    _shapes.removeWhere((DrawShape s) => s.tool == tool);
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
      final DrawShape s = _shapes[i];
      if (s.tool == DrawTool.pixelate || s.tool == DrawTool.blur || s.tool == DrawTool.magnifier) {
        continue;
      }
      if (_hitTest(s, pos)) {
        for (DrawShape s in _shapes) {
          s.selected = false;
        }
        s.selected = true;
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

  void resizeElement(Offset pos, Offset delta) {
    _clearGuideSelection(notify: false);

    // Scroll delta dy > 0 usually means scroll down (shrink), dy < 0 means scroll up (grow).
    final double scale = (1.0 - (delta.dy / 1000.0)).clamp(0.5, 2.0);

    for (int i = _shapes.length - 1; i >= 0; i--) {
      final DrawShape s = _shapes[i];
      if (s.tool == DrawTool.pixelate || s.tool == DrawTool.blur || s.tool == DrawTool.magnifier) {
        continue;
      }
      if (_hitTest(s, pos)) {
        for (final DrawShape shape in _shapes) {
          shape.selected = false;
        }

        // Calculate bounding box center to use as scaling anchor
        if (s.points.isEmpty) continue;
        double minX = s.points[0].dx;
        double maxX = s.points[0].dx;
        double minY = s.points[0].dy;
        double maxY = s.points[0].dy;
        for (final ui.Offset p in s.points) {
          if (p.dx < minX) minX = p.dx;
          if (p.dx > maxX) maxX = p.dx;
          if (p.dy < minY) minY = p.dy;
          if (p.dy > maxY) maxY = p.dy;
        }
        final ui.Offset center = ui.Offset((minX + maxX) / 2, (minY + maxY) / 2);

        // Scale points relative to center
        final List<ui.Offset> newPoints = s.points.map((ui.Offset p) => center + (p - center) * scale).toList();

        // Also scale font size and stroke width
        double? newFontSize = s.fontSize;
        if (newFontSize == null) {
          if (s.tool == DrawTool.text || s.tool == DrawTool.emoji) {
            newFontSize = s.strokeWidth * 8 + 12;
          } else if (s.tool == DrawTool.infoBalloon) {
            newFontSize = s.strokeWidth * 6 + 12;
          } else if (s.tool == DrawTool.stepCounter) {
            newFontSize = 28.0;
          }
        }

        if (newFontSize != null) {
          newFontSize = (newFontSize * scale).clamp(8.0, 1000.0);
        }

        _shapes[i] = s.copyWith(
          points: newPoints,
          fontSize: newFontSize,
          strokeWidth: (s.strokeWidth * scale).clamp(1.0, 100.0),
          selected: true,
        );
        selectedShapeIndex = i;
        notifyListeners();
        return;
      }
    }
    for (final DrawShape s in _shapes) {
      s.selected = false;
    }
    selectedShapeIndex = null;
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
        s.tool == DrawTool.ellipse ||
        s.tool == DrawTool.blur ||
        s.tool == DrawTool.pixelate ||
        s.tool == DrawTool.smartDelete ||
        s.tool == DrawTool.spotlight ||
        s.tool == DrawTool.imageDraw ||
        s.tool == DrawTool.imageFile ||
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
      final double r = (s.fontSize ?? 28.0) / 2;
      return Rect.fromCircle(center: a, radius: r + 8).contains(pos);
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

  Future<void> addLoadedImage(Uint8List bytes, int width, int height, {Offset? position}) async {
    final Offset topLeft = position ?? const Offset(200, 200);

    _redoStack.clear();
    _shapes.add(
      DrawShape(
        tool: DrawTool.imageFile,
        points: <Offset>[
          topLeft,
          topLeft + Offset(width.toDouble(), height.toDouble()),
        ],
        color: Colors.white,
        strokeWidth: 1,
        opacity: 1,
        imageBytes: bytes,
        imageW: width,
        imageH: height,
      ),
    );

    setTool(DrawTool.select);
    selectShapeAt(topLeft + Offset(width / 2, height / 2));
    notifyListeners();
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

  /// Virtual-desktop top-left in screen coords (SM_XVIRTUALSCREEN / SM_YVIRTUALSCREEN).
  late final Offset _virtualOrigin;

  /// Widget-local rect of the monitor the cursor is currently on.
  Rect _currentMonitorRect = Rect.zero;

  final List<ScreenCaptureUploadHost> uploadHosts = FancyShot.loadUploadHosts();
  final List<FancyShotProfile> profiles = FancyShot.loadProfiles();

  @override
  void initState() {
    super.initState();
    NativeHooks.registerCallHandler();
    NativeHooks.addListener(this);
    Settings.load();

    _ctrl.captureAndClose = Settings.getBool("captureAndClose") ?? false;

    final int action = Settings.getInt("capturePostAction") ?? 0;
    _ctrl.capturePostAction =
        ScreenDrawCaptureAction.values[action.clamp(0, ScreenDrawCaptureAction.values.length - 1)];

    final int ocrType = Settings.getInt("ocrCaptureType") ?? 0;
    _ctrl.ocrCaptureType =
        ScreenDrawOcrCaptureType.values[ocrType.clamp(0, ScreenDrawOcrCaptureType.values.length - 1)];

    final String? host = Settings.getString("captureUploadHost");
    _ctrl.captureUploadHost = uploadHosts.where((ScreenCaptureUploadHost h) => h.id == host).firstOrNull;

    final String? fancyshot = Settings.getString("captureSelectedFancyShotProfile");
    _ctrl.captureSelectedFancyShotProfile = fancyshot;

    final int? savedColor = Settings.getInt('strokeColor');
    if (savedColor != null) {
      _ctrl.strokeColor = Color(savedColor);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      Win32Window.setupOverlay();
      _ctrl.toggleDrawingMode(activated: true);
      unawaited(_registerScreenDrawHotkeys());
    });
    Monitor.fetchMonitors();

    _virtualOrigin = Offset(
      GetSystemMetrics(SM_XVIRTUALSCREEN).toDouble(),
      GetSystemMetrics(SM_YVIRTUALSCREEN).toDouble(),
    );

    _updateCurrentMonitorRect();
    _timer = Timer.periodic(const Duration(milliseconds: 50), (_) => _ticker());

    WinUtils.fixDrawBug(delay: const Duration(milliseconds: 300));
  }

  int _currentMonitorHandle = 0;

  void _updateCurrentMonitorRect() {
    final Pointer<POINT> pt = calloc<POINT>();
    try {
      if (GetCursorPos(pt) == 0) return;
      final int handle = MonitorFromPoint(pt.ref, MONITOR_DEFAULTTONEAREST);
      if (handle == _currentMonitorHandle && !_currentMonitorRect.isEmpty) return;
      _currentMonitorHandle = handle;
      final Square? m = Monitor.monitorSizes[handle];
      if (m == null) return;
      final Rect r = Rect.fromLTWH(
        m.x.toDouble() - _virtualOrigin.dx,
        m.y.toDouble() - _virtualOrigin.dy,
        m.width.toDouble(),
        m.height.toDouble(),
      );
      if (r != _currentMonitorRect) setState(() => _currentMonitorRect = r);
    } finally {
      calloc.free(pt);
    }
  }

  void _ticker() {
    _updateCurrentMonitorRect();
  }

  Future<void> _registerScreenDrawHotkeys() async {
    final List<Map<String, dynamic>> hotkeys = <Map<String, dynamic>>[];
    for (final ScreenDrawHotkeyBinding binding in Boxes.screenDrawHotkeys) {
      if (!binding.enabled || !binding.isScreenDraw) continue;
      final int? keyVk = Hotkeys.keyToVirtualKey(binding.key);
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
        builder: (_, __) => AnnotationOverlay(
          controller: _ctrl,
          currentMonitorRect: _currentMonitorRect,
          virtualOrigin: _virtualOrigin,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Main overlay widget
// ---------------------------------------------------------------------------

class AnnotationOverlay extends StatefulWidget {
  final AnnotationController controller;
  final Rect currentMonitorRect;
  final Offset virtualOrigin;
  const AnnotationOverlay({
    super.key,
    required this.controller,
    required this.currentMonitorRect,
    required this.virtualOrigin,
  });

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
  // Offset? _magnifierCenter;
  // DrawShape? _magnifierShape; // fetched pixels for the magnifier circle

  Timer? _liveRegionFetchDebounce;
  Timer? _selectedCaptureRefreshTimer;
  int _selectedImageRefreshToken = 0;
  bool _selectedCaptureRefreshInProgress = false;
  bool _selectedCaptureDragRefreshActive = false;

  // Single unified virtual-desktop snapshot used by all region tools.
  // Covers the full multi-monitor area via GDI GetDIBits (includes our drawings).
  Uint8List? _vdSnapshotBytes; // RGBA pixels
  Rect? _vdSnapshotRect; // screen rect (physical coords)
  int? _vdSnapshotW;
  int? _vdSnapshotH;
  bool _vdSnapshotInProgress = false;
  bool _lastDrawingModeActive = false;

  // Toolbar real size — measured after first build for crosshair hit-test.
  final GlobalKey _toolbarKey = GlobalKey();
  Size _toolbarSize = const Size(52, 600); // sensible fallback

  // Measure Distance: live cursor position + sampled snapshot for background detection
  Offset? _measureCursorPos;
  Uint8List? _measureSnapshotBytes;
  int? _measureSnapshotW;
  int? _measureSnapshotH;
  Rect? _measureSnapshotRect;

  @override
  void initState() {
    super.initState();
    _lastDrawingModeActive = ctrl.drawingModeActive;
    ctrl.addListener(_handleControllerChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measureToolbar());
  }

  void _measureToolbar() {
    final RenderBox? box = _toolbarKey.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final Size s = box.size;
    if (s != _toolbarSize) setState(() => _toolbarSize = s);
  }

  @override
  void dispose() {
    _liveRegionFetchDebounce?.cancel();
    _selectedCaptureRefreshTimer?.cancel();
    ctrl.removeListener(_handleControllerChanged);
    super.dispose();
  }

  void _handleControllerChanged() {
    if (ctrl.drawingModeActive && !_lastDrawingModeActive) {
      _discardMonitorSnapshot();
      // Re-measure toolbar once it's built.
      WidgetsBinding.instance.addPostFrameCallback((_) => _measureToolbar());
    }
    _lastDrawingModeActive = ctrl.drawingModeActive;
  }

  void _discardMonitorSnapshot() {
    _vdSnapshotBytes = null;
    _vdSnapshotRect = null;
    _vdSnapshotW = null;
    _vdSnapshotH = null;
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
    final Rect monRect = widget.currentMonitorRect;

    // Toolbar and status bar anchor to the active monitor.
    // Fall back to (8,8) relative to virtual canvas if monRect not yet known.
    final double toolbarLeft = (monRect.isEmpty ? 0 : monRect.left) + 8;
    final double toolbarTop = (monRect.isEmpty ? 0 : monRect.top) + 8;
    final double statusLeft = (monRect.isEmpty ? 0 : monRect.left) + 8;
    final double statusBottom = monRect.isEmpty ? 8 : (size.height - monRect.bottom) + 8;

    return KeyboardListener(
      focusNode: FocusNode()..requestFocus(),
      autofocus: true,
      onKeyEvent: _onKeyEvent,
      child: Stack(
        children: <Widget>[
          ListenableBuilder(
            listenable: ctrl,
            builder: (_, __) => Stack(
              children: ctrl.shapes
                  .where((DrawShape s) => s.imageBytes != null && s.tool == DrawTool.spotlight)
                  .map((DrawShape s) => _CommittedImageShape(shape: s))
                  .toList(),
            ),
          ),
          Positioned.fill(
            child: Listener(
              onPointerSignal: (PointerSignalEvent pointerSignal) {
                if (pointerSignal is PointerScrollEvent) _onScrollEvent(pointerSignal);
              },
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
          ),
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
                          s.tool == DrawTool.imageFile ||
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
          // if (false &&
          //     ctrl.drawingModeActive &&
          //     ctrl.activeTool == DrawTool.magnifier &&
          //     _magnifierShape != null &&
          //     _magnifierCenter != null)
          //   _MagnifierLens(center: _magnifierCenter!, shape: _magnifierShape!),
          // Toolbar anchored to active monitor
          if (ctrl.drawingModeActive)
            Positioned(
              left: toolbarLeft,
              top: toolbarTop,
              child: AnnotationToolbar(key: _toolbarKey, controller: ctrl, monitorRect: widget.currentMonitorRect),
            ),
          // Status bar anchored to active monitor
          if (ctrl.drawingModeActive)
            Positioned(
              bottom: statusBottom,
              left: statusLeft,
              child: _StatusBar(controller: ctrl),
            ),
          // Crosshair: knows the toolbar position so it can switch cursor there
          if (ctrl.drawingModeActive && !selectMode && ctrl.crosshairVisible)
            Positioned.fill(
              child: _CrosshairLayer(
                onHover: null,
                justTheMouse: <DrawTool>[
                  DrawTool.magnifier,
                  DrawTool.screenCapture,
                  DrawTool.imageDraw,
                  DrawTool.smartDelete,
                ].contains(ctrl.activeTool),
                toolbarRect: Rect.fromLTWH(
                  toolbarLeft,
                  toolbarTop,
                  _toolbarSize.width,
                  _toolbarSize.height,
                ),
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
          // Measure Distance: live hover overlay
          if (ctrl.drawingModeActive && ctrl.activeTool == DrawTool.measureDistance)
            Positioned.fill(
              child: MouseRegion(
                cursor: SystemMouseCursors.precise,
                onHover: (PointerHoverEvent e) {
                  setState(() => _measureCursorPos = e.localPosition);
                  _ensureMeasureSnapshot();
                },
                child: _measureCursorPos != null
                    ? IgnorePointer(
                        child: CustomPaint(
                          painter: _MeasureDistancePainter(
                            cursor: _measureCursorPos!,
                            snapshotBytes: _measureSnapshotBytes,
                            snapshotW: _measureSnapshotW,
                            snapshotH: _measureSnapshotH,
                            snapshotRect: _measureSnapshotRect,
                          ),
                        ),
                      )
                    : const SizedBox.shrink(),
              ),
            ),
        ],
      ),
    );
  }

  Timer? timer;
  void _onKeyEvent(KeyEvent e) {
    _shiftHeld = HardwareKeyboard.instance.isShiftPressed;
    if (e is KeyUpEvent) {
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        timer?.cancel();
        ctrl.toggleVisibility();
      }
    } else if (e is KeyDownEvent) {
      final bool lCtrl = HardwareKeyboard.instance.isControlPressed;
      // In-app shortcuts (focus required)
      if (lCtrl) {
        if (e.logicalKey == LogicalKeyboardKey.keyZ) ctrl.undo();
        if (e.logicalKey == LogicalKeyboardKey.keyY) ctrl.redo();
        if (e.logicalKey == LogicalKeyboardKey.keyG) {
          ctrl.toggleGrid();
        }
        if (e.logicalKey == LogicalKeyboardKey.keyC) {
          ctrl.toggleCrosshair();
        }
      }
      if (e.logicalKey == LogicalKeyboardKey.delete) ctrl.deleteSelected();
      if (e.logicalKey == LogicalKeyboardKey.escape) {
        timer = Timer(const Duration(milliseconds: 400), () {
          WindowManager.instance.close();
          // ctrl.toggleDrawingMode(activated: false);
        });
        // ctrl.currentShape = null;
        // ctrl.notifyListeners();
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
        LogicalKeyboardKey.keyK: DrawTool.imageFile,
        LogicalKeyboardKey.keyV: DrawTool.measureDistance,
      };
      if (!lCtrl && toolKeys.containsKey(e.logicalKey)) {
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

  void _startSelectedCaptureDragRefresh() {
    final DrawShape? shape = ctrl.selectedShape;
    if (shape == null || !_usesCaptureMonitorTool(shape.tool)) return;

    _selectedCaptureDragRefreshActive = true;
    _selectedCaptureRefreshTimer?.cancel();
    _selectedCaptureRefreshTimer = Timer.periodic(const Duration(milliseconds: 400), (_) {
      unawaited(_refreshSelectedCaptureMonitorShape(force: true));
    });
  }

  void _stopSelectedCaptureDragRefresh({bool refreshNow = false}) {
    final bool shouldRefresh = refreshNow && _selectedCaptureDragRefreshActive;
    _selectedCaptureDragRefreshActive = false;
    _selectedCaptureRefreshTimer?.cancel();
    _selectedCaptureRefreshTimer = null;
    if (shouldRefresh) {
      unawaited(_refreshSelectedCaptureMonitorShape(force: true));
    }
  }

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
    if (ctrl.activeTool == DrawTool.measureDistance) return; // handled by MouseRegion hover

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
      _startSelectedCaptureDragRefresh();
      return;
    }

    if (_isRegionTool(ctrl.activeTool)) {
      //hide crosshair

      setState(() {
        selectMode = true;
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

  void _onScrollEvent(PointerScrollEvent e) {
    if (!ctrl.drawingModeActive) return;
    if (!selectMode) return;

    final ui.Offset pos = e.localPosition;
    // final double scrollDelta = e.scrollDelta.dy;
    ctrl.resizeElement(pos, e.scrollDelta);
  }

  Future<void> _onPanEnd(DragEndDetails d) async {
    if (!ctrl.drawingModeActive) return;

    if (ctrl.activeTool == DrawTool.screenCapture) {
      unawaited(_copyCaptureSelection());
      return;
    }

    if (_isLiveRegionTool(ctrl.activeTool) && _captureStart != null && _captureCurrent != null) {
      _liveRegionFetchDebounce?.cancel();
      final Rect region = Rect.fromPoints(_captureStart!, _captureCurrent!);
      setState(() {
        _captureStart = null;
        _captureCurrent = null;
        _liveRegionShape = null;
      });
      if (region.width > 4 && region.height > 4) {
        // Await so _commitLiveRegion crops from the current frozen snapshot,
        // then discard so the *next* drag takes a fresh capture.
        final DrawTool committedTool = ctrl.activeTool;
        await _commitLiveRegion(region);
        // Restore blur/pixelate tool so the user can keep drawing regions.
        // For other live-region tools (smartDelete, spotlight) switch to select.
        if (committedTool != DrawTool.blur && committedTool != DrawTool.pixelate) {
          ctrl.setTool(DrawTool.select);
        } else {
          // Stay on the same tool — just clear selectMode so the crosshair returns.
          selectMode = false;
          setState(() {});
        }
      }
      _discardMonitorSnapshot();
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
    if (selectMode) {
      _stopSelectedCaptureDragRefresh(refreshNow: true);
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

  bool _measureSnapshotInProgress = false;
  DateTime _lastMeasureSnapshotTime = DateTime(0);

  Future<void> _ensureMeasureSnapshot() async {
    final DateTime now = DateTime.now();
    if (_measureSnapshotBytes != null && now.difference(_lastMeasureSnapshotTime).inSeconds < 2) return;
    if (_measureSnapshotInProgress) return;
    _measureSnapshotInProgress = true;
    try {
      final Size sz = MediaQuery.of(context).size;
      final Rect full = Offset.zero & sz;
      final Uint8List? bytes = await _captureScreenRegion(full);
      if (bytes == null || !mounted) return;
      setState(() {
        _measureSnapshotBytes = bytes;
        _measureSnapshotW = sz.width.round();
        _measureSnapshotH = sz.height.round();
        _measureSnapshotRect = full;
        _lastMeasureSnapshotTime = DateTime.now();
      });
    } finally {
      _measureSnapshotInProgress = false;
    }
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
      // Spotlight needs the full virtual desktop so the blur shader covers all monitors.
      final Rect vdRect = Rect.fromLTWH(
        0,
        0,
        GetSystemMetrics(SM_CXVIRTUALSCREEN).toDouble(),
        GetSystemMetrics(SM_CYVIRTUALSCREEN).toDouble(),
      );
      bytes = await _captureScreenRegion(vdRect);
      w = vdRect.width.round().clamp(1, 100000);
      h = vdRect.height.round().clamp(1, 100000);
    } else if (ctrl.activeTool == DrawTool.blur || ctrl.activeTool == DrawTool.pixelate) {
      // Never force-refresh mid-drag — always crop from the snapshot taken at
      // pan-start so we don't re-blur already-blurred pixels (feedback loop).
      bytes = await _captureMonitorRegion(localRect);
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
      // Remove any existing spotlight shape before committing the new one.
      ctrl.removeShapesOfTool(DrawTool.spotlight);
      // Capture the full virtual desktop for the spotlight background.
      final Rect vdRect = Rect.fromLTWH(
        0,
        0,
        GetSystemMetrics(SM_CXVIRTUALSCREEN).toDouble(),
        GetSystemMetrics(SM_CYVIRTUALSCREEN).toDouble(),
      );
      bytes = await _captureScreenRegion(vdRect);
      w = vdRect.width.round().clamp(1, 100000);
      h = vdRect.height.round().clamp(1, 100000);
    } else if (ctrl.activeTool == DrawTool.blur || ctrl.activeTool == DrawTool.pixelate) {
      // Crop from the same frozen snapshot used during the drag — never re-capture
      // at commit time (the screen now shows the live preview blur on top).
      bytes = await _captureMonitorRegion(region);
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
    if (ctrl.activeTool == DrawTool.imageDraw) {
      //selectSelecting mode
      ctrl.setTool(DrawTool.select);
    }
    await Future<void>.delayed(const Duration(milliseconds: 200));
    final Uint8List? bytes = await _captureScreenRegion(localRect);
    if (bytes == null) return;
    final int w = localRect.width.round().clamp(1, 100000);
    final int h = localRect.height.round().clamp(1, 100000);
    ctrl.commitImageShape(DrawTool.imageDraw, localRect, bytes, w, h);
  }

  // ── Frozen monitor capture helper ──────────────────────────────────────────

  Future<bool> _ensureRegionToolSnapshot(DrawTool tool) => _ensureVdSnapshot();

  void _debounceLiveRegionFetch(Rect region) {
    _liveRegionFetchDebounce?.cancel();
    _liveRegionFetchDebounce = Timer(const Duration(milliseconds: 30), () {
      unawaited(_fetchLiveRegion(region));
    });
  }

  // ── Unified virtual-desktop snapshot ──────────────────────────────────────
  // One GDI GetDIBits snapshot of the full virtual desktop per drawing-mode
  // activation. Includes our own annotations. Works across all monitors.

  Future<bool> _ensureVdSnapshot({bool force = false}) async {
    if (_vdSnapshotInProgress) {
      while (_vdSnapshotInProgress && mounted) {
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      return _vdSnapshotBytes != null;
    }
    if (!force && _vdSnapshotBytes != null && _vdSnapshotRect != null) return true;

    _vdSnapshotInProgress = true;
    try {
      final Rect vdRect = Rect.fromLTWH(
        widget.virtualOrigin.dx,
        widget.virtualOrigin.dy,
        GetSystemMetrics(SM_CXVIRTUALSCREEN).toDouble(),
        GetSystemMetrics(SM_CYVIRTUALSCREEN).toDouble(),
      );
      final Uint8List? bytes = _captureScreenRectRgba(vdRect);
      if (bytes == null) return false;
      _vdSnapshotBytes = bytes;
      _vdSnapshotRect = vdRect;
      _vdSnapshotW = vdRect.width.round();
      _vdSnapshotH = vdRect.height.round();
      return true;
    } finally {
      _vdSnapshotInProgress = false;
    }
  }

  Future<void> _refreshSelectedCaptureMonitorShape({bool force = false}) async {
    if (_selectedCaptureRefreshInProgress) return;
    final DrawShape? shape = ctrl.selectedShape;
    if (shape == null || !_usesCaptureMonitorTool(shape.tool) || shape.points.length < 2) return;

    _selectedCaptureRefreshInProgress = true;
    try {
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
    } finally {
      _selectedCaptureRefreshInProgress = false;
    }
  }

  /// Crop [localRect] (widget-local coords) from the virtual-desktop snapshot.
  Future<Uint8List?> _captureScreenRegion(Rect localRect) async {
    if (!await _ensureVdSnapshot()) return null;
    return _cropFromVdSnapshot(localRect);
  }

  /// Like [_captureScreenRegion] but always takes a fresh snapshot first.
  Future<Uint8List?> _captureMonitorRegion(Rect localRect, {bool force = false}) async {
    if (!await _ensureVdSnapshot(force: force)) return null;
    return _cropFromVdSnapshot(localRect);
  }

  /// Crop [localRect] (widget-local / virtual-canvas coords) from the snapshot.
  Uint8List? _cropFromVdSnapshot(Rect localRect) {
    final Uint8List? snap = _vdSnapshotBytes;
    final Rect? snapRect = _vdSnapshotRect;
    final int? snapW = _vdSnapshotW;
    final int? snapH = _vdSnapshotH;
    if (snap == null || snapRect == null || snapW == null || snapH == null) return null;

    final Rect r = localRect.normalized();
    final int outW = r.width.round().clamp(1, 100000);
    final int outH = r.height.round().clamp(1, 100000);

    // Widget-local → screen coords via virtualOrigin.
    final double screenLeft = r.left + widget.virtualOrigin.dx;
    final double screenTop = r.top + widget.virtualOrigin.dy;

    final Uint8List out = Uint8List(outW * outH * 4);
    for (int row = 0; row < outH; row++) {
      final int sy = (screenTop + row - snapRect.top).round();
      if (sy < 0 || sy >= snapH) continue;
      for (int col = 0; col < outW; col++) {
        final int sx = (screenLeft + col - snapRect.left).round();
        if (sx < 0 || sx >= snapW) continue;
        final int srcI = (sy * snapW + sx) * 4;
        final int dstI = (row * outW + col) * 4;
        out[dstI] = snap[srcI];
        out[dstI + 1] = snap[srcI + 1];
        out[dstI + 2] = snap[srcI + 2];
        out[dstI + 3] = snap[srcI + 3];
      }
    }
    return out;
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

  /// Compute the top-left position for a dialog of [dialogWidth] × [dialogHeight]
  /// so it appears centered on the active monitor.
  Offset _dialogOffset(double dialogWidth, double dialogHeight) {
    final Rect m = widget.currentMonitorRect;
    if (m.isEmpty) return Offset.zero;
    return Offset(
      m.left + (m.width - dialogWidth) / 2,
      m.top + (m.height - dialogHeight) / 2,
    );
  }

  Future<void> _showTextDialog(Offset pos) async {
    final TextEditingController tc = TextEditingController();
    bool localBg = ctrl.textBackground;
    // Text color is always the toolbar stroke color — shown as preview only.
    final Color textFgColor = ctrl.strokeColor;
    // Background color starts from last used bg or black.
    Color localBgColor = ctrl.textBgColor ?? Colors.black;
    double localSize = ctrl.fontSize;
    String? localFontFamily = ctrl.textFontFamily;

    // Approximate dialog size (width fixed, height estimated).
    const double dw = 400;
    const double dh = 340;
    final Offset dOff = _dialogOffset(dw, dh);

    Future<void> openFontPicker(StateSetter setSt) async {
      await showDialog<void>(
        context: context,
        barrierColor: Colors.black54,
        builder: (BuildContext pickerCtx) => Dialog(
          backgroundColor: Colors.transparent,
          child: SizedBox(
            width: 900,
            height: 700,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: FontPicker(
                showInDialog: false,
                initialFontFamily: localFontFamily,
                onFontChanged: (PickerFont font) {
                  setSt(() {
                    localFontFamily = font.fontFamily;
                  });
                },
              ),
            ),
          ),
        ),
      );
    }

    final String? result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black38,
      builder: (BuildContext ctx) => Stack(
        children: <Widget>[
          Positioned(
            left: dOff.dx,
            top: dOff.dy,
            width: dw,
            child: StatefulBuilder(
              builder: (BuildContext ctx2, StateSetter setSt) => AlertDialog(
                backgroundColor: Design.background,
                insetPadding: EdgeInsets.zero,
                title: Text(
                  ctrl.activeTool == DrawTool.infoBalloon ? 'Info Balloon Text' : 'Enter Text',
                  style: const TextStyle(color: Colors.white),
                ),
                content: SizedBox(
                  width: dw,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      TextField(
                        controller: tc,
                        autofocus: true,
                        style: TextStyle(color: Colors.white, fontFamily: localFontFamily),
                        decoration: const InputDecoration(
                          hintText: 'Type here…',
                          hintStyle: TextStyle(color: Colors.white38),
                          enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                          focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent)),
                        ),
                        onSubmitted: (String v) {
                          ctrl.textBackground = localBg;
                          ctrl.textBgColor = localBgColor;
                          ctrl.fontSize = localSize;
                          ctrl.textFontFamily = localFontFamily;
                          Navigator.pop(ctx, v);
                        },
                      ),
                      const SizedBox(height: 12),
                      Row(children: <Widget>[
                        Text('Size:', style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 2)),
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
                        Text('${localSize.round()}pt',
                            style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 1)),
                      ]),
                      const SizedBox(height: 8),
                      // Font family picker
                      Row(children: <Widget>[
                        Text('Font:', style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 2)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: GestureDetector(
                            onTap: () => openFontPicker(setSt),
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: Colors.white10,
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: Colors.white38),
                              ),
                              child: Row(children: <Widget>[
                                Expanded(
                                  child: Text(
                                    localFontFamily ?? 'Default',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: Design.baseFontSize + 1,
                                      fontFamily: localFontFamily,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 4),
                                const Icon(Icons.arrow_drop_down, color: Colors.white54, size: 18),
                              ]),
                            ),
                          ),
                        ),
                        if (localFontFamily != null) ...<Widget>[
                          const SizedBox(width: 6),
                          GestureDetector(
                            onTap: () => setSt(() => localFontFamily = null),
                            child: const Icon(Icons.close, color: Colors.white38, size: 16),
                          ),
                        ],
                      ]),
                      const SizedBox(height: 8),
                      // Text color preview (always from toolbar)
                      Row(children: <Widget>[
                        Text('Text color:', style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 2)),
                        const SizedBox(width: 8),
                        Container(
                          width: 20,
                          height: 20,
                          decoration: BoxDecoration(
                            color: textFgColor,
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white54, width: 1.5),
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text('(from toolbar)',
                            style: TextStyle(color: Colors.white38, fontSize: Design.baseFontSize + 1)),
                      ]),
                      const SizedBox(height: 8),
                      // Background toggle + background color picker
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
                              Text('BG', style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 1)),
                            ]),
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (localBg)
                          Expanded(
                            child: SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: Row(
                                children: AppColor.palette
                                    .map((Color c) => GestureDetector(
                                          onTap: () => setSt(() => localBgColor = c),
                                          child: Container(
                                            width: 20,
                                            height: 20,
                                            margin: const EdgeInsets.only(right: 4),
                                            decoration: BoxDecoration(
                                              color: c,
                                              shape: BoxShape.circle,
                                              border: localBgColor == c
                                                  ? Border.all(color: Colors.white, width: 2)
                                                  : Border.all(color: Colors.white24),
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
                      ctrl.textBgColor = localBgColor;
                      ctrl.fontSize = localSize;
                      ctrl.textFontFamily = localFontFamily;
                      Navigator.pop(ctx, tc.text);
                    },
                    child: const Text('OK'),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
    if (result != null && result.isNotEmpty) ctrl.commitTextShape(pos, result);
  }

  Future<void> _showEmojiDialog(Offset pos) async {
    String? selectedEmoji;
    double localSize = ctrl.fontSize.clamp(24.0, 160.0);

    const double dw = 480;
    const double dh = 540;
    final Offset dOff = _dialogOffset(dw, dh);

    final String? result = await showDialog<String>(
      context: context,
      barrierColor: Colors.black38,
      builder: (BuildContext ctx) => Stack(
        children: <Widget>[
          Positioned(
            left: dOff.dx,
            top: dOff.dy,
            width: dw,
            child: StatefulBuilder(
              builder: (BuildContext ctx2, StateSetter setSt) => AlertDialog(
                backgroundColor: Design.background,
                insetPadding: EdgeInsets.zero,
                title: const Text('Pick Emoji', style: TextStyle(color: Colors.white)),
                content: SizedBox(
                  width: dw,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: Design.background,
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
                          Text('Size:', style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 2)),
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
                          Text('${localSize.round()}pt',
                              style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 1)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 320,
                        child: ClipRRect(
                          child: Material(
                            color: Colors.transparent,
                            child: EmojiPickerModal(
                              title: 'Emoji Picker',
                              onEmojiSelected: (String e) => setSt(() => selectedEmoji = e),
                              userPredefined: false,
                              showPanelHeader: false,
                              onCloseRequested: () {},
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
          ),
        ],
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
    // Wait for the selection border to be removed from the screen before
    // capturing, so it doesn't appear in the screenshot.
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (start == null || current == null) return;
    final Rect localRect = Rect.fromPoints(start, current);
    if (localRect.width < 2 || localRect.height < 2) return;

    // Widget-local → screen coords. Our window is at virtualOrigin.
    final Rect screenRect = Rect.fromLTWH(
      localRect.left + widget.virtualOrigin.dx,
      localRect.top + widget.virtualOrigin.dy,
      localRect.width,
      localRect.height,
    );

    // 1. Capture raw PNG bytes (always needed).
    Uint8List? pngBytes;
    // Use the existing GDI clipboard capture path to get raw bytes.
    {
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
      pngBytes = Uint8List.fromList(img.encodePng(image));
    }

    // 2. Apply FancyShot profile if selected.
    final String? presetName = ctrl.captureSelectedFancyShotProfile;
    if ((presetName ?? '').isNotEmpty) {
      try {
        final FancyShotProfile? preset = FancyShot.profileByName(presetName!);
        if (preset != null) {
          pngBytes = await FancyShot.renderPresetCapture(
            captureBytes: pngBytes,
            profile: preset,
          );
        }
      } catch (_) {
        // fallback to raw bytes
      }
    }

    // 3. Always save to file (so Copy File / Upload have something to work with).
    String? savedFilePath;
    try {
      if (pngBytes != null) savedFilePath = await ScreenUtils.saveScreenshot(pngBytes);
    } catch (_) {
      savedFilePath = null;
    }

    // 4. Perform the chosen post-capture action.
    if (ctrl.captureAndClose) {
      windowManager.minimize();
      await ScreenUtils.playCameraSound();
    }
    switch (ctrl.capturePostAction) {
      case ScreenDrawCaptureAction.copyImage:
        if (pngBytes != null) await ScreenDrawCapture._copyPngToClipboard(pngBytes);
      case ScreenDrawCaptureAction.copyFile:
        if (savedFilePath != null) {
          ClipboardExtension.copyFile(savedFilePath);
        } else {
          // Fallback: copy image bytes
          if (pngBytes != null) await ScreenDrawCapture._copyPngToClipboard(pngBytes);
        }
      case ScreenDrawCaptureAction.upload:
        final ScreenCaptureUploadHost? host = ctrl.captureUploadHost;
        if (host != null && savedFilePath != null) {
          await UploadUtils.runUploadHost(host, savedFilePath, onSuccess: (String url) async {
            if (host.uploadType != UploadHostType.custom) {
              ClipboardExtended.copy(url);
              // await Process.start('cmd.exe', <String>['/c', 'start', '', url], mode: ProcessStartMode.detached);
            }
          }, onError: (_) {});
        } else {
          if (pngBytes != null) await ScreenDrawCapture._copyPngToClipboard(pngBytes);
        }
      case ScreenDrawCaptureAction.copyTextOcr:
        try {
          final String text = await getTextOCR(
            screenRect.left.round(),
            screenRect.top.round(),
            screenRect.width.round().clamp(1, 1000000),
            screenRect.height.round().clamp(1, 1000000),
            ctrl.ocrCaptureType.index,
          );
          await ClipboardExtended.copy(text);
        } catch (_) {
          if (pngBytes != null) await ScreenDrawCapture._copyPngToClipboard(pngBytes);
        }
    }

    final bool shouldClose = ctrl.captureAndClose;
    // captureAndClose is a persistent preference — do not reset it here.

    if (shouldClose) {
      await windowManager.close();
      return;
    } else {
      await WindowManager.instance.focus();
      ScreenUtils.playCameraSound();
    }
  }
}

// ---------------------------------------------------------------------------
// Crosshair overlay
// ---------------------------------------------------------------------------

class _CrosshairLayer extends StatefulWidget {
  final void Function(Offset)? onHover;

  /// Widget-local rect of the toolbar — cursor shows as arrow inside it.
  final Rect toolbarRect;
  final bool justTheMouse;
  const _CrosshairLayer({
    this.onHover,
    required this.toolbarRect,
    required this.justTheMouse,
  });
  @override
  State<_CrosshairLayer> createState() => _CrosshairLayerState();
}

class _CrosshairLayerState extends State<_CrosshairLayer> {
  Offset _cursor = Offset.zero;
  bool _overToolbar = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: _overToolbar ? SystemMouseCursors.basic : SystemMouseCursors.precise,
      hitTestBehavior: HitTestBehavior.translucent,
      onHover: (PointerHoverEvent e) {
        final bool over = widget.toolbarRect.contains(e.localPosition);
        if (over != _overToolbar) setState(() => _overToolbar = over);
        setState(() => _cursor = e.localPosition);
        widget.onHover?.call(e.localPosition);
      },
      child: IgnorePointer(
        ignoring: true,
        child: widget.justTheMouse
            ? const SizedBox.shrink()
            : CustomPaint(
                painter: _CrosshairPainter(_overToolbar ? null : _cursor),
              ),
      ),
    );
  }
}

class _CrosshairPainter extends CustomPainter {
  /// Null means: don't draw crosshair (cursor is over toolbar).
  final Offset? pos;
  _CrosshairPainter(this.pos);

  @override
  void paint(Canvas canvas, Size size) {
    if (pos == null) return;
    final ui.Paint paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1;
    canvas.drawLine(Offset(0, pos!.dy), Offset(size.width, pos!.dy), paint);
    canvas.drawLine(Offset(pos!.dx, 0), Offset(pos!.dx, size.height), paint);

    // Coordinate label — flip near edges
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '${pos!.dx.round()}, ${pos!.dy.round()}',
        style: TextStyle(
          color: Colors.white70,
          fontSize: 14,
          backgroundColor: Colors.black.withValues(alpha: 0.95),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    const double pad = 8;
    final double lx = (pos!.dx + pad + tp.width > size.width - 4) ? pos!.dx - pad - tp.width : pos!.dx + pad;
    final double ly = (pos!.dy + pad + tp.height > size.height - 4) ? pos!.dy - pad - tp.height : pos!.dy + pad;
    tp.paint(canvas, Offset(lx, ly));
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
// Committed image-backed shape widget (blur/pixelate/smartDelete/spotlight/imageDraw/imageFile)
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

    if (widget.shape.tool == DrawTool.imageFile) {
      return Positioned.fromRect(
        rect: rect,
        child: IgnorePointer(
          child: ClipRect(
            child: Image.memory(
              widget.shape.imageBytes!,
              fit: BoxFit.fill,
              gaplessPlayback: true,
              filterQuality: FilterQuality.high,
            ),
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
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12, tileMode: TileMode.mirror),
    );
    canvas.drawImageRect(image!, src, bounds, Paint()..filterQuality = FilterQuality.high);
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
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12, tileMode: TileMode.mirror),
      );
      canvas.drawImageRect(image!, src, bounds, Paint()..filterQuality = FilterQuality.high);
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
          fontSize: Design.baseFontSize + 2,
          backgroundColor: Colors.black.withValues(alpha: 0.85),
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    // Paint the label above the selection rect so it's never captured in the screenshot.
    final double labelX = rect.left + 6;
    final double labelY = rect.top - label.height - 6;
    label.paint(canvas, Offset(labelX, labelY < 0 ? rect.bottom + 4 : labelY));
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
  final Rect monitorRect;
  const AnnotationToolbar({super.key, required this.controller, required this.monitorRect});

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
              _ScreenCaptureBtnWithPopup(ctrl: controller),
              const Divider(color: Colors.white24, height: 10),
              _ToolBtn(Icons.edit, DrawTool.pen, controller, 'Pen (P)'),
              _ToolBtn(Icons.highlight, DrawTool.highlight, controller, 'Highlight (H)'),
              _ToolBtn(Icons.remove, DrawTool.line, controller, 'Line (L)'),
              _ToolBtnWithFillPopup(
                icon: Icons.crop_square,
                tool: DrawTool.rect,
                ctrl: controller,
                tooltip: 'Rect (R)',
              ),
              _ToolBtnWithFillPopup(
                icon: Icons.circle_outlined,
                tool: DrawTool.ellipse,
                ctrl: controller,
                tooltip: 'Ellipse (E)',
              ),
              _ToolBtn(Icons.arrow_forward, DrawTool.arrow, controller, 'Arrow (A)'),
              const Divider(color: Colors.white24, height: 10),
              _ToolBtn(Icons.text_fields, DrawTool.text, controller, 'Text (T)'),
              _ToolBtn(Icons.emoji_emotions_outlined, DrawTool.emoji, controller, 'Emoji (J)'),
              _ToolBtnWithPopup(
                icon: Icons.format_list_numbered,
                tool: DrawTool.stepCounter,
                ctrl: controller,
                tooltip: 'Step Counter (N)',
                popupActions: <_PopupAction>[
                  _PopupAction(
                    icon: Icons.exposure_zero,
                    label: 'Reset Steps',
                    onTap: () => controller.resetStepCounter(),
                  ),
                ],
              ),
              _ToolBtn(Icons.chat_bubble_outline, DrawTool.infoBalloon, controller, 'Info Balloon (I)'),
              _LoadImageButton(controller: controller),
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
              _ToolBtn(Icons.space_bar, DrawTool.measureDistance, controller, 'Measure Distance (V)'),
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
              // const Divider(color: Colors.white24, height: 10),
              _InfoBtn(controller, monitorRect),
              const Divider(color: Colors.white24, height: 10),
              const _CloseBtn(),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Close button ──────────────────────────────────────────────────────────────
class _CloseBtn extends StatelessWidget {
  const _CloseBtn();

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: 'Close Screen Draw',
      preferBelow: false,
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: () => windowManager.close(),
        child: Container(
          width: 36,
          height: 36,
          margin: const EdgeInsets.symmetric(vertical: 2),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: Colors.red.withValues(alpha: 0.18),
          ),
          child: const Icon(Icons.close, color: Colors.redAccent, size: 18),
        ),
      ),
    );
  }
}

// ── Info / hotkeys button ─────────────────────────────────────────────────────
class _InfoBtn extends StatelessWidget {
  final AnnotationController ctrl;
  final Rect monitorRect;
  const _InfoBtn(this.ctrl, this.monitorRect);

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: 'Hotkeys & Tips',
      child: IconButton(
        icon: const Icon(Icons.info_outline, size: 18),
        color: Colors.white70,
        onPressed: () => _showHotkeysModal(context),
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
      ),
    );
  }

  void _showHotkeysModal(BuildContext context) {
    const double dw = 520;
    const double dh = 640;
    final Offset dOff = monitorRect.isEmpty
        ? Offset.zero
        : Offset(
            monitorRect.left + (monitorRect.width - dw) / 2,
            monitorRect.top + (monitorRect.height - dh) / 2,
          );
    showDialog<void>(
      context: context,
      barrierColor: Colors.black54,
      builder: (_) => Stack(
        children: <Widget>[
          Positioned(
            left: dOff.dx,
            top: dOff.dy,
            width: dw,
            child: const _HotkeysModal(),
          ),
        ],
      ),
    );
  }
}

class _HotkeysModal extends StatelessWidget {
  const _HotkeysModal();

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 520,
        constraints: const BoxConstraints(maxHeight: 640),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white24),
          boxShadow: const <BoxShadow>[
            BoxShadow(color: Colors.black54, blurRadius: 32, offset: Offset(0, 8)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            // Header
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: Colors.white12)),
              ),
              child: Row(
                children: <Widget>[
                  const Icon(Icons.keyboard, color: Colors.white70, size: 20),
                  const SizedBox(width: 10),
                  const Text('Hotkeys & Tips',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                  const Spacer(),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, color: Colors.white54, size: 20),
                  ),
                ],
              ),
            ),
            // Scrollable body
            const Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    _HkSection('Tools', <_HkEntry>[
                      _HkEntry('S', 'Select / move shapes'),
                      _HkEntry('C', 'Screen capture'),
                      _HkEntry('P', 'Pen (freehand draw)'),
                      _HkEntry('H', 'Highlight'),
                      _HkEntry('L', 'Line'),
                      _HkEntry('R', 'Rectangle'),
                      _HkEntry('E', 'Ellipse'),
                      _HkEntry('A', 'Arrow'),
                      _HkEntry('T', 'Text'),
                      _HkEntry('J', 'Emoji'),
                      _HkEntry('N', 'Step counter'),
                      _HkEntry('I', 'Info balloon'),
                      _HkEntry('Z', 'Magnifier'),
                      _HkEntry('F', 'Blur region'),
                      _HkEntry('X', 'Pixelate region'),
                      _HkEntry('D', 'Smart delete'),
                      _HkEntry('O', 'Spotlight'),
                      _HkEntry('W', 'Image draw'),
                      _HkEntry('M', 'Ruler'),
                      _HkEntry('B', 'Size box'),
                      _HkEntry('U', 'Guide'),
                      _HkEntry('V', 'Measure distance'),
                    ]),
                    SizedBox(height: 16),
                    _HkSection('Actions', <_HkEntry>[
                      _HkEntry('Ctrl + Z', 'Undo'),
                      _HkEntry('Ctrl + Y', 'Redo'),
                      _HkEntry('Ctrl + G', 'Toggle grid'),
                      _HkEntry('Ctrl + C', 'Toggle crosshair'),
                      _HkEntry('Esc', 'Exit drawing mode / deselect'),
                      _HkEntry('Space', 'Toggle drawing mode on/off'),
                    ]),
                    SizedBox(height: 16),
                    _HkSection('Mouse interactions', <_HkEntry>[
                      _HkEntry('Right-click shape', 'Delete the shape'),
                      _HkEntry('Scroll on shape', 'Resize / scale the shape'),
                      _HkEntry('Drag shape', 'Move the shape (Select tool)'),
                    ]),
                    SizedBox(height: 16),
                    _HkSection('Tips', <_HkEntry>[
                      _HkEntry('Text color', 'Always uses the active toolbar color'),
                      _HkEntry('Text background', 'Choose color in the text dialog'),
                      _HkEntry('Balloon body', 'Choose color in the balloon dialog'),
                      _HkEntry('Measure distance',
                          'Hover over an area — measures same-color pixel runs horizontally & vertically'),
                    ]),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HkSection extends StatelessWidget {
  final String title;
  final List<_HkEntry> entries;
  const _HkSection(this.title, this.entries);

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(title,
            style: TextStyle(
                color: Colors.white60,
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1)),
        const SizedBox(height: 8),
        ...entries.map((_HkEntry e) => Padding(
              padding: const EdgeInsets.only(bottom: 5),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Container(
                    constraints: const BoxConstraints(minWidth: 130),
                    child: _KeyChip(e.key),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(e.desc, style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 2.5)),
                  ),
                ],
              ),
            )),
      ],
    );
  }
}

class _HkEntry {
  final String key;
  final String desc;
  const _HkEntry(this.key, this.desc);
}

class _KeyChip extends StatelessWidget {
  final String label;
  const _KeyChip(this.label);

  @override
  Widget build(BuildContext context) {
    // Split on "+" but keep multi-word keys whole
    final List<String> parts = label.split(' + ');
    if (parts.length == 1) {
      return _chip(label);
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        for (int i = 0; i < parts.length; i++) ...<Widget>[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 3),
              child: Text('+', style: TextStyle(color: Colors.white38, fontSize: Design.baseFontSize + 1)),
            ),
          _chip(parts[i]),
        ],
      ],
    );
  }

  Widget _chip(String text) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: const Color(0xFF2D2D4E),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white24),
        ),
        child: Text(text,
            style: TextStyle(
                color: Colors.white,
                fontSize: Design.baseFontSize + 1.5,
                fontWeight: FontWeight.w600,
                fontFamily: 'monospace')),
      );
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
  OverlayEntry? _eyedropperOverlayEntry;
  final LayerLink _layerLink = LayerLink();
  final LayerLink _pickerLayerLink = LayerLink();
  bool _pickerOpen = false;

  // ── Eyedropper (screen colour picker) ─────────────────────────────────────
  bool _eyedropperActive = false;
  Timer? _eyedropperTimer;
  Offset _eyedropperCursor = Offset.zero;
  Color _eyedropperPreviewColor = Colors.transparent;

  /// Sample the pixel at [x, y] in screen coordinates using Win32 GDI.
  Color _samplePixel(int x, int y) {
    final int hdc = GetDC(NULL);
    final int colorRef = GetPixel(hdc, x, y);
    ReleaseDC(NULL, hdc);
    if (colorRef == -1) return Colors.black; // CLR_INVALID
    final int r = colorRef & 0xFF;
    final int g = (colorRef >> 8) & 0xFF;
    final int b = (colorRef >> 16) & 0xFF;
    return Color.fromARGB(255, r, g, b);
  }

  void _startEyedropper() {
    // Close any open overlays first
    _closePicker();
    _overlayEntry?.remove();
    _overlayEntry = null;

    _eyedropperActive = true;

    // Poll cursor position every 16 ms (~60 fps) to show live preview
    _eyedropperTimer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      final Pointer<POINT> pt = calloc<POINT>();
      GetCursorPos(pt);
      final int sx = pt.ref.x;
      final int sy = pt.ref.y;
      calloc.free(pt);

      final Color sampled = _samplePixel(sx, sy);
      if (mounted) {
        setState(() {
          _eyedropperCursor = Offset(sx.toDouble(), sy.toDouble());
          _eyedropperPreviewColor = sampled;
        });
        _eyedropperOverlayEntry?.markNeedsBuild();
      }
    });

    _showEyedropperOverlay();
  }

  void _showEyedropperOverlay() {
    _eyedropperOverlayEntry = OverlayEntry(
      builder: (_) {
        // Full-screen transparent listener that captures the next click
        return Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTapDown: (TapDownDetails details) {
              // Sample the pixel at the exact tap position
              final int sx = _eyedropperCursor.dx.round();
              final int sy = _eyedropperCursor.dy.round();
              final Color picked = _samplePixel(sx, sy);
              widget.ctrl.setColor(picked);
              _stopEyedropper();
            },
            child: MouseRegion(
              cursor: SystemMouseCursors.precise,
              child: Material(
                type: MaterialType.transparency,
                child: Stack(
                  children: <Widget>[
                    // Preview magnifier bubble near cursor
                    AnimatedPositioned(
                      duration: Duration.zero,
                      left: (_eyedropperCursor.dx + 18).clamp(0, double.infinity),
                      top: (_eyedropperCursor.dy - 60).clamp(0, double.infinity),
                      child: IgnorePointer(
                        child: Container(
                          width: 85,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.88),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white38),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.4),
                                blurRadius: 8,
                              ),
                            ],
                          ),
                          padding: const EdgeInsets.all(6),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: <Widget>[
                              Row(
                                children: <Widget>[
                                  Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      color: _eyedropperPreviewColor,
                                      borderRadius: BorderRadius.circular(3),
                                      border: Border.all(color: Colors.white38),
                                    ),
                                  ),
                                  const SizedBox(width: 5),
                                  Expanded(
                                    child: Text(
                                      '#'
                                      '${_eyedropperPreviewColor.red8bit.toRadixString(16).padLeft(2, '0').toUpperCase()}'
                                      '${_eyedropperPreviewColor.green8bit.toRadixString(16).padLeft(2, '0').toUpperCase()}'
                                      '${_eyedropperPreviewColor.blue8bit.toRadixString(16).padLeft(2, '0').toUpperCase()}',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: Design.baseFontSize,
                                        fontFamily: 'monospace',
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 2),
                              const Text(
                                'Click to pick',
                                style: TextStyle(color: Colors.white54, fontSize: 9),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_eyedropperOverlayEntry!);
  }

  void _stopEyedropper() {
    _eyedropperTimer?.cancel();
    _eyedropperTimer = null;
    _eyedropperOverlayEntry?.remove();
    _eyedropperOverlayEntry = null;
    if (mounted) setState(() => _eyedropperActive = false);
  }

  void _show() {
    _closeTimer?.cancel();
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: 340,
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

                    const SizedBox(width: 5),

                    // ── Screen eyedropper ──────────────────────────────────
                    GestureDetector(
                      onTap: _startEyedropper,
                      child: Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _eyedropperActive ? Colors.white24 : Colors.transparent,
                          border: Border.all(
                            color: _eyedropperActive ? Colors.white : Colors.white38,
                            width: _eyedropperActive ? 2.0 : 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.colorize_outlined,
                          size: 14,
                          color: _eyedropperActive ? Colors.white : Colors.white70,
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
    _stopEyedropper();
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

// ---------------------------------------------------------------------------
// Popup-action descriptor — used by _ToolBtnWithPopup
// ---------------------------------------------------------------------------

/// A single extra action shown in the hover popup of a tool button.
class _PopupAction {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _PopupAction({required this.icon, required this.label, required this.onTap});
}

// ---------------------------------------------------------------------------
// Screen-Capture button: full hover popup with action, upload, FancyShot
// ---------------------------------------------------------------------------

/// The Screen Capture toolbar button.  On hover it shows a rich popup with:
///   • Four post-capture actions (Copy Image, Copy File, Capture & Close,
///     upload hosts)
///   • FancyShot profile selector (radio-style, "None" + all saved profiles)
class _ScreenCaptureBtnWithPopup extends StatefulWidget {
  final AnnotationController ctrl;
  const _ScreenCaptureBtnWithPopup({required this.ctrl});

  @override
  State<_ScreenCaptureBtnWithPopup> createState() => _ScreenCaptureBtnWithPopupState();
}

class _ScreenCaptureBtnWithPopupState extends State<_ScreenCaptureBtnWithPopup> {
  Timer? _closeTimer;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  void _show() {
    _closeTimer?.cancel();
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(builder: (_) => _buildOverlay());
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _scheduleHide() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 260), () {
      _overlayEntry?.remove();
      _overlayEntry = null;
    });
  }

  void _refresh() => _overlayEntry?.markNeedsBuild();

  final List<ScreenCaptureUploadHost> uploadHosts = FancyShot.loadUploadHosts();
  final List<FancyShotProfile> profiles = FancyShot.loadProfiles();
  Widget _buildOverlay() {
    final AnnotationController c = widget.ctrl;

    return Positioned(
      width: 260,
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
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.90),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.white24),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 16, offset: const Offset(0, 4)),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  // ── Section: After Capture ──────────────────────────────
                  _sectionLabel('AFTER CAPTURE'),
                  _actionRow(
                    icon: Icons.content_copy,
                    label: 'Copy Image',
                    selected: c.capturePostAction == ScreenDrawCaptureAction.copyImage && c.captureUploadHost == null,
                    onTap: () {
                      c.capturePostAction = ScreenDrawCaptureAction.copyImage;
                      Settings.setInt("capturePostAction", c.capturePostAction.index);
                      c.captureUploadHost = null;
                      Settings.setString("captureUploadHost", c.captureUploadHost?.id);
                      c.setTool(DrawTool.screenCapture);
                      _refresh();
                    },
                  ),
                  _actionRow(
                    icon: Icons.file_copy_outlined,
                    label: 'Copy File',
                    selected: c.capturePostAction == ScreenDrawCaptureAction.copyFile,
                    onTap: () {
                      c.capturePostAction = ScreenDrawCaptureAction.copyFile;
                      Settings.setInt("capturePostAction", c.capturePostAction.index);
                      c.captureUploadHost = null;
                      Settings.setString("captureUploadHost", c.captureUploadHost?.id);
                      c.setTool(DrawTool.screenCapture);
                      _refresh();
                    },
                  ),
                  _actionRow(
                    icon: Icons.text_snippet_outlined,
                    label: 'Copy OCR Text',
                    selected: c.capturePostAction == ScreenDrawCaptureAction.copyTextOcr,
                    onTap: () {
                      c.capturePostAction = ScreenDrawCaptureAction.copyTextOcr;
                      Settings.setInt("capturePostAction", c.capturePostAction.index);
                      c.captureUploadHost = null;
                      Settings.setString("captureUploadHost", c.captureUploadHost?.id);
                      c.setTool(DrawTool.screenCapture);
                      _refresh();
                    },
                  ),
                  if (c.capturePostAction == ScreenDrawCaptureAction.copyTextOcr) ...<Widget>[
                    const SizedBox(height: 4),
                    _sectionLabel('OCR CAPTURE'),
                    _actionRow(
                      icon: Icons.filter_none,
                      label: 'BitBlt',
                      selected: c.ocrCaptureType == ScreenDrawOcrCaptureType.bitBlt,
                      onTap: () {
                        c.ocrCaptureType = ScreenDrawOcrCaptureType.bitBlt;
                        Settings.setInt("ocrCaptureType", c.ocrCaptureType.index);
                        c.setTool(DrawTool.screenCapture);
                        _refresh();
                      },
                    ),
                    _actionRow(
                      icon: Icons.screenshot_monitor_outlined,
                      label: 'DirectX',
                      selected: c.ocrCaptureType == ScreenDrawOcrCaptureType.directX,
                      onTap: () {
                        c.ocrCaptureType = ScreenDrawOcrCaptureType.directX;
                        Settings.setInt("ocrCaptureType", c.ocrCaptureType.index);
                        c.setTool(DrawTool.screenCapture);
                        _refresh();
                      },
                    ),
                  ],
                  const SizedBox(height: 4),
                  _checkboxRow(
                    icon: Icons.close,
                    label: 'Close after Capture',
                    checked: c.captureAndClose,
                    onTap: () {
                      c.captureAndClose = !c.captureAndClose;
                      Settings.setBool('captureAndClose', c.captureAndClose);
                      c.setTool(c.activeTool); // triggers notifyListeners
                      _refresh();
                    },
                  ),

                  // ── Section: Upload Hosts ───────────────────────────────
                  if (uploadHosts.isNotEmpty) ...<Widget>[
                    const SizedBox(height: 6),
                    _sectionLabel('UPLOAD TO'),
                    ...uploadHosts.map((ScreenCaptureUploadHost host) => _actionRow(
                          icon: host.isBuiltIn ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
                          label: host.name,
                          selected: c.capturePostAction == ScreenDrawCaptureAction.upload &&
                              c.captureUploadHost?.id == host.id,
                          onTap: () {
                            c.capturePostAction = ScreenDrawCaptureAction.upload;
                            c.captureUploadHost = host;
                            Settings.setInt("capturePostAction", c.capturePostAction.index);
                            Settings.setString("captureUploadHost", c.captureUploadHost?.id);
                            c.setTool(DrawTool.screenCapture);
                            _refresh();
                          },
                        )),
                  ],

                  // ── Section: FancyShot Profile ──────────────────────────
                  const SizedBox(height: 6),
                  _sectionLabel('FANCYSHOT PROFILE'),
                  _profileRow(
                    label: 'None',
                    selected: (c.captureSelectedFancyShotProfile ?? '').isEmpty,
                    onTap: () {
                      c.captureSelectedFancyShotProfile = null;
                      Settings.setString("captureSelectedFancyShotProfile", null);
                      _refresh();
                    },
                  ),
                  ...profiles.map((FancyShotProfile p) => _profileRow(
                        label: p.name,
                        selected: c.captureSelectedFancyShotProfile == p.name,
                        onTap: () {
                          c.captureSelectedFancyShotProfile = p.name;
                          Settings.setString("captureSelectedFancyShotProfile", c.captureSelectedFancyShotProfile);
                          _refresh();
                        },
                      )),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _sectionLabel(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 2, 8, 4),
        child: Text(
          text,
          style: const TextStyle(
            color: Colors.white38,
            fontSize: 9,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
      );

  Widget _actionRow({
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        onTap();
        _scheduleHide();
      },
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: selected ? Colors.white.withValues(alpha: 0.12) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 14, color: selected ? Colors.yellowAccent : Colors.white60),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white70,
                  fontSize: Design.baseFontSize + 2,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (selected) const Icon(Icons.check, size: 12, color: Colors.yellowAccent),
          ],
        ),
      ),
    );
  }

  Widget _checkboxRow({
    required IconData icon,
    required String label,
    required bool checked,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 120),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: checked ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: checked ? Colors.yellowAccent.withValues(alpha: 0.35) : Colors.white12,
            width: 1,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              checked ? Icons.check_box : Icons.check_box_outline_blank,
              size: 14,
              color: checked ? Colors.yellowAccent : Colors.white38,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: checked ? Colors.white : Colors.white60,
                  fontSize: Design.baseFontSize + 2,
                  fontWeight: checked ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _profileRow({required String label, required bool selected, required VoidCallback onTap}) {
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: () {
        onTap();
        // Don't auto-hide — user may want to adjust other settings too.
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          children: <Widget>[
            Icon(
              selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              size: 13,
              color: selected ? Colors.yellowAccent : Colors.white38,
            ),
            const SizedBox(width: 7),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  color: selected ? Colors.white : Colors.white60,
                  fontSize: Design.baseFontSize + 2,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
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
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _scheduleHide(),
        child: _ToolBtn(Icons.screenshot_monitor_rounded, DrawTool.screenCapture, widget.ctrl, 'Screen Capture (C)'),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tool button with hover popup for extra actions
// ---------------------------------------------------------------------------

/// Wraps a normal [_ToolBtn] and, on hover, shows a compact panel to the
/// right containing one or more [_PopupAction] buttons.
///
/// Pattern is identical to [_ColorPopupBtn] / [_WidthPopupBtn] — uses
/// [CompositedTransformTarget] + [OverlayEntry] so the popup floats above
/// the toolbar's scroll container without clipping.
///
/// To add popup actions to any future tool button, simply swap it for a
/// [_ToolBtnWithPopup] and pass the desired [popupActions] list.
class _ToolBtnWithPopup extends StatefulWidget {
  final IconData icon;
  final DrawTool tool;
  final AnnotationController ctrl;
  final String tooltip;
  final List<_PopupAction> popupActions;

  const _ToolBtnWithPopup({
    required this.icon,
    required this.tool,
    required this.ctrl,
    required this.tooltip,
    required this.popupActions,
  });

  @override
  State<_ToolBtnWithPopup> createState() => _ToolBtnWithPopupState();
}

class _ToolBtnWithPopupState extends State<_ToolBtnWithPopup> {
  Timer? _closeTimer;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  void _show() {
    _closeTimer?.cancel();
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: 180,
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
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: widget.popupActions.map((_PopupAction action) {
                    return InkWell(
                      borderRadius: BorderRadius.circular(5),
                      onTap: () {
                        action.onTap();
                        _scheduleHide();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Icon(action.icon, size: 15, color: Colors.white70),
                            const SizedBox(width: 7),
                            Flexible(
                              child: Text(
                                action.label,
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: Design.baseFontSize + 2,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
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
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _scheduleHide(),
        child: _ToolBtn(widget.icon, widget.tool, widget.ctrl, widget.tooltip),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tool button with Fill sub-option (rect / ellipse)
// ---------------------------------------------------------------------------

/// Like [_ToolBtnWithPopup] but shows a persistent "Fill" checkbox that
/// toggles [AnnotationController.shapeFilled].  The popup stays open while
/// the mouse is inside so the user can tick/untick without re-hovering.
class _ToolBtnWithFillPopup extends StatefulWidget {
  final IconData icon;
  final DrawTool tool;
  final AnnotationController ctrl;
  final String tooltip;

  const _ToolBtnWithFillPopup({
    required this.icon,
    required this.tool,
    required this.ctrl,
    required this.tooltip,
  });

  @override
  State<_ToolBtnWithFillPopup> createState() => _ToolBtnWithFillPopupState();
}

class _ToolBtnWithFillPopupState extends State<_ToolBtnWithFillPopup> {
  Timer? _closeTimer;
  OverlayEntry? _overlayEntry;
  final LayerLink _layerLink = LayerLink();

  void _show() {
    _closeTimer?.cancel();
    if (_overlayEntry != null) return;

    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: 140,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: const Offset(40, -4),
          child: MouseRegion(
            onEnter: (_) => _show(),
            onExit: (_) => _scheduleHide(),
            child: Material(
              color: Colors.transparent,
              child: ListenableBuilder(
                listenable: widget.ctrl,
                builder: (_, __) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(5),
                    onTap: () {
                      widget.ctrl.toggleShapeFilled();
                      _overlayEntry?.markNeedsBuild();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 120),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                      decoration: BoxDecoration(
                        color: widget.ctrl.shapeFilled ? Colors.white.withValues(alpha: 0.08) : Colors.transparent,
                        borderRadius: BorderRadius.circular(5),
                        border: Border.all(
                          color: widget.ctrl.shapeFilled ? Colors.yellowAccent.withValues(alpha: 0.35) : Colors.white12,
                          width: 1,
                        ),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(
                            widget.ctrl.shapeFilled ? Icons.check_box : Icons.check_box_outline_blank,
                            size: 14,
                            color: widget.ctrl.shapeFilled ? Colors.yellowAccent : Colors.white38,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Fill',
                            style: TextStyle(
                              color: widget.ctrl.shapeFilled ? Colors.white : Colors.white60,
                              fontSize: Design.baseFontSize + 2,
                              fontWeight: widget.ctrl.shapeFilled ? FontWeight.w600 : FontWeight.w400,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
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
      child: MouseRegion(
        onEnter: (_) => _show(),
        onExit: (_) => _scheduleHide(),
        child: _ToolBtn(widget.icon, widget.tool, widget.ctrl, widget.tooltip),
      ),
    );
  }
}

class _LoadImageButton extends StatelessWidget {
  final AnnotationController controller;

  const _LoadImageButton({required this.controller});

  Future<void> _pick(BuildContext context) async {
    controller.toggleDrawingMode(activated: false);
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'Image Files': '*.jpg;*.jpeg;*.png;*.webp;*.jfif;*.bmp;*.gif;*.tiff',
        'All Files': '*.*',
      }
      ..defaultFilterIndex = 0
      ..title = 'Select Image';
    final File? result = picker.getFile();
    if (result == null || !result.existsSync()) return;

    final Uint8List bytes = result.readAsBytesSync();

    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();

    final ui.Image image = frame.image;

    controller.addLoadedImage(
      bytes,
      image.width,
      image.height,
    );
    controller.toggleDrawingMode(activated: true);
  }

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: 'Load Image (K)',
      child: IconButton(
        icon: const Icon(Icons.image_outlined, size: 18),
        color: Colors.white70,
        onPressed: () => _pick(context),
        padding: const EdgeInsets.all(5),
        constraints: const BoxConstraints(),
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
            padding: const EdgeInsets.all(5),
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
        padding: const EdgeInsets.all(5),
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
      _drawShape(canvas, s.tool, start, end, s.points, selPaint, s.color, s.strokeWidth, s.filled);
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
      case DrawTool.measureDistance:
        return; // measure distance is a live overlay, no committed shapes
      default:
        break;
    }

    _drawShape(canvas, s.tool, start, end, s.points, paint, s.color, s.strokeWidth, s.filled);

    // Measurement labels for ruler / sizebox / line
    if (s.tool == DrawTool.ruler || s.tool == DrawTool.sizebox) {
      _paintMeasurement(canvas, s.tool, start, end, s.color);
    }
  }

  // ── New tool painters ────────────────────────────────────────────────────

  void _drawText(Canvas canvas, DrawShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    final double fs = s.fontSize ?? (s.strokeWidth * 8 + 12);
    // Text color = stroke color (the main toolbar color)
    final Color tc = s.color;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: TextStyle(
          color: tc,
          fontSize: fs,
          fontWeight: FontWeight.bold,
          fontFamily: s.fontFamily,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (s.textBackground) {
      // Background color = textBgColor chosen in dialog (defaults to near-black)
      final Color bgColor = s.textBgColor ?? Colors.black;
      final Rect bg = Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4);
      canvas.drawRRect(
          RRect.fromRectAndRadius(bg, const Radius.circular(4)), Paint()..color = bgColor.withValues(alpha: 0.82));
    }
    tp.paint(canvas, pos);
  }

  void _drawInfoBalloon(Canvas canvas, DrawShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    const double padding = 10.0;
    const double tailH = 14.0;
    const double radius = 8.0;
    final double fs = s.fontSize ?? (s.strokeWidth * 6 + 12);
    // Text color = stroke color (main toolbar color), balloon body = textBgColor or s.color
    final Color tc = s.color;
    final Color balloonColor = s.textBgColor ?? s.color;
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

    canvas.drawPath(path, Paint()..color = balloonColor.withValues(alpha: 0.9));
    canvas.drawPath(
        path,
        Paint()
          ..color = Colors.white24
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);
    tp.paint(canvas, Offset(bubble.left + padding, bubble.top + padding));
  }

  void _drawStepCounter(Canvas canvas, DrawShape s, Offset pos) {
    final double r = (s.fontSize ?? 28.0) / 2;
    final int num = s.stepNumber ?? 1;
    canvas.drawCircle(pos, r, Paint()..color = s.color);
    canvas.drawCircle(
        pos,
        r,
        Paint()
          ..color = Colors.black38
          ..style = PaintingStyle.stroke
          ..strokeWidth = (r / 10).clamp(1.0, 4.0));
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: '$num',
        style: TextStyle(color: Colors.white, fontSize: r * 0.9, fontWeight: FontWeight.bold),
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

  void _drawShape(Canvas canvas, DrawTool tool, Offset start, Offset end, List<Offset> points, Paint paint, Color color,
      double sw, bool filled) {
    switch (tool) {
      case DrawTool.select:
        break;
      case DrawTool.pen:
        if (points.length < 2) return;
        {
          // Round caps/joins for a natural brush feel
          final Paint penPaint = Paint()
            ..color = paint.color
            ..strokeWidth = paint.strokeWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..strokeJoin = StrokeJoin.round;

          final ui.Path penPath = Path()..moveTo(points.first.dx, points.first.dy);
          if (points.length == 2) {
            penPath.lineTo(points[1].dx, points[1].dy);
          } else if (points.length == 3) {
            penPath.quadraticBezierTo(points[1].dx, points[1].dy, points[2].dx, points[2].dy);
          } else {
            // Chordal Catmull-Rom → cubic Bézier.
            // tension=0.5 gives a natural curve that passes through every point.
            const double tension = 0.5;
            for (int i = 0; i < points.length - 1; i++) {
              final Offset p0 = points[i == 0 ? 0 : i - 1];
              final Offset p1 = points[i];
              final Offset p2 = points[i + 1];
              final Offset p3 = points[i + 2 < points.length ? i + 2 : i + 1];
              final double cp1x = p1.dx + (p2.dx - p0.dx) * tension / 3.0;
              final double cp1y = p1.dy + (p2.dy - p0.dy) * tension / 3.0;
              final double cp2x = p2.dx - (p3.dx - p1.dx) * tension / 3.0;
              final double cp2y = p2.dy - (p3.dy - p1.dy) * tension / 3.0;
              penPath.cubicTo(cp1x, cp1y, cp2x, cp2y, p2.dx, p2.dy);
            }
          }
          canvas.drawPath(penPath, penPaint);
        }
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
        if (filled) {
          canvas.drawRect(
              Rect.fromPoints(start, end),
              Paint()
                ..color = paint.color
                ..style = PaintingStyle.fill);
        } else {
          canvas.drawRect(Rect.fromPoints(start, end), paint);
        }

      case DrawTool.sizebox:
        canvas.drawRect(Rect.fromPoints(start, end), paint);

      case DrawTool.ellipse:
        if (filled) {
          canvas.drawOval(
              Rect.fromPoints(start, end),
              Paint()
                ..color = paint.color
                ..style = PaintingStyle.fill);
        } else {
          canvas.drawOval(Rect.fromPoints(start, end), paint);
        }

      case DrawTool.arrow:
        _drawArrow(canvas, start, end, paint);

      case DrawTool.ruler:
        _drawRuler(canvas, start, end, paint);

      case DrawTool.guide:
        break; // guides drawn separately

      case DrawTool.measureDistance:
        break; // rendered by the live overlay

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

    final Offset mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);

    if (tool == DrawTool.sizebox) {
      final ui.Rect r = Rect.fromPoints(start, end);
      _drawPillLabel(canvas, '${r.width.round()} px', Offset(r.center.dx, r.top), color,
          anchor: _LabelAnchor.bottomCenter, offsetY: -4);
      _drawPillLabel(canvas, '${r.height.round()} px', Offset(r.right, r.center.dy), color,
          anchor: _LabelAnchor.leftCenter, vertical: true, offsetX: 6);
      _drawPillLabel(canvas, '(${r.left.round()}, ${r.top.round()})', r.topLeft + const Offset(4, 4), color,
          anchor: _LabelAnchor.topLeft);
    } else if (tool == DrawTool.ruler) {
      _drawPillLabel(canvas, '${dist.round()} px', mid, color, anchor: _LabelAnchor.bottomCenter, offsetY: -6);
      if (dist > 40) {
        _drawPillLabel(canvas, '${angleDeg.toStringAsFixed(1)}°', end, color,
            anchor: _LabelAnchor.topLeft, offsetX: 8, offsetY: -8);
      }
    } else {
      _drawPillLabel(canvas, '${dist.round()} px', mid, color, anchor: _LabelAnchor.bottomCenter, offsetY: -6);
    }
  }

  void _drawPillLabel(
    Canvas canvas,
    String text,
    Offset pos,
    Color color, {
    _LabelAnchor anchor = _LabelAnchor.bottomCenter,
    bool vertical = false,
    double offsetX = 0,
    double offsetY = 0,
  }) {
    const double fs = 11.5;
    const double padH = 7.0;
    const double padV = 3.5;
    const double cornerR = 4.0;

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: fs,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.2,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final double w = tp.width + padH * 2;
    final double h = tp.height + padV * 2;

    canvas.save();
    if (vertical) {
      canvas.translate(pos.dx + offsetX, pos.dy + offsetY);
      canvas.rotate(-pi / 2);
      canvas.translate(-w / 2, -h / 2);
    } else {
      double left = pos.dx + offsetX;
      double top = pos.dy + offsetY;
      switch (anchor) {
        case _LabelAnchor.bottomCenter:
          left -= w / 2;
          top -= h;
          break;
        case _LabelAnchor.topLeft:
          break;
        case _LabelAnchor.leftCenter:
          top -= h / 2;
          break;
      }
      canvas.translate(left, top);
    }

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(1, 1, w, h), const Radius.circular(cornerR)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.40)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(cornerR)),
      Paint()..color = color.withValues(alpha: 0.90),
    );
    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(0, 0, w, h), const Radius.circular(cornerR)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    tp.paint(canvas, const Offset(padH, padV));
    canvas.restore();
  }

  void _drawLabel(Canvas canvas, String text, Offset pos, Color color) {
    _drawPillLabel(canvas, text, pos, color.withValues(alpha: 0.85), anchor: _LabelAnchor.topLeft);
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

enum _LabelAnchor { bottomCenter, topLeft, leftCenter }

// ---------------------------------------------------------------------------
// Measure Distance painter
// ---------------------------------------------------------------------------

class _MeasureDistancePainter extends CustomPainter {
  final Offset cursor;
  final Uint8List? snapshotBytes;
  final int? snapshotW;
  final int? snapshotH;
  final Rect? snapshotRect;

  _MeasureDistancePainter({
    required this.cursor,
    required this.snapshotBytes,
    required this.snapshotW,
    required this.snapshotH,
    required this.snapshotRect,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final int cx = cursor.dx.round();
    final int cy = cursor.dy.round();

    // Draw crosshair lines
    final Paint crossPaint = Paint()
      ..color = Colors.cyan.withValues(alpha: 0.6)
      ..strokeWidth = 1.0;
    canvas.drawLine(Offset(0, cursor.dy), Offset(size.width, cursor.dy), crossPaint);
    canvas.drawLine(Offset(cursor.dx, 0), Offset(cursor.dx, size.height), crossPaint);

    // Draw cursor dot
    canvas.drawCircle(cursor, 4, Paint()..color = Colors.cyan);
    canvas.drawCircle(
        cursor,
        4,
        Paint()
          ..color = Colors.black
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5);

    if (snapshotBytes == null || snapshotW == null || snapshotH == null) {
      // No snapshot yet: just show crosshair with "Capturing..." hint
      _drawMeasurePill(canvas, 'Capturing screen...', cursor + const Offset(12, -24), Colors.cyan);
      return;
    }

    final int sw = snapshotW!;
    final int sh = snapshotH!;
    final Uint8List bytes = snapshotBytes!;

    Color pixel(int x, int y) {
      x = x.clamp(0, sw - 1);
      y = y.clamp(0, sh - 1);
      final int base = (y * sw + x) * 4;
      if (base + 3 >= bytes.length) return const Color(0xFF000000);
      return Color.fromARGB(255, bytes[base], bytes[base + 1], bytes[base + 2]);
    }

    bool colorSame(Color a, Color b, int thresh) {
      return (a.red8bit - b.red8bit).abs() < thresh &&
          (a.green8bit - b.green8bit).abs() < thresh &&
          (a.blue8bit - b.blue8bit).abs() < thresh;
    }

    final Color cursorPixel = pixel(cx, cy);
    const int thresh = 18;

    // --- Horizontal measurement ---
    // Find leftmost background edge from cursor going left
    int leftX = cx;
    while (leftX > 0 && colorSame(pixel(leftX - 1, cy), cursorPixel, thresh)) {
      leftX--;
    }
    // Find rightmost background edge from cursor going right
    int rightX = cx;
    while (rightX < sw - 1 && colorSame(pixel(rightX + 1, cy), cursorPixel, thresh)) {
      rightX++;
    }

    // --- Vertical measurement ---
    int topY = cy;
    while (topY > 0 && colorSame(pixel(cx, topY - 1), cursorPixel, thresh)) {
      topY--;
    }
    int bottomY = cy;
    while (bottomY < sh - 1 && colorSame(pixel(cx, bottomY + 1), cursorPixel, thresh)) {
      bottomY++;
    }

    final int hDist = rightX - leftX;
    final int vDist = bottomY - topY;

    // --- Draw horizontal span line ---
    if (hDist > 2) {
      final Paint spanPaint = Paint()
        ..color = Colors.cyanAccent.withValues(alpha: 0.85)
        ..strokeWidth = 2.0;
      final double y = cursor.dy;
      canvas.drawLine(Offset(leftX.toDouble(), y), Offset(rightX.toDouble(), y), spanPaint);
      // End ticks
      _drawTick(canvas, Offset(leftX.toDouble(), y), Axis.vertical, spanPaint);
      _drawTick(canvas, Offset(rightX.toDouble(), y), Axis.vertical, spanPaint);
      // Label above midpoint
      final double midX = (leftX + rightX) / 2.0;
      _drawMeasurePill(canvas, '$hDist px', Offset(midX, y - 6), Colors.cyan, anchorBottom: true);
    }

    // --- Draw vertical span line ---
    if (vDist > 2) {
      final Paint spanPaint = Paint()
        ..color = Colors.greenAccent.withValues(alpha: 0.85)
        ..strokeWidth = 2.0;
      final double x = cursor.dx;
      canvas.drawLine(Offset(x, topY.toDouble()), Offset(x, bottomY.toDouble()), spanPaint);
      _drawTick(canvas, Offset(x, topY.toDouble()), Axis.horizontal, spanPaint);
      _drawTick(canvas, Offset(x, bottomY.toDouble()), Axis.horizontal, spanPaint);
      final double midY = (topY + bottomY) / 2.0;
      _drawMeasurePill(canvas, '$vDist px', Offset(x + 8, midY), Colors.green);
    }

    // --- Info box: show both values and cursor position ---
    final String info = 'H: $hDist px   V: $vDist px   ($cx, $cy)';
    _drawMeasurePill(canvas, info, cursor + const Offset(12, 14), const Color(0xFF222244));
  }

  void _drawTick(Canvas canvas, Offset pos, Axis axis, Paint paint) {
    const double half = 5.0;
    if (axis == Axis.vertical) {
      canvas.drawLine(pos + const Offset(0, -half), pos + const Offset(0, half), paint);
    } else {
      canvas.drawLine(pos + const Offset(-half, 0), pos + const Offset(half, 0), paint);
    }
  }

  void _drawMeasurePill(Canvas canvas, String text, Offset pos, Color bgColor, {bool anchorBottom = false}) {
    const double fs = 11.5;
    const double padH = 7.0;
    const double padV = 3.5;
    const double cornerR = 4.0;

    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(color: Colors.white, fontSize: fs, fontWeight: FontWeight.w600, letterSpacing: 0.2),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final double w = tp.width + padH * 2;
    final double h = tp.height + padV * 2;
    final double left = pos.dx;
    final double top = anchorBottom ? pos.dy - h : pos.dy;

    // Shadow
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left + 1, top + 1, w, h), const Radius.circular(cornerR)),
      Paint()
        ..color = Colors.black.withValues(alpha: 0.45)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3),
    );
    // Background
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(cornerR)),
      Paint()..color = bgColor.withValues(alpha: 0.92),
    );
    // Border
    canvas.drawRRect(
      RRect.fromRectAndRadius(Rect.fromLTWH(left, top, w, h), const Radius.circular(cornerR)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8,
    );
    tp.paint(canvas, Offset(left + padH, top + padV));
  }

  @override
  bool shouldRepaint(_MeasureDistancePainter old) => old.cursor != cursor || old.snapshotBytes != snapshotBytes;
}
