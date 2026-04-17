import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/util/theme_colors.dart';
import '../../interface/theme_setup.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class QuickMenuDesignButton extends StatelessWidget {
  const QuickMenuDesignButton({super.key});
  @override
  Widget build(BuildContext context) {
    return const ModalButton(
        actionName: "QuickMenu Design", icon: Icon(Icons.palette_rounded), child: _QuickMenuDesignPanel());
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
  final ScrollController _designScrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    _paletteMode =
        globalSettings.themeTypeMode == ThemeType.dark ? _QuickMenuPaletteMode.dark : _QuickMenuPaletteMode.light;
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
    _designScrollController.dispose();
    super.dispose();
  }

  ThemeColors get _selectedTheme {
    return _paletteMode == _QuickMenuPaletteMode.dark ? globalSettings.darkTheme : globalSettings.lightTheme;
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

  Future<void> _resetCurrentPalette() async {
    final QuickMenuDesignThemeSet defaults =
        Settings.createDefaultQuickMenuDesignThemes()[globalSettings.currentQuickMenuDesign.name]!;
    await _updateTheme(() {
      if (_paletteMode == _QuickMenuPaletteMode.dark) {
        globalSettings.darkTheme = defaults.darkTheme.copyWith();
      } else {
        globalSettings.lightTheme = defaults.lightTheme.copyWith();
      }
    });
  }

  Future<void> _updateColor(int index, Color color) async {
    await _updateTheme(() {
      if (index == 0) {
        _selectedTheme.background = color.toInt32;
      } else if (index == 1) {
        _selectedTheme.textColor = color.toInt32;
      } else {
        _selectedTheme.accentColor = color.toInt32;
      }
    });
  }

  Future<void> _openCustomColorPicker(int index) async {
    final Color startColor = switch (index) {
      0 => Color(_selectedTheme.background),
      1 => Color(_selectedTheme.textColor),
      _ => Color(_selectedTheme.accentColor),
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
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color onSurface = theme.colorScheme.onSurface;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(
          title: "QuickMenu Design",
          accent: accent,
          boldFont: globalSettings.theme.quickMenuBoldFont,
          icon: Icons.dashboard_customize_outlined,
          buttonPressed: _resetCurrentPalette,
          buttonIcon: Icons.refresh_rounded,
        ),
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                _buildDesignsCard(accent, onSurface),
                const SizedBox(height: 8),
                _buildOpacityCard(accent, onSurface),
                const SizedBox(height: 8),
                ...List<Widget>.generate(_colorTitles.length, (int index) {
                  return Padding(
                    padding: EdgeInsets.only(bottom: index == _colorTitles.length - 1 ? 0 : 8),
                    child: _buildColorCard(accent, onSurface, index),
                  );
                }),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDesignsCard(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      decoration: _cardDecoration(onSurface, accent: accent),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "Design Type",
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
              color: onSurface,
            ),
          ),
          const SizedBox(height: 7),
          SizedBox(
            height: 38,
            child: Listener(
              onPointerSignal: (PointerSignalEvent event) {
                if (event is! PointerScrollEvent || !_designScrollController.hasClients) return;
                final double target =
                    (_designScrollController.offset + event.scrollDelta.dy + event.scrollDelta.dx).clamp(
                  _designScrollController.position.minScrollExtent,
                  _designScrollController.position.maxScrollExtent,
                );
                _designScrollController.jumpTo(target);
              },
              child: ListView.separated(
                controller: _designScrollController,
                scrollDirection: Axis.horizontal,
                primary: false,
                dragStartBehavior: DragStartBehavior.down,
                physics: const ClampingScrollPhysics(),
                itemCount: QuickMenuDesigns.values.length,
                separatorBuilder: (_, __) => const SizedBox(width: 6),
                itemBuilder: (BuildContext context, int index) {
                  final QuickMenuDesigns design = QuickMenuDesigns.values[index];
                  final bool selected = globalSettings.currentQuickMenuDesign == design;
                  return ChoiceChip(
                    label: Text(_designTitle(design)),
                    selected: selected,
                    onSelected: selected ? null : (_) => _switchDesign(design),
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
          ),
        ],
      ),
    );
  }

  Widget _buildOpacityCard(Color accent, Color onSurface) {
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
                      "Tint Value",
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
            value: _selectedTheme.gradientAlpha.toDouble(),
            activeColor: accent,
            inactiveColor: accent.withAlpha(40),
            onChanged: (double value) {
              setState(() => _selectedTheme.gradientAlpha = value.round());
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

  Widget _buildColorCard(Color accent, Color onSurface, int index) {
    final Color currentColor = switch (index) {
      0 => Color(_selectedTheme.background),
      1 => Color(_selectedTheme.textColor),
      _ => Color(_selectedTheme.accentColor),
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
