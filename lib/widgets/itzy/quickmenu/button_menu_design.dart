import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollCacheExtent;
import 'package:google_fonts/google_fonts.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/globals.dart';
import '../../../platform/app_paths.dart';
import '../../../models/settings.dart';
import '../../../models/util/theme_colors.dart';
import '../../interface/theme_setup.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/font_picker/models/picker_font.dart';
import '../../widgets/font_picker/ui/font_picker.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/panel_opacity_gradient_editor.dart';
import '../../../platform/file_picker_service.dart';

class QuickMenuDesignButton extends StatelessWidget {
  const QuickMenuDesignButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "QuickMenu Design",
      icon: const Icon(Icons.palette_rounded),
      onTap: () {
        Navigator.of(context).maybePop();
      },
      child: () => const _QuickMenuDesignPanel(),
      backdropFilter: false,
    );
  }
}

enum _QuickMenuPaletteMode {
  light,
  dark,
}

enum _DesignTarget {
  quickMenu,
  launcher,
}

class _QuickMenuDesignPanel extends StatefulWidget {
  const _QuickMenuDesignPanel();

  @override
  State<_QuickMenuDesignPanel> createState() => _QuickMenuDesignPanelState();
}

class _QuickMenuDesignPanelState extends State<_QuickMenuDesignPanel> {
  late _QuickMenuPaletteMode _paletteMode;
  late _DesignTarget _designTarget;
  late final List<Map<ColorSwatch<Object>, String>> _lightPresets;
  late final List<Map<ColorSwatch<Object>, String>> _darkPresets;
  final ScrollController _quickMenuDesignScrollController = ScrollController();
  final ScrollController _launcherDesignScrollController = ScrollController();
  final List<GlobalKey> _quickMenuDesignKeys = List<GlobalKey>.generate(
    QuickMenuDesigns.values.length,
    (_) => GlobalKey(),
  );
  final List<GlobalKey> _launcherDesignKeys = List<GlobalKey>.generate(
    LauncherDesign.values.length,
    (_) => GlobalKey(),
  );

  bool _isBackdropProcessing = false;
  int _backdropProcessingTotal = 0;
  int _backdropProcessingCompleted = 0;
  int _backdropProcessingConverted = 0;
  @override
  void initState() {
    super.initState();

    _designTarget = Globals.quickMenuPage == QuickMenuPage.launcher ? _DesignTarget.launcher : _DesignTarget.quickMenu;
    _paletteMode = user.themeTypeMode == ThemeType.dark ? _QuickMenuPaletteMode.dark : _QuickMenuPaletteMode.light;
    _lightPresets = <Map<ColorSwatch<Object>, String>>[
      getPredefinedColorSet(lightThemeOptions, 0, maximum: 24),
      getPredefinedColorSet(lightThemeOptions, 1, maximum: 24),
      getPredefinedColorSet(lightThemeOptions, 2, maximum: 24),
    ];
    _darkPresets = <Map<ColorSwatch<Object>, String>>[
      getPredefinedColorSet(darkThemeOptions, 0, maximum: 24),
      getPredefinedColorSet(darkThemeOptions, 1, maximum: 24),
      getPredefinedColorSet(darkThemeOptions, 2, maximum: 24),
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerSelectedDesign(isQuickMenu: _designTarget == _DesignTarget.quickMenu);
    });
  }

  @override
  void dispose() {
    _quickMenuDesignScrollController.dispose();
    _launcherDesignScrollController.dispose();
    super.dispose();
  }

  void _centerSelectedDesign({required bool isQuickMenu, int attempt = 0}) {
    final int selectedIndex = isQuickMenu
        ? QuickMenuDesigns.values.indexOf(user.currentQuickMenuDesign)
        : LauncherDesign.values.indexOf(user.launcherDesign);
    final ScrollController controller =
        isQuickMenu ? _quickMenuDesignScrollController : _launcherDesignScrollController;
    final BuildContext? selectedContext =
        (isQuickMenu ? _quickMenuDesignKeys : _launcherDesignKeys)[selectedIndex].currentContext;

    if (!mounted) return;
    if (!controller.hasClients || selectedContext == null) {
      if (attempt < 2) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _centerSelectedDesign(isQuickMenu: isQuickMenu, attempt: attempt + 1);
        });
      }
      return;
    }

    Scrollable.ensureVisible(
      selectedContext,
      alignment: 0.5,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  ThemeColors get _selectedTheme {
    if (_designTarget == _DesignTarget.launcher) {
      return _paletteMode == _QuickMenuPaletteMode.dark ? user.launcherDarkTheme : user.launcherLightTheme;
    }
    return _paletteMode == _QuickMenuPaletteMode.dark ? user.darkTheme : user.lightTheme;
  }

  List<Map<ColorSwatch<Object>, String>> get _presetOptions {
    return _paletteMode == _QuickMenuPaletteMode.dark ? _darkPresets : _lightPresets;
  }

  List<List<int>> get _themeOptions {
    return _paletteMode == _QuickMenuPaletteMode.dark ? darkThemeOptions : lightThemeOptions;
  }

  Future<void> _persistThemeChanges({bool customizeLauncherAppearance = true}) async {
    if (_designTarget == _DesignTarget.launcher) {
      if (customizeLauncherAppearance) {
        if (_paletteMode == _QuickMenuPaletteMode.dark) {
          user.launcherDarkThemeCustomized = true;
        } else {
          user.launcherLightThemeCustomized = true;
        }
      }
      await Boxes.saveLauncherDesignSettings(notify: true);
    } else {
      await Boxes.saveActiveQuickMenuThemes(notify: true);
    }
    await QuickMenuFunctions.refreshQuickMenu();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _updateTheme(
    VoidCallback updater, {
    bool customizeLauncherAppearance = true,
  }) async {
    setState(updater);
    await _persistThemeChanges(customizeLauncherAppearance: customizeLauncherAppearance);
  }

  Future<void> _switchDesign(QuickMenuDesigns design) async {
    await Boxes.switchQuickMenuDesign(design);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _switchLauncherDesign(LauncherDesign design) async {
    await Boxes.switchLauncherDesign(design);
    if (!mounted) return;
    setState(() {});
  }

  void _syncSelectedBackdrop({String? selectedPath}) {
    if (_designTarget == _DesignTarget.quickMenu) {
      QuickMenuFunctions.syncSelectedBackdrop(selectedPath: selectedPath);
      return;
    }

    final ThemeColors theme = _selectedTheme;
    if (theme.backdropType.isEmpty) {
      theme.backdropPath = '';
      return;
    }

    String nextPath = selectedPath ?? theme.backdropPath;
    if (theme.backdropType == 'builtIn') {
      if (!nextPath.startsWith('resources/gradient/')) {
        nextPath = QuickMenuFunctions.defaultBackdropPath;
      }
    } else if (theme.backdropType == 'custom') {
      if (!theme.backdropImages.contains(nextPath)) {
        nextPath = theme.backdropImages.isEmpty ? '' : theme.backdropImages.first;
      }
    } else {
      nextPath = '';
    }
    theme.backdropPath = nextPath;
  }

  Future<void> _addBackdropImages() async {
    if (_isBackdropProcessing) return;
    QuickMenuFunctions.keepOpen = true;
    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'Images': '*.jpg;*.jpeg;*.png;*.webp',
      }
      ..title = 'Select Backdrop Image';
    final List<File> results = picker.getFiles();
    Future<void>.delayed(const Duration(milliseconds: 1000), () {
      QuickMenuFunctions.keepOpen = false;
    });
    if (results.isEmpty) return;

    final String backdropsDir = AppPaths.cachePath('backdrops', forWrite: true);
    if (!Directory(backdropsDir).existsSync()) {
      Directory(backdropsDir).createSync(recursive: true);
    }

    setState(() {
      _isBackdropProcessing = true;
      _backdropProcessingTotal = results.length;
      _backdropProcessingCompleted = 0;
      _backdropProcessingConverted = 0;
    });

    bool changed = false;
    final int batchStartedAt = DateTime.now().millisecondsSinceEpoch;
    try {
      for (int i = 0; i < results.length; i++) {
        final File result = results[i];
        final String fileName = result.uri.pathSegments.last;
        final String targetPath = "$backdropsDir\\${batchStartedAt}_${i}_$fileName";
        try {
          await compute(_resizeAndSaveBackdropInPanel, <String, String>{
            'source': result.path,
            'target': targetPath,
          });
          _selectedTheme.backdropImages.add(targetPath);
          changed = true;
          if (!mounted) return;
          setState(() {
            _backdropProcessingConverted++;
          });
        } catch (e) {
          // ignore per-file errors
        } finally {
          if (mounted) {
            setState(() {
              _backdropProcessingCompleted = i + 1;
            });
          }
        }
      }
    } finally {
      if (mounted) {
        if (changed) {
          _syncSelectedBackdrop();
          await _persistThemeChanges();
        }
        setState(() {
          _isBackdropProcessing = false;
          _backdropProcessingCompleted = _backdropProcessingTotal;
        });
      }
    }
  }

  Future<void> _selectBuiltInGradient(int index) async {
    _syncSelectedBackdrop(selectedPath: 'resources/gradient/gradient$index.jpg');
    await _persistThemeChanges();
  }

  int get _selectedGradientIndex {
    final String path = _selectedTheme.backdropPath;
    final RegExp re = RegExp(r'gradient(\d+)\.jpg$');
    final Match? m = re.firstMatch(path);
    if (m == null) return -1;
    return int.tryParse(m.group(1)!) ?? -1;
  }

  Future<void> _resetCurrentPalette() async {
    if (_designTarget == _DesignTarget.launcher) {
      final LauncherDesignThemeSet defaults =
          Settings.createDefaultLauncherDesignThemes()[user.launcherDesign.displayName]!;
      await _updateTheme(() {
        final ThemeColors source =
            _paletteMode == _QuickMenuPaletteMode.dark ? defaults.darkTheme : defaults.lightTheme;
        final ThemeColors copy = ThemeColors.fromMap(source.toMap());
        if (_paletteMode == _QuickMenuPaletteMode.dark) {
          user.launcherDarkTheme = copy;
          user.launcherDarkThemeCustomized = true;
          user.launcherDarkFontCustomized = false;
        } else {
          user.launcherLightTheme = copy;
          user.launcherLightThemeCustomized = true;
          user.launcherLightFontCustomized = false;
        }
        user.launcherUseCustomFont = false;
        _syncSelectedBackdrop();
      }, customizeLauncherAppearance: false);
      return;
    }

    final QMDesignThemeSet defaults =
        Settings.createDefaultQuickMenuDesignThemes()[user.currentQuickMenuDesign.displayName]!;
    await _updateTheme(() {
      if (_paletteMode == _QuickMenuPaletteMode.dark) {
        user.darkTheme = defaults.darkTheme.copyWith();
      } else {
        user.lightTheme = defaults.lightTheme.copyWith();
      }
    });
  }

  Future<void> _updateColor(int index, Color color) async {
    await _updateTheme(() {
      if (index == 0) {
        _selectedTheme.background = color;
      } else if (index == 1) {
        _selectedTheme.text = color;
      } else {
        _selectedTheme.accent = color;
      }
    });
  }

  Future<void> _openCustomColorPicker(int index) async {
    final Color startColor = switch (index) {
      0 => _selectedTheme.background,
      1 => _selectedTheme.text,
      _ => _selectedTheme.accent,
    };
    Color pendingColor = startColor;

    final bool? apply = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          title: Text(
            _colorTitles[index],
            style: Theme.of(dialogContext).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
          ),
          content: CustomColorPicker(
            startColor: startColor,
            themeOptions: _themeOptions,
            colorIndex: index,
            onColorChanged: (Color color) => pendingColor = color,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text("Cancel"),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text("Apply"),
            ),
          ],
        );
      },
    );

    if (apply == true) {
      await _updateColor(index, pendingColor);
    }
  }

  void _selectDesignTarget(_DesignTarget target) {
    if (_designTarget == target) return;
    setState(() => _designTarget = target);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _centerSelectedDesign(isQuickMenu: target == _DesignTarget.quickMenu);
    });
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color accent = Design.accent;
    final Color onSurface = theme.colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: _designTarget == _DesignTarget.quickMenu ? "QuickMenu Design" : "Launcher Design",
          icon: Icons.dashboard_customize_outlined,
          buttonPressed: _resetCurrentPalette,
          buttonTooltip: "Reset To Design Defaults",
          buttonIcon: Icons.history,
          extraActions: <Widget>[
            CustomTooltip(
              message: "Change to ${user.isDark(context) ? "Light" : "Dark"}",
              child: IconButton(
                icon: const Icon(Icons.theater_comedy_sharp),
                onPressed: () {
                  bool isSimple = false;
                  if (<ThemeType>[ThemeType.light, ThemeType.dark].contains(user.themeType)) isSimple = true;

                  final bool switchingToDark = !user.isDark(context);
                  user.themeType = switchingToDark ? ThemeType.dark : ThemeType.light;
                  if (isSimple) Boxes.updateSettings("themeType", user.themeType.index);

                  // ✅ Keep _paletteMode in sync with the new theme
                  setState(() {
                    _paletteMode = switchingToDark ? _QuickMenuPaletteMode.dark : _QuickMenuPaletteMode.light;
                  });

                  // ✅ Sync the active backdrop path for the newly active theme
                  QuickMenuFunctions.syncSelectedBackdrop();

                  Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                },
              ),
            ),
          ],
        ),
        _buildTargetTabs(accent, onSurface),
        const SizedBox(height: 10),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 2,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: accent.withAlpha(200),
            inactiveTrackColor: onSurface.withAlpha(20),
            thumbColor: accent,
          ),
          child: Flexible(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              children: <Widget>[
                _buildDesignsCard(
                  _designTarget == _DesignTarget.quickMenu ? "QuickMenu" : "Launcher",
                  accent,
                  onSurface,
                ),
                const SizedBox(height: 8),
                ...List<Widget>.generate(_colorTitles.length, (int index) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == _colorTitles.length - 1 ? 0 : 8),
                    child: _buildColorCard(accent, onSurface, index),
                  );
                }),
                const SizedBox(height: 8),
                _buildBorderRadiusCard(accent, onSurface),
                const SizedBox(height: 8),
                _buildFontPickerCard(accent, onSurface),
                const SizedBox(height: 8),
                _buildTransparencyGradientCard(accent, onSurface),
                const SizedBox(height: 8),
                _buildBackdropSourceCard(accent, onSurface),
                const SizedBox(height: 8),
                if (_selectedTheme.backdropType == 'builtIn') ...<Widget>[
                  _buildBuiltInGradientPickerCard(accent, onSurface),
                  const SizedBox(height: 8),
                ],
                if (_selectedTheme.backdropType == 'custom') ...<Widget>[
                  _buildBackdropImagesCard(accent, onSurface),
                  const SizedBox(height: 8),
                ],
                if (_selectedTheme.backdropType.isNotEmpty) ...<Widget>[
                  _buildBackdropOpacityCard(accent, onSurface),
                  const SizedBox(height: 8),
                ],
                if (_designTarget == _DesignTarget.quickMenu) ...<Widget>[
                  const SizedBox(height: 8),
                  _buildPanelTintCard(accent, onSurface),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTargetTabs(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: onSurface.withAlpha(18))),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: _buildTargetTab(
              target: _DesignTarget.quickMenu,
              label: "QuickMenu",
              icon: Icons.dashboard_customize_outlined,
              accent: accent,
              onSurface: onSurface,
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: _buildTargetTab(
              target: _DesignTarget.launcher,
              label: "Launcher",
              icon: Icons.search_rounded,
              accent: accent,
              onSurface: onSurface,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTargetTab({
    required _DesignTarget target,
    required String label,
    required IconData icon,
    required Color accent,
    required Color onSurface,
  }) {
    final bool selected = _designTarget == target;
    return InkWell(
      onTap: () => _selectDesignTarget(target),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? accent.withAlpha(18) : onSurface.withAlpha(7),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: selected ? accent.withAlpha(80) : onSurface.withAlpha(18)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(icon, size: 14, color: selected ? accent : onSurface.withAlpha(130)),
            const SizedBox(width: 6),
            Text(
              label.toUpperCase(),
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: selected ? accent : onSurface.withAlpha(180),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDesignsCard(String type, Color accent, Color onSurface) {
    final bool isQuickMenu = type == "QuickMenu";
    final String items =
        isQuickMenu ? QuickMenuDesigns.values.length.toString() : LauncherDesign.values.length.toString();
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isQuickMenu ? "QuickMenu Design Type" : "Launcher Design Type",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Choose one of the $items Designs.",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 0.5,
                        color: onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              _buildMetaChip(
                label: items,
                background: accent.withAlpha(18),
                foreground: accent.withAlpha(220),
              ),
            ],
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 38,
            child: ListView(
              controller: isQuickMenu ? _quickMenuDesignScrollController : _launcherDesignScrollController,
              scrollDirection: Axis.horizontal,
              primary: false,
              scrollCacheExtent: const ScrollCacheExtent.pixels(10000),
              dragStartBehavior: DragStartBehavior.down,
              physics: const ClampingScrollPhysics(),
              children:
                  List<Widget>.generate(isQuickMenu ? QuickMenuDesigns.values.length : LauncherDesign.values.length, (
                int index,
              ) {
                QuickMenuDesigns design = QuickMenuDesigns.classic;
                bool selected = isQuickMenu
                    ? user.currentQuickMenuDesign == design
                    : user.launcherDesign == LauncherDesign.values[index];

                if (isQuickMenu) {
                  design = QuickMenuDesigns.values[index];
                  selected = user.currentQuickMenuDesign == design;
                }
                return ChoiceChip(
                  key: (isQuickMenu ? _quickMenuDesignKeys : _launcherDesignKeys)[index],
                  label: isQuickMenu ? Text(_designTitle(design)) : Text(LauncherDesign.values[index].displayName),
                  selected: selected,
                  onSelected: selected
                      ? null
                      : (_) async {
                          if (isQuickMenu) {
                            _switchDesign(design);
                          } else {
                            await _switchLauncherDesign(LauncherDesign.values[index]);
                          }
                        },
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(
                    fontSize: Design.baseFontSize + 1.5,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? accent : onSurface,
                  ),
                  labelPadding: const EdgeInsets.all(0),
                  showCheckmark: false,
                  selectedColor: accent.withAlpha(18),
                  side: BorderSide(
                    color: selected ? accent.withAlpha(70) : onSurface.withAlpha(20),
                  ),
                  backgroundColor: onSurface.withAlpha(8),
                );
              }).expand((Widget chip) => <Widget>[chip, const SizedBox(width: 6)]).toList()
                    ..removeLast(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBorderRadiusCard(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 6),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Border Radius",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Set the border radius for the ${_designTarget == _DesignTarget.quickMenu ? "QuickMenu" : "Launcher"}.",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 0.5,
                        color: onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              _buildMetaChip(
                label: "${_selectedTheme.borderRadius}",
                background: accent.withAlpha(18),
                foreground: accent.withAlpha(220),
              ),
            ],
          ),
          Slider(
            min: 0,
            max: 40,
            value: _selectedTheme.borderRadius.toDouble().clamp(0, 40),
            activeColor: accent,
            inactiveColor: accent.withAlpha(40),
            onChanged: (double value) {
              setState(() => _selectedTheme.borderRadius = value.floorToDouble());
              Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
            },
            onChangeEnd: (double value) async {
              _selectedTheme.borderRadius = value.floorToDouble();
              await _persistThemeChanges();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildPanelTintCard(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 6),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Panel Tint",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Panel tint strength for this palette.",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 0.5,
                        color: onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              _buildMetaChip(
                label: "${_selectedTheme.gradientAlpha}",
                background: accent.withAlpha(18),
                foreground: accent.withAlpha(220),
              ),
            ],
          ),
          Slider(
            min: 0,
            max: 255,
            value: _selectedTheme.gradientAlpha.toDouble().clamp(0, 255),
            activeColor: accent,
            inactiveColor: accent.withAlpha(40),
            onChanged: (double value) {
              setState(() => _selectedTheme.gradientAlpha = value.round());
              Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
            },
            onChangeEnd: (double value) async {
              _selectedTheme.gradientAlpha = value.round();
              await _persistThemeChanges();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackdropSourceCard(Color accent, Color onSurface) {
    const Map<String, String> options = <String, String>{
      '': 'None',
      'builtIn': 'Built-in',
      'custom': 'Custom',
    };
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Backdrop Source",
                style: TextStyle(
                  fontSize: Design.baseFontSize + 2.5,
                  fontWeight: FontWeight.w700,
                  color: onSurface,
                ),
              ),
              const SizedBox(height: 2),
              const SizedBox(width: 8),
              Center(
                child: ToggleButtons(
                  isSelected: options.keys.map((String key) => key == _selectedTheme.backdropType).toList(),
                  onPressed: (int index) async {
                    await _updateTheme(() {
                      _selectedTheme.backdropType = options.keys.elementAt(index);
                      _syncSelectedBackdrop();
                    });
                  },
                  borderRadius: BorderRadius.circular(8),
                  selectedColor: accent,
                  fillColor: accent.withAlpha(18),
                  textStyle: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.bold),
                  constraints: const BoxConstraints(minHeight: 30),
                  children: options.values
                      .map((String val) => Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(val),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBuiltInGradientPickerCard(Color accent, Color onSurface) {
    final int selected = _selectedGradientIndex;
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Built-in Gradient",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Choose one of the ${Globals.totalGradients} built-in gradients.",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 0.5,
                        color: onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              _buildMetaChip(
                label: selected >= 0 ? "${selected + 1}" : "1",
                background: accent.withAlpha(18),
                foreground: accent.withAlpha(220),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 3,
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              childAspectRatio: 1.5,
            ),
            itemCount: Globals.totalGradients,
            itemBuilder: (BuildContext context, int index) {
              final bool isSelected = selected == index;
              return GestureDetector(
                onTap: isSelected ? null : () => _selectBuiltInGradient(index),
                child: Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.asset(
                          'resources/gradient/gradient$index.jpg',
                          fit: BoxFit.cover,
                          errorBuilder: (BuildContext ctx, Object e, StackTrace? s) => Container(
                            decoration: BoxDecoration(
                              color: onSurface.withAlpha(14),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Center(
                              child: Text(
                                '${index + 1}',
                                style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(100)),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isSelected)
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: accent, width: 2),
                          ),
                          child: Align(
                            alignment: Alignment.bottomRight,
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Container(
                                padding: const EdgeInsets.all(2),
                                decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                                child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      )
                    else
                      Positioned.fill(
                        child: Container(
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: onSurface.withAlpha(20)),
                          ),
                        ),
                      ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBackdropImagesCard(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "Custom Backdrop Image",
            style: TextStyle(fontSize: Design.baseFontSize + 2.5, fontWeight: FontWeight.w700, color: onSurface),
          ),
          const SizedBox(height: 2),
          Text(
            "Choose one custom image for the ${_designTarget == _DesignTarget.quickMenu ? "QuickMenu" : "Launcher"} backdrop.",
            style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: onSurface.withAlpha(150)),
          ),
          const SizedBox(height: 10),
          if (_selectedTheme.backdropImages.isEmpty)
            Container(
              padding: const EdgeInsets.symmetric(vertical: 16),
              decoration: BoxDecoration(
                color: onSurface.withAlpha(6),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: onSurface.withAlpha(14)),
              ),
              child: Center(
                child: Column(
                  children: <Widget>[
                    Icon(Icons.image_search_rounded, size: 28, color: onSurface.withAlpha(50)),
                    const SizedBox(height: 6),
                    Text(
                      "No custom images added",
                      style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(100)),
                    ),
                  ],
                ),
              ),
            )
          else
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                mainAxisSpacing: 6,
                crossAxisSpacing: 6,
                childAspectRatio: 1.5,
              ),
              itemCount: _selectedTheme.backdropImages.length,
              itemBuilder: (BuildContext context, int index) {
                final String path = _selectedTheme.backdropImages[index];
                final bool isActive = _selectedTheme.backdropPath == path;
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: isActive
                            ? null
                            : () async {
                                _syncSelectedBackdrop(selectedPath: path);
                                await _persistThemeChanges();
                              },
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(6),
                          child: Image.file(
                            File(path),
                            cacheWidth: 200,
                            fit: BoxFit.cover,
                            errorBuilder: (BuildContext ctx, Object e, StackTrace? s) => Container(
                              color: onSurface.withAlpha(14),
                              child: const Icon(Icons.broken_image_rounded, size: 18),
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (isActive)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: Container(
                            decoration: BoxDecoration(
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: accent, width: 2),
                            ),
                            child: Align(
                              alignment: Alignment.bottomRight,
                              child: Padding(
                                padding: const EdgeInsets.all(3),
                                child: Container(
                                  padding: const EdgeInsets.all(2),
                                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                                  child: const Icon(Icons.check_rounded, size: 10, color: Colors.white),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: 3,
                      right: 3,
                      child: InkWell(
                        onTap: () async {
                          final String removedPath = _selectedTheme.backdropImages[index];
                          _selectedTheme.backdropImages.remove(removedPath);
                          _syncSelectedBackdrop();
                          await _updateTheme(() {});
                          if (File(removedPath).existsSync()) {
                            try {
                              await File(removedPath).delete();
                            } catch (_) {}
                          }
                        },
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                          child: const Icon(Icons.close_rounded, size: 12, color: Colors.white),
                        ),
                      ),
                    ),
                  ],
                );
              },
            ),
          const SizedBox(height: 10),
          if (_isBackdropProcessing) ...<Widget>[
            Row(
              children: <Widget>[
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: accent.withAlpha(200)),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    "Converting $_backdropProcessingConverted / $_backdropProcessingTotal",
                    style: TextStyle(
                        fontSize: Design.baseFontSize + 1,
                        fontWeight: FontWeight.w700,
                        color: onSurface.withAlpha(200)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            LinearProgressIndicator(
              value: _backdropProcessingTotal == 0 ? null : _backdropProcessingCompleted / _backdropProcessingTotal,
              minHeight: 3,
              borderRadius: BorderRadius.circular(999),
              color: accent,
              backgroundColor: accent.withAlpha(35),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _isBackdropProcessing ? null : _addBackdropImages,
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 10),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                side: BorderSide(color: accent.withAlpha(80)),
                visualDensity: VisualDensity.compact,
              ),
              icon: Icon(
                _isBackdropProcessing ? Icons.hourglass_top_rounded : Icons.add_photo_alternate_rounded,
                size: 16,
              ),
              label: Text(
                _isBackdropProcessing ? "Converting..." : "Add Image",
                style: TextStyle(fontSize: Design.baseFontSize + 1.5, fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBackdropOpacityCard(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 6),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Backdrop Intensity",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Opacity of the background image layer.",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 0.5,
                        color: onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              _buildMetaChip(
                label: "${(_selectedTheme.backdropOpacity * 100).toInt()}%",
                background: accent.withAlpha(18),
                foreground: accent.withAlpha(220),
              ),
            ],
          ),
          Slider(
            min: 0.0,
            max: 1.0,
            value: _selectedTheme.backdropOpacity.clamp(0.0, 1.0),
            activeColor: accent,
            inactiveColor: accent.withAlpha(40),
            onChanged: (double value) {
              setState(() => _selectedTheme.backdropOpacity = value);
              Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
            },
            onChangeEnd: (double value) async {
              _selectedTheme.backdropOpacity = value;
              await _persistThemeChanges();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFontPickerCard(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  "Typography",
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 2.5,
                    fontWeight: FontWeight.w700,
                    color: onSurface,
                  ),
                ),
              ),
              if (_designTarget == _DesignTarget.launcher)
                _buildMetaChip(
                  label: user.launcherUseCustomFont ? "CUSTOM" : "DESIGN FONT",
                  background: (user.launcherUseCustomFont ? accent : onSurface).withAlpha(18),
                  foreground: user.launcherUseCustomFont ? accent : onSurface.withAlpha(170),
                ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            _designTarget == _DesignTarget.launcher
                ? "Choose launcher fonts, then decide whether they replace each design's built-in type."
                : "Custom fonts for general UI and data entries.",
            style: TextStyle(
              fontSize: Design.baseFontSize + 0.5,
              color: onSurface.withAlpha(150),
            ),
          ),
          const SizedBox(height: 10),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: _fontPreviewTile(
                    "UI Font",
                    _selectedTheme.uiFontFamily,
                    _selectedTheme.uiFontWeight,
                    _selectedTheme.uiFontItalic,
                    (PickerFont font) async {
                      await _updateTheme(() {
                        _selectedTheme.uiFontFamily = font.fontFamily;
                        _selectedTheme.uiFontWeight = font.fontWeight.value;
                        _selectedTheme.uiFontItalic = font.fontStyle == FontStyle.italic;
                        if (_designTarget == _DesignTarget.launcher) {
                          if (_paletteMode == _QuickMenuPaletteMode.dark) {
                            user.launcherDarkFontCustomized = true;
                          } else {
                            user.launcherLightFontCustomized = true;
                          }
                          user.launcherUseCustomFont = true;
                        }
                      }, customizeLauncherAppearance: false);
                      Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                      QuickMenuFunctions.refreshQuickMenu();
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _fontPreviewTile(
                    "Entry Font",
                    _selectedTheme.entryFontFamily,
                    _selectedTheme.entryFontWeight,
                    _selectedTheme.entryFontItalic,
                    (PickerFont font) async {
                      await _updateTheme(() {
                        _selectedTheme.entryFontFamily = font.fontFamily;
                        _selectedTheme.entryFontWeight = font.fontWeight.value;
                        _selectedTheme.entryFontItalic = font.fontStyle == FontStyle.italic;
                        if (_designTarget == _DesignTarget.launcher) {
                          if (_paletteMode == _QuickMenuPaletteMode.dark) {
                            user.launcherDarkFontCustomized = true;
                          } else {
                            user.launcherLightFontCustomized = true;
                          }
                          user.launcherUseCustomFont = true;
                        }
                      }, customizeLauncherAppearance: false);
                      if (_designTarget == _DesignTarget.quickMenu) {
                        baseEntryStyle = GoogleFonts.getFont(
                          Design.entryFontFamily,
                          fontSize: Design.baseFontSize + 2,
                          color: Design.text,
                          fontWeight: FontWeight(Design.entryFontWeight),
                          fontStyle: Design.entryFontItalic ? FontStyle.italic : FontStyle.normal,
                        );
                      }
                      Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                      QuickMenuFunctions.refreshQuickMenu();
                    },
                  ),
                ),
              ],
            ),
          ),
          if (_designTarget == _DesignTarget.launcher) ...<Widget>[
            const SizedBox(height: 8),
            _buildLauncherFontOverrideOption(accent, onSurface),
          ],
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "Base font size",
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              _buildMetaChip(
                label: "${_selectedTheme.baseFontSize}",
                background: accent.withAlpha(18),
                foreground: accent.withAlpha(220),
              ),
            ],
          ),
          Slider(
            min: 8,
            max: 16,
            divisions: 8,
            showValueIndicator: ShowValueIndicator.onDrag,
            value: _selectedTheme.baseFontSize.toDouble().clamp(8, 16),
            activeColor: accent,
            inactiveColor: accent.withAlpha(40),
            onChanged: (double value) {
              // setState(() => _selectedTheme.baseFontSize = value.floorToDouble());
              // Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
            },
            onChangeEnd: (double value) async {
              await _updateTheme(() {
                _selectedTheme.baseFontSize = value.floorToDouble();
              });
              _selectedTheme.baseFontSize = value.floorToDouble();
              Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
              await _persistThemeChanges();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLauncherFontOverrideOption(Color accent, Color onSurface) {
    final bool enabled = user.launcherUseCustomFont;

    Future<void> updateOverride(bool value) async {
      await _updateTheme(
        () => user.launcherUseCustomFont = value,
        customizeLauncherAppearance: false,
      );
    }

    return InkWell(
      onTap: () => updateOverride(!enabled),
      borderRadius: BorderRadius.circular(8),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.fromLTRB(9, 7, 5, 7),
        decoration: BoxDecoration(
          color: enabled ? accent.withAlpha(10) : onSurface.withAlpha(5),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: enabled ? accent.withAlpha(45) : onSurface.withAlpha(16)),
        ),
        child: Row(
          children: <Widget>[
            Icon(
              enabled ? Icons.font_download_rounded : Icons.auto_fix_off_rounded,
              size: 16,
              color: enabled ? accent : onSurface.withAlpha(110),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Override Design Font",
                    style: TextStyle(
                      fontSize: Design.baseFontSize + 1,
                      fontWeight: FontWeight.w700,
                      color: onSurface,
                    ),
                  ),
                  const SizedBox(height: 1),
                  Text(
                    enabled
                        ? "Use the launcher fonts selected above."
                        : "Keep the font supplied by each launcher design.",
                    style: TextStyle(
                      fontSize: Design.baseFontSize,
                      color: onSurface.withAlpha(145),
                    ),
                  ),
                ],
              ),
            ),
            Checkbox(
              value: enabled,
              onChanged: (bool? value) => updateOverride(value ?? false),
              visualDensity: VisualDensity.compact,
            ),
          ],
        ),
      ),
    );
  }

  Widget _fontPreviewTile(
      String title, String family, int weight, bool italic, ValueChanged<PickerFont> onFontChanged) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(30),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context).colorScheme.onSurface.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title,
              style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: Design.baseFontSize + 1.5,
                  color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 2),
          Text(
            "Preview: $family",
            style: GoogleFonts.getFont(
              family,
              fontWeight: FontWeight.values.firstWhere(
                (FontWeight w) => w.value == weight,
                orElse: () => FontWeight.normal,
              ),
              fontStyle: italic ? FontStyle.italic : FontStyle.normal,
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: InkWell(
              onTap: () => _openFontPicker(family, onFontChanged),
              borderRadius: BorderRadius.circular(8),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurface.withAlpha(14),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  "Change",
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 0.5,
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.onSurface.withAlpha(185),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openFontPicker(String initialFamily, ValueChanged<PickerFont> onFontChanged) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          backgroundColor: Theme.of(dialogContext).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: SizedBox(
            width: 400,
            height: 500,
            child: FontPicker(
              initialFontFamily: initialFamily,
              showInDialog: true,
              onFontChanged: onFontChanged,
            ),
          ),
        );
      },
    );
  }

  Widget _buildTransparencyGradientCard(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "Interface Transparency Gradient",
            style: TextStyle(
              fontSize: Design.baseFontSize + 2.5,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Overall panel transparency stops.",
            style: TextStyle(
              fontSize: Design.baseFontSize + 0.5,
              color: onSurface.withAlpha(150),
            ),
          ),
          const SizedBox(height: 10),
          PanelOpacityGradientEditor(
            points: _selectedTheme.panelOpacityPoints,
            begin: _selectedTheme.panelOpacityBegin,
            end: _selectedTheme.panelOpacityEnd,
            onChanged: (List<double> points) async {
              setState(() => _selectedTheme.panelOpacityPoints = points);
              Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
              await _persistThemeChanges();
            },
            onBeginChanged: (String val) async {
              setState(() => _selectedTheme.panelOpacityBegin = val);
              Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
              await _persistThemeChanges();
            },
            onEndChanged: (String val) async {
              setState(() => _selectedTheme.panelOpacityEnd = val);
              Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
              await _persistThemeChanges();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildColorCard(Color accent, Color onSurface, int index) {
    final Color currentColor = switch (index) {
      0 => _selectedTheme.background,
      1 => _selectedTheme.text,
      _ => _selectedTheme.accent,
    };

    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 10),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              _buildSwatch(currentColor, onSurface, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      _colorTitles[index],
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 2.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      index == 0
                          ? "Primary surface behind the ${_designTarget == _DesignTarget.quickMenu ? "QuickMenu" : "Launcher"} content."
                          : _colorDescriptions[index],
                      style: TextStyle(
                        fontSize: Design.baseFontSize + 0.5,
                        height: 1.25,
                        color: onSurface.withAlpha(150),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: <Widget>[
                  _buildMetaChip(
                    label: _hexLabel(currentColor),
                    background: currentColor.withAlpha(20),
                    foreground: onSurface.withAlpha(185),
                  ),
                  const SizedBox(height: 5),
                  MouseRegion(
                    cursor: SystemMouseCursors.click,
                    child: InkWell(
                      onTap: () => _openCustomColorPicker(index),
                      borderRadius: BorderRadius.circular(8),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(14),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            "Pick",
                            style: TextStyle(
                              fontSize: Design.baseFontSize + 0.5,
                              fontWeight: FontWeight.w700,
                              color: accent.withAlpha(220),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          ListColors(
            colorsNameMap: _presetOptions[index],
            onColorChanged: (Color color) => _updateColor(index, color),
          ),
        ],
      ),
    );
  }

  BoxDecoration _cardDecoration(Color onSurface, {Color? accent, bool highlighted = false}) {
    return BoxDecoration(
      color: highlighted ? (accent ?? onSurface).withAlpha(10) : onSurface.withAlpha(7),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(
        color: highlighted ? (accent ?? onSurface).withAlpha(30) : onSurface.withAlpha(16),
      ),
    );
  }

  Widget _buildMetaChip({
    required String label,
    required Color background,
    required Color foreground,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: Design.baseFontSize + 0.5,
          fontWeight: FontWeight.w700,
          color: foreground,
        ),
      ),
    );
  }

  Widget _buildSwatch(Color color, Color outline, {double size = 20}) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color,
        shape: BoxShape.circle,
        border: Border.all(color: outline.withAlpha(35)),
      ),
    );
  }

  String _hexLabel(Color color) {
    return "#${color.toInt32.toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}";
  }

  String _designTitle(QuickMenuDesigns design) {
    return design.displayName;
  }
}

const List<String> _colorTitles = <String>[
  "Background Color",
  "Text Color",
  "Accent Color",
];

const List<String> _colorDescriptions = <String>[
  "",
  "Labels, titles, and general text color.",
  "Highlights, active states, and focus color.",
];

Future<void> _resizeAndSaveBackdropInPanel(Map<String, String> args) async {
  final String sourcePath = args['source']!;
  final String targetPath = args['target']!;

  final File sourceFile = File(sourcePath);
  if (!sourceFile.existsSync()) return;

  try {
    final Uint8List sourceBytes = await sourceFile.readAsBytes();
    final img.Image? decoded = img.decodeImage(sourceBytes);

    if (decoded == null) {
      await sourceFile.copy(targetPath);
      return;
    }

    if (decoded.width > 1200) {
      final img.Image resized = img.copyResize(decoded, width: 1200);
      final Uint8List encoded = Uint8List.fromList(img.encodeJpg(resized, quality: 90));
      await File(targetPath).writeAsBytes(encoded);
    } else {
      await sourceFile.copy(targetPath);
    }
  } catch (e) {
    if (sourceFile.existsSync()) {
      await sourceFile.copy(targetPath);
    }
  }
}
