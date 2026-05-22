// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/material.dart';
// ignore: depend_on_referenced_packages
import 'package:image/image.dart' as img;
import 'package:screenshot/screenshot.dart';
import 'package:tabamewin32/tabamewin32.dart';
import 'package:win32/win32.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes.dart';
import '../../models/win32/win_utils.dart';

enum UploadHostType {
  /// Custom PowerShell command supplied by the user.
  custom,

  /// catbox.moe anonymous upload via HTTP multipart.
  catbox,
}

class ScreenCaptureUploadHost {
  ScreenCaptureUploadHost({
    required this.id,
    required this.name,
    required this.command,
    this.uploadType = UploadHostType.custom,
  });

  final String id;
  final String name;
  final String command;
  final UploadHostType uploadType;

  /// True for the built-in hosts that ship with the app.
  /// Built-in hosts cannot be deleted from the dialog.
  bool get isBuiltIn => uploadType != UploadHostType.custom;

  ScreenCaptureUploadHost copyWith({
    String? id,
    String? name,
    String? command,
    UploadHostType? uploadType,
  }) {
    return ScreenCaptureUploadHost(
      id: id ?? this.id,
      name: name ?? this.name,
      command: command ?? this.command,
      uploadType: uploadType ?? this.uploadType,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'command': command,
      'uploadType': uploadType.name,
    };
  }

  factory ScreenCaptureUploadHost.fromMap(Map<String, dynamic> map) {
    UploadHostType type = UploadHostType.custom;
    final String? typeName = map['uploadType'] as String?;
    if (typeName != null) {
      type = UploadHostType.values.firstWhere(
        (UploadHostType e) => e.name == typeName,
        orElse: () => UploadHostType.custom,
      );
    }
    return ScreenCaptureUploadHost(
      id: (map['id'] ?? DateTime.now().microsecondsSinceEpoch.toString()) as String,
      name: (map['name'] ?? '') as String,
      command: (map['command'] ?? '') as String,
      uploadType: type,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory ScreenCaptureUploadHost.fromJson(String source) {
    return ScreenCaptureUploadHost.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }

  // ── Built-in host definitions ─────────────────────────────────────────────

  static ScreenCaptureUploadHost get catbox => ScreenCaptureUploadHost(
        id: 'builtin:catbox',
        name: 'catbox.moe',
        command: '',
        uploadType: UploadHostType.catbox,
      );

  /// All built-in hosts in display order.
  static List<ScreenCaptureUploadHost> get builtInHosts => <ScreenCaptureUploadHost>[catbox];
}

class Fancyshot extends StatefulWidget {
  const Fancyshot({super.key});
  @override
  FancyshotState createState() => FancyshotState();
}

class FancyshotState extends State<Fancyshot> {
  static const List<({String label, int value, double? ratio})> aspectRatioOptions = <({
    String label,
    int value,
    double? ratio,
  })>[
    (label: 'Auto', value: 0, ratio: null),
    (label: '1:1', value: 1, ratio: 1),
    (label: '3:2', value: 2, ratio: 3 / 2),
    (label: '4:3', value: 3, ratio: 4 / 3),
    (label: '16:9', value: 4, ratio: 16 / 9),
    (label: '9:16', value: 5, ratio: 9 / 16),
  ];

  static const List<({String label, int value, Color color})> stageTintOptions = <({
    String label,
    int value,
    Color color,
  })>[
    (label: 'None', value: 0, color: Color(0x00000000)),
    (label: 'Graphite', value: 0xFF1B2432, color: Color(0xFF1B2432)),
    (label: 'Cobalt', value: 0xFF1D4ED8, color: Color(0xFF1D4ED8)),
    (label: 'Emerald', value: 0xFF0F766E, color: Color(0xFF0F766E)),
    (label: 'Amber', value: 0xFFB45309, color: Color(0xFFB45309)),
    (label: 'Rose', value: 0xFFBE185D, color: Color(0xFFBE185D)),
  ];

  final FancyShotProfile defaultProfile = FancyShot.defaultProfiles().first.copyWith();
  final TextEditingController textEditingController = TextEditingController();
  final TextEditingController watermarkTextController = TextEditingController();
  final TextEditingController skewPerspectiveController = TextEditingController();
  final ScrollController inspectorScrollController = ScrollController();

  late final List<FancyShotProfile> profiles;
  late FancyShotProfile filters;

  Uint8List? capture;
  img.Image? photo;
  Color bgColor = const Color(0xFF121723);
  String? selectedProfile;
  bool _previewActualSize = false;
  bool _autosavePending = false;
  DateTime? _lastAutosavedAt;
  Timer? _autosaveTimer;

  @override
  void initState() {
    super.initState();
    initializeGDI();
    profiles = FancyShot.loadProfiles();
    if (profiles.isEmpty) {
      profiles.add(defaultProfile.copyWith(name: 'Default'));
    }
    filters = profiles.first.copyWith();
    _applySelectedProfile(Boxes.pref.getString('fancyshot') ?? profiles.first.name, notify: false);
    _loadLatestScreenshotPreview();
  }

  @override
  void dispose() {
    _autosaveTimer?.cancel();
    textEditingController.dispose();
    watermarkTextController.dispose();
    skewPerspectiveController.dispose();
    inspectorScrollController.dispose();
    super.dispose();
  }

  bool get hasCapture => capture != null && photo != null;

  void _syncControllersFromFilters() {
    watermarkTextController.text = filters.watermark;
    skewPerspectiveController.text = filters.skewPerspective == 0 ? '' : filters.skewPerspective.toStringAsFixed(3);
  }

  void _applySelectedProfile(String name, {bool notify = true}) {
    final int index = profiles.indexWhere((FancyShotProfile element) => element.name == name);
    final int safeIndex = index >= 0 ? index : 0;
    final FancyShotProfile selected = profiles[safeIndex];
    selectedProfile = selected.name;
    filters = selected.copyWith();
    _syncControllersFromFilters();
    Boxes.pref.setString('fancyshot', selected.name);
    if (notify && mounted) setState(() {});
  }

  void _stashCurrentProfileLocally() {
    final String? currentName = selectedProfile;
    if (currentName == null) return;
    final FancyShotProfile snapshot = filters.copyWith(name: currentName);
    final int index = profiles.indexWhere((FancyShotProfile profile) => profile.name == currentName);
    if (index >= 0) {
      profiles[index] = snapshot;
    } else {
      profiles.add(snapshot);
    }
  }

  Future<void> _persistProfilesNow() async {
    _autosaveTimer?.cancel();
    _stashCurrentProfileLocally();
    await Boxes.updateSettings('fancyShotProfile', jsonEncode(profiles));
    if (!mounted) return;
    setState(() {
      _autosavePending = false;
      _lastAutosavedAt = DateTime.now();
    });
  }

  void _scheduleAutosave({bool immediate = false}) {
    if (selectedProfile == null) return;
    _autosaveTimer?.cancel();
    if (mounted && !_autosavePending) {
      setState(() => _autosavePending = true);
    }
    if (immediate) {
      unawaited(_persistProfilesNow());
      return;
    }
    _autosaveTimer = Timer(const Duration(milliseconds: 220), () {
      unawaited(_persistProfilesNow());
    });
  }

  void _updateFilters(VoidCallback change, {bool immediate = false}) {
    setState(change);
    _scheduleAutosave(immediate: immediate);
  }

  File? _latestScreenshotFile() {
    final Directory screenshotsRoot = Directory('${WinUtils.getTabameAppDataFolder()}\\screenshots');
    if (!screenshotsRoot.existsSync()) return null;

    final List<File> screenshotFiles = screenshotsRoot
        .listSync(recursive: true)
        .whereType<File>()
        .where((File file) => file.path.toLowerCase().endsWith('.png'))
        .toList();
    if (screenshotFiles.isEmpty) return null;

    screenshotFiles.sort((File a, File b) => b.statSync().modified.compareTo(a.statSync().modified));
    return screenshotFiles.first;
  }

  Color _samplePreviewColor(img.Image decoded) {
    final img.Pixel pixel32 = decoded.getPixelSafe(0, 0);
    final int hex =
        _abgrToArgb(pixel32.a.toInt() << 24 | pixel32.r.toInt() << 16 | pixel32.g.toInt() << 8 | pixel32.b.toInt());
    return Color(hex);
  }

  void _loadLatestScreenshotPreview() {
    final File? latestFile = _latestScreenshotFile();
    if (latestFile == null) {
      setState(() {
        capture = null;
        photo = null;
        bgColor = const Color(0xFF121723);
      });
      return;
    }

    try {
      final Uint8List bytes = latestFile.readAsBytesSync();
      final img.Image? decoded = img.decodeImage(bytes);
      if (decoded == null) {
        setState(() {
          capture = null;
          photo = null;
          bgColor = const Color(0xFF121723);
        });
        return;
      }

      setState(() {
        capture = bytes;
        photo = decoded;
        bgColor = _samplePreviewColor(decoded);
      });
    } catch (_) {
      setState(() {
        capture = null;
        photo = null;
        bgColor = const Color(0xFF121723);
      });
    }
  }

  int _abgrToArgb(int argbColor) {
    final int r = (argbColor >> 16) & 0xFF;
    final int b = argbColor & 0xFF;
    return (argbColor & 0xFF00FF00) | (b << 16) | r;
  }

  String _autosaveLabel() {
    if (_autosavePending) return 'Autosaving...';
    if (_lastAutosavedAt == null) return 'Autosave enabled';
    return 'Autosaved ${_lastAutosavedAt!.hour.toString().padLeft(2, '0')}:${_lastAutosavedAt!.minute.toString().padLeft(2, '0')}:${_lastAutosavedAt!.second.toString().padLeft(2, '0')}';
  }

  String _uniqueProfileName(String seed) {
    String candidate = seed.trim().isEmpty ? 'Profile' : seed.trim();
    final Set<String> existing = profiles.map((FancyShotProfile profile) => profile.name.toLowerCase()).toSet();
    if (!existing.contains(candidate.toLowerCase())) return candidate;

    int suffix = 2;
    while (existing.contains('$candidate $suffix'.toLowerCase())) {
      suffix++;
    }
    return '$candidate $suffix';
  }

  Future<void> _createProfile({FancyShotProfile? source}) async {
    final String typedName = textEditingController.text.trim();
    final String baseName = typedName.isNotEmpty
        ? typedName
        : source != null
            ? '${source.name} Copy'
            : 'Profile';
    final String profileName = _uniqueProfileName(baseName);

    final FancyShotProfile newProfile = source != null ? source.copyWith() : defaultProfile.copyWith();
    profiles.add(newProfile.copyWith(name: profileName));
    textEditingController.clear();
    _applySelectedProfile(profileName, notify: false);
    await _persistProfilesNow();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteProfile(FancyShotProfile profile) async {
    if (profile.name == 'Default') return;
    profiles.removeWhere((FancyShotProfile p) => p.name == profile.name);
    if (profiles.isEmpty) {
      profiles.add(defaultProfile.copyWith(name: 'Default'));
    }
    if (selectedProfile == profile.name) {
      _applySelectedProfile(profiles.first.name, notify: false);
    }
    await _persistProfilesNow();
    if (!mounted) return;
    setState(() {});
  }

  void _selectProfile(String profileName) {
    _stashCurrentProfileLocally();
    unawaited(Boxes.updateSettings('fancyShotProfile', jsonEncode(profiles)));
    _applySelectedProfile(profileName);
  }

  void _pickCustomBackground() {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{'PNG Image (*.png)': '*.png'}
      ..defaultFilterIndex = 0
      ..defaultExtension = 'png'
      ..title = 'Select an image';

    final File? result = file.getFile();
    if (result == null) return;

    _updateFilters(() {
      filters.backgroundType = BackgroundType.custom;
      filters.backgroundImage = result.path;
    });
  }

  Future<void> _openUploadHostsSettings() async {
    final List<ScreenCaptureUploadHost>? hosts = await showDialog<List<ScreenCaptureUploadHost>>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.36),
      builder: (BuildContext context) {
        return _UploadHostsDialog(initialHosts: FancyShot.loadUploadHosts());
      },
    );
    if (hosts == null) return;
    await FancyShot.saveUploadHosts(hosts);
    if (mounted) setState(() {});
  }

  Widget _buildCanvasEditor() {
    final double srcW = (photo?.width ?? 1280).toDouble();
    final double srcH = (photo?.height ?? 800).toDouble();

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints outer) {
        // Compute the natural (scale=1) canvas size to find the fit scale.
        // frameW/frameH must match _mainLayerSize exactly (scale=1):
        //   capture + imagePadding*2  (frameBorderWidth is inset, not additive)
        final double scaledW = srcW * filters.imageScale;
        final double scaledH = srcH * filters.imageScale;
        final double frameW = scaledW + filters.imagePadding * 2;
        final double frameH = scaledH + filters.imagePadding * 2 + (filters.showBrowserFrame ? 32 : 0);
        double naturalW = frameW + filters.backgroundPadding * 2;
        double naturalH = frameH + filters.backgroundPadding * 2;
        final double? ratio = <int, double>{1: 1, 2: 3 / 2, 3: 4 / 3, 4: 16 / 9, 5: 9 / 16}[filters.aspectRatio];
        if (ratio != null) {
          if (naturalW / naturalH < ratio) {
            naturalW = naturalH * ratio;
          } else {
            naturalH = naturalW / ratio;
          }
        }

        final double availW = outer.maxWidth - 80;
        final double availH = outer.maxHeight - 80;
        final double scale = (availW / naturalW).clamp(0.0, availH / naturalH);

        final Widget subject = hasCapture
            ? GestureDetector(
                onPanUpdate: (DragUpdateDetails details) {
                  _updateFilters(() {
                    filters.skewX += details.delta.dx / (srcW / 2);
                    filters.skewY += details.delta.dy / (srcH / 2);
                  });
                },
                onDoubleTap: () => _updateFilters(
                  () {
                    filters.skewX = 0;
                    filters.skewY = 0;
                  },
                  immediate: true,
                ),
                child: Image.memory(
                  capture!,
                  fit: BoxFit.fill,
                  filterQuality: FilterQuality.high,
                ),
              )
            : const _FancyShotPlaceholderSubject();

        return MediaQuery(
          data: const MediaQueryData(),
          child: Material(
            color: Colors.transparent,
            child: _FancyShotFrameSurface(
              captureImage: subject,
              captureBytesForBackground: capture,
              profile: filters,
              surfaceColor: bgColor,
              sourceWidth: srcW,
              sourceHeight: srcH,
              scale: scale,
            ),
          ),
        );
      },
    );
  }

  Widget _buildProfileLibrary(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SizedBox(
            height: 80,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: profiles.length + 1,
              separatorBuilder: (_, __) => const SizedBox(width: 12),
              itemBuilder: (BuildContext context, int index) {
                if (index == 0) {
                  return _CreateProfileCard(
                    controller: textEditingController,
                    onCreate: () => _createProfile(),
                  );
                }

                final FancyShotProfile profile = profiles[index - 1];
                return SizedBox(
                  width: 244,
                  child: _ProfileEntryCard(
                    profile: profile,
                    selected: profile.name == selectedProfile,
                    onTap: () => _selectProfile(profile.name),
                    onDelete: profile.name != 'Default' ? () => _deleteProfile(profile) : null,
                    onDuplicate: () => _createProfile(source: profile),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPreviewPane(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Expanded(
      flex: 3,
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerLowest,
          border: Border(right: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08))),
        ),
        child: Column(
          children: <Widget>[
            const SizedBox(height: 3),
            Text(
              'LIVE PREVIEW',
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.0,
                color: colorScheme.onSurface.withValues(alpha: 0.58),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 12),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: <Widget>[
                  const Spacer(),
                  IconButton(
                    tooltip: _previewActualSize ? 'Fit preview' : 'Actual size',
                    onPressed: () => setState(() => _previewActualSize = !_previewActualSize),
                    icon: Icon(_previewActualSize ? Icons.fit_screen_rounded : Icons.fullscreen_rounded),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ColoredBox(
                color: const Color(0xFF1A1A1A),
                child: Center(
                  child: _buildCanvasEditor(),
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(18, 12, 18, 16),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08))),
              ),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: <Widget>[
                    _MetaChip(
                      icon: Icons.aspect_ratio_rounded,
                      label: hasCapture ? '${photo!.width} x ${photo!.height}' : '1280 x 800',
                    ),
                    const SizedBox(width: 8),
                    _MetaChip(
                      icon: Icons.layers_outlined,
                      label: filters.backgroundType.name.toUpperCase(),
                    ),
                    const SizedBox(width: 8),
                    _MetaChip(
                      icon: Icons.save_as_rounded,
                      label: _autosaveLabel(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInspectorPane(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      width: 340,
      color: colorScheme.surface,
      child: SingleChildScrollView(
        controller: inspectorScrollController,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Align(
              alignment: Alignment.center,
              child: FutureBuilder<bool>(
                  future: windowManager.isMaximized(),
                  builder: (BuildContext context, AsyncSnapshot<bool> snapshot) {
                    if (snapshot.hasError) {
                      return const SizedBox.shrink();
                    }
                    if (snapshot.hasData && snapshot.data! == false) {
                      return Padding(
                        padding: const EdgeInsets.only(right: 14, bottom: 12),
                        child: FilledButton.tonalIcon(
                          onPressed: () async {
                            await windowManager.maximize();
                            setState(() {});
                          },
                          icon: const Icon(Icons.fullscreen_rounded, size: 16),
                          label: const Text('Maximize for a better preview'),
                        ),
                      );
                    }
                    return const SizedBox.shrink();
                  }),
            ),
            _SectionCard(
              title: 'Layout',
              subtitle: 'Control the stage size, crop rhythm, and frame silhouette.',
              child: Column(
                children: <Widget>[
                  _ChoicePills<int>(
                    value: filters.aspectRatio,
                    options: aspectRatioOptions
                        .map((({String label, int value, double? ratio}) option) => (
                              label: option.label,
                              value: option.value,
                            ))
                        .toList(),
                    onChanged: (int value) => _updateFilters(() => filters.aspectRatio = value),
                  ),
                  const SizedBox(height: 10),
                  _ToggleTile(
                    label: 'Browser Frame',
                    subtitle: 'Wrap the screenshot in a browser-style chrome.',
                    value: filters.showBrowserFrame,
                    onChanged: (bool value) => _updateFilters(() => filters.showBrowserFrame = value),
                  ),
                  const SizedBox(height: 12),
                  _CompactSlider(
                    label: 'Background Padding',
                    value: filters.backgroundPadding,
                    min: 0,
                    max: 84,
                    onChanged: (double v) => _updateFilters(() => filters.backgroundPadding = v),
                  ),
                  _CompactSlider(
                    label: 'Image Padding',
                    value: filters.imagePadding,
                    min: 0,
                    max: 64,
                    onChanged: (double v) => _updateFilters(() => filters.imagePadding = v),
                  ),
                  _CompactSlider(
                    label: 'Corner Radius',
                    value: filters.borderRadius,
                    min: 0,
                    max: 28,
                    onChanged: (double v) => _updateFilters(() => filters.borderRadius = v),
                  ),
                  _CompactSlider(
                    label: 'Image Scale',
                    value: filters.imageScale,
                    min: 0.8,
                    decimals: 2,
                    max: 1.35,
                    onChanged: (double v) => _updateFilters(() => filters.imageScale = v),
                  ),
                  _CompactSlider(
                    label: 'Frame Border',
                    value: filters.frameBorderWidth,
                    min: 0,
                    max: 6,
                    onChanged: (double v) => _updateFilters(() => filters.frameBorderWidth = v),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Effects',
              subtitle: 'Shadow, blur, tilt, and motion language.',
              child: Column(
                children: <Widget>[
                  _CompactSlider(
                    label: 'Shadow Radius',
                    value: filters.shadowRadius,
                    min: 0,
                    max: 28,
                    onChanged: (double v) => _updateFilters(() => filters.shadowRadius = v),
                  ),
                  _CompactSlider(
                    label: 'Shadow Spread',
                    value: filters.shadowSpread,
                    min: 0,
                    max: 12,
                    onChanged: (double v) => _updateFilters(() => filters.shadowSpread = v),
                  ),
                  _CompactSlider(
                    label: 'Shadow Opacity',
                    value: filters.shadowOpacity,
                    min: 0,
                    decimals: 2,
                    max: 0.8,
                    onChanged: (double v) => _updateFilters(() => filters.shadowOpacity = v),
                  ),
                  _CompactSlider(
                    label: 'Backdrop Blur',
                    value: filters.backgroundBlur,
                    min: 0,
                    max: 28,
                    onChanged: (double v) => _updateFilters(() => filters.backgroundBlur = v),
                  ),
                  _CompactSlider(
                    label: 'Rotation',
                    value: filters.rotation,
                    min: -8,
                    decimals: 1,
                    max: 8,
                    onChanged: (double v) => _updateFilters(() => filters.rotation = v),
                  ),
                  _CompactTextField(
                    label: 'Perspective',
                    controller: skewPerspectiveController,
                    hint: '0.001',
                    onChanged: (String value) =>
                        _updateFilters(() => filters.skewPerspective = double.tryParse(value) ?? 0),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: <Widget>[
                      Expanded(
                        child: Text(
                          'Drag the preview image to adjust tilt. Double-click it to reset skew.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.56),
                            height: 1.3,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      TextButton.icon(
                        onPressed: () => _updateFilters(() {
                          filters.skewX = 0;
                          filters.skewY = 0;
                          filters.rotation = 0;
                          filters.skewPerspective = 0;
                          skewPerspectiveController.clear();
                        }, immediate: true),
                        icon: const Icon(Icons.refresh_rounded, size: 16),
                        label: const Text('Reset'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Decoration',
              subtitle: 'Watermarks, edge treatment, and stage tinting.',
              child: Column(
                children: <Widget>[
                  _CompactTextField(
                    label: 'Watermark',
                    controller: watermarkTextController,
                    hint: 'brand.name',
                    onChanged: (String value) => _updateFilters(() => filters.watermark = value),
                  ),
                  const SizedBox(height: 12),
                  _CompactSlider(
                    label: 'Watermark Size',
                    value: filters.watermarkSize,
                    min: 10,
                    max: 28,
                    onChanged: (double v) => _updateFilters(() => filters.watermarkSize = v),
                  ),
                  _CompactSlider(
                    label: 'Watermark Opacity',
                    value: filters.watermarkOpacity,
                    min: 0,
                    decimals: 2,
                    max: 1,
                    onChanged: (double v) => _updateFilters(() => filters.watermarkOpacity = v),
                  ),
                  _CompactSlider(
                    label: 'Stage Tint',
                    value: filters.backgroundTintOpacity,
                    min: 0,
                    decimals: 2,
                    max: 0.72,
                    onChanged: (double v) => _updateFilters(() => filters.backgroundTintOpacity = v),
                  ),
                  const SizedBox(height: 8),
                  _ColorSwatchRow(
                    value: filters.background,
                    options: stageTintOptions
                        .map((({String label, int value, Color color}) option) => (
                              label: option.label,
                              value: option.value,
                              color: option.color,
                            ))
                        .toList(),
                    onChanged: (int value) => _updateFilters(() => filters.background = value),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _SectionCard(
              title: 'Background Source',
              subtitle: 'Choose the canvas behind the framed screenshot.',
              child: _BackgroundGrid(
                filters: filters,
                capture: capture,
                onBackgroundChanged: (BackgroundType type, String? image) {
                  _updateFilters(() {
                    filters.backgroundType = type;
                    if (image != null) filters.backgroundImage = image;
                  });
                },
                onPickCustom: _pickCustomBackground,
                onHover: (_) {},
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08))),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: colorScheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.auto_fix_high_rounded, size: 20, color: colorScheme.primary),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'FancyShot Profile Creator',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  'Edit reusable screenshot looks here. Screen Capture now handles export and after-capture actions.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: colorScheme.onSurface.withValues(alpha: 0.58),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: _openUploadHostsSettings,
            icon: const Icon(Icons.cloud_upload_outlined, size: 16),
            label: const Text('Upload Hosts'),
          ),
          const SizedBox(width: 8),
          FilledButton.tonalIcon(
            onPressed: () => WinUtils.open('${WinUtils.getTabameAppDataFolder()}\\screenshots'),
            icon: const Icon(Icons.folder_open_rounded, size: 16),
            label: const Text('Screenshots'),
          ),
        ],
      ),
    );
  }

  Widget _buildToolLayout(BuildContext context) {
    return Column(
      children: <Widget>[
        _buildHeader(context),
        _buildProfileLibrary(context),
        Expanded(
          child: Row(
            children: <Widget>[
              _buildPreviewPane(context),
              _buildInspectorPane(context),
            ],
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

class _CompactSlider extends StatelessWidget {
  const _CompactSlider({
    required this.label,
    required this.value,
    this.min = 0,
    this.decimals = 0,
    required this.max,
    required this.onChanged,
  });

  final String label;
  final double value;
  final double min;
  final int decimals;
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
                value.toStringAsFixed(decimals),
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

class _CreateProfileCard extends StatelessWidget {
  const _CreateProfileCard({
    required this.controller,
    required this.onCreate,
  });

  final TextEditingController controller;
  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Container(
      width: 332,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            colorScheme.primary.withValues(alpha: 0.15),
            colorScheme.surfaceContainerHigh,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.20)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onCreate(),
                  decoration: InputDecoration(
                    labelText: 'Profile Name',
                    hintText: 'Campaign Polish',
                    isDense: true,
                    filled: true,
                    fillColor: colorScheme.surface.withValues(alpha: 0.74),
                    prefixIcon: const Icon(Icons.bookmark_add_outlined, size: 18),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.10)),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colorScheme.outline.withValues(alpha: 0.10)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: colorScheme.primary.withValues(alpha: 0.55)),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: onCreate,
                icon: const Icon(Icons.add_rounded, size: 20),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProfileEntryCard extends StatelessWidget {
  const _ProfileEntryCard({
    required this.profile,
    required this.selected,
    required this.onTap,
    this.onDelete,
    required this.onDuplicate,
  });

  final FancyShotProfile profile;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onDelete;
  final VoidCallback onDuplicate;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: selected
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHighest.withValues(alpha: 0.26),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: selected ? colorScheme.primary.withValues(alpha: 0.34) : colorScheme.outline.withValues(alpha: 0.08),
          ),
          boxShadow: selected
              ? <BoxShadow>[
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                const SizedBox(width: 8),
                if (selected) Icon(Icons.check_circle_rounded, size: 18, color: colorScheme.primary),
              ],
            ),
            const Spacer(),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                IconButton.filledTonal(
                  onPressed: onDuplicate,
                  tooltip: 'Duplicate profile',
                  icon: const Icon(Icons.copy_all_rounded, size: 16),
                  padding: const EdgeInsets.all(8),
                  constraints: const BoxConstraints(),
                  style: IconButton.styleFrom(
                    backgroundColor: colorScheme.surfaceContainerHighest,
                  ),
                ),
                if (onDelete != null) ...<Widget>[
                  const SizedBox(width: 8),
                  IconButton.filledTonal(
                    onPressed: onDelete,
                    tooltip: 'Delete profile',
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    padding: const EdgeInsets.all(8),
                    constraints: const BoxConstraints(),
                    style: IconButton.styleFrom(
                      backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.5),
                      foregroundColor: colorScheme.error,
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });

  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.10)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: colorScheme.onSurface.withValues(alpha: 0.56),
                  height: 1.3,
                ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({
    required this.icon,
    required this.label,
  });

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: colorScheme.onSurface.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(icon, size: 14, color: colorScheme.primary),
          const SizedBox(width: 6),
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _ChoicePills<T> extends StatelessWidget {
  const _ChoicePills({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final T value;
  final List<({String label, T value})> options;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((({String label, T value}) option) {
        return ChoiceChip(
          label: Text(option.label),
          selected: option.value == value,
          visualDensity: VisualDensity.compact,
          onSelected: (_) => onChanged(option.value),
        );
      }).toList(),
    );
  }
}

class _ToggleTile extends StatelessWidget {
  const _ToggleTile({
    required this.label,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(label, style: Theme.of(context).textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.56),
                      ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _ColorSwatchRow extends StatelessWidget {
  const _ColorSwatchRow({
    required this.value,
    required this.options,
    required this.onChanged,
  });

  final int value;
  final List<({String label, int value, Color color})> options;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colorScheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.map((({String label, int value, Color color}) option) {
        final bool selected = option.value == value;
        return Tooltip(
          message: option.label,
          child: InkWell(
            onTap: () => onChanged(option.value),
            borderRadius: BorderRadius.circular(999),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 160),
              width: 26,
              height: 26,
              decoration: BoxDecoration(
                color: option.value == 0 ? colorScheme.surface : option.color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: selected ? colorScheme.primary : colorScheme.outline.withValues(alpha: 0.16),
                  width: selected ? 2 : 1,
                ),
              ),
              child: option.value == 0
                  ? Icon(
                      Icons.close_rounded,
                      size: 14,
                      color: colorScheme.onSurface.withValues(alpha: 0.52),
                    )
                  : null,
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _FancyShotPlaceholderSubject extends StatelessWidget {
  const _FancyShotPlaceholderSubject();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1280,
      height: 800,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: <Color>[
            Color(0xFF111723),
            Color(0xFF1A2231),
          ],
        ),
      ),
      child: Stack(
        children: <Widget>[
          const Positioned(
            left: 44,
            top: 42,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  'Latest saved screenshot preview',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 34,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  'Take a screenshot from Screen Capture to replace this placeholder.',
                  style: TextStyle(
                    color: Color(0xB3FFFFFF),
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: 44,
            right: 44,
            bottom: 46,
            child: Row(
              children: List<Widget>.generate(3, (int index) {
                return Expanded(
                  child: Container(
                    height: 132 + index * 8,
                    margin: EdgeInsets.only(right: index == 2 ? 0 : 14),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06 + (index * 0.02)),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                  ),
                );
              }),
            ),
          ),
        ],
      ),
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

class _UploadHostDraft {
  _UploadHostDraft(ScreenCaptureUploadHost host)
      : hostId = host.id,
        nameController = TextEditingController(text: host.name),
        commandController = TextEditingController(text: host.command);

  final String hostId;
  final TextEditingController nameController;
  final TextEditingController commandController;

  ScreenCaptureUploadHost toHost() {
    return ScreenCaptureUploadHost(
      id: hostId,
      name: nameController.text.trim(),
      command: commandController.text.trim(),
    );
  }

  void dispose() {
    nameController.dispose();
    commandController.dispose();
  }
}

class _UploadHostsDialog extends StatefulWidget {
  const _UploadHostsDialog({required this.initialHosts});

  final List<ScreenCaptureUploadHost> initialHosts;

  @override
  State<_UploadHostsDialog> createState() => _UploadHostsDialogState();
}

class _UploadHostsDialogState extends State<_UploadHostsDialog> {
  late final List<_UploadHostDraft> _drafts;

  @override
  void initState() {
    super.initState();
    // Only show custom (user-defined) hosts in the editable list.
    // Built-in hosts are shown separately as read-only.
    _drafts = widget.initialHosts.where((ScreenCaptureUploadHost h) => !h.isBuiltIn).map(_UploadHostDraft.new).toList();
    if (_drafts.isEmpty) _drafts.add(_UploadHostDraft(_newHost()));
  }

  @override
  void dispose() {
    for (final _UploadHostDraft draft in _drafts) {
      draft.dispose();
    }
    super.dispose();
  }

  ScreenCaptureUploadHost _newHost() {
    return ScreenCaptureUploadHost(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      name: '',
      command: '',
    );
  }

  void _addDraft() {
    setState(() => _drafts.add(_UploadHostDraft(_newHost())));
  }

  void _removeDraft(_UploadHostDraft draft) {
    setState(() {
      _drafts.remove(draft);
      draft.dispose();
      if (_drafts.isEmpty) _drafts.add(_UploadHostDraft(_newHost()));
    });
  }

  void _save() {
    final List<ScreenCaptureUploadHost> hosts = _drafts
        .map((_UploadHostDraft draft) => draft.toHost())
        .where((ScreenCaptureUploadHost host) => host.name.isNotEmpty && host.command.isNotEmpty)
        .toList();
    Navigator.pop(context, hosts);
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(horizontal: 56, vertical: 48),
      backgroundColor: Colors.transparent,
      child: Container(
        width: 780,
        constraints: const BoxConstraints(maxHeight: 720),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: colorScheme.outline.withValues(alpha: 0.08)),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.32),
              blurRadius: 28,
              offset: const Offset(0, 16),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: <Widget>[
                  Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.cloud_upload_outlined, size: 18, color: colorScheme.primary),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          'Uploading Hosts',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          'Use \${file} where the captured file path should be inserted. Older commands without \${file} still get the file path appended as the last argument.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withValues(alpha: 0.65),
                          ),
                        ),
                      ],
                    ),
                  ),
                  TextButton.icon(
                    onPressed: _addDraft,
                    icon: const Icon(Icons.add_rounded, size: 18),
                    label: const Text('Add Host'),
                  ),
                ],
              ),
            ),
            Flexible(
              child: ListView(
                padding: const EdgeInsets.all(20),
                children: <Widget>[
                  // ── Built-in hosts (read-only) ──────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'BUILT-IN HOSTS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  ...ScreenCaptureUploadHost.builtInHosts.map((ScreenCaptureUploadHost host) {
                    return Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.06),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.14)),
                      ),
                      child: Row(
                        children: <Widget>[
                          Icon(Icons.cloud_done_outlined, size: 18, color: colorScheme.primary),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              host.name,
                              style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              'Built-in',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                  const SizedBox(height: 12),
                  // ── Custom hosts (user-defined) ────────────────────────────
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'CUSTOM HOSTS',
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.8,
                        color: colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  ..._drafts.asMap().entries.map((MapEntry<int, _UploadHostDraft> entry) {
                    final int index = entry.key;
                    final _UploadHostDraft draft = entry.value;
                    return Container(
                      margin: const EdgeInsets.only(bottom: 14),
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.28),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: colorScheme.outline.withValues(alpha: 0.06)),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Row(
                            children: <Widget>[
                              Text(
                                'Custom Host ${index + 1}',
                                style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                              ),
                              const Spacer(),
                              IconButton(
                                tooltip: 'Delete host',
                                onPressed: () => _removeDraft(draft),
                                icon: const Icon(Icons.delete_outline_rounded, size: 20),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          TextField(
                            controller: draft.nameController,
                            decoration: const InputDecoration(
                              labelText: 'Name',
                              hintText: 'My Uploader',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: draft.commandController,
                            minLines: 2,
                            maxLines: 4,
                            decoration: const InputDecoration(
                              labelText: 'CLI',
                              hintText: r'python "C:\scripts\upload.py" --file ${file}',
                            ),
                          ),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
              decoration: BoxDecoration(
                border: Border(top: BorderSide(color: colorScheme.outline.withValues(alpha: 0.08))),
              ),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      'Built-in hosts cannot be removed. Custom hosts need both a name and a CLI command to be saved.',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurface.withValues(alpha: 0.55),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel'),
                  ),
                  const SizedBox(width: 8),
                  FilledButton(
                    onPressed: _save,
                    child: const Text('Save Hosts'),
                  ),
                ],
              ),
            ),
          ],
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
  double imageScale = 1;
  //enum
  BackgroundType backgroundType = BackgroundType.transparent;
  String backgroundImage = "resources/gradient/gradient1.jpg";
  double borderRadius = 10;
  double frameBorderWidth = 0;
  double shadowSpread = 0;
  double shadowRadius = 0;
  double shadowOpacity = 0.35;
  double backgroundBlur = 0;
  double backgroundTintOpacity = 0;
  double skewX = 0;
  double skewY = 0;
  double skewPerspective = 0;
  double rotation = 0;
  int background = 0;
  int aspectRatio = 0;
  String watermark = "";
  double watermarkOpacity = 0.90;
  double watermarkSize = 14;
  bool showBrowserFrame = false;
  int width = 0;
  int height = 0;
  FancyShotProfile({
    required this.name,
    this.backgroundPadding = 10,
    this.imagePadding = 10,
    this.imageScale = 1,
    this.backgroundType = BackgroundType.transparent,
    this.backgroundImage = "resources/gradient/gradient1.jpg",
    this.borderRadius = 10,
    this.frameBorderWidth = 0,
    this.shadowSpread = 0,
    this.shadowRadius = 0,
    this.shadowOpacity = 0.35,
    this.backgroundBlur = 0,
    this.backgroundTintOpacity = 0,
    this.skewX = 0,
    this.skewY = 0,
    this.skewPerspective = 0,
    this.rotation = 0,
    this.background = 0,
    this.aspectRatio = 0,
    this.watermark = "",
    this.watermarkOpacity = 0.90,
    this.watermarkSize = 14,
    this.showBrowserFrame = false,
    this.width = 0,
    this.height = 0,
  });

  FancyShotProfile copyWith({
    String? name,
    double? backgroundPadding,
    double? imagePadding,
    double? imageScale,
    BackgroundType? backgroundType,
    String? backgroundImage,
    double? borderRadius,
    double? frameBorderWidth,
    double? shadowSpread,
    double? shadowRadius,
    double? shadowOpacity,
    double? backgroundBlur,
    double? backgroundTintOpacity,
    double? skewX,
    double? skewY,
    double? skewPerspective,
    double? rotation,
    int? background,
    int? aspectRatio,
    String? watermark,
    double? watermarkOpacity,
    double? watermarkSize,
    bool? showBrowserFrame,
    int? width,
    int? height,
  }) {
    return FancyShotProfile(
      name: name ?? this.name,
      backgroundPadding: backgroundPadding ?? this.backgroundPadding,
      imagePadding: imagePadding ?? this.imagePadding,
      imageScale: imageScale ?? this.imageScale,
      backgroundType: backgroundType ?? this.backgroundType,
      backgroundImage: backgroundImage ?? this.backgroundImage,
      borderRadius: borderRadius ?? this.borderRadius,
      frameBorderWidth: frameBorderWidth ?? this.frameBorderWidth,
      shadowSpread: shadowSpread ?? this.shadowSpread,
      shadowRadius: shadowRadius ?? this.shadowRadius,
      shadowOpacity: shadowOpacity ?? this.shadowOpacity,
      backgroundBlur: backgroundBlur ?? this.backgroundBlur,
      backgroundTintOpacity: backgroundTintOpacity ?? this.backgroundTintOpacity,
      skewX: skewX ?? this.skewX,
      skewY: skewY ?? this.skewY,
      skewPerspective: skewPerspective ?? this.skewPerspective,
      rotation: rotation ?? this.rotation,
      background: background ?? this.background,
      aspectRatio: aspectRatio ?? this.aspectRatio,
      watermark: watermark ?? this.watermark,
      watermarkOpacity: watermarkOpacity ?? this.watermarkOpacity,
      watermarkSize: watermarkSize ?? this.watermarkSize,
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
      'imageScale': imageScale,
      'backgroundType': backgroundType.index,
      'backgroundImage': backgroundImage,
      'borderRadius': borderRadius,
      'frameBorderWidth': frameBorderWidth,
      'shadowSpread': shadowSpread,
      'shadowRadius': shadowRadius,
      'shadowOpacity': shadowOpacity,
      'backgroundBlur': backgroundBlur,
      'backgroundTintOpacity': backgroundTintOpacity,
      'skewX': skewX,
      'skewY': skewY,
      'skewPerspective': skewPerspective,
      'rotation': rotation,
      'background': background,
      'aspectRatio': aspectRatio,
      'watermark': watermark,
      'watermarkOpacity': watermarkOpacity,
      'watermarkSize': watermarkSize,
      'showBrowserFrame': showBrowserFrame,
      'width': width,
      'height': height,
    };
  }

  factory FancyShotProfile.fromMap(Map<String, dynamic> map) {
    return FancyShotProfile(
      name: (map['name'] ?? '') as String,
      backgroundPadding: ((map['backgroundPadding'] ?? 0.0) as num).toDouble(),
      imagePadding: ((map['imagePadding'] ?? 0.0) as num).toDouble(),
      imageScale: ((map['imageScale'] ?? 1.0) as num).toDouble(),
      backgroundType: BackgroundType.values[(map['backgroundType'] ?? 0) as int],
      backgroundImage: (map['backgroundImage'] ?? "resources/gradient/gradient1.jpg") as String,
      borderRadius: ((map['borderRadius'] ?? 0.0) as num).toDouble(),
      frameBorderWidth: ((map['frameBorderWidth'] ?? 0.0) as num).toDouble(),
      shadowSpread: ((map['shadowSpread'] ?? 0.0) as num).toDouble(),
      shadowRadius: ((map['shadowRadius'] ?? 0.0) as num).toDouble(),
      shadowOpacity: ((map['shadowOpacity'] ?? 0.35) as num).toDouble(),
      backgroundBlur: ((map['backgroundBlur'] ?? 0.0) as num).toDouble(),
      backgroundTintOpacity: ((map['backgroundTintOpacity'] ?? 0.0) as num).toDouble(),
      skewX: ((map['skewX'] ?? 0.0) as num).toDouble(),
      skewY: ((map['skewY'] ?? 0.0) as num).toDouble(),
      skewPerspective: ((map['skewPerspective'] ?? 0.0) as num).toDouble(),
      rotation: ((map['rotation'] ?? 0.0) as num).toDouble(),
      background: (map['background'] ?? 0) as int,
      aspectRatio: (map['aspectRatio'] ?? 0) as int,
      watermark: (map['watermark'] ?? '') as String,
      watermarkOpacity: ((map['watermarkOpacity'] ?? 0.90) as num).toDouble(),
      watermarkSize: ((map['watermarkSize'] ?? 14.0) as num).toDouble(),
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
    return 'FancyShotProfile(name: $name, backgroundPadding: $backgroundPadding, imagePadding: $imagePadding, imageScale: $imageScale, backgroundType: $backgroundType, backgroundImage: $backgroundImage, borderRadius: $borderRadius, frameBorderWidth: $frameBorderWidth, shadowSpread: $shadowSpread, shadowRadius: $shadowRadius, shadowOpacity: $shadowOpacity, backgroundBlur: $backgroundBlur, backgroundTintOpacity: $backgroundTintOpacity, skewX: $skewX, skewY: $skewY, skewPerspective: $skewPerspective, rotation: $rotation, background: $background, aspectRatio: $aspectRatio, watermark: $watermark, watermarkOpacity: $watermarkOpacity, watermarkSize: $watermarkSize, showBrowserFrame: $showBrowserFrame, width: $width, height: $height)';
  }

  @override
  bool operator ==(covariant FancyShotProfile other) {
    if (identical(this, other)) return true;

    return other.name == name &&
        other.backgroundPadding == backgroundPadding &&
        other.imagePadding == imagePadding &&
        other.imageScale == imageScale &&
        other.backgroundType == backgroundType &&
        other.backgroundImage == backgroundImage &&
        other.borderRadius == borderRadius &&
        other.frameBorderWidth == frameBorderWidth &&
        other.shadowSpread == shadowSpread &&
        other.shadowRadius == shadowRadius &&
        other.shadowOpacity == shadowOpacity &&
        other.backgroundBlur == backgroundBlur &&
        other.backgroundTintOpacity == backgroundTintOpacity &&
        other.skewX == skewX &&
        other.skewY == skewY &&
        other.skewPerspective == skewPerspective &&
        other.rotation == rotation &&
        other.background == background &&
        other.aspectRatio == aspectRatio &&
        other.watermark == watermark &&
        other.watermarkOpacity == watermarkOpacity &&
        other.watermarkSize == watermarkSize &&
        other.showBrowserFrame == showBrowserFrame &&
        other.width == width &&
        other.height == height;
  }

  @override
  int get hashCode {
    return name.hashCode ^
        backgroundPadding.hashCode ^
        imagePadding.hashCode ^
        imageScale.hashCode ^
        backgroundType.hashCode ^
        backgroundImage.hashCode ^
        borderRadius.hashCode ^
        frameBorderWidth.hashCode ^
        shadowSpread.hashCode ^
        shadowRadius.hashCode ^
        shadowOpacity.hashCode ^
        backgroundBlur.hashCode ^
        backgroundTintOpacity.hashCode ^
        skewX.hashCode ^
        skewY.hashCode ^
        skewPerspective.hashCode ^
        rotation.hashCode ^
        background.hashCode ^
        aspectRatio.hashCode ^
        watermark.hashCode ^
        watermarkOpacity.hashCode ^
        watermarkSize.hashCode ^
        showBrowserFrame.hashCode ^
        width.hashCode ^
        height.hashCode;
  }
}

class FancyShot {
  static List<ScreenCaptureUploadHost> loadUploadHosts() {
    final List<ScreenCaptureUploadHost> custom = Boxes.getSavedMap<ScreenCaptureUploadHost>(
      ScreenCaptureUploadHost.fromJson,
      "screenCaptureUploadHosts",
      def: <ScreenCaptureUploadHost>[],
    );
    // Built-in hosts are always prepended; user-defined custom hosts follow.
    return <ScreenCaptureUploadHost>[
      ...ScreenCaptureUploadHost.builtInHosts,
      ...custom.where((ScreenCaptureUploadHost h) => !h.isBuiltIn),
    ];
  }

  static Future<void> saveUploadHosts(List<ScreenCaptureUploadHost> hosts) {
    // Only persist user-defined custom hosts; built-in hosts are always re-injected at load time.
    final List<ScreenCaptureUploadHost> custom = hosts.where((ScreenCaptureUploadHost h) => !h.isBuiltIn).toList();
    return Boxes.updateSettings(
      "screenCaptureUploadHosts",
      jsonEncode(custom.map((ScreenCaptureUploadHost host) => host.toJson()).toList()),
    );
  }

  static List<FancyShotProfile> defaultProfiles() => <FancyShotProfile>[
        FancyShotProfile(
          name: "Default",
          backgroundPadding: 18,
          imagePadding: 6,
          backgroundType: BackgroundType.transparent,
          backgroundImage: "resources/gradient/gradient1.jpg",
          borderRadius: 10,
          frameBorderWidth: 1,
          shadowSpread: 1,
          shadowRadius: 14,
          shadowOpacity: 0.26,
          backgroundBlur: 0,
          background: 0,
          aspectRatio: 0,
          width: 0,
          height: 0,
          watermark: "",
        ),
        FancyShotProfile(
          name: "Self Background",
          backgroundPadding: 24,
          imagePadding: 10,
          backgroundType: BackgroundType.self,
          backgroundImage: "resources/gradient/gradient1.jpg",
          borderRadius: 12,
          frameBorderWidth: 1,
          shadowSpread: 2,
          shadowRadius: 20,
          shadowOpacity: 0.30,
          backgroundBlur: 12,
          background: 0xFF1B2432,
          backgroundTintOpacity: 0.20,
          aspectRatio: 0,
          width: 0,
          height: 0,
          watermark: "",
        ),
        FancyShotProfile(
          name: "Image Background",
          backgroundPadding: 36,
          imagePadding: 12,
          backgroundType: BackgroundType.stock,
          backgroundImage: "resources/gradient/gradient7.jpg",
          borderRadius: 14,
          frameBorderWidth: 1,
          shadowSpread: 3,
          shadowRadius: 24,
          shadowOpacity: 0.30,
          backgroundBlur: 20,
          background: 0xFF1D4ED8,
          backgroundTintOpacity: 0.12,
          showBrowserFrame: true,
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

    // Compute the exact canvas size at scale=1 so captureFromLongWidget receives
    // tight constraints.  captureFromWidget does NOT support constraints; using
    // captureFromLongWidget avoids the unbounded-viewport black-bitmap bug that
    // occurs with large/wide images.
    final _FancyShotFrameSurface surface = _FancyShotFrameSurface(
      captureImage: Image.memory(captureBytes, fit: BoxFit.fill, filterQuality: FilterQuality.high),
      captureBytesForBackground: captureBytes,
      profile: profile,
      surfaceColor: bgColor,
      sourceWidth: photo.width.toDouble(),
      sourceHeight: photo.height.toDouble(),
    );
    final Size canvasSize = surface.canvasSize;

    return screenshotController.captureFromLongWidget(
      MediaQuery(
        data: const MediaQueryData(),
        child: Material(
          color: Colors.transparent,
          child: surface,
        ),
      ),
      pixelRatio: 1.0,
      delay: Duration(milliseconds: (canvasSize.width >= 1000 || canvasSize.height >= 1000) ? 80 : 20),
      constraints: BoxConstraints.tight(canvasSize),
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
    if (capture == null || photo == null) return;

    final Uint8List output = await FancyShot.renderPresetCapture(
      captureBytes: capture!,
      profile: filters.copyWith(),
    );

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

// ignore: unused_element
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

  @override
  Widget build(BuildContext context) {
    return _FancyShotFrameSurface(
      captureBytesForBackground: captureBytes,
      captureImage: Image.memory(
        captureBytes,
        fit: BoxFit.fill,
        filterQuality: FilterQuality.high,
      ),
      profile: profile,
      surfaceColor: bgColor,
      sourceWidth: photo.width.toDouble(),
      sourceHeight: photo.height.toDouble(),
    );
  }
}

class _FancyShotFrameSurface extends StatelessWidget {
  const _FancyShotFrameSurface({
    required this.captureImage,
    required this.profile,
    required this.surfaceColor,
    required this.sourceWidth,
    required this.sourceHeight,
    this.captureBytesForBackground,
    this.scale = 1.0,
  });

  final Widget captureImage;
  final FancyShotProfile profile;
  final Color surfaceColor;
  final double sourceWidth;
  final double sourceHeight;
  final Uint8List? captureBytesForBackground;
  final double scale;
  Size get _captureSize => Size(
        sourceWidth * profile.imageScale * scale,
        sourceHeight * profile.imageScale * scale,
      );

  // The main layer's outer dimensions: capture + imagePadding on all sides +
  // optional browser bar height.
  // NOTE: frameBorderWidth is an *inset* BoxDecoration border — it does NOT
  // expand the container, so it must NOT be included in the size calculation.
  // When showBrowserFrame is true the top imagePadding is suppressed (the bar
  // itself acts as the top spacing) so only bottom imagePadding is counted.
  Size get _mainLayerSize {
    final double hPad = profile.imagePadding * 2 * scale; // horizontal: left+right
    final double vPad = profile.showBrowserFrame
        ? profile.imagePadding * scale // bottom only (top=0)
        : profile.imagePadding * 2 * scale; // top+bottom
    final double browserBar = profile.showBrowserFrame ? 32.0 * scale : 0.0;
    return Size(
      _captureSize.width + hPad,
      _captureSize.height + vPad + browserBar,
    );
  }

  // Public alias used by renderPresetCapture to pass explicit constraints.
  Size get canvasSize => _canvasSize;

  Size get _canvasSize {
    final double bp = profile.backgroundPadding * 2 * scale;
    double w = _mainLayerSize.width + bp;
    double h = _mainLayerSize.height + bp;
    final double? ratio = _aspectRatio();
    if (ratio != null) {
      if (w / h < ratio) {
        w = h * ratio;
      } else {
        h = w / ratio;
      }
    }
    return Size(w, h);
  }

  double? _aspectRatio() {
    switch (profile.aspectRatio) {
      case 1:
        return 1;
      case 2:
        return 3 / 2;
      case 3:
        return 4 / 3;
      case 4:
        return 16 / 9;
      case 5:
        return 9 / 16;
    }
    return null;
  }

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
          image: captureBytesForBackground == null
              ? null
              : DecorationImage(
                  image: MemoryImage(captureBytesForBackground!),
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

  Color _frameBorderColor() {
    if (profile.background != 0) {
      return Color(profile.background).withValues(alpha: 0.30);
    }
    return profile.showBrowserFrame ? Colors.black.withValues(alpha: 0.10) : Colors.white.withValues(alpha: 0.14);
  }

  Matrix4 _buildTransform() {
    final Matrix4 matrix = Matrix4.identity();
    if (profile.skewX != 0 || profile.skewY != 0) {
      matrix
        ..setEntry(3, 2, profile.skewPerspective)
        ..rotateX(0.1 * profile.skewY)
        ..rotateY(-0.1 * profile.skewX);
      // removed: ..scale(0.1) — this was shrinking the widget to 10% size
    }
    if (profile.rotation != 0) {
      matrix.rotateZ(profile.rotation * math.pi / 180);
    }
    return matrix;
  }

  @override
  Widget build(BuildContext context) {
    final Size capture = _captureSize;
    final Size canvas = _canvasSize;
    final BorderRadius radius = BorderRadius.circular(profile.borderRadius * scale);

    // ── capturedImageLayer ──────────────────────────────────────────────────
    // Exact source size, rounded corners, no shadow.
    final Widget capturedImageLayer = ClipRRect(
      borderRadius: radius,
      child: SizedBox(
        width: capture.width,
        height: capture.height,
        child: captureImage,
      ),
    );

    // ── mainImageLayer ──────────────────────────────────────────────────────
    // Grows outward from capture via imagePadding + frameBorderWidth.
    // Carries shadow and border. Never resizes capturedImageLayer.
    final Widget mainImageLayer = Container(
      // Remove width/height here — Column drives the size
      decoration: BoxDecoration(
        color: profile.showBrowserFrame ? const Color(0xFFEBEBEB) : surfaceColor,
        borderRadius: radius,
        border: profile.frameBorderWidth > 0
            ? Border.all(
                color: _frameBorderColor(),
                width: profile.frameBorderWidth * scale,
              )
            : null,
        boxShadow: (profile.shadowRadius > 0 || profile.shadowSpread > 0)
            ? <BoxShadow>[
                BoxShadow(
                  offset: Offset(0, 14 * scale),
                  spreadRadius: profile.shadowSpread * scale,
                  blurRadius: profile.shadowRadius * scale,
                  color: Colors.black.withValues(alpha: profile.shadowOpacity),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          // Optional browser chrome bar
          if (profile.showBrowserFrame)
            Container(
              width: capture.width + profile.imagePadding * 2 * scale,
              height: 32 * scale,
              padding: EdgeInsets.symmetric(horizontal: 14 * scale),
              decoration: BoxDecoration(
                color: const Color(0xFFEBEBEB),
                borderRadius: BorderRadius.only(
                  topLeft: Radius.circular(profile.borderRadius * scale),
                  topRight: Radius.circular(profile.borderRadius * scale),
                ),
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black.withValues(alpha: 0.05),
                    width: 1,
                  ),
                ),
              ),
              child: Row(
                children: <Widget>[
                  _trafficLight(const Color(0xFFFF5F56)),
                  const SizedBox(width: 8),
                  _trafficLight(const Color(0xFFFFBD2E)),
                  const SizedBox(width: 8),
                  _trafficLight(const Color(0xFF27C93F)),
                ],
              ),
            ),

          // imagePadding sits between the mainLayer edge and the capturedImageLayer.
          // When the browser bar is visible it already occupies the top space,
          // so we suppress the top padding to avoid a double-gap that pushes the
          // image down and causes overflow.
          Padding(
            padding: profile.showBrowserFrame
                ? EdgeInsets.fromLTRB(
                    profile.imagePadding * scale,
                    0,
                    profile.imagePadding * scale,
                    profile.imagePadding * scale,
                  )
                : EdgeInsets.all(profile.imagePadding * scale),
            child: capturedImageLayer,
          ),
        ],
      ),
    );

    // Watermark floats over mainImageLayer
    final Widget mainWithWatermark = Stack(
      clipBehavior: Clip.none,
      children: <Widget>[
        mainImageLayer,
        if (profile.watermark.isNotEmpty)
          Positioned(
            bottom: profile.imagePadding * scale + 6,
            right: profile.imagePadding * scale + 6,
            child: Transform(
              transform: Matrix4.skewX(-0.1),
              child: Text(
                profile.watermark,
                textAlign: TextAlign.right,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: profile.watermarkSize * scale,
                  letterSpacing: 0.4,
                  color: Colors.white.withValues(alpha: profile.watermarkOpacity),
                  shadows: <Shadow>[
                    Shadow(
                      blurRadius: 10,
                      color: Colors.black.withValues(alpha: 0.42),
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );

    // ── backgroundLayer + canvas ────────────────────────────────────────────
    // Canvas is sized to mainLayer + backgroundPadding + aspect ratio expansion.
    // The background fills the canvas. mainImageLayer is centered inside it.
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: canvas.width,
        height: canvas.height,
        child: Stack(
          fit: StackFit.expand,
          children: <Widget>[
            // 1. Background fills entire canvas
            Container(
              width: canvas.width,
              height: canvas.height,
              decoration: _backgroundDecoration(),
            ),

            // 2. Colour tint
            if (profile.background != 0 && profile.backgroundTintOpacity > 0)
              Container(
                color: Color(profile.background).withValues(alpha: profile.backgroundTintOpacity),
              ),

            // 3. Background blur (blurs background only, not the frame)
            if (profile.backgroundBlur > 0)
              ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: profile.backgroundBlur,
                    sigmaY: profile.backgroundBlur,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),

            // 4. mainImageLayer centered — backgroundPadding is the space
            //    between canvas edge and mainLayer, enforced by Center +
            //    the canvas being exactly mainLayer + backgroundPadding*2.
            Center(
              child: Transform(
                transform: _buildTransform(),
                filterQuality: FilterQuality.high,
                alignment: Alignment.center,
                child: mainWithWatermark,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _trafficLight(Color color) => Container(
        width: 12 * scale,
        height: 12 * scale,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
