// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dropdown_button2/dropdown_button2.dart';
import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as img;
import 'package:screenshot/screenshot.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:vector_math/vector_math_64.dart' show Vector3;
import 'package:win32/win32.dart';

import '../../models/classes/boxes.dart';
import '../../models/settings.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/mouse_scroll_widget.dart';

class Fancyshot extends StatefulWidget {
  const Fancyshot({super.key});
  @override
  FancyshotState createState() => FancyshotState();
}

class FancyshotState extends State<Fancyshot> {
  final List<List<double>> aspectRatioList = <List<double>>[
    <double>[1, 1],
    <double>[3 / 2, 2 / 3],
    <double>[4 / 3, 3 / 4],
    <double>[16 / 9, 9 / 16]
  ];
  final FancyShotProfile defaultProfile = FancyShotProfile(
    name: "Default",
    backgroundPadding: 10,
    imagePadding: 0,
    backgroundType: BackgroundType.transparent,
    backgroundImage: "resources/gradient/gradient1.jpg",
    borderRadius: 5,
    shadowSpread: 1,
    shadowRadius: 1,
    backgroundBlur: 0,
    background: 0,
    aspectRatio: 0,
    width: 0,
    height: 0,
    watermark: "",
  );
  late FancyShotProfile filters;

  Uint8List? capture;
  Color? bgColor;
  // final List<String> profiles = <String>[""];
  final List<FancyShotProfile> profiles =
      Boxes.getSavedMap<FancyShotProfile>(FancyShotProfile.fromJson, "fancyShotProfile", def: <FancyShotProfile>[
    FancyShotProfile(
      name: "Default",
      backgroundPadding: 10,
      imagePadding: 0,
      backgroundType: BackgroundType.transparent,
      backgroundImage: "resources/gradient/gradient1.jpg",
      borderRadius: 5,
      shadowSpread: 1,
      shadowRadius: 1,
      backgroundBlur: 0,
      background: 0,
      aspectRatio: 0,
      width: 0,
      height: 0,
      watermark: "",
    ),
    FancyShotProfile(
      name: "Self Background",
      backgroundPadding: 16,
      imagePadding: 7.5,
      backgroundType: BackgroundType.self,
      backgroundImage: "resources/gradient/gradient1.jpg",
      borderRadius: 8,
      shadowSpread: 3,
      shadowRadius: 6,
      backgroundBlur: 8,
      background: 0,
      aspectRatio: 0,
      width: 0,
      height: 0,
      watermark: "",
    ),
    FancyShotProfile(
      name: "Image Background",
      backgroundPadding: 28,
      imagePadding: 7.5,
      backgroundType: BackgroundType.stock,
      backgroundImage: "resources/gradient/gradient7.jpg",
      borderRadius: 5,
      shadowSpread: 3,
      shadowRadius: 6,
      backgroundBlur: 18,
      background: 0,
      aspectRatio: 0,
      width: 0,
      height: 0,
      watermark: "",
    )
  ]);
  final List<String> profilesName = <String>[""];
  int aspectRatio = 0;
  String? selectedProfile;
  final TextEditingController textEditingController = TextEditingController();
  final ScrollController bottomScrollController = ScrollController();

  bool capturing = false;

  TextEditingController watermarkTextController = TextEditingController();
  TextEditingController skewPerspectiveController = TextEditingController();

  bool closeOnAction = true;

  String copyMessage = "Copy";
  final WinClipboard winClipboard = WinClipboard();
  bool _isOverVerticalGrid = false;
  @override
  void initState() {
    super.initState();
    initializeGDI();
    filters = defaultProfile.copyWith();
    if (profiles.isEmpty) profiles.add(defaultProfile);
    profilesName.addAll(profiles.map((FancyShotProfile e) => e.name));
    String? profile = Boxes.pref.getString("fancyshot");
    profile ??= "Default";
    final int i = profiles.indexWhere((FancyShotProfile element) => element.name == profile);
    if (i >= 0) {
      selectedProfile = profile;
      filters = profiles[i].copyWith();
      watermarkTextController.text = filters.watermark;
      skewPerspectiveController.text = filters.skewPerspective.toString();
    }

    if (profilesName.length > 1) profilesName.remove("");
    loadCaptureFile();
  }

  @override
  void dispose() {
    textEditingController.dispose();
    watermarkTextController.dispose();
    skewPerspectiveController.dispose();
    bottomScrollController.dispose();
    super.dispose();
  }

  img.Image? photo;
  void loadCaptureFile() async {
    final String temp = WinUtils.getTempFolder();
    if (File("$temp\\capture.png").existsSync()) {
      capture = File("$temp\\capture.png").readAsBytesSync();
      photo = img.decodeImage(capture!);
      final img.Pixel pixel32 = photo!.getPixelSafe(0, 0);
      int hex =
          abgrToArgb(pixel32.a.toInt() << 24 | pixel32.r.toInt() << 16 | pixel32.g.toInt() << 8 | pixel32.b.toInt());
      bgColor = Color(hex);
    } else {
      capture = null;
    }
  }

  int abgrToArgb(int argbColor) {
    int r = (argbColor >> 16) & 0xFF;
    int b = argbColor & 0xFF;
    return (argbColor & 0xFF00FF00) | (b << 16) | r;
  }

  bool get hasCapture => capture != null && photo != null;

  Future<void> _captureScreen() async {
    await WinUtils.screenCapture();
    capture = null;
    setState(() {});
    loadCaptureFile();
    if (mounted) setState(() {});
  }

  ScreenshotController screenshotController = ScreenshotController();

  Future<void> _saveCapture() async {
    if (!hasCapture) return;
    setState(() => capturing = true);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    try {
      await screenshotController.captureAndSave('${WinUtils.getTabameAppDataFolder()}/fancyshot');
      WinUtils.open('${WinUtils.getTabameAppDataFolder()}/fancyshot');
      if (globalSettings.args.contains("-fancyshot") && closeOnAction) {
        exit(0);
      }
    } finally {
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () => mounted ? setState(() => capturing = false) : null,
      );
    }
  }

  Future<void> _copyCapture() async {
    if (!hasCapture) return;
    setState(() => capturing = true);
    await Future<void>.delayed(const Duration(milliseconds: 16));
    try {
      final String? filename =
          (await screenshotController.captureAndSave('${WinUtils.getTabameAppDataFolder()}/fancyshot'))
              ?.replaceAll('/', r'\');
      if (filename == null) return;
      await winClipboard.copyImageToClipboard(filename);
      if (globalSettings.args.contains("-fancyshot") && closeOnAction) {
        exit(0);
      }
      setState(() => copyMessage = "Copied!");
      Future<void>.delayed(
        const Duration(seconds: 1),
        () => mounted ? setState(() => copyMessage = "Copy") : null,
      );
    } finally {
      Future<void>.delayed(
        const Duration(milliseconds: 50),
        () => mounted ? setState(() => capturing = false) : null,
      );
    }
  }

  void _deleteSelectedProfile() {
    if (selectedProfile == null || selectedProfile == "Default") return;
    profiles.removeWhere((FancyShotProfile e) => e.name == selectedProfile);
    profilesName.removeWhere((String element) => element == selectedProfile);
    Boxes.updateSettings("fancyShotProfile", jsonEncode(profiles));

    final int defaultIndex = profiles.indexWhere((FancyShotProfile element) => element.name == "Default");
    if (defaultIndex >= 0) {
      selectedProfile = "Default";
      filters = profiles[defaultIndex].copyWith();
      watermarkTextController.text = filters.watermark;
      skewPerspectiveController.text = filters.skewPerspective.toString();
      Boxes.pref.setString("fancyshot", "Default");
    } else {
      selectedProfile = null;
    }
    if (profilesName.isEmpty) profilesName.add("");
    setState(() {});
  }

  void _selectProfile(String? value) {
    if (value == null) return;
    final int i = profiles.indexWhere((FancyShotProfile element) => element.name == value);
    if (i < 0) return;
    selectedProfile = value;
    filters = profiles[i].copyWith();
    watermarkTextController.text = filters.watermark;
    skewPerspectiveController.text = filters.skewPerspective.toString();
    Boxes.pref.setString("fancyshot", value);
    setState(() {});
  }

  void _createProfile(String? newValue) {
    if (newValue == null) return;
    final String profileName = newValue.trim();
    if (profileName.isEmpty) return;

    final int existingIndex =
        profiles.indexWhere((FancyShotProfile element) => element.name.toLowerCase() == profileName.toLowerCase());
    if (existingIndex >= 0) {
      _selectProfile(profiles[existingIndex].name);
      textEditingController.clear();
      return;
    }

    profiles.add(filters.copyWith(name: profileName));
    profilesName.add(profileName);
    if (profilesName.contains("")) profilesName.remove("");
    Boxes.updateSettings("fancyShotProfile", jsonEncode(profiles));
    Boxes.pref.setString("fancyshot", profileName);
    textEditingController.clear();
    selectedProfile = profileName;
    setState(() {});
  }

  void _pickCustomBackground() {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{'PNG Image (*.png)': '*.png'}
      ..defaultFilterIndex = 0
      ..defaultExtension = 'png'
      ..title = 'Select an image';

    final File? result = file.getFile();
    if (result == null) return;

    filters.backgroundType = BackgroundType.custom;
    filters.backgroundImage = result.path;
    setState(() {});
  }

  BoxDecoration _previewBackgroundDecoration() {
    switch (filters.backgroundType) {
      case BackgroundType.stock:
        return BoxDecoration(
          image: DecorationImage(
            image: AssetImage(filters.backgroundImage),
            fit: BoxFit.cover,
          ),
        );
      case BackgroundType.self:
        return BoxDecoration(
          image: DecorationImage(
            image: MemoryImage(capture!),
            fit: BoxFit.cover,
          ),
        );
      case BackgroundType.custom:
        return BoxDecoration(
          image: File(filters.backgroundImage).existsSync()
              ? DecorationImage(
                  image: FileImage(File(filters.backgroundImage)),
                  fit: BoxFit.cover,
                )
              : null,
        );
      case BackgroundType.transparent:
        return const BoxDecoration(color: Colors.transparent);
    }
  }

  Widget _buildPreviewCanvas() {
    if (!hasCapture) return const SizedBox.shrink();

    return Screenshot(
      controller: screenshotController,
      child: Material(
        type: MaterialType.transparency,
        child: ClipRect(
          child: Stack(
            children: <Widget>[
              if (!capturing)
                Positioned.fill(
                  child: Container(
                    color: globalSettings.themeTypeMode == ThemeType.dark ? Colors.white : const Color(0xFF1E1E1E),
                  ),
                ),
              Container(
                padding: EdgeInsets.all(filters.backgroundPadding.ceil().toDouble()),
                decoration: _previewBackgroundDecoration(),
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: filters.backgroundBlur,
                    sigmaY: filters.backgroundBlur,
                  ),
                  child: Transform(
                    transform: filters.skewX != 0 && filters.skewY != 0
                        ? (Matrix4.identity()
                          ..scaledByVector3(Vector3.all(0.1))
                          ..setEntry(3, 2, filters.skewPerspective)
                          ..rotateX(0.1 * filters.skewY)
                          ..rotateY(-0.1 * filters.skewX))
                        : Matrix4.identity(),
                    filterQuality: FilterQuality.high,
                    alignment: Alignment.center,
                    child: Padding(
                      padding: EdgeInsets.all(filters.watermark.isNotEmpty ? 20 : 0),
                      child: Container(
                        constraints: capturing ? null : const BoxConstraints(maxHeight: 400, maxWidth: 500),
                        child: FittedBox(
                          alignment: Alignment.center,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: <Widget>[
                              IntrinsicWidth(
                                child: Container(
                                  decoration: BoxDecoration(
                                    color: filters.showBrowserFrame
                                        ? const Color(0xFFEBEBEB)
                                        : bgColor, // macOS light grey or match existing bg
                                    borderRadius: BorderRadius.all(Radius.circular(filters.borderRadius)),
                                    boxShadow: filters.shadowRadius != 0 && filters.shadowSpread != 0
                                        ? <BoxShadow>[
                                            BoxShadow(
                                              offset: const Offset(3, 3),
                                              spreadRadius: filters.shadowSpread,
                                              blurRadius: filters.shadowRadius,
                                              color: const Color.fromRGBO(0, 0, 0, 0.5),
                                            ),
                                          ]
                                        : null,
                                  ),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: <Widget>[
                                      if (filters.showBrowserFrame)
                                        Container(
                                          height: 32,
                                          padding: const EdgeInsets.symmetric(horizontal: 14),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFEBEBEB),
                                            borderRadius: BorderRadius.only(
                                              topLeft: Radius.circular(filters.borderRadius),
                                              topRight: Radius.circular(filters.borderRadius),
                                            ),
                                            border: Border(
                                                bottom:
                                                    BorderSide(color: Colors.black.withValues(alpha: 0.05), width: 1)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            crossAxisAlignment: CrossAxisAlignment.center,
                                            children: <Widget>[
                                              Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: const BoxDecoration(
                                                      color: Color(0xFFFF5F56), shape: BoxShape.circle)),
                                              const SizedBox(width: 8),
                                              Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: const BoxDecoration(
                                                      color: Color(0xFFFFBD2E), shape: BoxShape.circle)),
                                              const SizedBox(width: 8),
                                              Container(
                                                  width: 12,
                                                  height: 12,
                                                  decoration: const BoxDecoration(
                                                      color: Color(0xFF27C93F), shape: BoxShape.circle)),
                                              const Spacer(),
                                            ],
                                          ),
                                        ),
                                      Padding(
                                        padding: EdgeInsets.all(filters.imagePadding.ceil().toDouble()),
                                        child: GestureDetector(
                                          onPanUpdate: (DragUpdateDetails details) => setState(() => filters
                                            ..skewX = (filters.skewX + details.delta.dx / (photo!.width / 2))
                                            ..skewY = (filters.skewY + details.delta.dy / (photo!.height / 2))),
                                          onDoubleTap: () => setState(() => filters
                                            ..skewX = 0
                                            ..skewY = 0),
                                          child: ClipRRect(
                                            borderRadius: filters.showBrowserFrame
                                                ? BorderRadius.only(
                                                    bottomLeft: Radius.circular(filters.borderRadius),
                                                    bottomRight: Radius.circular(filters.borderRadius))
                                                : BorderRadius.circular(filters.borderRadius),
                                            child: Image.memory(
                                              capture!,
                                              fit: BoxFit.contain,
                                              width: photo!.width.toDouble(),
                                              height: photo!.height.toDouble(),
                                              filterQuality: FilterQuality.high,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 12,
                                right: 12,
                                child: Transform(
                                  transform: Matrix4.skewX(-0.1),
                                  child: Text(
                                    filters.watermark,
                                    textAlign: TextAlign.right,
                                    style: TextStyle(
                                      fontWeight: FontWeight.w900,
                                      fontSize: 14,
                                      letterSpacing: 0.5,
                                      color: Colors.white.withValues(alpha: 0.9),
                                      shadows: <Shadow>[
                                        Shadow(
                                          blurRadius: 10,
                                          color: Colors.black.withValues(alpha: 0.5),
                                          offset: const Offset(0, 2),
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
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildToolLayout(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Column(
      children: <Widget>[
        // --- Top Bar ---
        Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            color: colorScheme.surface.withValues(alpha: 0.9),
            border: Border(bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08))),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.auto_fix_high_rounded, size: 20, color: colorScheme.primary),
              const SizedBox(width: 12),
              Text(
                "FancyShot".toUpperCase(),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.2,
                  color: colorScheme.onSurface.withValues(alpha: 0.8),
                ),
              ),
              const Spacer(),
              // Profile Selection in Top Bar
              SizedBox(
                width: 200,
                child: DropdownButtonHideUnderline(
                  child: DropdownButton2<String>(
                    isExpanded: true,
                    hint: Text("Select Profile",
                        style: TextStyle(fontSize: 12, color: theme.hintColor, fontWeight: FontWeight.w600)),
                    buttonStyleData: ButtonStyleData(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      height: 34,
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.05)),
                      ),
                    ),
                    dropdownStyleData: DropdownStyleData(
                      maxHeight: 400,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: colorScheme.surface,
                      ),
                      elevation: 8,
                    ),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                    items: profilesName
                        .map((String item) => DropdownMenuItem<String>(
                              value: item,
                              child: Text(item, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                            ))
                        .toList(),
                    value: selectedProfile,
                    onChanged: _selectProfile,
                    dropdownSearchData: DropdownSearchData<String>(
                      searchController: textEditingController,
                      searchInnerWidgetHeight: 50,
                      searchInnerWidget: Padding(
                        padding: const EdgeInsets.all(8),
                        child: TextFormField(
                          controller: textEditingController,
                          style: const TextStyle(fontSize: 12),
                          decoration: InputDecoration(
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            hintText: 'Create new profile...',
                            hintStyle: const TextStyle(fontSize: 11),
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                            fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
                            filled: true,
                          ),
                          onFieldSubmitted: _createProfile,
                        ),
                      ),
                      searchMatchFn: (DropdownMenuItem<dynamic> item, String searchValue) => true,
                    ),
                  ),
                ),
              ),
              if (selectedProfile != null && selectedProfile != "Default") ...<Widget>[
                const SizedBox(width: 8),
                IconButton(
                  iconSize: 18,
                  visualDensity: VisualDensity.compact,
                  tooltip: "Delete profile",
                  onPressed: _deleteSelectedProfile,
                  icon: const Icon(Icons.delete_outline_rounded),
                  style: IconButton.styleFrom(
                    foregroundColor: colorScheme.error,
                    backgroundColor: colorScheme.error.withValues(alpha: 0.05),
                  ),
                ),
              ],
              const VerticalDivider(width: 32, indent: 14, endIndent: 14, thickness: 1),
              IconButton(
                iconSize: 20,
                visualDensity: VisualDensity.compact,
                tooltip: capturing ? "Fit Preview" : "Actual Size",
                onPressed: () => setState(() => capturing = !capturing),
                icon: Icon(capturing ? Icons.fit_screen_rounded : Icons.fullscreen_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: colorScheme.primary.withValues(alpha: 0.05),
                ),
              ),
            ],
          ),
        ),

        // --- Main Content Area ---
        Expanded(
          child: Row(
            children: <Widget>[
              // --- Left Toolbar (Slim) ---
              Container(
                width: 44,
                decoration: BoxDecoration(
                  color: colorScheme.surface,
                  border: Border(right: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1))),
                ),
                child: Column(
                  children: <Widget>[
                    const SizedBox(height: 8),
                    _ToolbarAction(
                      icon: Icons.photo_camera_rounded,
                      tooltip: "Capture Screen",
                      onTap: _captureScreen,
                    ),
                    _ToolbarAction(
                      icon: Icons.save_rounded,
                      tooltip: "Save to File",
                      onTap: hasCapture ? _saveCapture : null,
                    ),
                    _ToolbarAction(
                      icon: Icons.copy_all_rounded,
                      tooltip: copyMessage,
                      onTap: hasCapture ? _copyCapture : null,
                      color: copyMessage == "Copied!" ? Colors.green : null,
                    ),
                    const Divider(height: 16, indent: 8, endIndent: 8),
                    _ToolbarAction(
                      icon: Icons.refresh_rounded,
                      tooltip: "Reset Skew",
                      onTap: () => setState(() => filters
                        ..skewX = 0
                        ..skewY = 0),
                    ),
                    const Spacer(),
                    if (globalSettings.args.contains("-fancyshot"))
                      _ToolbarAction(
                        icon: closeOnAction ? Icons.exit_to_app_rounded : Icons.stay_current_landscape_rounded,
                        tooltip: "Close on action: ${closeOnAction ? 'ON' : 'OFF'}",
                        onTap: () => setState(() => closeOnAction = !closeOnAction),
                        active: closeOnAction,
                      ),
                    const SizedBox(height: 8),
                  ],
                ),
              ),

              // --- Central Canvas ---
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: colorScheme.surfaceContainerLowest),
                  child: Stack(
                    children: <Widget>[
                      Center(
                        child: hasCapture
                            ? MouseScrollWidget(
                                scrollDirection: Axis.horizontal,
                                child: MouseScrollWidget(
                                  scrollDirection: Axis.vertical,
                                  child: Padding(
                                    padding: const EdgeInsets.all(60),
                                    child: _buildPreviewCanvas(),
                                  ),
                                ),
                              )
                            : _buildEmptyState(context),
                      ),
                      if (hasCapture)
                        Positioned(
                          bottom: 16,
                          left: 16,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: colorScheme.surface.withValues(alpha: 0.9),
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(color: colorScheme.outline.withValues(alpha: 0.1)),
                              boxShadow: <BoxShadow>[
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.1),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: <Widget>[
                                Icon(Icons.aspect_ratio_rounded, size: 14, color: colorScheme.primary),
                                const SizedBox(width: 8),
                                Text(
                                  "${photo!.width} × ${photo!.height} PX",
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: colorScheme.onSurface,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // --- Bottom Property Bar ---
        Container(
          height: 220,
          decoration: BoxDecoration(
            color: colorScheme.surface,
            border: Border(top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1))),
          ),
          child: Listener(
            onPointerSignal: (PointerSignalEvent event) {
              if (event is PointerScrollEvent && !_isOverVerticalGrid) {
                final double offset = event.scrollDelta.dy;
                bottomScrollController.jumpTo(
                    (bottomScrollController.offset + offset).clamp(0, bottomScrollController.position.maxScrollExtent));
              }
            },
            child: SingleChildScrollView(
              controller: bottomScrollController,
              scrollDirection: Axis.horizontal,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    SizedBox(
                      width: 220,
                      child: _SidebarSection(
                        title: "LAYOUT",
                        children: <Widget>[
                          _CompactSlider(
                            label: "Background Padding",
                            value: filters.backgroundPadding,
                            min: 10,
                            max: 50,
                            onChanged: (double v) => setState(() => filters.backgroundPadding = v),
                          ),
                          _CompactSlider(
                            label: "Image Padding",
                            value: filters.imagePadding,
                            min: 0,
                            max: 50,
                            onChanged: (double v) => setState(() => filters.imagePadding = v),
                          ),
                          _CompactSlider(
                            label: "Radius",
                            value: filters.borderRadius,
                            min: 0,
                            max: 20,
                            onChanged: (double v) => setState(() => filters.borderRadius = v),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 32, indent: 8, endIndent: 8),
                    SizedBox(
                      width: 220,
                      child: _SidebarSection(
                        title: "EFFECTS",
                        children: <Widget>[
                          _CompactSlider(
                            label: "Shadow Radius",
                            value: filters.shadowRadius,
                            max: 10,
                            onChanged: (double v) {
                              filters.shadowRadius = v;
                              if (v > 0 && filters.shadowSpread == 0) filters.shadowSpread = 1;
                              if (v == 0) filters.shadowSpread = 0;
                              setState(() {});
                            },
                          ),
                          _CompactSlider(
                            label: "Shadow Spread",
                            value: filters.shadowSpread,
                            max: 10,
                            onChanged: (double v) {
                              filters.shadowSpread = v;
                              if (v > 0 && filters.shadowRadius == 0) filters.shadowRadius = 1;
                              if (v == 0) filters.shadowRadius = 0;
                              setState(() {});
                            },
                          ),
                          _CompactSlider(
                            label: "Blur",
                            value: filters.backgroundBlur,
                            max: 20,
                            onChanged: (double v) => setState(() => filters.backgroundBlur = v),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 32, indent: 8, endIndent: 8),
                    SizedBox(
                      width: 200,
                      child: _SidebarSection(
                        title: "DECORATION",
                        children: <Widget>[
                          _CompactTextField(
                            label: "Watermark",
                            controller: watermarkTextController,
                            hint: "Text...",
                            onChanged: (String v) => setState(() => filters.watermark = v),
                          ),
                          const SizedBox(height: 12),
                          _CompactTextField(
                            label: "Perspective",
                            controller: skewPerspectiveController,
                            hint: "0.001",
                            onChanged: (String v) => setState(() => filters.skewPerspective = double.tryParse(v) ?? 0),
                          ),
                        ],
                      ),
                    ),
                    const VerticalDivider(width: 32, indent: 8, endIndent: 8),
                    SizedBox(
                      width: 320,
                      child: _SidebarSection(
                        title: "BACKGROUND",
                        children: <Widget>[
                          _BackgroundGrid(
                            filters: filters,
                            capture: capture,
                            onBackgroundChanged: (BackgroundType type, String? image) {
                              setState(() {
                                filters.backgroundType = type;
                                if (image != null) filters.backgroundImage = image;
                              });
                            },
                            onPickCustom: _pickCustomBackground,
                            onHover: (bool hovered) => setState(() => _isOverVerticalGrid = hovered),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: <Widget>[
        Icon(Icons.add_photo_alternate_outlined, size: 48, color: colorScheme.primary.withValues(alpha: 0.5)),
        const SizedBox(height: 16),
        Text(
          "No capture loaded",
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.6),
                fontWeight: FontWeight.w600,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          "Click the camera icon on the left to start",
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface.withValues(alpha: 0.4),
              ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return _buildToolLayout(context);
  }
}

class _ToolbarAction extends StatefulWidget {
  const _ToolbarAction({
    required this.icon,
    required this.tooltip,
    this.onTap,
    this.active = false,
    this.color,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final bool active;
  final Color? color;

  @override
  State<_ToolbarAction> createState() => _ToolbarActionState();
}

class _ToolbarActionState extends State<_ToolbarAction> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isHovered = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
    _scaleAnimation =
        Tween<double>(begin: 1.0, end: 1.1).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) {
        setState(() => _isHovered = true);
        _controller.forward();
      },
      onExit: (_) {
        setState(() => _isHovered = false);
        _controller.reverse();
      },
      child: CustomTooltip(
        message: widget.tooltip,
        child: ScaleTransition(
          scale: _scaleAnimation,
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 4),
            child: IconButton(
              onPressed: widget.onTap,
              icon: Icon(
                widget.icon,
                size: 20,
                color: widget.color ??
                    (widget.active || _isHovered ? colorScheme.primary : colorScheme.onSurface.withValues(alpha: 0.6)),
              ),
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                backgroundColor: widget.active
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : _isHovered
                        ? colorScheme.primary.withValues(alpha: 0.05)
                        : Colors.transparent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SidebarSection extends StatelessWidget {
  const _SidebarSection({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          title,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.2,
                color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
              ),
        ),
        const SizedBox(height: 12),
        ...children,
      ],
    );
  }
}

class _CompactSlider extends StatelessWidget {
  const _CompactSlider({
    required this.label,
    required this.value,
    this.min = 0,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final double max;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Text(
                label.toUpperCase(),
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: colorScheme.onSurface.withValues(alpha: 0.6),
                ),
              ),
              Text(
                value.toStringAsFixed(0),
                style: TextStyle(
                  fontSize: 10,
                  color: colorScheme.primary,
                  fontWeight: FontWeight.w900,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 4),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6, elevation: 2),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: colorScheme.primary,
            inactiveTrackColor: colorScheme.primary.withValues(alpha: 0.1),
            thumbColor: colorScheme.primary,
            trackShape: const RectangularSliderTrackShape(),
          ),
          child: Slider(
            value: value,
            min: min,
            max: max,
            onChanged: onChanged,
          ),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _CompactTextField extends StatelessWidget {
  const _CompactTextField({
    required this.label,
    required this.controller,
    required this.hint,
    required this.onChanged,
  });

  final String label;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: Text(
            label.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: colorScheme.onSurface.withValues(alpha: 0.6),
            ),
          ),
        ),
        const SizedBox(height: 6),
        SizedBox(
          height: 36,
          child: TextField(
            controller: controller,
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
            decoration: InputDecoration(
              isDense: true,
              hintText: hint,
              hintStyle: TextStyle(fontSize: 11, color: colorScheme.onSurface.withValues(alpha: 0.3)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.1)),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide(color: colorScheme.primary.withValues(alpha: 0.5)),
              ),
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              filled: true,
            ),
            onChanged: onChanged,
          ),
        ),
      ],
    );
  }
}

class _BackgroundGrid extends StatelessWidget {
  const _BackgroundGrid({
    required this.filters,
    this.capture,
    required this.onBackgroundChanged,
    required this.onPickCustom,
    required this.onHover,
  });

  final FancyShotProfile filters;
  final Uint8List? capture;
  final Function(BackgroundType, String?) onBackgroundChanged;
  final VoidCallback onPickCustom;
  final ValueChanged<bool> onHover;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => onHover(true),
      onExit: (_) => onHover(false),
      child: SizedBox(
        height: 150,
        child: GridView.count(
          crossAxisCount: 3,
          mainAxisSpacing: 8,
          crossAxisSpacing: 8,
          children: <Widget>[
            // Transparent
            _BgTile(
              selected: filters.backgroundType == BackgroundType.transparent,
              onTap: () => onBackgroundChanged(BackgroundType.transparent, null),
              child: const Icon(Icons.layers_clear_rounded, size: 20),
            ),
            // Custom
            _BgTile(
              selected: filters.backgroundType == BackgroundType.custom,
              onTap: onPickCustom,
              child: filters.backgroundType == BackgroundType.custom && File(filters.backgroundImage).existsSync()
                  ? Image.file(File(filters.backgroundImage), fit: BoxFit.cover)
                  : const Icon(Icons.add_photo_alternate_rounded, size: 20),
            ),
            // Capture
            if (capture != null)
              _BgTile(
                selected: filters.backgroundType == BackgroundType.self,
                onTap: () => onBackgroundChanged(BackgroundType.self, null),
                child: Image.memory(capture!, fit: BoxFit.cover),
              ),
            // Gradients
            ...List<Widget>.generate(10, (int i) {
              final String path = "resources/gradient/gradient$i.jpg";
              return _BgTile(
                selected: filters.backgroundType == BackgroundType.stock && filters.backgroundImage == path,
                onTap: () => onBackgroundChanged(BackgroundType.stock, path),
                child: Image.asset(path, fit: BoxFit.cover),
              );
            }),
          ],
        ),
      ),
    );
  }
}

class _BgTile extends StatefulWidget {
  const _BgTile({required this.selected, required this.onTap, required this.child});

  final bool selected;
  final VoidCallback onTap;
  final Widget child;

  @override
  State<_BgTile> createState() => _BgTileState();
}

class _BgTileState extends State<_BgTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: widget.selected
                  ? colorScheme.primary
                  : _isHovered
                      ? colorScheme.primary.withValues(alpha: 0.5)
                      : colorScheme.outline.withValues(alpha: 0.1),
              width: widget.selected ? 2 : 1,
            ),
            boxShadow: widget.selected
                ? <BoxShadow>[
                    BoxShadow(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          clipBehavior: Clip.antiAlias,
          child: widget.child,
        ),
      ),
    );
  }
}

enum BackgroundType {
  transparent,
  self,
  custom,
  stock,
}

class FancyShotProfile {
  String name;
  double backgroundPadding = 10;
  double imagePadding = 10;
  //enum
  BackgroundType backgroundType = BackgroundType.transparent;
  String backgroundImage = "resources/gradient/gradient1.jpg";
  double borderRadius = 10;
  double shadowSpread = 0;
  double shadowRadius = 0;
  double backgroundBlur = 0;
  double skewX = 0;
  double skewY = 0;
  double skewPerspective = 0;
  int background = 0;
  int aspectRatio = 0;
  String watermark = "";
  bool showBrowserFrame = false;
  int width = 0;
  int height = 0;
  FancyShotProfile({
    required this.name,
    this.backgroundPadding = 10,
    this.imagePadding = 10,
    this.backgroundType = BackgroundType.transparent,
    this.backgroundImage = "resources/gradient/gradient1.jpg",
    this.borderRadius = 10,
    this.shadowSpread = 0,
    this.shadowRadius = 0,
    this.backgroundBlur = 0,
    this.skewX = 0,
    this.skewY = 0,
    this.skewPerspective = 0,
    this.background = 0,
    this.aspectRatio = 0,
    this.watermark = "",
    this.showBrowserFrame = false,
    this.width = 0,
    this.height = 0,
  });

  FancyShotProfile copyWith({
    String? name,
    double? backgroundPadding,
    double? imagePadding,
    BackgroundType? backgroundType,
    String? backgroundImage,
    double? borderRadius,
    double? shadowSpread,
    double? shadowRadius,
    double? backgroundBlur,
    double? skewX,
    double? skewY,
    double? skewPerspective,
    int? background,
    int? aspectRatio,
    String? watermark,
    bool? showBrowserFrame,
    int? width,
    int? height,
  }) {
    return FancyShotProfile(
      name: name ?? this.name,
      backgroundPadding: backgroundPadding ?? this.backgroundPadding,
      imagePadding: imagePadding ?? this.imagePadding,
      backgroundType: backgroundType ?? this.backgroundType,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      borderRadius: borderRadius ?? this.borderRadius,
      shadowSpread: shadowSpread ?? this.shadowSpread,
      shadowRadius: shadowRadius ?? this.shadowRadius,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      skewX: skewX ?? this.skewX,
      skewY: skewY ?? this.skewY,
      skewPerspective: skewPerspective ?? this.skewPerspective,
      background: background ?? this.background,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      watermark: watermark ?? this.watermark,
      showBrowserFrame: showBrowserFrame ?? this.showBrowserFrame,
      width: width ?? this.width,
      height: height ?? this.height,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'backgroundPadding': backgroundPadding,
      'imagePadding': imagePadding,
      'backgroundType': backgroundType.index,
      'backgroundImage': backgroundImage,
      'borderRadius': borderRadius,
      'shadowSpread': shadowSpread,
      'shadowRadius': shadowRadius,
      'backgroundBlur': backgroundBlur,
      'skewX': skewX,
      'skewY': skewY,
      'skewPerspective': skewPerspective,
      'background': background,
      'aspectRatio': aspectRatio,
      'watermark': watermark,
      'showBrowserFrame': showBrowserFrame,
      'width': width,
      'height': height,
    };
  }

  factory FancyShotProfile.fromMap(Map<String, dynamic> map) {
    return FancyShotProfile(
      name: (map['name'] ?? '') as String,
      backgroundPadding: (map['backgroundPadding'] ?? 0.0) as double,
      imagePadding: (map['imagePadding'] ?? 0.0) as double,
      backgroundType: BackgroundType.values[(map['backgroundType'] ?? 0) as int],
      backgroundImage: (map['backgroundImage'] ?? "resources/gradient/gradient1.jpg") as String,
      borderRadius: (map['borderRadius'] ?? 0.0) as double,
      shadowSpread: (map['shadowSpread'] ?? 0.0) as double,
      shadowRadius: (map['shadowRadius'] ?? 0.0) as double,
      backgroundBlur: (map['backgroundBlur'] ?? 0.0) as double,
      skewX: (map['skewX'] ?? 0.0) as double,
      skewY: (map['skewY'] ?? 0.0) as double,
      skewPerspective: (map['skewPerspective'] ?? 0.0) as double,
      background: (map['background'] ?? 0) as int,
      aspectRatio: (map['aspectRatio'] ?? 0) as int,
      watermark: (map['watermark'] ?? '') as String,
      showBrowserFrame: (map['showBrowserFrame'] ?? false) as bool,
      width: (map['width'] ?? 0) as int,
      height: (map['height'] ?? 0) as int,
    );
  }

  String toJson() => json.encode(toMap());

  factory FancyShotProfile.fromJson(String source) =>
      FancyShotProfile.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'FancyShotProfile(name: $name, backgroundPadding: $backgroundPadding, imagePadding: $imagePadding, backgroundType: $backgroundType, backgroundImage: $backgroundImage, borderRadius: $borderRadius, shadowSpread: $shadowSpread, shadowRadius: $shadowRadius, backgroundBlur: $backgroundBlur, skewX: $skewX, skewY: $skewY, background: $background, aspectRatio: $aspectRatio, watermark: $watermark, showBrowserFrame: $showBrowserFrame, width: $width, height: $height)';
  }

  @override
  bool operator ==(covariant FancyShotProfile other) {
    if (identical(this, other)) return true;

    return other.name == name &&
        other.backgroundPadding == backgroundPadding &&
        other.imagePadding == imagePadding &&
        other.backgroundType == backgroundType &&
        other.backgroundImage == backgroundImage &&
        other.borderRadius == borderRadius &&
        other.shadowSpread == shadowSpread &&
        other.shadowRadius == shadowRadius &&
        other.backgroundBlur == backgroundBlur &&
        other.skewX == skewX &&
        other.skewY == skewY &&
        other.skewPerspective == skewPerspective &&
        other.background == background &&
        other.aspectRatio == aspectRatio &&
        other.watermark == watermark &&
        other.showBrowserFrame == showBrowserFrame &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode {
    return name.hashCode ^
        backgroundPadding.hashCode ^
        imagePadding.hashCode ^
        backgroundType.hashCode ^
        backgroundImage.hashCode ^
        borderRadius.hashCode ^
        shadowSpread.hashCode ^
        shadowRadius.hashCode ^
        backgroundBlur.hashCode ^
        skewX.hashCode ^
        skewY.hashCode ^
        skewPerspective.hashCode ^
        background.hashCode ^
        aspectRatio.hashCode ^
        watermark.hashCode ^
        showBrowserFrame.hashCode ^
        width.hashCode ^
        height.hashCode;
  }
}

class FancyShot {
  static List<FancyShotProfile> defaultProfiles() => <FancyShotProfile>[
        FancyShotProfile(
          name: "Default",
          backgroundPadding: 10,
          imagePadding: 0,
          backgroundType: BackgroundType.transparent,
          backgroundImage: "resources/gradient/gradient1.jpg",
          borderRadius: 5,
          shadowSpread: 1,
          shadowRadius: 1,
          backgroundBlur: 0,
          background: 0,
          aspectRatio: 0,
          width: 0,
          height: 0,
          watermark: "",
        ),
        FancyShotProfile(
          name: "Self Background",
          backgroundPadding: 16,
          imagePadding: 7.5,
          backgroundType: BackgroundType.self,
          backgroundImage: "resources/gradient/gradient1.jpg",
          borderRadius: 8,
          shadowSpread: 3,
          shadowRadius: 6,
          backgroundBlur: 8,
          background: 0,
          aspectRatio: 0,
          width: 0,
          height: 0,
          watermark: "",
        ),
        FancyShotProfile(
          name: "Image Background",
          backgroundPadding: 28,
          imagePadding: 7.5,
          backgroundType: BackgroundType.stock,
          backgroundImage: "resources/gradient/gradient7.jpg",
          borderRadius: 5,
          shadowSpread: 3,
          shadowRadius: 6,
          backgroundBlur: 18,
          background: 0,
          aspectRatio: 0,
          width: 0,
          height: 0,
          watermark: "",
        ),
      ];

  static List<FancyShotProfile> loadProfiles() {
    final List<FancyShotProfile> profiles = Boxes.getSavedMap<FancyShotProfile>(
      FancyShotProfile.fromJson,
      "fancyShotProfile",
      def: defaultProfiles(),
    );
    if (profiles.isEmpty) return defaultProfiles();
    return profiles;
  }

  static FancyShotProfile? profileByName(String name) {
    final List<FancyShotProfile> profiles = loadProfiles();
    final int index = profiles.indexWhere((FancyShotProfile profile) => profile.name == name);
    if (index < 0) return null;
    return profiles[index].copyWith();
  }

  static Future<Uint8List> renderPresetCapture({
    required Uint8List captureBytes,
    required FancyShotProfile profile,
  }) async {
    await initializeGDI();
    final img.Image? photo = img.decodeImage(captureBytes);
    if (photo == null) {
      throw Exception('Failed to decode captured image for FancyShot preset.');
    }

    final img.Pixel pixel32 = photo.getPixelSafe(0, 0);
    final int hex = _abgrToArgb(
      pixel32.a.toInt() << 24 | pixel32.r.toInt() << 16 | pixel32.g.toInt() << 8 | pixel32.b.toInt(),
    );
    final Color bgColor = Color(hex);
    final ScreenshotController screenshotController = ScreenshotController();

    return screenshotController.captureFromWidget(
      _FancyShotRenderSurface(
        captureBytes: captureBytes,
        photo: photo,
        bgColor: bgColor,
        profile: profile.copyWith(),
      ),
    );
  }

  static int _abgrToArgb(int argbColor) {
    final int r = (argbColor >> 16) & 0xFF;
    final int b = argbColor & 0xFF;
    return (argbColor & 0xFF00FF00) | (b << 16) | r;
  }

  img.Image? photo;
  Uint8List? capture;
  Color? bgColor;

  late FancyShotProfile filters;
  final List<FancyShotProfile> profiles =
      Boxes.getSavedMap<FancyShotProfile>(FancyShotProfile.fromJson, "fancyShotProfile");
  String? profile = Boxes.pref.getString("fancyshot");
  final WinClipboard winClipboard = WinClipboard();

  bool wasInitialized = false;
  Future<void> init() async {
    if (wasInitialized) return;
    wasInitialized = true;
    await initializeGDI();
    if (profile == null) return;
    final int i = profiles.indexWhere((FancyShotProfile element) => element.name == profile);
    if (i == -1) return;
    filters = profiles[i].copyWith();
  }

  Future<void> quickCapture() async {
    await init();
    loadCaptureFile();

    ScreenshotController screenshotController = ScreenshotController();

    final Uint8List output = await screenshotController.captureFromWidget(Material(
      type: MaterialType.transparency,
      child: ClipRect(
        child: Container(
          width: photo!.width.toDouble(),
          height: photo!.height.toDouble(),
          padding: EdgeInsets.all(filters.backgroundPadding.ceil().toDouble()),
          decoration: filters.backgroundType == BackgroundType.stock
              ? BoxDecoration(
                  image: DecorationImage(
                    image: AssetImage(filters.backgroundImage),
                    fit: BoxFit.cover,
                  ),
                )
              : filters.backgroundType == BackgroundType.self
                  ? BoxDecoration(
                      image: DecorationImage(
                        image: MemoryImage(capture!),
                        fit: BoxFit.cover,
                      ),
                    )
                  : filters.backgroundType == BackgroundType.custom
                      ? BoxDecoration(
                          image: File(filters.backgroundImage).existsSync()
                              ? DecorationImage(
                                  image: FileImage(File(filters.backgroundImage)),
                                  fit: BoxFit.cover,
                                )
                              : null,
                        )
                      : const BoxDecoration(color: Colors.transparent),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: filters.backgroundBlur,
              sigmaY: filters.backgroundBlur,
            ),
            child: Transform(
              transform: filters.skewX != 0 && filters.skewY != 0
                  ? (Matrix4.identity()
                    ..scaledByVector3(Vector3.all(0.1))
                    ..setEntry(3, 2, filters.skewPerspective)
                    ..rotateX(0.1 * filters.skewY)
                    ..rotateY(-0.1 * filters.skewX))
                  : Matrix4.identity(),
              filterQuality: FilterQuality.high,
              alignment: Alignment.center,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (filters.watermark.isNotEmpty) const SizedBox(width: 20),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      if (filters.watermark.isNotEmpty) const SizedBox(height: 20),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 400, maxWidth: 500),
                        child: FittedBox(
                          alignment: Alignment.center,
                          // fit: BoxFit.fill,
                          child: Stack(
                            children: <Widget>[
                              Container(
                                decoration: BoxDecoration(
                                  color: bgColor,
                                  borderRadius: BorderRadius.all(Radius.circular(filters.borderRadius)),
                                  boxShadow: filters.shadowRadius != 0 && filters.shadowSpread != 0
                                      ? <BoxShadow>[
                                          BoxShadow(
                                            offset: const Offset(3, 3),
                                            spreadRadius: filters.shadowSpread,
                                            blurRadius: filters.shadowRadius,
                                            color: const Color.fromRGBO(0, 0, 0, 0.5),
                                          ),
                                        ]
                                      : null,
                                ),
                                padding: EdgeInsets.all(filters.imagePadding.ceil().toDouble()),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(filters.borderRadius),
                                  child: Image.memory(
                                    capture!,
                                    fit: BoxFit.contain,
                                    width: photo!.width.toDouble(),
                                    height: photo!.height.toDouble(),
                                    filterQuality: FilterQuality.high,
                                  ),
                                ),
                              ),
                              Positioned(
                                bottom: 0,
                                right: 0,
                                child: Transform.translate(
                                  offset: const Offset(0, 25),
                                  child: Transform(
                                    transform: Matrix4.skewX(-0.2),
                                    child: Text(
                                      filters.watermark,
                                      textAlign: TextAlign.right,
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 17,
                                        shadows: <Shadow>[
                                          Shadow(blurRadius: 1, color: Colors.black.withValues(alpha: 0.7))
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                            ],
                          ),
                        ),
                      ),
                      if (filters.watermark.isNotEmpty) const SizedBox(height: 20),
                    ],
                  ),
                  if (filters.watermark.isNotEmpty) const SizedBox(width: 20),
                ],
              ),
            ),
          ),
        ),
      ),
    ));

    final String path = "${WinUtils.getTempFolder()}/copy.png";
    File(path).writeAsBytesSync(output);
    await winClipboard.copyImageToClipboard(path);
    Beep(1000, 200);
    Beep(500, 200);
    Beep(200, 200);
  }

  void loadCaptureFile() async {
    final String temp = WinUtils.getTempFolder();
    if (File("$temp\\capture.png").existsSync()) {
      capture = File("$temp\\capture.png").readAsBytesSync();
      photo = img.decodeImage(capture!);
      img.Pixel pixel32 = photo!.getPixelSafe(0, 0);
      int hex =
          abgrToArgb(pixel32.a.toInt() << 24 | pixel32.r.toInt() << 16 | pixel32.g.toInt() << 8 | pixel32.b.toInt());
      bgColor = Color(hex);
    } else {
      capture = null;
    }
  }

  int abgrToArgb(int argbColor) {
    int r = (argbColor >> 16) & 0xFF;
    int b = argbColor & 0xFF;
    return (argbColor & 0xFF00FF00) | (b << 16) | r;
  }
}

class _FancyShotRenderSurface extends StatelessWidget {
  const _FancyShotRenderSurface({
    required this.captureBytes,
    required this.photo,
    required this.bgColor,
    required this.profile,
  });

  final Uint8List captureBytes;
  final img.Image photo;
  final Color bgColor;
  final FancyShotProfile profile;

  BoxDecoration _backgroundDecoration() {
    switch (profile.backgroundType) {
      case BackgroundType.stock:
        return BoxDecoration(
          image: DecorationImage(
            image: AssetImage(profile.backgroundImage),
            fit: BoxFit.cover,
          ),
        );
      case BackgroundType.self:
        return BoxDecoration(
          image: DecorationImage(
            image: MemoryImage(captureBytes),
            fit: BoxFit.cover,
          ),
        );
      case BackgroundType.custom:
        return BoxDecoration(
          image: File(profile.backgroundImage).existsSync()
              ? DecorationImage(
                  image: FileImage(File(profile.backgroundImage)),
                  fit: BoxFit.cover,
                )
              : null,
        );
      case BackgroundType.transparent:
        return const BoxDecoration(color: Colors.transparent);
    }
  }

  Matrix4 _buildTransform() {
    if (profile.skewX == 0 || profile.skewY == 0) {
      return Matrix4.identity();
    }
    return Matrix4.identity()
      ..scaledByVector3(Vector3.all(0.1))
      ..setEntry(3, 2, profile.skewPerspective)
      ..rotateX(0.1 * profile.skewY)
      ..rotateY(-0.1 * profile.skewX);
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: ClipRect(
        child: Container(
          padding: EdgeInsets.all(profile.backgroundPadding.ceil().toDouble()),
          decoration: _backgroundDecoration(),
          child: BackdropFilter(
            filter: ImageFilter.blur(
              sigmaX: profile.backgroundBlur,
              sigmaY: profile.backgroundBlur,
            ),
            child: Transform(
              transform: _buildTransform(),
              filterQuality: FilterQuality.high,
              alignment: Alignment.center,
              child: Padding(
                padding: EdgeInsets.all(profile.watermark.isNotEmpty ? 20 : 0),
                child: Stack(
                  clipBehavior: Clip.none,
                  children: <Widget>[
                    IntrinsicWidth(
                      child: Container(
                        decoration: BoxDecoration(
                          color: profile.showBrowserFrame ? const Color(0xFFEBEBEB) : bgColor,
                          borderRadius: BorderRadius.all(Radius.circular(profile.borderRadius)),
                          boxShadow: profile.shadowRadius != 0 && profile.shadowSpread != 0
                              ? <BoxShadow>[
                                  BoxShadow(
                                    offset: const Offset(3, 3),
                                    spreadRadius: profile.shadowSpread,
                                    blurRadius: profile.shadowRadius,
                                    color: const Color.fromRGBO(0, 0, 0, 0.5),
                                  ),
                                ]
                              : null,
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: <Widget>[
                            if (profile.showBrowserFrame)
                              Container(
                                height: 32,
                                padding: const EdgeInsets.symmetric(horizontal: 14),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEBEBEB),
                                  borderRadius: BorderRadius.only(
                                    topLeft: Radius.circular(profile.borderRadius),
                                    topRight: Radius.circular(profile.borderRadius),
                                  ),
                                  border: Border(
                                    bottom: BorderSide(color: Colors.black.withValues(alpha: 0.05), width: 1),
                                  ),
                                ),
                                child: Row(
                                  children: <Widget>[
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(color: Color(0xFFFF5F56), shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(color: Color(0xFFFFBD2E), shape: BoxShape.circle),
                                    ),
                                    const SizedBox(width: 8),
                                    Container(
                                      width: 12,
                                      height: 12,
                                      decoration: const BoxDecoration(color: Color(0xFF27C93F), shape: BoxShape.circle),
                                    ),
                                  ],
                                ),
                              ),
                            Padding(
                              padding: EdgeInsets.all(profile.imagePadding.ceil().toDouble()),
                              child: ClipRRect(
                                borderRadius: profile.showBrowserFrame
                                    ? BorderRadius.only(
                                        bottomLeft: Radius.circular(profile.borderRadius),
                                        bottomRight: Radius.circular(profile.borderRadius),
                                      )
                                    : BorderRadius.circular(profile.borderRadius),
                                child: Image.memory(
                                  captureBytes,
                                  fit: BoxFit.contain,
                                  width: photo.width.toDouble(),
                                  height: photo.height.toDouble(),
                                  filterQuality: FilterQuality.high,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (profile.watermark.isNotEmpty)
                      Positioned(
                        bottom: 12,
                        right: 12,
                        child: Transform(
                          transform: Matrix4.skewX(-0.1),
                          child: Text(
                            profile.watermark,
                            textAlign: TextAlign.right,
                            style: TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 14,
                              letterSpacing: 0.5,
                              color: Colors.white.withValues(alpha: 0.90),
                              shadows: <Shadow>[
                                Shadow(
                                  blurRadius: 6,
                                  color: Colors.black.withValues(alpha: 0.45),
                                  offset: const Offset(0, 2),
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
        ),
      ),
    );
  }
}
