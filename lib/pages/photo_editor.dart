import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../logic/app_startup.dart';
import '../models/classes/boxes/boxes_base.dart';
import '../models/classes/saved_maps.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/win32/win_utils.dart';
import '../widgets/interface/fancyshot.dart';
import '../widgets/widgets/color_picker.dart';
import '../widgets/widgets/custom_tooltip.dart';
import '../widgets/widgets/emoji_picker_modal.dart';
import '../widgets/widgets/font_picker/models/picker_font.dart';
import '../widgets/widgets/font_picker/ui/font_picker.dart';
import 'screen_capture.dart';

Future<void> startPhotoEditor(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  await AppStartup.initialize();

  final int fileIndex = arguments.indexOf('-file');
  final String? imageFilePath = fileIndex >= 0 && fileIndex + 1 < arguments.length ? arguments[fileIndex + 1] : null;

  Uint8List? initialImageBytes;
  img.Image? image;
  String effectiveFilePath = imageFilePath ?? '';

  if (imageFilePath != null && imageFilePath.isNotEmpty) {
    final File imageFile = File(imageFilePath);
    if (imageFile.existsSync()) {
      initialImageBytes = await imageFile.readAsBytes();
      image = img.decodeImage(initialImageBytes);
    }
  }

  final Size initialSize = image != null
      ? Size(
          (image.width + 360).clamp(980, 1800).toDouble(),
          (image.height + 240).clamp(720, 1200).toDouble(),
        )
      : const Size(1280, 800);

  const WindowOptions windowOptions = WindowOptions(
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.hidden,
    alwaysOnTop: false,
    title: 'Tabame Photo Editor',
  );

  await windowManager.waitUntilReadyToShow(windowOptions, () async {
    await Boxes.registerBoxes(justLoad: true);
    checkThemeChange();
    await windowManager.setAsFrameless();
    await windowManager.setHasShadow(false);
    await windowManager.setMinimumSize(const Size(980, 720));
    await windowManager.setSize(initialSize);
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(
    _StandalonePhotoEditorApp(
      filePath: effectiveFilePath,
      initialImageBytes: initialImageBytes,
      imageW: image?.width,
      imageH: image?.height,
    ),
  );
}

// ── Tool enum ─────────────────────────────────────────────────────────────────

enum EditorTool {
  select,
  pen,
  highlight,
  line,
  rect,
  ellipse,
  arrow,
  ruler,
  sizebox,
  text,
  emoji,
  stepCounter,
  infoBalloon,
  blur,
  pixelate,
  smartDelete,
  imageElement,
  magnifier,
  spotlight,
}

// ── Color palette ─────────────────────────────────────────────────────────────

class _Palette {
  static const List<Color> colors = <ui.Color>[
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

// ── Draw shape model ──────────────────────────────────────────────────────────

class EditorShape {
  final String id;
  final EditorTool tool;
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final double opacity;
  bool selected;
  final String? text;
  final bool textBackground;
  final Color? textColor;
  final double? fontSize;
  final String? fontFamily;
  final int? stepNumber;
  final Uint8List? imageBytes;
  final int? imageW;
  final int? imageH;
  final Color? fillColor;

  EditorShape({
    required this.id,
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
  });

  EditorShape copyWith({
    String? id,
    List<Offset>? points,
    bool? selected,
    String? text,
    bool? textBackground,
    Color? textColor,
    double? fontSize,
    Uint8List? imageBytes,
    int? imageW,
    int? imageH,
    String? fontFamily,
    Color? fillColor,
  }) {
    return EditorShape(
      id: id ?? this.id,
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
      fontFamily: fontFamily ?? this.fontFamily,
      stepNumber: stepNumber,
      imageBytes: imageBytes ?? this.imageBytes,
      imageW: imageW ?? this.imageW,
      imageH: imageH ?? this.imageH,
      fillColor: fillColor ?? this.fillColor,
    );
  }
}

// ── Editor controller ─────────────────────────────────────────────────────────

class EditorController extends ChangeNotifier {
  EditorTool activeTool = EditorTool.pen;
  Color strokeColor = Colors.red;
  double strokeWidth = 2.0;
  double opacity = 1.0;
  bool textBackground = true;
  double fontSize = 16.0;
  Color? textColor;
  String fontFamily = 'Roboto';
  bool gridVisible = false;

  int _stepCount = 1;
  int get nextStepNumber => _stepCount;
  void resetStepCounter() {
    _stepCount = 1;
    notifyListeners();
  }

  void toggleGrid() {
    gridVisible = !gridVisible;
    notifyListeners();
  }

  final List<EditorShape> _shapes = <EditorShape>[];
  final List<EditorShape> _redo = <EditorShape>[];
  int _shapeCounter = 0;

  List<EditorShape> get shapes => List<EditorShape>.unmodifiable(_shapes);

  EditorShape? currentShape;
  Offset? currentEnd;
  int? selectedShapeIndex;

  EditorShape? get selectedShape {
    final int? i = selectedShapeIndex;
    if (i == null || i < 0 || i >= _shapes.length) return null;
    return _shapes[i];
  }

  void setTool(EditorTool t) {
    activeTool = t;
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

  void setFontFamily(String family) {
    fontFamily = family;
    notifyListeners();
  }

  String _nextShapeId() {
    _shapeCounter++;
    return 'editor-shape-$_shapeCounter';
  }

  void startShape(Offset pos) {
    _redo.clear();
    currentShape = EditorShape(
      id: _nextShapeId(),
      tool: activeTool,
      points: <ui.Offset>[pos],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      textBackground: textBackground,
      stepNumber: activeTool == EditorTool.stepCounter ? _stepCount : null,
    );
    notifyListeners();
  }

  void updateShape(Offset pos, {bool shiftHeld = false}) {
    if (currentShape == null) return;
    Offset end = pos;
    if (shiftHeld) end = _snap45(currentShape!.points.first, pos);
    currentEnd = end;
    if (currentShape!.tool == EditorTool.pen || currentShape!.tool == EditorTool.highlight) {
      currentShape = currentShape!.copyWith(points: <ui.Offset>[...currentShape!.points, pos]);
    }
    notifyListeners();
  }

  void endShape() {
    if (currentShape == null) return;
    final Offset end = currentEnd ?? currentShape!.points.last;
    EditorShape committed;
    if (currentShape!.tool == EditorTool.pen || currentShape!.tool == EditorTool.highlight) {
      committed = currentShape!;
    } else {
      committed = currentShape!.copyWith(points: <ui.Offset>[currentShape!.points.first, end]);
    }
    if (committed.tool == EditorTool.spotlight) {
      _shapes.removeWhere((EditorShape shape) => shape.tool == EditorTool.spotlight);
      selectedShapeIndex = null;
    }
    _shapes.add(committed);
    if (committed.tool == EditorTool.stepCounter) _stepCount++;
    currentShape = null;
    currentEnd = null;
    notifyListeners();
  }

  EditorShape commitTextShape(
    Offset pos,
    String text, {
    double? size,
    String? family,
    Color? explicitTextColor,
    bool? useBackground,
    EditorTool? tool,
  }) {
    final EditorShape shape = EditorShape(
      id: _nextShapeId(),
      tool: tool ?? activeTool,
      points: <ui.Offset>[pos],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      text: text,
      textBackground: useBackground ?? textBackground,
      textColor: explicitTextColor ?? textColor,
      fontSize: size ?? fontSize,
      fontFamily: family ?? fontFamily,
    );
    _redo.clear();
    _shapes.add(shape);
    notifyListeners();
    return shape;
  }

  EditorShape commitRegionShape(EditorTool tool, Rect region, Uint8List bytes, int w, int h, {Color? fillColor}) {
    final EditorShape shape = EditorShape(
      id: _nextShapeId(),
      tool: tool,
      points: <ui.Offset>[region.topLeft, region.bottomRight],
      color: strokeColor,
      strokeWidth: strokeWidth,
      opacity: opacity,
      imageBytes: bytes,
      imageW: w,
      imageH: h,
      fillColor: fillColor,
    );
    _redo.clear();
    _shapes.add(shape);
    notifyListeners();
    return shape;
  }

  void undo() {
    if (_shapes.isEmpty) return;
    _redo.add(_shapes.removeLast());
    notifyListeners();
  }

  void redo() {
    if (_redo.isEmpty) return;
    _shapes.add(_redo.removeLast());
    notifyListeners();
  }

  void clearAll() {
    _shapes.clear();
    _redo.clear();
    currentShape = null;
    currentEnd = null;
    selectedShapeIndex = null;
    notifyListeners();
  }

  void selectShapeAt(Offset pos) {
    _clearSelection();
    for (int i = _shapes.length - 1; i >= 0; i--) {
      if (_hitTest(_shapes[i], pos)) {
        _shapes[i].selected = true;
        selectedShapeIndex = i;
        notifyListeners();
        return;
      }
    }
    selectedShapeIndex = null;
    notifyListeners();
  }

  void selectShapeById(String id) {
    _clearSelection();
    for (int i = 0; i < _shapes.length; i++) {
      if (_shapes[i].id != id) continue;
      _shapes[i].selected = true;
      selectedShapeIndex = i;
      notifyListeners();
      return;
    }
  }

  void _clearSelection() {
    for (final EditorShape shape in _shapes) {
      shape.selected = false;
    }
  }

  void moveSelected(Offset delta) {
    if (selectedShapeIndex == null) return;
    final EditorShape s = _shapes[selectedShapeIndex!];
    _shapes[selectedShapeIndex!] = s.copyWith(
      points: s.points.map((ui.Offset p) => p + delta).toList(),
    );
    notifyListeners();
  }

  void deleteShapeAt(Offset pos) {
    for (int i = _shapes.length - 1; i >= 0; i--) {
      if (_hitTest(_shapes[i], pos)) {
        _shapes.removeAt(i);
        selectedShapeIndex = null;
        notifyListeners();
        return;
      }
    }
  }

  bool _hitTest(EditorShape s, Offset pos) {
    if (s.points.isEmpty) return false;
    final Offset a = s.points.first;

    if (s.tool == EditorTool.pen || s.tool == EditorTool.highlight) {
      return s.points.any((ui.Offset p) => (p - pos).distance < 8);
    }

    if (s.tool == EditorTool.text) {
      return _textBounds(s, a).inflate(8).contains(pos);
    }

    if (s.tool == EditorTool.infoBalloon) {
      return _infoBalloonBounds(s, a).inflate(10).contains(pos);
    }

    if (s.tool == EditorTool.emoji) {
      return _emojiBounds(s, a).inflate(8).contains(pos);
    }

    if (s.tool == EditorTool.stepCounter) {
      return Rect.fromCircle(center: a, radius: 22).contains(pos);
    }

    if (s.points.length < 2) return false;
    final Offset b = s.points.last;

    if (s.tool == EditorTool.rect ||
        s.tool == EditorTool.blur ||
        s.tool == EditorTool.pixelate ||
        s.tool == EditorTool.smartDelete ||
        s.tool == EditorTool.imageElement ||
        s.tool == EditorTool.spotlight ||
        s.tool == EditorTool.magnifier) {
      return Rect.fromPoints(a, b).inflate(6).contains(pos);
    }

    final Offset center = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    return (center - pos).distance < 24;
  }

  Rect _textBounds(EditorShape shape, Offset pos) {
    final String text = shape.text ?? '';
    if (text.isEmpty) return Rect.fromCircle(center: pos, radius: 18);
    final double fontSize = shape.fontSize ?? (shape.strokeWidth * 8 + 12);
    final Color textColor = shape.textColor ?? shape.color;
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: _textStyleForHitTest(shape, color: textColor, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    Rect bounds = Rect.fromLTWH(pos.dx, pos.dy, textPainter.width, textPainter.height);
    if (shape.textBackground) {
      bounds = Rect.fromLTWH(pos.dx - 4, pos.dy - 2, textPainter.width + 8, textPainter.height + 4);
    }
    return bounds;
  }

  Rect _emojiBounds(EditorShape shape, Offset pos) {
    final String text = shape.text ?? '';
    if (text.isEmpty) return Rect.fromCircle(center: pos, radius: 18);
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(fontSize: shape.fontSize ?? 32),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    return Rect.fromLTWH(pos.dx, pos.dy, textPainter.width, textPainter.height);
  }

  Rect _infoBalloonBounds(EditorShape shape, Offset pos) {
    final String text = shape.text ?? '';
    if (text.isEmpty) return Rect.fromCircle(center: pos, radius: 18);
    const double padding = 10;
    const double tailHeight = 14;
    final double fontSize = shape.fontSize ?? (shape.strokeWidth * 6 + 12);
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: _textStyleForHitTest(shape, color: Colors.white, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 280);
    final double bubbleWidth = textPainter.width + padding * 2;
    final double bubbleHeight = textPainter.height + padding * 2;
    final Rect bubble = Rect.fromLTWH(
      pos.dx - bubbleWidth / 2,
      pos.dy - bubbleHeight - tailHeight,
      bubbleWidth,
      bubbleHeight,
    );
    return bubble.expandToInclude(Rect.fromLTWH(pos.dx - 8, bubble.bottom, 16, tailHeight));
  }

  TextStyle _textStyleForHitTest(EditorShape shape, {required Color color, required double fontSize}) {
    if (shape.tool == EditorTool.emoji) {
      return TextStyle(fontSize: fontSize);
    }
    final String? family = shape.fontFamily;
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      fontFamily: family == null ? null : GoogleFonts.getFont(family).fontFamily,
    );
  }

  Offset _snap45(Offset start, Offset end) {
    final double dx = end.dx - start.dx;
    final double dy = end.dy - start.dy;
    final double angle = atan2(dy, dx);
    final double len = sqrt(dx * dx + dy * dy);
    final double snapped = (angle / (pi / 4)).round() * (pi / 4);
    return Offset(start.dx + cos(snapped) * len, start.dy + sin(snapped) * len);
  }

  // Public hit test proxy for hover/scroll evaluation
  bool hitTestShapeForResize(EditorShape shape, Offset pos) {
    return _hitTest(shape, pos);
  }

  // Allows updating element sizes interactively (e.g., text font sizes, strokes, or region box scales)
  void updateShapeSizeAtIndex(int index, double newSize) {
    if (index < 0 || index >= _shapes.length) return;
    final EditorShape s = _shapes[index];

    if (s.tool == EditorTool.text || s.tool == EditorTool.infoBalloon || s.tool == EditorTool.emoji) {
      _shapes[index] = s.copyWith(fontSize: newSize);
    } else {
      // If drawing lines/shapes/boxes, resize their layout path presentation thickness
      _shapes[index] = EditorShape(
        id: s.id,
        tool: s.tool,
        points: s.points,
        color: s.color,
        strokeWidth: (newSize / 8).clamp(1.0, 30.0), // map size factor seamlessly down to scale
        opacity: s.opacity,
        selected: s.selected,
        text: s.text,
        textBackground: s.textBackground,
        textColor: s.textColor,
        fontSize: s.fontSize,
        fontFamily: s.fontFamily,
        stepNumber: s.stepNumber,
        imageBytes: s.imageBytes,
        imageW: s.imageW,
        imageH: s.imageH,
        fillColor: s.fillColor,
      );
    }
    notifyListeners();
  }
}

Rect _fitImageRect(Size viewportSize, ui.Image? image, {Rect? override}) {
  if (override != null) return override;
  if (image == null || viewportSize.width <= 0 || viewportSize.height <= 0) {
    return Rect.zero;
  }
  final double scale = min(viewportSize.width / image.width, viewportSize.height / image.height);
  final double width = image.width * scale;
  final double height = image.height * scale;
  return Rect.fromLTWH(
    (viewportSize.width - width) / 2,
    (viewportSize.height - height) / 2,
    width,
    height,
  );
}
// ─────────────────────────────────────────────────────────────────────────────
// Photo Editor View
// ─────────────────────────────────────────────────────────────────────────────

class PhotoEditorView extends StatefulWidget {
  final Uint8List? initialImageBytes;
  final int? imageW;
  final int? imageH;
  final String filePath;
  final bool standaloneMode;
  final VoidCallback? onBack;

  const PhotoEditorView({
    super.key,
    this.initialImageBytes,
    this.imageW,
    this.imageH,
    required this.filePath,
    this.standaloneMode = false,
    this.onBack,
  });

  @override
  State<PhotoEditorView> createState() => _PhotoEditorViewState();
}

class _PhotoEditorViewState extends State<PhotoEditorView> {
  final EditorController _ctrl = EditorController();
  final FocusNode _focusNode = FocusNode();
  late Uint8List? _originalImageBytes;
  late String _currentFilePath;
  ui.Image? _backgroundImage;
  List<FancyShotProfile> _editorFancyShotProfiles = <FancyShotProfile>[];
  String? _selectedEditorPresetName;
  final Map<String, ui.Image> _shapeImages = <String, ui.Image>{};
  ThemeColors get _theme => user.theme;
  bool _shiftHeld = false;
  Offset? _lastSelectPos;
  Offset? _dragStart;
  Offset? _dragCurrent;
  bool _selectMode = false;
  bool _isRegionDragging = false;
  bool _captureMoreBusy = false;
  bool _presetBusy = false;
  double _zoomFactor = 1.0;
  final ScrollController _verticalScrollCtrl = ScrollController();
  final ScrollController _horizontalScrollCtrl = ScrollController();
  Offset? _middleMouseStart;

  void _zoomIn() {
    setState(() {
      _zoomFactor = (_zoomFactor + 0.1).clamp(0.1, 5.0);
    });
  }

  void _zoomOut() {
    setState(() {
      _zoomFactor = (_zoomFactor - 0.1).clamp(0.1, 5.0);
    });
  }

  void _resetZoom() {
    setState(() {
      _zoomFactor = 1.0;
    });
  }

  void _handleBackAction() {
    final VoidCallback? onBack = widget.onBack;
    if (onBack != null) {
      onBack();
      return;
    }
    if (widget.standaloneMode) {
      unawaited(windowManager.close());
      return;
    }
    appState.backToCapture();
  }

  @override
  void initState() {
    super.initState();
    _currentFilePath = widget.filePath;
    _originalImageBytes = widget.initialImageBytes != null ? Uint8List.fromList(widget.initialImageBytes!) : null;
    _editorFancyShotProfiles = FancyShot.loadProfiles();
    _ctrl.addListener(_handleControllerChanged);
    if (_originalImageBytes != null) {
      _decodeBackground();
    }
    WinUtils.fixDrawBug();
  }

  Future<void> _decodeBackground() async {
    if (_originalImageBytes != null) {
      await _decodeBackgroundBytes(_originalImageBytes!);
    }
  }

  Future<void> _decodeBackgroundBytes(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    if (mounted) setState(() => _backgroundImage = frame.image);
  }

  Future<void> _applyEditorFancyShotPreset(String? presetName) async {
    final String? normalizedName = presetName == null || presetName.isEmpty || presetName == 'none' ? null : presetName;
    if (_presetBusy) return;

    setState(() {
      _presetBusy = true;
      _selectedEditorPresetName = normalizedName;
    });

    try {
      Uint8List? bytes = _originalImageBytes;
      if (normalizedName != null && bytes != null) {
        FancyShotProfile? preset;
        for (final FancyShotProfile profile in _editorFancyShotProfiles) {
          if (profile.name == normalizedName) {
            preset = profile.copyWith();
            break;
          }
        }
        preset ??= FancyShot.profileByName(normalizedName);
        if (preset != null) {
          bytes = await FancyShot.renderPresetCapture(
            captureBytes: _originalImageBytes!,
            profile: preset,
          );
        }
      }

      if (!mounted) return;
      if (bytes != null) await _decodeBackgroundBytes(bytes);
    } finally {
      if (mounted) {
        setState(() => _presetBusy = false);
      }
    }
  }

  void _handleControllerChanged() {
    if (_selectMode && _ctrl.activeTool != EditorTool.select) {
      _selectMode = false;
    }
    unawaited(_syncShapeImages());
  }

  bool _needsDecodedImage(EditorShape shape) {
    return (shape.tool == EditorTool.blur || shape.tool == EditorTool.imageElement) &&
        shape.imageBytes != null &&
        shape.imageW != null &&
        shape.imageH != null;
  }

  Future<ui.Image?> _decodeRawRgbaImage(Uint8List? bytes, int? width, int? height) async {
    if (bytes == null || width == null || height == null || width <= 0 || height <= 0) return null;
    final ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final ui.ImageDescriptor descriptor = ui.ImageDescriptor.raw(
      buffer,
      width: width,
      height: height,
      pixelFormat: ui.PixelFormat.rgba8888,
    );
    final ui.Codec codec = await descriptor.instantiateCodec();
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }

  Future<void> _syncShapeImages() async {
    bool changed = false;
    final Set<String> liveIds = _ctrl.shapes.map((EditorShape shape) => shape.id).toSet();
    final List<String> removedIds = _shapeImages.keys.where((String id) => !liveIds.contains(id)).toList();
    for (final String id in removedIds) {
      _shapeImages.remove(id);
      changed = true;
    }

    for (final EditorShape shape in _ctrl.shapes) {
      if (!_needsDecodedImage(shape) || _shapeImages.containsKey(shape.id)) continue;
      final ui.Image? image = await _decodeRawRgbaImage(shape.imageBytes, shape.imageW, shape.imageH);
      if (!mounted || image == null) continue;
      _shapeImages[shape.id] = image;
      changed = true;
    }

    if (changed && mounted) setState(() {});
  }

  Future<void> _ensureAllShapeImagesDecoded() async {
    for (final EditorShape shape in _ctrl.shapes) {
      if (!_needsDecodedImage(shape) || _shapeImages.containsKey(shape.id)) continue;
      final ui.Image? image = await _decodeRawRgbaImage(shape.imageBytes, shape.imageW, shape.imageH);
      if (image != null) _shapeImages[shape.id] = image;
    }
  }

  bool _isRegionTool(EditorTool t) {
    return t == EditorTool.blur ||
        t == EditorTool.pixelate ||
        t == EditorTool.smartDelete ||
        t == EditorTool.imageElement;
  }

  Future<void> _handleOpenFile() async {
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'Image Files (*.png; *.jpg; *.jpeg; *.bmp; *.gif)': '*.png;*.jpg;*.jpeg;*.bmp;*.gif',
        'All Files': '*.*'
      }
      ..defaultFilterIndex = 0
      ..title = 'Select an image';

    final File? result = picker.getFile();
    if (result == null) return;

    try {
      final Uint8List bytes = await result.readAsBytes();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) return;

      setState(() {
        _originalImageBytes = bytes;
        _currentFilePath = result.path;
      });

      await _decodeBackgroundBytes(bytes);

      _ctrl.clearAll();
      _ctrl.resetStepCounter();

      final Size newSize = Size(
        (decoded.width + 360).clamp(980, 1800).toDouble(),
        (decoded.height + 240).clamp(720, 1200).toDouble(),
      );
      await windowManager.setSize(newSize);
      await windowManager.center();
    } catch (e) {
      debugPrint('Error loading image: $e');
    }
  }

  Widget _buildNoPhotoPlaceholder() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.photo_library_outlined, size: 64, color: Colors.white.withValues(alpha: 0.1)),
          const SizedBox(height: 16),
          const Text(
            'No photo loaded',
            style: TextStyle(color: Colors.white38, fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Design.accent.withValues(alpha: 0.8),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: _handleOpenFile,
            icon: const Icon(Icons.folder_open_rounded, size: 18),
            label: const Text('Open an Image'),
          ),
        ],
      ),
    );
  }

  Rect _imageRect(Size viewSize) {
    return _fitImageRect(viewSize, _backgroundImage);
  }

  Offset? _viewToImage(Offset viewPos, Size viewSize) {
    final Rect rect = _imageRect(viewSize);
    final ui.Image? image = _backgroundImage;
    if (image == null || rect.isEmpty || !rect.contains(viewPos)) return null;
    final double scale = rect.width / image.width;
    return Offset((viewPos.dx - rect.left) / scale, (viewPos.dy - rect.top) / scale);
  }

  @override
  void dispose() {
    _ctrl.removeListener(_handleControllerChanged);
    _focusNode.dispose();
    _ctrl.dispose();
    _verticalScrollCtrl.dispose();
    _horizontalScrollCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return KeyboardListener(
      focusNode: _focusNode,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Container(
        color: Colors.transparent,
        child: FutureBuilder<bool>(
            future: windowManager.isMaximized(),
            builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
              if (snapshot.data == null) return const SizedBox.shrink();
              final bool maximized = snapshot.data ?? false;
              return SafeArea(
                minimum: maximized ? const EdgeInsets.all(0) : const EdgeInsets.all(12).copyWith(top: 0),
                child: DragToResizeArea(
                  child: Container(
                    decoration: BoxDecoration(
                      color: _theme.background,
                      borderRadius: maximized ? null : BorderRadius.circular(18),
                      border: Border.all(color: _theme.text.withValues(alpha: 0.08)),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.36),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Column(
                      children: <Widget>[
                        _EditorWindowBar(
                          filePath: _currentFilePath,
                          onBack: _handleBackAction,
                          standaloneMode: widget.standaloneMode,
                          resetState: () => setState(() {}),
                          onOpenFile: _handleOpenFile,
                        ),
                        Expanded(
                          child: Row(
                            children: <Widget>[
                              Padding(
                                padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
                                child: _EditorToolbar(
                                  ctrl: _ctrl,
                                  onBack: _handleBackAction,
                                  zoomFactor: _zoomFactor,
                                  onZoomIn: _zoomIn,
                                  onZoomOut: _zoomOut,
                                  onResetZoom: _resetZoom,
                                ),
                              ),
                              Expanded(
                                child: Padding(
                                  padding: const EdgeInsets.fromLTRB(0, 12, 12, 0),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      color: _theme.background.darken(5),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
                                    ),
                                    child: LayoutBuilder(
                                      builder: (BuildContext context, BoxConstraints constraints) {
                                        final Size viewportSize = Size(constraints.maxWidth, constraints.maxHeight);
                                        final Size canvasSize = viewportSize * _zoomFactor;

                                        return Listener(
                                          onPointerSignal: (PointerSignalEvent event) {
                                            if (event is PointerScrollEvent) {
                                              final bool ctrlHeld = HardwareKeyboard.instance.isControlPressed;

                                              // 2. Ctrl + Scroll Wheel to Zoom In / Zoom Out
                                              if (ctrlHeld) {
                                                if (event.scrollDelta.dy < 0) {
                                                  _zoomIn();
                                                } else if (event.scrollDelta.dy > 0) {
                                                  _zoomOut();
                                                }
                                                return; // Absorb event to prevent standard list scrolling
                                              }

                                              // 3. Select Mode Element Resize via Hover Scroll
                                              if (_selectMode || _ctrl.activeTool == EditorTool.select) {
                                                final Offset? imagePos = _viewToImage(event.localPosition, canvasSize);
                                                if (imagePos != null) {
                                                  // Iterate backwards to hit test the top-most elements first
                                                  for (int i = _ctrl.shapes.length - 1; i >= 0; i--) {
                                                    // Check if mouse is hovering over this element
                                                    if (_ctrl.hitTestShapeForResize(_ctrl.shapes[i], imagePos)) {
                                                      setState(() {
                                                        final EditorShape shape = _ctrl.shapes[i];
                                                        // Determine baseline dimension size
                                                        final double currentSize =
                                                            shape.fontSize ?? (shape.strokeWidth * 8 + 12);
                                                        final double delta = event.scrollDelta.dy < 0 ? 2.0 : -2.0;
                                                        final double newSize = (currentSize + delta).clamp(8.0, 200.0);

                                                        _ctrl.updateShapeSizeAtIndex(i, newSize);
                                                      });
                                                      return; // Size adjustment complete
                                                    }
                                                  }
                                                }
                                              }

                                              // Fallback: Default workspace scrolling
                                              final bool altHeld = HardwareKeyboard.instance.isAltPressed;
                                              final ScrollController target =
                                                  altHeld ? _horizontalScrollCtrl : _verticalScrollCtrl;
                                              final double delta = event.scrollDelta.dy;
                                              final double newOffset =
                                                  (target.offset + delta).clamp(0.0, target.position.maxScrollExtent);
                                              target.jumpTo(newOffset);
                                            }
                                          },
                                          onPointerDown: (PointerDownEvent event) {
                                            // 1. Detect Middle Mouse Button down click
                                            if (event.buttons == kMiddleMouseButton) {
                                              _middleMouseStart = event.position;
                                            }
                                          },
                                          onPointerMove: (PointerMoveEvent event) {
                                            // 1. Process active panning when dragging with Middle Mouse Button held
                                            if (_middleMouseStart != null) {
                                              final Offset delta = event.position - _middleMouseStart!;
                                              _middleMouseStart = event.position; // Track relative continuous delta

                                              if (_verticalScrollCtrl.hasClients) {
                                                _verticalScrollCtrl.jumpTo(
                                                  (_verticalScrollCtrl.offset - delta.dy)
                                                      .clamp(0.0, _verticalScrollCtrl.position.maxScrollExtent),
                                                );
                                              }
                                              if (_horizontalScrollCtrl.hasClients) {
                                                _horizontalScrollCtrl.jumpTo(
                                                  (_horizontalScrollCtrl.offset - delta.dx)
                                                      .clamp(0.0, _horizontalScrollCtrl.position.maxScrollExtent),
                                                );
                                              }
                                            }
                                          },
                                          onPointerUp: (PointerUpEvent event) {
                                            // 1. Release middle mouse pan tracking
                                            _middleMouseStart = null;
                                          },
                                          child: Scrollbar(
                                            controller: _verticalScrollCtrl,
                                            child: SingleChildScrollView(
                                              scrollDirection: Axis.horizontal,
                                              controller: _horizontalScrollCtrl,
                                              child: SingleChildScrollView(
                                                scrollDirection: Axis.vertical,
                                                controller: _verticalScrollCtrl,
                                                child: Container(
                                                  width: max(viewportSize.width, canvasSize.width),
                                                  height: max(viewportSize.height, canvasSize.height),
                                                  alignment: Alignment.center,
                                                  child: Stack(
                                                    children: <Widget>[
                                                      SizedBox(
                                                        width: canvasSize.width,
                                                        height: canvasSize.height,
                                                        child: _backgroundImage == null
                                                            ? (_originalImageBytes == null
                                                                ? _buildNoPhotoPlaceholder()
                                                                : const Center(
                                                                    child: SizedBox(
                                                                      width: 40,
                                                                      height: 40,
                                                                      child: CircularProgressIndicator(),
                                                                    ),
                                                                  ))
                                                            : GestureDetector(
                                                                behavior: HitTestBehavior.translucent,
                                                                onPanStart: (DragStartDetails details) {
                                                                  if (_middleMouseStart != null) {
                                                                    return; // Ignore drag if panning instead
                                                                  }
                                                                  _onPanStart(details, canvasSize);
                                                                },
                                                                onPanUpdate: (DragUpdateDetails details) {
                                                                  if (_middleMouseStart != null) {
                                                                    return; // Ignore drag if panning instead
                                                                  }
                                                                  _onPanUpdate(details, canvasSize);
                                                                },
                                                                onPanEnd: (DragEndDetails details) {
                                                                  if (_middleMouseStart != null) return;
                                                                  _onPanEnd(details);
                                                                },
                                                                onTapDown: (TapDownDetails details) =>
                                                                    _onTapDown(details, canvasSize),
                                                                onSecondaryTapDown: (TapDownDetails details) {
                                                                  final Offset? imagePos =
                                                                      _viewToImage(details.localPosition, canvasSize);
                                                                  if (imagePos != null) _ctrl.deleteShapeAt(imagePos);
                                                                },
                                                                child: ListenableBuilder(
                                                                  listenable: _ctrl,
                                                                  builder: (_, __) => CustomPaint(
                                                                    size: canvasSize,
                                                                    painter: _EditorPainter(
                                                                      shapes: _ctrl.shapes,
                                                                      currentShape: _ctrl.currentShape,
                                                                      currentEnd: _ctrl.currentEnd,
                                                                      backgroundImage: _backgroundImage,
                                                                      shapeImages: _shapeImages,
                                                                      gridVisible: _ctrl.gridVisible,
                                                                      dragStart: _dragStart,
                                                                      dragCurrent: _dragCurrent,
                                                                      isRegionDrag: _isRegionDragging,
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
                                        );
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                          child: Align(
                            alignment: Alignment.centerRight,
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: <Widget>[
                                _SaveButton(
                                  ctrl: _ctrl,
                                  backgroundImage: _backgroundImage,
                                  filePath: widget.filePath,
                                  shapeImages: _shapeImages,
                                  onCaptureMore: _captureMoreFromScreen,
                                  captureMoreBusy: _captureMoreBusy,
                                  presetNames:
                                      _editorFancyShotProfiles.map((FancyShotProfile profile) => profile.name).toList(),
                                  value: _selectedEditorPresetName,
                                  busy: _presetBusy,
                                  onPresetChanged: _applyEditorFancyShotPreset,
                                  showScreenCaptureActions: !widget.standaloneMode,
                                  onNewCapture: _handleBackAction,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }),
      ),
    );
  }

  void _onKey(KeyEvent e) {
    if (e is KeyDownEvent) {
      _shiftHeld = HardwareKeyboard.instance.isShiftPressed;
      final bool lCtrl = HardwareKeyboard.instance.isControlPressed;
      if (lCtrl && e.logicalKey == LogicalKeyboardKey.keyZ) {
        _ctrl.undo();
        return;
      }
      if (lCtrl && e.logicalKey == LogicalKeyboardKey.keyY) {
        _ctrl.redo();
        return;
      }
      if (lCtrl && (e.logicalKey == LogicalKeyboardKey.equal || e.logicalKey == LogicalKeyboardKey.add)) {
        _zoomIn();
        return;
      }
      if (lCtrl && e.logicalKey == LogicalKeyboardKey.minus) {
        _zoomOut();
        return;
      }
      if (lCtrl && (e.logicalKey == LogicalKeyboardKey.digit0 || e.logicalKey == LogicalKeyboardKey.numpad0)) {
        _resetZoom();
        return;
      }
      if (e.logicalKey == LogicalKeyboardKey.escape) _handleBackAction();

      final Map<LogicalKeyboardKey, EditorTool> toolKeys = <LogicalKeyboardKey, EditorTool>{
        LogicalKeyboardKey.keyS: EditorTool.select,
        LogicalKeyboardKey.keyP: EditorTool.pen,
        LogicalKeyboardKey.keyH: EditorTool.highlight,
        LogicalKeyboardKey.keyL: EditorTool.line,
        LogicalKeyboardKey.keyR: EditorTool.rect,
        LogicalKeyboardKey.keyE: EditorTool.ellipse,
        LogicalKeyboardKey.keyA: EditorTool.arrow,
        LogicalKeyboardKey.keyM: EditorTool.ruler,
        LogicalKeyboardKey.keyB: EditorTool.sizebox,
        LogicalKeyboardKey.keyT: EditorTool.text,
        LogicalKeyboardKey.keyN: EditorTool.stepCounter,
        LogicalKeyboardKey.keyI: EditorTool.infoBalloon,
        LogicalKeyboardKey.keyG: EditorTool.imageElement,
        LogicalKeyboardKey.keyF: EditorTool.blur,
        LogicalKeyboardKey.keyX: EditorTool.pixelate,
        LogicalKeyboardKey.keyD: EditorTool.smartDelete,
      };
      if (toolKeys.containsKey(e.logicalKey)) {
        _ctrl.setTool(toolKeys[e.logicalKey]!);
        _selectMode = _ctrl.activeTool == EditorTool.select;
      }
    }
    if (e is KeyUpEvent) _shiftHeld = false;
  }

  void _onPanStart(DragStartDetails d, Size canvasSize) {
    final Offset? imagePos = _viewToImage(d.localPosition, canvasSize);
    if (imagePos == null) return;
    final Offset pos = imagePos;
    if (_ctrl.activeTool == EditorTool.select || _selectMode) {
      _ctrl.selectShapeAt(pos);
      _lastSelectPos = pos;
      return;
    }
    if (_isRegionTool(_ctrl.activeTool)) {
      setState(() {
        _dragStart = pos;
        _dragCurrent = pos;
        _isRegionDragging = true;
      });
      return;
    }
    _ctrl.startShape(pos);
  }

  void _onPanUpdate(DragUpdateDetails d, Size canvasSize) {
    final Offset? imagePos = _viewToImage(d.localPosition, canvasSize);
    if (imagePos == null) return;
    final Offset pos = imagePos;
    if (_ctrl.activeTool == EditorTool.select || _selectMode) {
      if (_lastSelectPos != null) {
        _ctrl.moveSelected(pos - _lastSelectPos!);
        _lastSelectPos = pos;
      }
      return;
    }
    if (_isRegionTool(_ctrl.activeTool) && _dragStart != null) {
      setState(() => _dragCurrent = pos);
      return;
    }
    _ctrl.updateShape(pos, shiftHeld: _shiftHeld);
  }

  Future<void> _onPanEnd(DragEndDetails _) async {
    if (_ctrl.activeTool == EditorTool.select || _selectMode) {
      _lastSelectPos = null;
      return;
    }
    if (_isRegionTool(_ctrl.activeTool) && _dragStart != null && _dragCurrent != null) {
      final Rect region = Rect.fromPoints(_dragStart!, _dragCurrent!).normalized();
      if (region.width > 4 && region.height > 4) {
        if (_ctrl.activeTool == EditorTool.imageElement) {
          await _createImageElementFromRegion(region);
        } else {
          await _commitRegion(region);
        }
      }
      setState(() {
        _dragStart = null;
        _dragCurrent = null;
        _isRegionDragging = false;
      });
      return;
    }
    _ctrl.endShape();
  }

  void _onTapDown(TapDownDetails d, Size canvasSize) {
    final Offset? imagePos = _viewToImage(d.localPosition, canvasSize);
    if (imagePos == null) return;
    final Offset pos = imagePos;
    if (_selectMode) {
      _ctrl.selectShapeAt(pos);
      return;
    }
    if (_ctrl.activeTool == EditorTool.text || _ctrl.activeTool == EditorTool.infoBalloon) {
      _showTextDialog(pos);
      return;
    }
    if (_ctrl.activeTool == EditorTool.emoji) {
      _showEmojiDialog(pos);
      return;
    }
    if (_ctrl.activeTool == EditorTool.stepCounter) {
      _ctrl.startShape(pos);
      _ctrl.endShape();
      return;
    }
  }

  Future<void> _commitRegion(Rect region) async {
    final img.Image? composite = await _renderCompositeImagePackage();
    if (composite == null) return;
    final img.Image crop = _cropCompositeRegion(composite, region);
    final Uint8List rgba = Uint8List.fromList(crop.getBytes(order: img.ChannelOrder.rgba));
    _ctrl.commitRegionShape(
      _ctrl.activeTool,
      region,
      rgba,
      crop.width,
      crop.height,
      fillColor: _smartDeleteFillColor(crop),
    );
    await _syncShapeImages();
  }

  img.Image _cropCompositeRegion(img.Image composite, Rect region) {
    final Rect safeRect =
        region.normalized().intersect(Rect.fromLTWH(0, 0, composite.width.toDouble(), composite.height.toDouble()));
    return img.copyCrop(
      composite,
      x: safeRect.left.floor().clamp(0, composite.width - 1),
      y: safeRect.top.floor().clamp(0, composite.height - 1),
      width: max(1, safeRect.width.round()),
      height: max(1, safeRect.height.round()),
    );
  }

  Color _smartDeleteFillColor(img.Image source) {
    if (source.width == 0 || source.height == 0) {
      return Colors.white;
    }
    final img.Pixel pixel = source.getPixelSafe(0, 0);
    return Color.fromARGB(
      pixel.a.toInt(),
      pixel.r.toInt(),
      pixel.g.toInt(),
      pixel.b.toInt(),
    );
  }

  Future<img.Image?> _renderCompositeImagePackage() async {
    final ui.Image? backgroundImage = _backgroundImage;
    if (backgroundImage == null) return null;
    await _ensureAllShapeImagesDecoded();
    final Uint8List? pngBytes = await _renderEditorPngBytes(
      backgroundImage: backgroundImage,
      shapes: _ctrl.shapes,
      shapeImages: _shapeImages,
    );
    if (pngBytes == null) return null;
    return img.decodeImage(pngBytes);
  }

  Rect _imageBoundsRect() {
    final ui.Image? image = _backgroundImage;
    if (image == null) return Rect.zero;
    return Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  }

  Rect _duplicateInsertRect(Rect sourceRect) {
    final Rect imageBounds = _imageBoundsRect();
    Rect shifted = sourceRect.shift(const Offset(24, 24));
    if (shifted.right > imageBounds.right) shifted = shifted.shift(Offset(imageBounds.right - shifted.right, 0));
    if (shifted.bottom > imageBounds.bottom) shifted = shifted.shift(Offset(0, imageBounds.bottom - shifted.bottom));
    if (shifted.left < imageBounds.left) shifted = shifted.shift(Offset(imageBounds.left - shifted.left, 0));
    if (shifted.top < imageBounds.top) shifted = shifted.shift(Offset(0, imageBounds.top - shifted.top));
    return shifted;
  }

  Rect _defaultInsertedImageRect(int width, int height) {
    final Rect imageBounds = _imageBoundsRect();
    if (imageBounds.isEmpty) return Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
    final double scale = min(1.0, min(imageBounds.width * 0.6 / width, imageBounds.height * 0.6 / height));
    return Rect.fromCenter(
      center: imageBounds.center,
      width: width * scale,
      height: height * scale,
    );
  }

  Future<void> _createImageElementFromRegion(Rect region) async {
    final img.Image? composite = await _renderCompositeImagePackage();
    if (composite == null) return;
    final img.Image crop = _cropCompositeRegion(composite, region);
    final Uint8List rgba = Uint8List.fromList(crop.getBytes(order: img.ChannelOrder.rgba));
    final EditorShape shape = _ctrl.commitRegionShape(
      EditorTool.imageElement,
      _duplicateInsertRect(region),
      rgba,
      crop.width,
      crop.height,
    );
    await _syncShapeImages();
    _ctrl.setTool(EditorTool.select);
    _selectMode = true;
    _ctrl.selectShapeById(shape.id);
  }

  Future<void> _captureMoreFromScreen() async {
    if (_captureMoreBusy) return;
    setState(() => _captureMoreBusy = true);
    Win32.getMainHandle();
    final int hwnd = Win32.hWnd;
    try {
      if (hwnd != 0) ShowWindow(hwnd, SW_HIDE);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final bool captured = await WinUtils.screenCapture();
      if (hwnd != 0) ShowWindow(hwnd, SW_SHOW);
      await windowManager.focus();
      if (!captured) return;

      final File file = File('${WinUtils.getTempFolder()}\\capture.png');
      if (!file.existsSync()) return;
      final Uint8List pngBytes = await file.readAsBytes();
      final img.Image? image = img.decodeImage(pngBytes);
      if (image == null) return;

      final Uint8List rgba = Uint8List.fromList(image.getBytes(order: img.ChannelOrder.rgba));
      final EditorShape shape = _ctrl.commitRegionShape(
        EditorTool.imageElement,
        _defaultInsertedImageRect(image.width, image.height),
        rgba,
        image.width,
        image.height,
      );
      await _syncShapeImages();
      _ctrl.setTool(EditorTool.select);
      _selectMode = true;
      _ctrl.selectShapeById(shape.id);
    } finally {
      if (mounted) setState(() => _captureMoreBusy = false);
      if (hwnd != 0) ShowWindow(hwnd, SW_SHOW);
    }
  }

  Future<void> _showTextDialog(Offset pos) async {
    final TextEditingController tc = TextEditingController();
    double localSize = _ctrl.fontSize;
    String localFontFamily = _ctrl.fontFamily;

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

    final List<dynamic>? result = await showDialog<List<dynamic>>(
      context: context,
      barrierColor: Colors.black38,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSt) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: Text(
              _ctrl.activeTool == EditorTool.infoBalloon ? 'Info Balloon' : 'Enter Text',
              style: const TextStyle(color: Colors.white),
            ),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                    onSubmitted: (String v) => Navigator.pop(ctx, <dynamic>[v, localSize, localFontFamily]),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: <Widget>[
                      Text('Size', style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 2)),
                      Expanded(
                        child: Slider(
                          value: localSize,
                          min: 8,
                          max: 120,
                          activeColor: Colors.yellowAccent,
                          onChanged: (double v) => setSt(() => localSize = v),
                        ),
                      ),
                      Text(localSize.round().toString(),
                          style: TextStyle(
                              color: Colors.white, fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.bold)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title:
                        Text('Font Family', style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 2)),
                    subtitle:
                        Text(localFontFamily, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    trailing: const Icon(Icons.font_download, color: Colors.white54),
                    onTap: () => openFontPicker(setSt),
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, <dynamic>[tc.text, localSize, localFontFamily]),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );
    if (result != null && result.isNotEmpty) {
      final double chosenSize = result[1] as double;
      final String chosenFontFamily = result[2] as String;
      _ctrl.fontSize = chosenSize;
      _ctrl.setFontFamily(chosenFontFamily);
      _ctrl.commitTextShape(
        pos,
        result[0] as String,
        size: chosenSize,
        family: chosenFontFamily,
      );
    }
  }

  Future<void> _showEmojiDialog(Offset pos) async {
    final TextEditingController emojiController = TextEditingController();
    double localSize = max(_ctrl.fontSize, 24);

    final List<dynamic>? result = await showDialog<List<dynamic>>(
      context: context,
      barrierColor: Colors.black38,
      builder: (BuildContext ctx) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSt) {
          return AlertDialog(
            backgroundColor: Colors.grey[900],
            title: const Text('Emoji', style: TextStyle(color: Colors.white)),
            content: SizedBox(
              width: 320,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  EmojiPickerTextField(
                    controller: emojiController,
                    autofocus: true,
                    dialogTitle: 'Pick emoji',
                    decoration: const InputDecoration(
                      hintText: 'Pick or paste an emoji',
                      hintStyle: TextStyle(color: Colors.white38),
                      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.white38)),
                      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: Colors.yellowAccent)),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Row(
                    children: <Widget>[
                      Text('Size', style: TextStyle(color: Colors.white70, fontSize: Design.baseFontSize + 2)),
                      Expanded(
                        child: Slider(
                          value: localSize,
                          min: 18,
                          max: 160,
                          activeColor: Colors.yellowAccent,
                          onChanged: (double value) => setSt(() => localSize = value),
                        ),
                      ),
                      Text(
                        localSize.round().toString(),
                        style: TextStyle(
                            color: Colors.white, fontSize: Design.baseFontSize + 2, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
              TextButton(
                onPressed: () => Navigator.pop(ctx, <dynamic>[emojiController.text.trim(), localSize]),
                child: const Text('OK'),
              ),
            ],
          );
        },
      ),
    );

    if (result == null || result.isEmpty) return;
    final String emoji = (result[0] as String).trim();
    if (emoji.isEmpty) return;
    _ctrl.commitTextShape(
      pos,
      emoji,
      size: result[1] as double,
      family: null,
      explicitTextColor: null,
      useBackground: false,
      tool: EditorTool.emoji,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor Painter
// ─────────────────────────────────────────────────────────────────────────────

class _EditorPainter extends CustomPainter {
  final List<EditorShape> shapes;
  final EditorShape? currentShape;
  final Offset? currentEnd;
  final ui.Image? backgroundImage;
  final Map<String, ui.Image> shapeImages;
  final bool gridVisible;
  final Offset? dragStart;
  final Offset? dragCurrent;
  final bool isRegionDrag;
  final Rect? imageRectOverride;

  _EditorPainter({
    required this.shapes,
    required this.currentShape,
    required this.currentEnd,
    required this.backgroundImage,
    required this.shapeImages,
    required this.gridVisible,
    this.dragStart,
    this.dragCurrent,
    this.isRegionDrag = false,
    this.imageRectOverride,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final ui.Image? image = backgroundImage;
    final Rect imageRect = _displayImageRect(size);

    if (image != null && !imageRect.isEmpty) {
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        imageRect,
        Paint()..filterQuality = FilterQuality.high,
      );

      final double scale = imageRect.width / image.width;
      canvas.save();
      canvas.clipRect(imageRect);
      canvas.translate(imageRect.left, imageRect.top);
      canvas.scale(scale, scale);

      final EditorShape? spotlightShape = _effectiveSpotlightShape();
      if (spotlightShape != null) {
        final Rect spotlightRect = _shapeRect(spotlightShape).intersect(_imageBounds());
        if (!spotlightRect.isEmpty) {
          _drawSpotlightRect(canvas, spotlightRect);
        }
      }

      for (final EditorShape s in shapes) {
        if (s.tool == EditorTool.spotlight) continue;
        _paintShape(canvas, s, null);
      }
      if (currentShape != null && currentShape!.tool != EditorTool.spotlight) {
        _paintShape(canvas, currentShape!, currentEnd);
      }

      // Region drag preview; drag coordinates are stored in image space.
      if (isRegionDrag && dragStart != null && dragCurrent != null) {
        final Rect r = Rect.fromPoints(dragStart!, dragCurrent!).normalized();
        canvas.drawRect(r, Paint()..color = Colors.cyan.withValues(alpha: 0.25));
        _drawDashedRect(canvas, r, Colors.cyanAccent);
      }

      canvas.restore();
    }

    if (gridVisible) _paintGrid(canvas, size);
  }

  Rect _displayImageRect(Size size) {
    return _fitImageRect(size, backgroundImage, override: imageRectOverride);
  }

  EditorShape? _effectiveSpotlightShape() {
    if (currentShape?.tool == EditorTool.spotlight) {
      final EditorShape spotlight = currentShape!;
      return spotlight.copyWith(points: <Offset>[spotlight.points.first, currentEnd ?? spotlight.points.first]);
    }
    for (int i = shapes.length - 1; i >= 0; i--) {
      if (shapes[i].tool == EditorTool.spotlight) return shapes[i];
    }
    return null;
  }

  Rect _shapeRect(EditorShape shape) {
    if (shape.points.isEmpty) return Rect.zero;
    final Offset start = shape.points.first;
    final Offset end = shape.points.length > 1 ? shape.points.last : start;
    return Rect.fromPoints(start, end).normalized();
  }

  Paint _makePaint(EditorShape s) => Paint()
    ..color = s.color.withValues(alpha: s.opacity)
    ..strokeWidth = s.strokeWidth
    ..style = PaintingStyle.stroke
    ..strokeCap = StrokeCap.round;

  void _paintShape(Canvas canvas, EditorShape s, Offset? liveEnd) {
    final Paint paint = _makePaint(s);
    final Offset start = s.points.isNotEmpty ? s.points.first : Offset.zero;
    final Offset end = liveEnd ?? (s.points.length > 1 ? s.points.last : start);

    if (s.selected) {
      final Paint selPaint = Paint()
        ..color = Colors.blue.withValues(alpha: 0.3)
        ..strokeWidth = s.strokeWidth + 4
        ..style = PaintingStyle.stroke;
      _drawShape(canvas, s.tool, start, end, s.points, selPaint, s.color, s.strokeWidth);
    }

    switch (s.tool) {
      case EditorTool.text:
        _drawText(canvas, s, start);
        return;
      case EditorTool.emoji:
        _drawEmoji(canvas, s, start);
        return;
      case EditorTool.infoBalloon:
        _drawInfoBalloon(canvas, s, start);
        return;
      case EditorTool.stepCounter:
        _drawStepCounter(canvas, s, start);
        return;
      case EditorTool.blur:
        _drawBlurRect(canvas, s, Rect.fromPoints(start, end).normalized());
        return;
      case EditorTool.pixelate:
        _drawPixelateRect(canvas, s, Rect.fromPoints(start, end).normalized());
        return;
      case EditorTool.smartDelete:
        _drawSmartDeleteRect(canvas, Rect.fromPoints(start, end).normalized(), s.fillColor);
        return;
      case EditorTool.imageElement:
        _drawImageElement(canvas, s, Rect.fromPoints(start, end).normalized());
        return;
      case EditorTool.spotlight:
        _drawDashedRect(canvas, Rect.fromPoints(start, end).normalized(), Colors.white70);
        return;
      default:
        break;
    }

    _drawShape(canvas, s.tool, start, end, s.points, paint, s.color, s.strokeWidth);

    if (s.tool == EditorTool.ruler ||
        s.tool == EditorTool.line ||
        s.tool == EditorTool.sizebox ||
        s.tool == EditorTool.arrow) {
      _paintMeasurement(canvas, s.tool, start, end, s.color);
    }
  }

  void _drawShape(Canvas canvas, EditorTool tool, Offset start, Offset end, List<Offset> points, Paint paint,
      Color color, double sw) {
    switch (tool) {
      case EditorTool.pen:
        if (points.length < 2) return;
        final Path path = Path()..moveTo(points.first.dx, points.first.dy);
        for (int i = 1; i < points.length; i++) {
          path.lineTo(points[i].dx, points[i].dy);
        }
        canvas.drawPath(path, paint);
      case EditorTool.highlight:
        final Paint hp = Paint()
          ..color = color.withValues(alpha: 0.27)
          ..strokeWidth = sw * 16
          ..style = PaintingStyle.stroke
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round;
        if (points.length <= 2) {
          canvas.drawLine(start, end, hp);
        } else {
          final Path p = Path()..moveTo(points.first.dx, points.first.dy);
          for (int i = 1; i < points.length; i++) {
            p.lineTo(points[i].dx, points[i].dy);
          }
          canvas.drawPath(p, hp);
        }
      case EditorTool.line:
        canvas.drawLine(start, end, paint);
      case EditorTool.rect:
      case EditorTool.sizebox:
        canvas.drawRect(Rect.fromPoints(start, end), paint);
      case EditorTool.ellipse:
        canvas.drawOval(Rect.fromPoints(start, end), paint);
      case EditorTool.arrow:
        _drawArrow(canvas, start, end, paint);
      case EditorTool.ruler:
        _drawRuler(canvas, start, end, paint);
      default:
        break;
    }
  }

  void _drawArrow(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final double angle = atan2(end.dy - start.dy, end.dx - start.dx);
    const double headLen = 14.0, headAngle = 0.45;
    canvas.drawLine(
        end, Offset(end.dx - headLen * cos(angle - headAngle), end.dy - headLen * sin(angle - headAngle)), paint);
    canvas.drawLine(
        end, Offset(end.dx - headLen * cos(angle + headAngle), end.dy - headLen * sin(angle + headAngle)), paint);
  }

  void _drawRuler(Canvas canvas, Offset start, Offset end, Paint paint) {
    canvas.drawLine(start, end, paint);
    final double dx = end.dx - start.dx, dy = end.dy - start.dy;
    final double len = sqrt(dx * dx + dy * dy);
    if (len < 1) return;
    final double nx = -dy / len, ny = dx / len;
    const double tick = 6;
    canvas.drawLine(
        Offset(start.dx + nx * tick, start.dy + ny * tick), Offset(start.dx - nx * tick, start.dy - ny * tick), paint);
    canvas.drawLine(
        Offset(end.dx + nx * tick, end.dy + ny * tick), Offset(end.dx - nx * tick, end.dy - ny * tick), paint);
  }

  void _drawText(Canvas canvas, EditorShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    final double fs = s.fontSize ?? (s.strokeWidth * 8 + 12);
    final Color tc = s.textColor ?? s.color;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: _textStyleForShape(s, color: tc, fontSize: fs),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    if (s.textBackground) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(pos.dx - 4, pos.dy - 2, tp.width + 8, tp.height + 4), const Radius.circular(4)),
        Paint()..color = Colors.black.withValues(alpha: 0.72),
      );
    }
    tp.paint(canvas, pos);
  }

  void _drawEmoji(Canvas canvas, EditorShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: TextStyle(fontSize: s.fontSize ?? 32),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos);
  }

  TextStyle _textStyleForShape(EditorShape shape, {required Color color, required double fontSize}) {
    if (shape.tool == EditorTool.emoji) {
      return TextStyle(fontSize: fontSize);
    }
    final String? family = shape.fontFamily;
    return TextStyle(
      color: color,
      fontSize: fontSize,
      fontWeight: FontWeight.bold,
      fontFamily: family == null ? null : GoogleFonts.getFont(family).fontFamily,
    );
  }

  void _drawInfoBalloon(Canvas canvas, EditorShape s, Offset pos) {
    if (s.text == null || s.text!.isEmpty) return;
    const double padding = 10, tailH = 14, radius = 8;
    final double fontSize = s.fontSize ?? (s.strokeWidth * 6 + 12);
    final TextPainter tp = TextPainter(
      text: TextSpan(
        text: s.text,
        style: _textStyleForShape(s, color: Colors.white, fontSize: fontSize),
      ),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: 280);
    final double bw = tp.width + padding * 2, bh = tp.height + padding * 2;
    final Rect bubble = Rect.fromLTWH(pos.dx - bw / 2, pos.dy - bh - tailH, bw, bh);
    final Path path = Path()
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

  void _drawStepCounter(Canvas canvas, EditorShape s, Offset pos) {
    const double r = 14;
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
          text: '${s.stepNumber ?? 1}',
          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, pos - Offset(tp.width / 2, tp.height / 2));
  }

  Rect _imageBounds() {
    final ui.Image? image = backgroundImage;
    if (image == null) return Rect.zero;
    return Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
  }

  void _drawBlurRect(Canvas canvas, EditorShape shape, Rect rect) {
    final ui.Image? image = shapeImages[shape.id];
    final Rect clipped = rect.intersect(_imageBounds());
    if (image == null || clipped.isEmpty) {
      canvas.drawRect(rect, Paint()..color = Colors.white12);
      // _drawDashedRect(canvas, rect, Colors.white54);
      return;
    }

    canvas.save();
    canvas.clipRect(clipped);
    canvas.saveLayer(
      clipped.inflate(24),
      Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 12, sigmaY: 12),
    );
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      clipped.inflate(16),
      Paint()..filterQuality = FilterQuality.high,
    );
    canvas.restore();
    canvas.drawRect(clipped, Paint()..color = Colors.white.withValues(alpha: 0.10));
    canvas.restore();
    // _drawDashedRect(canvas, clipped, Colors.white54);
  }

  void _drawPixelateRect(Canvas canvas, EditorShape shape, Rect rect) {
    final Rect clipped = rect.intersect(_imageBounds());
    if (clipped.isEmpty) {
      _drawDashedRect(canvas, rect, Colors.orangeAccent);
      return;
    }
    _paintPixelatedRgba(canvas, clipped, shape.imageBytes, shape.imageW, shape.imageH, blockSize: 14);
    // _drawDashedRect(canvas, clipped, Colors.white54);
  }

  void _drawSmartDeleteRect(Canvas canvas, Rect rect, Color? fillColor) {
    canvas.drawRect(rect, Paint()..color = fillColor ?? Colors.white);
    // _drawDashedRect(canvas, rect, Colors.redAccent);
  }

  void _drawImageElement(Canvas canvas, EditorShape shape, Rect rect) {
    final ui.Image? image = shapeImages[shape.id];
    if (image == null) {
      canvas.drawRect(rect, Paint()..color = Colors.white10);
      // _drawDashedRect(canvas, rect, Colors.white54);
      return;
    }
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      rect,
      Paint()..filterQuality = FilterQuality.high,
    );
    if (shape.selected) {
      canvas.drawRect(
        rect,
        Paint()
          ..color = Colors.lightBlueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2,
      );
    }
  }

  void _drawSpotlightRect(Canvas canvas, Rect rect) {
    final ui.Image? image = backgroundImage;
    final Rect full = _imageBounds();
    final Path outside = Path()
      ..addRect(full)
      ..addRect(rect)
      ..fillType = PathFillType.evenOdd;

    if (image != null) {
      canvas.save();
      canvas.clipPath(outside);
      canvas.saveLayer(
        full,
        Paint()..imageFilter = ui.ImageFilter.blur(sigmaX: 14, sigmaY: 14),
      );
      canvas.drawImageRect(
        image,
        Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
        full,
        Paint()..filterQuality = FilterQuality.high,
      );
      canvas.restore();
      canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.28));
      canvas.restore();
    } else {
      canvas.drawPath(outside, Paint()..color = Colors.black.withValues(alpha: 0.45));
    }

    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.55)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  void _drawDashedRect(Canvas canvas, Rect r, Color color) {
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

  void _paintMeasurement(Canvas canvas, EditorTool tool, Offset start, Offset end, Color color) {
    final double dx = end.dx - start.dx, dy = end.dy - start.dy;
    final double dist = sqrt(dx * dx + dy * dy);
    final double angleDeg = atan2(dy, dx) * 180 / pi;
    String label;
    if (tool == EditorTool.sizebox) {
      final Rect r = Rect.fromPoints(start, end);
      label = 'X:${r.left.round()} Y:${r.top.round()} W:${r.width.round()} H:${r.height.round()}';
    } else {
      label = '${dist.round()}px  Δ${dx.round()},${dy.round()}  ${angleDeg.toStringAsFixed(1)}°';
    }
    final Offset mid = Offset((start.dx + end.dx) / 2, (start.dy + end.dy) / 2);
    final TextPainter tp = TextPainter(
      text: TextSpan(
          text: label,
          style: TextStyle(
              color: color,
              fontSize: Design.baseFontSize + 1,
              backgroundColor: Colors.black.withValues(alpha: 0.9),
              fontFamily: 'monospace')),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, Offset(mid.dx - tp.width / 2, mid.dy - 30));
  }

  void _paintGrid(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Design.text.withValues(alpha: 0.08)
      ..strokeWidth = 0.5;
    for (double x = 0; x < size.width; x += 50) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }
    for (double y = 0; y < size.height; y += 50) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }
  }

  @override
  bool shouldRepaint(_EditorPainter old) => true;
}

// ─────────────────────────────────────────────────────────────────────────────
// Editor Toolbar
// ─────────────────────────────────────────────────────────────────────────────

Future<Uint8List?> _renderEditorPngBytes({
  required ui.Image backgroundImage,
  required List<EditorShape> shapes,
  required Map<String, ui.Image> shapeImages,
}) async {
  final int width = backgroundImage.width;
  final int height = backgroundImage.height;
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder, Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()));

  final _EditorPainter painter = _EditorPainter(
    shapes: shapes,
    currentShape: null,
    currentEnd: null,
    backgroundImage: backgroundImage,
    shapeImages: shapeImages,
    gridVisible: false,
    imageRectOverride: Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
  );
  painter.paint(canvas, Size(width.toDouble(), height.toDouble()));

  final ui.Image rendered = await recorder.endRecording().toImage(width, height);
  final ByteData? byteData = await rendered.toByteData(format: ui.ImageByteFormat.png);
  return byteData?.buffer.asUint8List();
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
          final int index = (y * imageW + x) * 4;
          if (index + 3 >= rgba.length) continue;
          r += rgba[index];
          g += rgba[index + 1];
          b += rgba[index + 2];
          a += rgba[index + 3];
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

class _EditorWindowBar extends StatelessWidget {
  const _EditorWindowBar({
    required this.filePath,
    required this.onBack,
    required this.standaloneMode,
    required this.resetState,
    required this.onOpenFile,
  });

  final String filePath;
  final VoidCallback onBack;
  final bool standaloneMode;
  final VoidCallback resetState;
  final VoidCallback onOpenFile;

  @override
  Widget build(BuildContext context) {
    final String fileName = filePath.split(RegExp(r'[\\/]')).last;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onPanStart: (_) => windowManager.startDragging(),
      onDoubleTap: () async {
        final bool maximized = await windowManager.isMaximized();
        if (maximized) {
          await windowManager.unmaximize();
        } else {
          await windowManager.maximize();
        }
        resetState();
      },
      child: Container(
        height: 44,
        decoration: BoxDecoration(
          color: Design.background.lighten(4),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(18)),
          border: Border(bottom: BorderSide(color: Design.text.withValues(alpha: 0.06))),
        ),
        child: Row(
          children: <Widget>[
            if (!standaloneMode)
              IconButton(
                onPressed: onBack,
                tooltip: 'Back to Capture',
                icon: const Icon(Icons.arrow_back_rounded, size: 18),
                color: Design.text.withValues(alpha: 0.7),
              )
            else
              const SizedBox(width: 20),
            Expanded(
              child: Row(
                children: <Widget>[
                  const Icon(Icons.photo_size_select_large_rounded, size: 16, color: Colors.white70),
                  const SizedBox(width: 10),
                  Text(
                    'Photo Editor',
                    style: GoogleFonts.getFont(
                      Design.uiFontFamily,
                      color: Design.text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      fileName,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.getFont(
                        Design.uiFontFamily,
                        color: Design.text.withValues(alpha: 0.4),
                        fontSize: Design.baseFontSize + 1,
                      ),
                    ),
                  ),
                  _WindowBarButton(
                    icon: Icons.folder_open_rounded,
                    tooltip: 'Open Image',
                    onTap: onOpenFile,
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            _WindowBarButton(
              icon: Icons.minimize_rounded,
              tooltip: 'Minimize',
              onTap: () => windowManager.minimize(),
            ),
            _WindowBarButton(
              icon: Icons.crop_square_rounded,
              tooltip: 'Maximize / Restore',
              onTap: () async {
                final bool maximized = await windowManager.isMaximized();
                if (maximized) {
                  await windowManager.unmaximize();
                } else {
                  await windowManager.maximize();
                }
              },
            ),
            _WindowBarButton(
              icon: Icons.close_rounded,
              tooltip: 'Close',
              isClose: true,
              onTap: () => windowManager.close(),
            ),
          ],
        ),
      ),
    );
  }
}

class _WindowBarButton extends StatelessWidget {
  const _WindowBarButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.isClose = false,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool isClose;

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: tooltip,
      preferBelow: true,
      verticalOffset: 0,
      child: InkWell(
        onTap: onTap,
        child: Container(
          width: 46,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isClose ? Colors.redAccent.withValues(alpha: 0.0) : Colors.transparent,
          ),
          child: Icon(icon, size: 18, color: isClose ? Colors.redAccent.shade100 : Design.text.withValues(alpha: 0.7)),
        ),
      ),
    );
  }
}

class _EditorToolbar extends StatelessWidget {
  final EditorController ctrl;
  final VoidCallback onBack;
  final double zoomFactor;
  final VoidCallback onZoomIn;
  final VoidCallback onZoomOut;
  final VoidCallback onResetZoom;

  const _EditorToolbar({
    required this.ctrl,
    required this.onBack,
    required this.zoomFactor,
    required this.onZoomIn,
    required this.onZoomOut,
    required this.onResetZoom,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 52,
      decoration: BoxDecoration(
        color: Design.background.darken(2).withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withValues(alpha: 0.1)),
      ),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _TipBtn(
              icon: Icons.arrow_back,
              tooltip: 'Back to Capture (ESC)',
              onTap: onBack,
            ),
            const Divider(color: Colors.white10, height: 10),
            _EditorToolBtn(Icons.mouse_rounded, EditorTool.select, ctrl, 'Select (S)'),
            const Divider(color: Colors.white10, height: 10),
            _EditorToolBtn(Icons.edit, EditorTool.pen, ctrl, 'Pen (P)'),
            _EditorToolBtn(Icons.highlight, EditorTool.highlight, ctrl, 'Highlight (H)'),
            _EditorToolBtn(Icons.remove, EditorTool.line, ctrl, 'Line (L)'),
            _EditorToolBtn(Icons.crop_square, EditorTool.rect, ctrl, 'Rect (R)'),
            _EditorToolBtn(Icons.circle_outlined, EditorTool.ellipse, ctrl, 'Ellipse (E)'),
            _EditorToolBtn(Icons.arrow_forward, EditorTool.arrow, ctrl, 'Arrow (A)'),
            const Divider(color: Colors.white10, height: 10),
            _EditorToolBtn(Icons.text_fields, EditorTool.text, ctrl, 'Text (T)'),
            _EditorToolBtn(Icons.emoji_emotions_outlined, EditorTool.emoji, ctrl, 'Emoji'),
            _EditorToolBtn(Icons.format_list_numbered, EditorTool.stepCounter, ctrl, 'Step (N)'),
            _EditorToolBtn(Icons.chat_bubble_outline, EditorTool.infoBalloon, ctrl, 'Balloon (I)'),
            const Divider(color: Colors.white10, height: 10),
            _EditorToolBtn(Icons.blur_on, EditorTool.blur, ctrl, 'Blur (F)'),
            _EditorToolBtn(Icons.grid_3x3, EditorTool.pixelate, ctrl, 'Pixelate (X)'),
            _EditorToolBtn(Icons.auto_fix_high, EditorTool.smartDelete, ctrl, 'Smart Delete (D)'),
            _EditorToolBtn(Icons.image_outlined, EditorTool.imageElement, ctrl, 'Image (G)'),
            _EditorToolBtn(Icons.highlight_alt, EditorTool.spotlight, ctrl, 'Spotlight'),
            const Divider(color: Colors.white10, height: 10),
            _EditorToolBtn(Icons.straighten, EditorTool.ruler, ctrl, 'Ruler (M)'),
            _EditorToolBtn(Icons.aspect_ratio, EditorTool.sizebox, ctrl, 'Sizebox (B)'),
            const Divider(color: Colors.white10, height: 10),
            _EditorColorBtn(ctrl),
            _EditorWidthBtn(ctrl),
            const Divider(color: Colors.white10, height: 10),
            _TipBtn(icon: Icons.undo, tooltip: 'Undo (Ctrl+Z)', onTap: ctrl.undo),
            _TipBtn(icon: Icons.redo, tooltip: 'Redo (Ctrl+Y)', onTap: ctrl.redo),
            _TipBtn(icon: Icons.delete_sweep, tooltip: 'Clear All', onTap: ctrl.clearAll),
            _TipBtn(icon: Icons.grid_on, tooltip: 'Toggle Grid', onTap: ctrl.toggleGrid),
            _TipBtn(icon: Icons.exposure_zero, tooltip: 'Reset Steps', onTap: ctrl.resetStepCounter),
            const Divider(color: Colors.white24, height: 10),
            _TipBtn(icon: Icons.zoom_in, tooltip: 'Zoom In', onTap: onZoomIn),
            Text(
              '${(zoomFactor * 100).round()}%',
              style: GoogleFonts.getFont(
                Design.uiFontFamily,
                color: Design.text.withValues(alpha: 0.4),
                fontSize: Design.baseFontSize,
                fontWeight: FontWeight.bold,
              ),
            ),
            _TipBtn(icon: Icons.zoom_out, tooltip: 'Zoom Out', onTap: onZoomOut),
            _TipBtn(icon: Icons.zoom_out_map, tooltip: 'Reset Zoom', onTap: onResetZoom),
          ],
        ),
      ),
    );
  }
}

class _EditorToolBtn extends StatelessWidget {
  final IconData icon;
  final EditorTool tool;
  final EditorController ctrl;
  final String tooltip;

  const _EditorToolBtn(this.icon, this.tool, this.ctrl, this.tooltip);

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
            color: active ? Design.accent : Design.text.withValues(alpha: 0.7),
            onPressed: () => ctrl.setTool(tool),
            padding: const EdgeInsets.all(6),
            constraints: const BoxConstraints(),
          ),
        );
      },
    );
  }
}

class _TipBtn extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  const _TipBtn({required this.icon, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return CustomTooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, size: 18),
        color: Design.text.withValues(alpha: 0.7),
        onPressed: onTap,
        padding: const EdgeInsets.all(6),
        constraints: const BoxConstraints(),
      ),
    );
  }
}

// Color picker popup button
class _EditorColorBtn extends StatefulWidget {
  final EditorController ctrl;
  const _EditorColorBtn(this.ctrl);
  @override
  State<_EditorColorBtn> createState() => _EditorColorBtnState();
}

class _EditorColorBtnState extends State<_EditorColorBtn> {
  Timer? _closeTimer;
  OverlayEntry? _overlay;
  final LayerLink _link = LayerLink();

  void _show() {
    _closeTimer?.cancel();
    if (_overlay != null) return;
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 420,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(42, -4),
          child: MouseRegion(
            onEnter: (_) => _show(),
            onExit: (_) => _scheduleHide(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: <Widget>[
                    ..._Palette.colors.map((ui.Color c) => GestureDetector(
                          onTap: () {
                            widget.ctrl.setColor(c);
                            _hide();
                          },
                          child: ListenableBuilder(
                            listenable: widget.ctrl,
                            builder: (_, __) => Container(
                              width: 24,
                              height: 24,
                              decoration: BoxDecoration(
                                color: c,
                                shape: BoxShape.circle,
                                border: widget.ctrl.strokeColor == c
                                    ? Border.all(color: Colors.white, width: 2.5)
                                    : Border.all(color: Colors.white24),
                              ),
                            ),
                          ),
                        )),
                    CustomColorPicker(
                      startColor: widget.ctrl.strokeColor,
                      themeOptions: <List<int>>[<int>[]],
                      colorIndex: 0,
                      onColorChanged: (Color color) {
                        widget.ctrl.setColor(color);
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _scheduleHide() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 220), _hide);
  }

  void _hide() {
    _closeTimer?.cancel();
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
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
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(vertical: 2),
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

// Width popup button
class _EditorWidthBtn extends StatefulWidget {
  final EditorController ctrl;
  const _EditorWidthBtn(this.ctrl);
  @override
  State<_EditorWidthBtn> createState() => _EditorWidthBtnState();
}

class _EditorWidthBtnState extends State<_EditorWidthBtn> {
  Timer? _closeTimer;
  OverlayEntry? _overlay;
  final LayerLink _link = LayerLink();
  static const List<double> _widths = <double>[1, 2, 4, 8];

  void _show() {
    _closeTimer?.cancel();
    if (_overlay != null) return;
    _overlay = OverlayEntry(
      builder: (_) => Positioned(
        width: 200,
        child: CompositedTransformFollower(
          link: _link,
          showWhenUnlinked: false,
          offset: const Offset(42, -4),
          child: MouseRegion(
            onEnter: (_) => _show(),
            onExit: (_) => _scheduleHide(),
            child: Material(
              color: Colors.transparent,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.88),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.white24),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: _widths
                      .map((double w) => GestureDetector(
                            onTap: () {
                              widget.ctrl.setStrokeWidth(w);
                              _hide();
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
    Overlay.of(context).insert(_overlay!);
  }

  void _scheduleHide() {
    _closeTimer?.cancel();
    _closeTimer = Timer(const Duration(milliseconds: 220), _hide);
  }

  void _hide() {
    _closeTimer?.cancel();
    _overlay?.remove();
    _overlay = null;
  }

  @override
  void dispose() {
    _hide();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _link,
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
              alignment: Alignment.center,
              margin: const EdgeInsets.symmetric(vertical: 2),
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

// ─────────────────────────────────────────────────────────────────────────────
// Save / Export button (bottom right)
// ─────────────────────────────────────────────────────────────────────────────

class _SaveButton extends StatefulWidget {
  final EditorController ctrl;
  final ui.Image? backgroundImage;
  final String filePath;
  final Map<String, ui.Image> shapeImages;
  final Future<void> Function() onCaptureMore;
  final bool captureMoreBusy;
  final List<String> presetNames;
  final String? value;
  final bool busy;
  final Function(String? e) onPresetChanged;
  final bool showScreenCaptureActions;
  final VoidCallback onNewCapture;

  const _SaveButton({
    required this.ctrl,
    required this.backgroundImage,
    required this.filePath,
    required this.shapeImages,
    required this.onCaptureMore,
    required this.captureMoreBusy,
    required this.presetNames,
    required this.value,
    required this.busy,
    required this.onPresetChanged,
    required this.showScreenCaptureActions,
    required this.onNewCapture,
  });

  @override
  State<_SaveButton> createState() => _SaveButtonState();
}

class _SaveButtonState extends State<_SaveButton> {
  bool _saving = false;
  String? _msg;

  Future<Uint8List?> _renderEditedPng() async {
    final ui.Image? backgroundImage = widget.backgroundImage;
    if (backgroundImage == null) return null;
    return _renderEditorPngBytes(
      backgroundImage: backgroundImage,
      shapes: widget.ctrl.shapes,
      shapeImages: widget.shapeImages,
    );
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final Uint8List? pngBytes = await _renderEditedPng();
      if (pngBytes == null) return;
      final String savedPath = await ScreenCapture.saveToFile(pngBytes);
      if (mounted) {
        setState(() {
          _msg = 'Saved to $savedPath';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  Future<void> _copyToClipboard() async {
    setState(() {
      _saving = true;
      _msg = null;
    });
    try {
      final Uint8List? pngBytes = await _renderEditedPng();
      if (pngBytes == null) return;
      await ScreenCapture.copyPngToClipboard(pngBytes);
      if (mounted) {
        setState(() {
          _msg = 'Copied to clipboard';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _msg = 'Error: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: <Widget>[
        if (_msg != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black87,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(_msg!, style: TextStyle(color: Colors.greenAccent, fontSize: Design.baseFontSize + 2)),
          ),
        Row(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              width: 150,
              child: _EditorPresetButton(
                presetNames: widget.presetNames,
                presetValue: widget.value,
                busy: widget.busy,
                onChanged: (String? e) => widget.onPresetChanged(e),
              ),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Design.accent,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _saving ? null : _save,
              icon: _saving
                  ? const SizedBox(
                      width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.save_alt, size: 18),
              label: Text(_saving ? 'Saving…' : 'Save Edited'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: _saving ? null : _copyToClipboard,
              icon: const Icon(Icons.copy, size: 18),
              label: const Text('Copy to clipboard'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: widget.captureMoreBusy ? null : widget.onCaptureMore,
              icon: widget.captureMoreBusy
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.add_photo_alternate_outlined, size: 18),
              label: Text(widget.captureMoreBusy ? 'Capturing…' : 'Capture More'),
            ),
            const SizedBox(width: 10),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white12,
                foregroundColor: Colors.white70,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              onPressed: widget.onNewCapture,
              icon: const Icon(Icons.camera_alt_outlined, size: 18),
              label: const Text('New Capture'),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditorPresetButton extends StatelessWidget {
  const _EditorPresetButton({
    required this.presetNames,
    required this.presetValue,
    required this.busy,
    required this.onChanged,
  });

  final List<String> presetNames;
  final String? presetValue;
  final bool busy;
  final ValueChanged<String?> onChanged;

  @override
  Widget build(BuildContext context) {
    final String label = presetValue ?? 'Original';

    return Material(
      type: MaterialType.transparency,
      child: PopupMenuButton<String?>(
        tooltip: 'Apply FancyShot preset',
        enabled: !busy,
        color: const Color(0xFF121826),
        elevation: 12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: const BorderSide(color: Colors.white24),
        ),
        onSelected: onChanged,
        itemBuilder: (BuildContext context) => <PopupMenuEntry<String?>>[
          const PopupMenuItem<String?>(
            value: 'none',
            child: _PresetMenuRow(
              icon: Icons.image_outlined,
              title: 'Original',
              subtitle: 'Use the original captured image',
            ),
          ),
          ...presetNames.map(
            (String presetName) => PopupMenuItem<String?>(
              value: presetName,
              child: _PresetMenuRow(
                icon: Icons.auto_awesome,
                title: presetName,
                subtitle: 'Apply to the original capture',
              ),
            ),
          ),
        ],
        child: Container(
          // constraints: const BoxConstraints(minWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: 0.72),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: Colors.white24),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Expanded(
                child: Text(
                  busy ? 'Applying…' : label,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ),
              const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}

class _PresetMenuRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _PresetMenuRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            color: Colors.white10,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 18, color: Colors.white70),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Text(
                title,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(color: Colors.white54, fontSize: Design.baseFontSize + 1),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _StandalonePhotoEditorApp extends StatelessWidget {
  const _StandalonePhotoEditorApp({
    required this.filePath,
    this.initialImageBytes,
    this.imageW,
    this.imageH,
  });

  final String filePath;
  final Uint8List? initialImageBytes;
  final int? imageW;
  final int? imageH;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(),
      home: Scaffold(
        backgroundColor: Colors.transparent,
        body: PhotoEditorView(
          initialImageBytes: initialImageBytes,
          imageW: imageW,
          imageH: imageH,
          filePath: filePath,
          standaloneMode: true,
          onBack: () => windowManager.close(),
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
