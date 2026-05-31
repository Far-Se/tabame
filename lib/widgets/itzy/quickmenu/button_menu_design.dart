import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/util/theme_colors.dart';
import '../../../pages/launcher/launcher_design.dart';
import '../../interface/theme_setup.dart';
import '../../widgets/color_picker.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/font_picker/models/picker_font.dart';
import '../../widgets/font_picker/ui/font_picker.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/panel_opacity_gradient_editor.dart';

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
  LauncherDesign launcherDesign = LauncherDesign.classic;
  @override
  void initState() {
    super.initState();

    final int savedIndex = Boxes.pref.getInt('launcherDesign') ?? 0;
    launcherDesign = LauncherDesign.values[savedIndex.clamp(0, LauncherDesign.values.length - 1)];
    _paletteMode =
        userSettings.themeTypeMode == ThemeType.dark ? _QuickMenuPaletteMode.dark : _QuickMenuPaletteMode.light;
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
    return _paletteMode == _QuickMenuPaletteMode.dark ? userSettings.darkTheme : userSettings.lightTheme;
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

  Future<void> _shuffleBackdrop() async {
    final ThemeColors currentTheme = _selectedTheme;
    if (currentTheme.backdropType == 'builtIn') {
      final int random = math.Random().nextInt(10);
      userSettings.activeBackdropPath = 'resources/gradient/gradient$random.jpg';
    } else {
      final List<String> images = currentTheme.backdropImages;
      if (images.length < 2) return;

      final String current = userSettings.activeBackdropPath;
      final List<String> others = images.where((String path) => path != current).toList();

      final math.Random random = math.Random();
      final String next = others[random.nextInt(others.length)];

      userSettings.activeBackdropPath = next;
    }

    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    if (mounted) setState(() {});
  }

  Future<void> _resetCurrentPalette() async {
    final QuickMenuDesignThemeSet defaults =
        Settings.createDefaultQuickMenuDesignThemes()[userSettings.currentQuickMenuDesign.name]!;
    await _updateTheme(() {
      if (_paletteMode == _QuickMenuPaletteMode.dark) {
        userSettings.darkTheme = defaults.darkTheme.copyWith();
      } else {
        userSettings.lightTheme = defaults.lightTheme.copyWith();
      }
    });
  }

  Future<void> _updateColor(int index, Color color) async {
    await _updateTheme(() {
      if (index == 0) {
        _selectedTheme.background = color;
      } else if (index == 1) {
        _selectedTheme.textColor = color;
      } else {
        _selectedTheme.accentColor = color;
      }
    });
  }

  Future<void> _openCustomColorPicker(int index) async {
    final Color startColor = switch (index) {
      0 => _selectedTheme.background,
      1 => _selectedTheme.textColor,
      _ => _selectedTheme.accentColor,
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
    final Color accent = userSettings.themeColors.accentColor;
    final Color onSurface = theme.colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: "QuickMenu Design",
          accent: accent,
          icon: Icons.dashboard_customize_outlined,
          buttonPressed: _resetCurrentPalette,
          buttonTooltip: "Reset To Default Colors",
          buttonIcon: Icons.history,
          extraActions: <Widget>[
            CustomTooltip(
              message: "Change to ${User.s.isDark(context) ? "Light" : "Dark"}",
              child: IconButton(
                  icon: const Icon(Icons.theater_comedy_sharp),
                  onPressed: () {
                    bool isSimple = false;
                    if (<ThemeType>[ThemeType.light, ThemeType.dark].contains(userSettings.themeType)) isSimple = true;
                    userSettings.themeType = User.s.isDark(context) ? ThemeType.light : ThemeType.dark;
                    if (isSimple) Boxes.updateSettings("themeType", userSettings.themeType.index);

                    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                  }),
            )
          ],
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildDesignsCard("QuickMenu", accent, onSurface),
                const SizedBox(height: 8),
                _buildDesignsCard("Launcher", accent, onSurface),
                const SizedBox(height: 8),
                _buildPanelTintCard(accent, onSurface),
                const SizedBox(height: 8),
                if (_selectedTheme.backdropType.isNotEmpty) ...<Widget>[
                  _buildBackdropOpacityCard(accent, onSurface),
                  const SizedBox(height: 8),
                ],
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
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesignsCard(String type, Color accent, Color onSurface) {
    final bool isQuickMenu = type == "QuickMenu";
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            isQuickMenu ? "QuickMenu Design Type" : "Launcher Design Type",
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
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
                    ? userSettings.currentQuickMenuDesign == design
                    : launcherDesign == LauncherDesign.values[index];

                if (isQuickMenu) {
                  design = QuickMenuDesigns.values[index];
                  selected = userSettings.currentQuickMenuDesign == design;
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
                            launcherDesign = LauncherDesign.values[index];
                            setState(() {});
                          }
                        },
                  visualDensity: VisualDensity.compact,
                  labelStyle: TextStyle(
                    fontSize: 11.5,
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
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Set the border radius for the QuickMenu.",
                      style: TextStyle(
                        fontSize: 10.5,
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
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Panel tint strength for this palette.",
                      style: TextStyle(
                        fontSize: 10.5,
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
                    Row(
                      children: <Widget>[
                        if (_selectedTheme.backdropType == 'builtIn' || _selectedTheme.backdropImages.length > 1)
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: InkWell(
                              onTap: _shuffleBackdrop,
                              borderRadius: BorderRadius.circular(4),
                              child: CustomTooltip(
                                message: "Random backdrop",
                                child: Icon(Icons.shuffle_rounded, size: 14, color: accent),
                              ),
                            ),
                          ),
                        Text(
                          "Backdrop Intensity",
                          style: TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                            color: onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Opacity of the background image layer.",
                      style: TextStyle(
                        fontSize: 10.5,
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
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Custom fonts for general UI and data entries.",
            style: TextStyle(
              fontSize: 10.5,
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
                    "Sets the main font used across the application.",
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
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _fontPreviewTile(
                    "Entry Font",
                    "Overrides typography for taskbar items and headers.",
                    _selectedTheme.entryFontFamily,
                    _selectedTheme.entryFontWeight,
                    _selectedTheme.entryFontItalic,
                    (PickerFont font) async {
                      await _updateTheme(() {
                        _selectedTheme.entryFontFamily = font.fontFamily;
                        _selectedTheme.entryFontWeight = font.fontWeight.value;
                        _selectedTheme.entryFontItalic = font.fontStyle == FontStyle.italic;
                      });
                      Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _fontPreviewTile(
      String title, String subtitle, String family, int weight, bool italic, ValueChanged<PickerFont> onFontChanged) {
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
                  fontWeight: FontWeight.w600, fontSize: 11.5, color: Theme.of(context).colorScheme.onSurface)),
          const SizedBox(height: 2),
          Text(subtitle, style: TextStyle(fontSize: 10, color: Theme.of(context).colorScheme.onSurface.withAlpha(150))),
          const SizedBox(height: 8),
          Text(
            "Preview: $family",
            style: TextStyle(
              fontFamily: family,
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
                    fontSize: 10.5,
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
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Overall panel transparency stops.",
            style: TextStyle(
              fontSize: 10.5,
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
      1 => _selectedTheme.textColor,
      _ => _selectedTheme.accentColor,
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
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      _colorDescriptions[index],
                      style: TextStyle(
                        fontSize: 10.5,
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
                          fontSize: 10.5,
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
          fontSize: 10.5,
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
