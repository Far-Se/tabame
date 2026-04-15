// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/globals.dart' show Globals;
import '../../models/util/theme_colors.dart';
import '../../models/settings.dart';

class ThemeSetup extends StatefulWidget {
  const ThemeSetup({super.key});

  @override
  ThemeSetupState createState() => ThemeSetupState();
}

const List<int> _indexPrimary = <int>[50, 100, 200, 300, 400, 500, 600, 700, 800, 900];
MaterialColor createPrimarySwatch(Color color) {
  final Map<int, Color> swatch = <int, Color>{};
  final int a = color.alpha8bit;
  final int r = color.red8bit;
  final int g = color.green8bit;
  final int b = color.blue8bit;
  for (final int strength in _indexPrimary) {
    final double ds = 0.5 - strength / 1000;
    swatch[strength] = Color.fromARGB(
      a,
      r + ((ds < 0 ? r : (255 - r)) * ds).round(),
      g + ((ds < 0 ? g : (255 - g)) * ds).round(),
      b + ((ds < 0 ? b : (255 - b)) * ds).round(),
    );
  }
  swatch[50] = swatch[50]!.lighten(18);
  swatch[100] = swatch[100]!.lighten(16);
  swatch[200] = swatch[200]!.lighten(14);
  swatch[300] = swatch[300]!.lighten(10);
  swatch[400] = swatch[400]!.lighten(6);
  swatch[700] = swatch[700]!.darken(2);
  swatch[800] = swatch[800]!.darken(3);
  swatch[900] = swatch[900]!.darken(4);
  return MaterialColor(color.value32bit, swatch);
}

Map<ColorSwatch<Object>, String> getPredefinedColorSet(List<List<int>> predefined, int offset, {int maximum = 60}) {
  final Map<ColorSwatch<Object>, String> output = <ColorSwatch<Object>, String>{};
  final List<int> colorSet = predefined.map((List<int> e) => e[offset]).toSet().toList();
  int i = 0;
  for (int element in colorSet) {
    i++;
    output[createPrimarySwatch(Color(element))] = "Variant #$i";
    if (i == maximum) break;
  }
  return output;
}

class ThemeSetupState extends State<ThemeSetup> {
  final ScrollController mainScrollControl = ScrollController();
  bool changed = false;

  ThemeColors savedLightTheme = globalSettings.lightTheme.copyWith();
  ThemeColors savedDarkTheme = globalSettings.darkTheme.copyWith();

  List<Map<ColorSwatch<Object>, String>> predefinedColorsLight = <Map<ColorSwatch<Object>, String>>[
    getPredefinedColorSet(lightThemeOptions, 0),
    getPredefinedColorSet(lightThemeOptions, 1),
    getPredefinedColorSet(lightThemeOptions, 2),
  ];
  List<Map<ColorSwatch<Object>, String>> predefinedColorsDark = <Map<ColorSwatch<Object>, String>>[
    getPredefinedColorSet(darkThemeOptions, 0),
    getPredefinedColorSet(darkThemeOptions, 1),
    getPredefinedColorSet(darkThemeOptions, 2),
  ];
  @override
  void initState() {
    super.initState();
    final String? lightTheme = Boxes.pref.getString('lightTheme');
    if (lightTheme != null) savedLightTheme = ThemeColors.fromJson(lightTheme).copyWith();

    final String? darkTheme = Boxes.pref.getString('darkTheme');
    if (darkTheme != null) savedDarkTheme = ThemeColors.fromJson(darkTheme).copyWith();
  }

  @override
  void dispose() {
    mainScrollControl.dispose();
    super.dispose();
  }

  void _onSaved() async {
    if (globalSettings.themeTypeMode == ThemeType.dark) {
      await Boxes.saveActiveQuickMenuThemes();
      savedDarkTheme = globalSettings.darkTheme.copyWith();
      Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
    } else {
      await Boxes.saveActiveQuickMenuThemes();
      savedLightTheme = globalSettings.lightTheme.copyWith();
      Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
    }
    setState(() => changed = false);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: SingleChildScrollView(
            controller: mainScrollControl,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
            child: Material(
              type: MaterialType.transparency,
              child: globalSettings.themeTypeMode == ThemeType.dark
                  ? ThemeSetupWidget(
                      title: "Dark Theme",
                      savedColors: savedDarkTheme,
                      currentColors: globalSettings.darkTheme,
                      onChanged: () => setState(() => changed = true),
                      onGradientChanged: (double e) {
                        globalSettings.darkTheme.gradientAlpha = e.toInt();
                        Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                      },
                      quickMenuBoldChanged: (bool e) {
                        globalSettings.darkTheme.quickMenuBoldFont = e;
                        Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                      },
                      onColorChanged: (Color color, int i) {
                        if (i == 0) globalSettings.darkTheme.background = color.toInt32;
                        if (i == 1) globalSettings.darkTheme.textColor = color.toInt32;
                        if (i == 2) globalSettings.darkTheme.accentColor = color.toInt32;
                        Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                        Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                      },
                      predefinedColors: predefinedColorsDark,
                      themeOptions: darkThemeOptions,
                      onDesignChanged: (QuickMenuDesigns design) async {
                        await Boxes.switchQuickMenuDesign(design);
                        savedDarkTheme = globalSettings.darkTheme.copyWith();
                        savedLightTheme = globalSettings.lightTheme.copyWith();
                        setState(() => changed = false);
                      },
                    )
                  : ThemeSetupWidget(
                      title: "Light Theme",
                      savedColors: savedLightTheme,
                      currentColors: globalSettings.lightTheme,
                      onChanged: () => setState(() => changed = true),
                      onGradientChanged: (double e) {
                        globalSettings.lightTheme.gradientAlpha = e.toInt();
                        Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                      },
                      quickMenuBoldChanged: (bool e) {
                        globalSettings.lightTheme.quickMenuBoldFont = e;
                        Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                      },
                      onColorChanged: (Color color, int i) {
                        if (i == 0) globalSettings.lightTheme.background = color.toInt32;
                        if (i == 1) globalSettings.lightTheme.textColor = color.toInt32;
                        if (i == 2) globalSettings.lightTheme.accentColor = color.toInt32;
                        Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                        Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                      },
                      predefinedColors: predefinedColorsLight,
                      themeOptions: lightThemeOptions,
                      onDesignChanged: (QuickMenuDesigns design) async {
                        await Boxes.switchQuickMenuDesign(design);
                        savedDarkTheme = globalSettings.darkTheme.copyWith();
                        savedLightTheme = globalSettings.lightTheme.copyWith();
                        setState(() => changed = false);
                      },
                    ),
            ),
          ),
        ),
        Positioned(
          bottom: 24,
          left: 16,
          right: 16,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 400),
            transitionBuilder: (Widget child, Animation<double> animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.5), end: Offset.zero)
                      .animate(CurvedAnimation(parent: animation, curve: Curves.easeOutCubic)),
                  child: child,
                ),
              );
            },
            child: changed
                ? Center(
                    key: const ValueKey<String>('floating_save_pill'),
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 15,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: ElevatedButton.icon(
                        onPressed: _onSaved,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red.shade400,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 18),
                          elevation: 0,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                        ),
                        icon: const Icon(Icons.save_rounded, size: 22),
                        label: const Text(
                          "Commit Changes",
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, letterSpacing: 0.2),
                        ),
                      ),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

class ThemeSetupWidget extends StatefulWidget {
  final String title;
  final VoidCallback onChanged;
  final Function(double) onGradientChanged;
  final Function(bool) quickMenuBoldChanged;
  final Function(Color, int) onColorChanged;
  final ThemeColors savedColors;
  final ThemeColors currentColors;
  final List<Map<ColorSwatch<Object>, String>> predefinedColors;
  final List<List<int>> themeOptions;
  final Function(QuickMenuDesigns) onDesignChanged;
  const ThemeSetupWidget({
    super.key,
    required this.title,
    required this.onChanged,
    required this.onGradientChanged,
    required this.quickMenuBoldChanged,
    required this.onColorChanged,
    required this.savedColors,
    required this.currentColors,
    required this.predefinedColors,
    required this.themeOptions,
    required this.onDesignChanged,
  });

  @override
  State<ThemeSetupWidget> createState() => _ThemeSetupWidgetState();
}

class _ThemeSetupWidgetState extends State<ThemeSetupWidget> {
  late TextEditingController gradientController;

  @override
  void initState() {
    super.initState();
    gradientController = TextEditingController(text: widget.currentColors.gradientAlpha.toString());
  }

  @override
  void dispose() {
    gradientController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Color(globalSettings.themeColors.accentColor).withValues(alpha: 1.0);
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        // Page Header
        Padding(
          padding: const EdgeInsets.only(bottom: 24),
          child: Row(
            children: <Widget>[
              Icon(Icons.palette_rounded, size: 28, color: accent),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    widget.title,
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.5,
                        ),
                  ),
                  Text(
                    "All changes are applied immediately to the preview but must be committed to be permanent.",
                    style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ],
          ),
        ),

        // Design Presets
        _settingsCard(
          title: "Design Type",
          subtitle: "Quickly switch between predefined interface styles.",
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              const SizedBox(height: 4),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: QuickMenuDesigns.values.map((QuickMenuDesigns design) {
                  final bool selected = globalSettings.currentQuickMenuDesign == design;
                  return ChoiceChip(
                    label: Text(design.name),
                    selected: selected,
                    onSelected: (bool val) {
                      if (val && !selected) {
                        widget.onDesignChanged(design);
                        setState(() {});
                      }
                    },
                    showCheckmark: false,
                    selectedColor: accent.withValues(alpha: 0.15),
                    backgroundColor: onSurface.withValues(alpha: 0.05),
                    labelStyle: TextStyle(
                      fontSize: 12,
                      color: selected ? accent : onSurface,
                      fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: selected ? accent.withValues(alpha: 0.5) : onSurface.withValues(alpha: 0.1),
                        width: selected ? 1.5 : 1.0,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),

        _settingsCard(
          title: "QuickMenu Configuration",
          subtitle: "Fine-tune the appearance of the main interface.",
          child: Column(
            children: <Widget>[
              _buildSwitchTile(
                "Bold Application Titles",
                "Uses a stronger font weight for app names in the menu.",
                widget.currentColors.quickMenuBoldFont,
                (bool v) {
                  widget.onChanged();
                  widget.quickMenuBoldChanged(v);
                  setState(() {});
                },
              ),
              const SizedBox(height: 12),
              _buildSliderTile(
                "Gradient Opacity",
                "Adjust the visible strength of the theme background.",
                accent,
                onSurface,
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        _buildColorSection(
          "Background",
          "The primary background color for all interfaces.",
          0,
          Color(widget.savedColors.background),
          Color(widget.currentColors.background),
          widget.predefinedColors[0],
        ),

        const SizedBox(height: 16),

        _buildColorSection(
          "Primary Text",
          "Used for titles, labels, and general content.",
          1,
          Color(widget.savedColors.textColor),
          Color(widget.currentColors.textColor),
          widget.predefinedColors[1],
        ),

        const SizedBox(height: 16),

        _buildColorSection(
          "Accent Highlight",
          "Used for buttons, switches, and active states.",
          2,
          Color(widget.savedColors.accentColor),
          Color(widget.currentColors.accentColor),
          widget.predefinedColors[2],
        ),
      ],
    );
  }

  Widget _buildColorSection(
      String title, String subtitle, int index, Color saved, Color current, Map<ColorSwatch<Object>, String> options) {
    return _settingsCard(
      title: title,
      subtitle: subtitle,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              _colorPreview("Saved", saved, () {
                widget.onChanged();
                widget.onColorChanged(saved, index);
                setState(() {});
              }),
              const SizedBox(width: 12),
              _colorPreview("Active", current, () => _openPicker(index, current)),
              const Spacer(),
              _CustomPickerButton(onPressed: () => _openPicker(index, current)),
            ],
          ),
          const SizedBox(height: 16),
          const Text("Preset Variants",
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
          const SizedBox(height: 8),
          ListColors(
            colorsNameMap: options,
            onColorChanged: (Color color) {
              widget.onChanged();
              widget.onColorChanged(color, index);
              setState(() {});
            },
          ),
        ],
      ),
    );
  }

  Widget _colorPreview(String label, Color color, VoidCallback onTap) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: onSurface.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: onSurface.withValues(alpha: 0.08)),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.black12),
                boxShadow: <BoxShadow>[
                  BoxShadow(color: color.withValues(alpha: 0.3), blurRadius: 4, offset: const Offset(0, 2))
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
          ],
        ),
      ),
    );
  }

  void _openPicker(int index, Color current) {
    Color? newColor;
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text("Refine Color",
              style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
          content: CustomColorPicker(
            startColor: current,
            themeOptions: widget.themeOptions,
            colorIndex: index,
            onColorChanged: (Color color) => newColor = color,
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Apply'),
            ),
          ],
        );
      },
    ).then((dynamic value) {
      if (value == true && newColor != null) {
        widget.onChanged();
        widget.onColorChanged(newColor!, index);
        setState(() {});
      }
    });
  }

  Widget _settingsCard({required String title, required String subtitle, required Widget child, Widget? trailing}) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(80),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: onSurface.withValues(alpha: 0.08)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                    const SizedBox(height: 4),
                    Text(subtitle, style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.65))),
                  ],
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
          const SizedBox(height: 14),
          child,
        ],
      ),
    );
  }

  Widget _buildSwitchTile(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.62))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Switch(value: value, onChanged: onChanged),
        ],
      ),
    );
  }

  Widget _buildSliderTile(String title, String subtitle, Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
          Text(subtitle, style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.62))),
          const SizedBox(height: 8),
          Row(
            children: <Widget>[
              Expanded(
                child: SliderTheme(
                  data: Theme.of(context).sliderTheme.copyWith(
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: accent,
                        thumbColor: accent,
                      ),
                  child: Slider(
                    min: 0,
                    max: 255,
                    value: widget.currentColors.gradientAlpha.toDouble(),
                    onChanged: (double e) {
                      widget.onChanged();
                      widget.onGradientChanged(e);
                      if (int.tryParse(gradientController.text) != e.toInt()) {
                        gradientController.text = e.toInt().toString();
                      }
                      setState(() {});
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 44,
                child: TextField(
                  controller: gradientController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                    filled: true,
                    fillColor: onSurface.withValues(alpha: 0.05),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
                  ),
                  onChanged: (String v) {
                    int? val = int.tryParse(v);
                    if (val != null) {
                      if (val > 255) {
                        val = 255;
                        gradientController.text = "255";
                        gradientController.selection = TextSelection.fromPosition(const TextPosition(offset: 3));
                      }
                      widget.onChanged();
                      widget.onGradientChanged(val.toDouble());
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomPickerButton extends StatelessWidget {
  const _CustomPickerButton({required this.onPressed});
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: const Icon(Icons.colorize_rounded, size: 16),
      label: const Text("Custom Picker"),
      style: TextButton.styleFrom(
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 12),
      ),
    );
  }
}

class CustomColorPicker extends StatefulWidget {
  const CustomColorPicker({
    super.key,
    required this.startColor,
    required this.themeOptions,
    required this.colorIndex,
    required this.onColorChanged,
  });
  final Color startColor;
  final List<List<int>> themeOptions;
  final int colorIndex;
  final Function(Color) onColorChanged;

  @override
  State<CustomColorPicker> createState() => _CustomColorPickerState();
}

class _CustomColorPickerState extends State<CustomColorPicker> {
  late Color currentColor;
  late TextEditingController rController;
  late TextEditingController gController;
  late TextEditingController bController;
  late TextEditingController hexController;

  @override
  void initState() {
    super.initState();
    currentColor = widget.startColor;
    rController = TextEditingController(text: currentColor.red8bit.toString());
    gController = TextEditingController(text: currentColor.green8bit.toString());
    bController = TextEditingController(text: currentColor.blue8bit.toString());
    hexController = TextEditingController(text: _colorToHex(currentColor));
  }

  @override
  void dispose() {
    rController.dispose();
    gController.dispose();
    bController.dispose();
    hexController.dispose();
    super.dispose();
  }

  String _colorToHex(Color color) {
    return color.value32bit.toRadixString(16).padLeft(8, '0').toUpperCase().substring(2);
  }

  void _updateHexFromColor() {
    final String hex = _colorToHex(currentColor);
    if (hexController.text.toUpperCase() != hex) {
      hexController.text = hex;
    }
  }

  void _updateColorFromHex(String hex) {
    hex = hex.replaceAll('#', '');
    if (hex.length == 6) {
      final int? val = int.tryParse(hex, radix: 16);
      if (val != null) {
        setState(() {
          currentColor = Color(0xFF000000 | val);
          _syncRgbControllers();
          widget.onColorChanged(currentColor);
        });
      }
    }
  }

  void _syncRgbControllers() {
    rController.text = currentColor.red8bit.toString();
    gController.text = currentColor.green8bit.toString();
    bController.text = currentColor.blue8bit.toString();
  }

  @override
  Widget build(BuildContext context) {
    final Set<Color> predefinedColors = <Color>{};
    for (List<int> list in widget.themeOptions) {
      if (widget.colorIndex >= 0 && widget.colorIndex < list.length) {
        predefinedColors.add(Color(list[widget.colorIndex]).withAlpha(255));
      }
    }
    final List<Color> colorsList = predefinedColors.toList();
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    // Sync controllers if currentColor changed from sliders
    if (int.tryParse(rController.text) != currentColor.red8bit) {
      rController.text = currentColor.red8bit.toString();
    }
    if (int.tryParse(gController.text) != currentColor.green8bit) {
      gController.text = currentColor.green8bit.toString();
    }
    if (int.tryParse(bController.text) != currentColor.blue8bit) {
      bController.text = currentColor.blue8bit.toString();
    }
    _updateHexFromColor();

    return SizedBox(
        width: 400,
        child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
          Row(children: <Widget>[
            Column(
              children: <Widget>[
                Container(
                  width: 70,
                  height: 70,
                  decoration: BoxDecoration(
                    color: currentColor,
                    shape: BoxShape.circle,
                    border: Border.all(color: onSurface.withValues(alpha: 0.2)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(color: currentColor.withValues(alpha: 0.25), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: 90,
                  child: TextField(
                    controller: hexController,
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1),
                    decoration: InputDecoration(
                      prefixText: "#",
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      filled: true,
                      fillColor: onSurface.withValues(alpha: 0.05),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                    ),
                    onChanged: _updateColorFromHex,
                  ),
                ),
              ],
            ),
            const SizedBox(width: 20),
            Expanded(
                child: Column(children: <Widget>[
              _buildSlider(currentColor.red8bit.toDouble(), Colors.red, rController, (double v) {
                setState(() {
                  currentColor =
                      Color.fromARGB(currentColor.alpha8bit, v.toInt(), currentColor.green8bit, currentColor.blue8bit);
                  widget.onColorChanged(currentColor);
                });
              }),
              _buildSlider(currentColor.green8bit.toDouble(), Colors.green, gController, (double v) {
                setState(() {
                  currentColor =
                      Color.fromARGB(currentColor.alpha8bit, currentColor.red8bit, v.toInt(), currentColor.blue8bit);
                  widget.onColorChanged(currentColor);
                });
              }),
              _buildSlider(currentColor.blue8bit.toDouble(), Colors.blue, bController, (double v) {
                setState(() {
                  currentColor =
                      Color.fromARGB(currentColor.alpha8bit, currentColor.red8bit, currentColor.green8bit, v.toInt());
                  widget.onColorChanged(currentColor);
                });
              })
            ])),
          ]),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          Text('Theme Palette Sources',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontSize: 12, fontWeight: FontWeight.bold)),
          const SizedBox(height: 12),
          Flexible(
              child: GridView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.only(bottom: 10),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 32,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemCount: colorsList.length,
                  itemBuilder: (BuildContext context, int index) {
                    final Color color = colorsList[index];
                    return InkWell(
                        onTap: () {
                          setState(() {
                            currentColor = color;
                            widget.onColorChanged(currentColor);
                          });
                        },
                        borderRadius: BorderRadius.circular(20),
                        child: Container(
                            decoration: BoxDecoration(
                          color: color,
                          shape: BoxShape.circle,
                          border: Border.all(color: onSurface.withValues(alpha: 0.15)),
                        )));
                  }))
        ]));
  }

  Widget _buildSlider(double value, Color activeColor, TextEditingController controller, Function(double) onChanged) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Row(
      children: <Widget>[
        Expanded(
          child: SliderTheme(
            data: SliderTheme.of(context).copyWith(
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6.0),
              overlayShape: SliderComponentShape.noOverlay,
              activeTrackColor: activeColor,
              thumbColor: activeColor,
            ),
            child: Slider(
              value: value,
              min: 0,
              max: 255,
              onChanged: (double e) {
                onChanged(e);
                if (int.tryParse(controller.text) != e.toInt()) {
                  controller.text = e.toInt().toString();
                }
              },
            ),
          ),
        ),
        const SizedBox(width: 12),
        Listener(
          onPointerSignal: (PointerSignalEvent pointerSignal) {
            if (pointerSignal is PointerScrollEvent) {
              controller.text =
                  ((int.tryParse(controller.text) ?? 0) + (pointerSignal.scrollDelta.dy < 0 ? 10 : -10)).toString();
              onChanged(double.tryParse(controller.text) ?? 0);
            }
          },
          child: SizedBox(
            width: 44,
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold),
              inputFormatters: <TextInputFormatter>[FilteringTextInputFormatter.digitsOnly],
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                filled: true,
                fillColor: onSurface.withValues(alpha: 0.05),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(6), borderSide: BorderSide.none),
              ),
              onChanged: (String v) {
                int? val = int.tryParse(v);
                if (val != null) {
                  if (val > 255) {
                    val = 255;
                    controller.text = "255";
                    controller.selection = TextSelection.fromPosition(const TextPosition(offset: 3));
                  }
                  onChanged(val.toDouble());
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}

class ListColors extends StatefulWidget {
  const ListColors({
    super.key,
    required this.colorsNameMap,
    required this.onColorChanged,
  });

  final Map<ColorSwatch<Object>, String> colorsNameMap;
  final Function(Color) onColorChanged;

  @override
  State<ListColors> createState() => _ListColorsState();
}

class _ListColorsState extends State<ListColors> {
  final ScrollController colorScrollController = ScrollController();

  @override
  void dispose() {
    colorScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Listener(
        onPointerSignal: (PointerSignalEvent pointerSignal) {
          if (pointerSignal is PointerScrollEvent) {
            if (pointerSignal.scrollDelta.dy < 0) {
              colorScrollController.animateTo(colorScrollController.offset - 190,
                  duration: const Duration(milliseconds: 200), curve: Curves.ease);
            } else {
              colorScrollController.animateTo(colorScrollController.offset + 190,
                  duration: const Duration(milliseconds: 200), curve: Curves.ease);
            }
          }
        },
        child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: ShaderMask(
                shaderCallback: (Rect rect) {
                  return const LinearGradient(
                    begin: Alignment.centerLeft,
                    end: Alignment.centerRight,
                    colors: <Color>[Colors.transparent, Colors.transparent, Color.fromARGB(255, 0, 0, 0)],
                    stops: <double>[0.0, 0.95, 1.0],
                  ).createShader(rect);
                },
                blendMode: BlendMode.dstOut,
                child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    controller: colorScrollController,
                    child: Row(children: <Widget>[
                      ...widget.colorsNameMap.keys.map((ColorSwatch<Object> color) {
                        return Padding(
                            padding: const EdgeInsets.only(right: 12),
                            child: InkWell(
                                onTap: () => widget.onColorChanged(color),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                    width: 28,
                                    height: 28,
                                    decoration: BoxDecoration(
                                      color: color,
                                      shape: BoxShape.circle,
                                      border: Border.all(color: onSurface.withValues(alpha: 0.15)),
                                      boxShadow: <BoxShadow>[
                                        BoxShadow(
                                            color: color.withValues(alpha: 0.2),
                                            blurRadius: 4,
                                            offset: const Offset(0, 2))
                                      ],
                                    ))));
                      }),
                      const SizedBox(width: 40)
                    ])))));
  }
}
