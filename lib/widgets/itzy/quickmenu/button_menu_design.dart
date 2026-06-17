import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/util/theme_colors.dart';
import '../../../models/win32/win_utils.dart';
import '../../interface/theme_setup.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/font_picker/models/picker_font.dart';
import '../../widgets/font_picker/ui/font_picker.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/panel_opacity_gradient_editor.dart';
import 'package:filepicker_windows/filepicker_windows.dart';

class QuickMenuDesignButton extends StatelessWidget {
  const QuickMenuDesignButton({super.key});
  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "QuickMenu Design",
      icon: const Icon(Icons.palette_rounded),
      child: () => const _QuickMenuDesignPanel(),
      backdropFilter: false,
    );
  }
}

enum _QuickMenuPaletteMode {
  light,
  dark,
}

class _QuickMenuDesignPanel extends StatefulWidget {
  const _QuickMenuDesignPanel();

  @override
  State<_QuickMenuDesignPanel> createState() => _QuickMenuDesignPanelState();
}

class _QuickMenuDesignPanelState extends State<_QuickMenuDesignPanel> {
  late _QuickMenuPaletteMode _paletteMode;
  late final List<Map<ColorSwatch<Object>, String>> _lightPresets;
  late final List<Map<ColorSwatch<Object>, String>> _darkPresets;

  bool _isBackdropProcessing = false;
  int _backdropProcessingTotal = 0;
  int _backdropProcessingCompleted = 0;
  int _backdropProcessingConverted = 0;
  @override
  void initState() {
    super.initState();

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
  }

  @override
  void dispose() {
    super.dispose();
  }

  ThemeColors get _selectedTheme {
    return _paletteMode == _QuickMenuPaletteMode.dark ? user.darkTheme : user.lightTheme;
  }

  List<Map<ColorSwatch<Object>, String>> get _presetOptions {
    return _paletteMode == _QuickMenuPaletteMode.dark ? _darkPresets : _lightPresets;
  }

  List<List<int>> get _themeOptions {
    return _paletteMode == _QuickMenuPaletteMode.dark ? darkThemeOptions : lightThemeOptions;
  }

  Future<void> _persistThemeChanges() async {
    await Boxes.saveActiveQuickMenuThemes(notify: true);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _updateTheme(VoidCallback updater) async {
    setState(updater);
    await _persistThemeChanges();
  }

  Future<void> _switchDesign(QuickMenuDesigns design) async {
    await Boxes.switchQuickMenuDesign(design);
    if (!mounted) return;
    setState(() {});
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

    final String backdropsDir = "${WinUtils.getTabameAppDataFolder()}\\cache\\backdrops";
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
          QuickMenuFunctions.syncSelectedBackdrop();
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
    QuickMenuFunctions.syncSelectedBackdrop(selectedPath: 'resources/gradient/gradient$index.jpg');
    await _persistThemeChanges();
  }

  int get _selectedGradientIndex {
    final String path = user.activeBackdropPath;
    final RegExp re = RegExp(r'gradient(\d+)\.jpg$');
    final Match? m = re.firstMatch(path);
    if (m == null) return -1;
    return int.tryParse(m.group(1)!) ?? -1;
  }

  Future<void> _resetCurrentPalette() async {
    final QMDesignThemeSet defaults = Settings.createDefaultQuickMenuDesignThemes()[user.currentQuickMenuDesign.name]!;
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
          title: "QuickMenu Design",
          icon: Icons.dashboard_customize_outlined,
          buttonPressed: _resetCurrentPalette,
          buttonTooltip: "Reset To Default Colors",
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
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  _buildDesignsCard("QuickMenu", accent, onSurface),
                  const SizedBox(height: 8),
                  _buildDesignsCard("Launcher", accent, onSurface),
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
                  const SizedBox(height: 8),
                  _buildPanelTintCard(accent, onSurface),
                  const SizedBox(height: 8),
                ],
              ),
            ),
          ),
        ),
      ],
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
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              primary: false,
              dragStartBehavior: DragStartBehavior.down,
              physics: const ClampingScrollPhysics(),
              itemCount: isQuickMenu ? QuickMenuDesigns.values.length : LauncherDesign.values.length,
              separatorBuilder: (_, __) => const SizedBox(width: 6),
              itemBuilder: (BuildContext context, int index) {
                QuickMenuDesigns design = QuickMenuDesigns.classic;
                bool selected = isQuickMenu
                    ? user.currentQuickMenuDesign == design
                    : user.launcherDesign == LauncherDesign.values[index];

                if (isQuickMenu) {
                  design = QuickMenuDesigns.values[index];
                  selected = user.currentQuickMenuDesign == design;
                }
                return ChoiceChip(
                  label: isQuickMenu
                      ? Text(_designTitle(design))
                      : Text(LauncherDesign.values[index].name.toUpperCaseFirst()),
                  selected: selected,
                  onSelected: selected
                      ? null
                      : (_) async {
                          if (isQuickMenu) {
                            _switchDesign(design);
                          } else {
                            await Boxes.pref.setInt("launcherDesign", index);
                            user.launcherDesign = LauncherDesign.values[index];
                            setState(() {});
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
              },
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
                      "Set the border radius for the QuickMenu.",
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
                      QuickMenuFunctions.syncSelectedBackdrop();
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
              const SizedBox(height: 6),
              Material(
                type: MaterialType.transparency,
                child: ListTile(
                  visualDensity: const VisualDensity(vertical: -4),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
                  minTileHeight: 36, // optional
                  title: Text("Use the backdrop on Launcher", style: TextStyle(fontSize: Design.baseFontSize)),
                  onTap: () async {
                    await _updateTheme(() {
                      _selectedTheme.backdropLauncher = !_selectedTheme.backdropLauncher;
                      QuickMenuFunctions.syncSelectedBackdrop();
                    });
                  },
                  trailing: MiniToggleSwitch(
                    value: _selectedTheme.backdropLauncher,
                    onChanged: (bool value) async {
                      await _updateTheme(() {
                        _selectedTheme.backdropLauncher = !_selectedTheme.backdropLauncher;
                        QuickMenuFunctions.syncSelectedBackdrop();
                      });
                    },
                  ),
                ),
              )
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
            "Choose one custom image for the QuickMenu backdrop.",
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
                final bool isActive = user.activeBackdropPath == path;
                return Stack(
                  children: <Widget>[
                    Positioned.fill(
                      child: GestureDetector(
                        onTap: isActive
                            ? null
                            : () async {
                                QuickMenuFunctions.syncSelectedBackdrop(selectedPath: path);
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
                          QuickMenuFunctions.syncSelectedBackdrop();
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
          Text(
            "Typography",
            style: TextStyle(
              fontSize: Design.baseFontSize + 2.5,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Custom fonts for general UI and data entries.",
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
                      });
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
                      });
                      baseEntryStyle = GoogleFonts.getFont(
                        Design.entryFontFamily,
                        fontSize: Design.baseFontSize + 2,
                        color: Design.text,
                        fontWeight: FontWeight(Design.entryFontWeight),
                        fontStyle: Design.entryFontItalic ? FontStyle.italic : FontStyle.normal,
                      );
                      Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                      QuickMenuFunctions.refreshQuickMenu();
                    },
                  ),
                ),
              ],
            ),
          ),
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
                      _colorDescriptions[index],
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
                  InkWell(
                    onTap: () => _openCustomColorPicker(index),
                    borderRadius: BorderRadius.circular(8),
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
    return design.name;
  }
}

const List<String> _colorTitles = <String>[
  "Background Color",
  "Text Color",
  "Accent Color",
];

const List<String> _colorDescriptions = <String>[
  "Primary surface behind the QuickMenu content.",
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
