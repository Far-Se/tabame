import 'dart:convert';
import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image/image.dart' as img;

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/globals.dart' show Globals;
import '../../models/settings.dart';
import '../../models/theme.dart';
import '../../models/util/theme_colors.dart';
import '../../models/win32/win_utils.dart';
import '../widgets/color_picker.dart';
import '../widgets/custom_tooltip.dart';
import '../widgets/font_picker/models/picker_font.dart';
import '../widgets/font_picker/ui/font_picker.dart';
import '../widgets/panel_opacity_gradient_editor.dart';
import '../widgets/windows_scroll.dart';

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

  Future<void> _exportThemes() async {
    final Map<String, dynamic> data = jsonDecode(globalSettings.quickMenuDesignThemesToJson());
    for (final dynamic designEntry in data.values) {
      if (designEntry is Map<dynamic, dynamic>) {
        for (final String themeKey in <String>['lightTheme', 'darkTheme']) {
          if (designEntry[themeKey] != null && designEntry[themeKey] is Map<dynamic, dynamic>) {
            final Map<String, dynamic> theme =
                Map<String, dynamic>.from(designEntry[themeKey] as Map<dynamic, dynamic>);
            theme['backdropImages'] = <String>[];
            theme['backdropType'] = "";
            theme['backdropOpacity'] = 0.7;
            designEntry[themeKey] = theme;
          }
        }
      }
    }

    final String json = jsonEncode(data);
    final SaveFilePicker picker = SaveFilePicker()
      ..title = 'Export Themes'
      ..defaultExtension = 'json'
      ..filterSpecification = <String, String>{'JSON Files': '*.json', 'All Files': '*.*'}
      ..fileName = 'tabame_themes.json';

    final File? file = picker.getFile();
    if (file != null) {
      await file.writeAsString(json);
    }
  }

  Future<void> _importThemes() async {
    final OpenFilePicker picker = OpenFilePicker()
      ..title = 'Import Themes'
      ..filterSpecification = <String, String>{'JSON Files': '*.json', 'All Files': '*.*'};

    final File? file = picker.getFile();
    if (file != null) {
      try {
        final String content = await file.readAsString();
        final Map<String, dynamic> data = jsonDecode(content);

        // Sanitize imported data to exclude backdrops
        for (final dynamic designEntry in data.values) {
          if (designEntry is Map<dynamic, dynamic>) {
            for (final String themeKey in <String>['lightTheme', 'darkTheme']) {
              if (designEntry[themeKey] != null && designEntry[themeKey] is Map<dynamic, dynamic>) {
                final Map<String, dynamic> theme =
                    Map<String, dynamic>.from(designEntry[themeKey] as Map<dynamic, dynamic>);
                theme['backdropImages'] = <String>[];
                theme['backdropType'] = "";
                theme['backdropOpacity'] = 0.7;
                designEntry[themeKey] = theme;
              }
            }
          }
        }

        globalSettings.loadQuickMenuDesignThemesFromJson(jsonEncode(data));
        await Boxes.saveActiveQuickMenuThemes(notify: true);

        // Update local state to reflect imported themes for current design
        final String? lightTheme = Boxes.pref.getString('lightTheme');
        if (lightTheme != null) savedLightTheme = ThemeColors.fromJson(lightTheme).copyWith();

        final String? darkTheme = Boxes.pref.getString('darkTheme');
        if (darkTheme != null) savedDarkTheme = ThemeColors.fromJson(darkTheme).copyWith();

        if (mounted) {
          setState(() {
            changed = false;
          });
        }
      } catch (e) {
        // ignore
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: <Widget>[
        Positioned.fill(
          child: WindowsScrollView(
            child: Padding(
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
                        onBackdropOpacityChanged: (double e) {
                          globalSettings.darkTheme.backdropOpacity = e;
                          Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                        },
                        onPanelOpacityPointsChanged: (List<double> e) {
                          globalSettings.darkTheme.panelOpacityPoints = e;
                          Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                          Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                        },
                        onPanelOpacityBeginChanged: (String e) {
                          globalSettings.darkTheme.panelOpacityBegin = e;
                          Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                          Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                        },
                        onPanelOpacityEndChanged: (String e) {
                          globalSettings.darkTheme.panelOpacityEnd = e;
                          Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                          Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                        },
                        onColorChanged: (Color color, int i) {
                          if (i == 0) globalSettings.darkTheme.background = color;
                          if (i == 1) globalSettings.darkTheme.textColor = color;
                          if (i == 2) globalSettings.darkTheme.accentColor = color;
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
                        onExport: _exportThemes,
                        onImport: _importThemes,
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
                        onBackdropOpacityChanged: (double e) {
                          globalSettings.lightTheme.backdropOpacity = e;
                          Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                        },
                        onPanelOpacityPointsChanged: (List<double> e) {
                          globalSettings.lightTheme.panelOpacityPoints = e;
                          Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                          Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                        },
                        onPanelOpacityBeginChanged: (String e) {
                          globalSettings.lightTheme.panelOpacityBegin = e;
                          Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                          Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                        },
                        onPanelOpacityEndChanged: (String e) {
                          globalSettings.lightTheme.panelOpacityEnd = e;
                          Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                          Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                        },
                        onColorChanged: (Color color, int i) {
                          if (i == 0) globalSettings.lightTheme.background = color;
                          if (i == 1) globalSettings.lightTheme.textColor = color;
                          if (i == 2) globalSettings.lightTheme.accentColor = color;
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
                        onExport: _exportThemes,
                        onImport: _importThemes,
                      ),
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
  final Function(double) onBackdropOpacityChanged;
  final Function(List<double>) onPanelOpacityPointsChanged;
  final Function(String) onPanelOpacityBeginChanged;
  final Function(String) onPanelOpacityEndChanged;
  final Function(Color, int) onColorChanged;
  final ThemeColors savedColors;
  final ThemeColors currentColors;
  final List<Map<ColorSwatch<Object>, String>> predefinedColors;
  final List<List<int>> themeOptions;
  final Function(QuickMenuDesigns) onDesignChanged;
  final VoidCallback onExport;
  final VoidCallback onImport;
  const ThemeSetupWidget({
    super.key,
    required this.title,
    required this.onChanged,
    required this.onGradientChanged,
    required this.onBackdropOpacityChanged,
    required this.onColorChanged,
    required this.savedColors,
    required this.currentColors,
    required this.predefinedColors,
    required this.themeOptions,
    required this.onDesignChanged,
    required this.onPanelOpacityPointsChanged,
    required this.onPanelOpacityBeginChanged,
    required this.onPanelOpacityEndChanged,
    required this.onExport,
    required this.onImport,
  });

  @override
  State<ThemeSetupWidget> createState() => _ThemeSetupWidgetState();
}

class _ThemeSetupWidgetState extends State<ThemeSetupWidget> {
  late TextEditingController gradientController;
  late TextEditingController backdropOpacityController;
  bool _isBackdropProcessing = false;
  int _backdropProcessingTotal = 0;
  int _backdropProcessingCompleted = 0;
  int _backdropProcessingConverted = 0;

  @override
  void initState() {
    super.initState();
    gradientController = TextEditingController(text: widget.currentColors.gradientAlpha.toString());
    backdropOpacityController =
        TextEditingController(text: (widget.currentColors.backdropOpacity * 100).toInt().toString());
  }

  @override
  void dispose() {
    gradientController.dispose();
    backdropOpacityController.dispose();
    super.dispose();
  }

  Future<void> _setThemeType(ThemeType? value) async {
    globalSettings.themeType = value ?? ThemeType.system;
    await Boxes.updateSettings("themeType", globalSettings.themeType.index);
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    setState(() {});
  }

  Future<void> _pickThemeStart() async {
    final int hour = (globalSettings.themeScheduleMin ~/ 60);
    final int minute = (globalSettings.themeScheduleMin % 60);
    final TimeOfDay? timePicker = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
      },
    );
    if (timePicker == null) return;
    globalSettings.themeScheduleMin = (timePicker.hour) * 60 + (timePicker.minute);
    await Boxes.updateSettings("themeScheduleMin", globalSettings.themeScheduleMin);
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    setState(() {});
  }

  Future<void> _pickThemeEnd() async {
    final int hour = (globalSettings.themeScheduleMax ~/ 60);
    final int minute = (globalSettings.themeScheduleMax % 60);
    final TimeOfDay? timePicker = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: hour, minute: minute),
      initialEntryMode: TimePickerEntryMode.dial,
      builder: (BuildContext context, Widget? child) {
        return MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true), child: child ?? Container());
      },
    );
    if (timePicker == null) return;
    final int newTime = (timePicker.hour) * 60 + (timePicker.minute);
    if (newTime < globalSettings.themeScheduleMin) return;
    globalSettings.themeScheduleMax = newTime;
    await Boxes.updateSettings("themeScheduleMax", globalSettings.themeScheduleMax);
    Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
    setState(() {});
  }

  Future<void> _addBackdropImages() async {
    if (_isBackdropProcessing) return;

    final OpenFilePicker picker = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'Images': '*.jpg;*.jpeg;*.png;*.webp',
      }
      ..title = 'Select Backdrop Image';
    final List<File> results = picker.getFiles();
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
          await compute(_resizeAndSaveBackdrop, <String, String>{
            'source': result.path,
            'target': targetPath,
          });
          widget.currentColors.backdropImages = List<String>.from(widget.currentColors.backdropImages)..add(targetPath);
          changed = true;
          if (!mounted) return;
          setState(() {
            _backdropProcessingConverted++;
          });
        } catch (e) {
          Debug.add("Theme Setup Error processing file [$fileName]: $e");
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
        if (changed) widget.onChanged();
        setState(() {
          _isBackdropProcessing = false;
          _backdropProcessingCompleted = _backdropProcessingTotal;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = globalSettings.themeColors.accentColor.withValues(alpha: 1.0);
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
              Expanded(
                child: Column(
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
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.download_rounded,
                label: "Import",
                onPressed: widget.onImport,
                accent: accent,
              ),
              const SizedBox(width: 8),
              _ActionButton(
                icon: Icons.upload_rounded,
                label: "Export",
                onPressed: widget.onExport,
                accent: accent,
              ),
            ],
          ),
        ),

        _buildAppearanceCard(accent, onSurface),
        const SizedBox(height: 16),

        _buildTypographySection(accent, onSurface),

        const SizedBox(height: 16),

        _buildColorSection(
          "Background",
          "The primary background color for all interfaces.",
          0,
          widget.savedColors.background,
          widget.currentColors.background,
          widget.predefinedColors[0],
        ),

        const SizedBox(height: 16),

        _buildColorSection(
          "Primary Text",
          "Used for titles, labels, and general content.",
          1,
          widget.savedColors.textColor,
          widget.currentColors.textColor,
          widget.predefinedColors[1],
        ),

        const SizedBox(height: 16),

        _buildColorSection(
          "Accent Highlight",
          "Used for buttons, switches, and active states.",
          2,
          widget.savedColors.accentColor,
          widget.currentColors.accentColor,
          widget.predefinedColors[2],
        ),
        const SizedBox(height: 16),
        _buildSliderTile(
          "Accent Gradient Opacity/Tint",
          "Adjust the visible strength of the theme background and accent.",
          accent,
          onSurface,
          widget.currentColors.gradientAlpha.toDouble(),
          255,
          gradientController,
          (double v) {
            widget.onChanged();
            widget.onGradientChanged(v);
          },
          min: 0,
        ),
        const SizedBox(height: 16),

        _buildBackdropSection(accent, onSurface),
        const SizedBox(height: 16),
        _settingsCard(
          title: "Interface Transparency Gradient",
          subtitle: "Define a multi-stop gradient for the overall panel transparency.",
          child: PanelOpacityGradientEditor(
            points: widget.currentColors.panelOpacityPoints,
            begin: widget.currentColors.panelOpacityBegin,
            end: widget.currentColors.panelOpacityEnd,
            onChanged: (List<double> points) {
              widget.onChanged();
              widget.onPanelOpacityPointsChanged(points);
            },
            onBeginChanged: (String val) {
              widget.onChanged();
              widget.onPanelOpacityBeginChanged(val);
            },
            onEndChanged: (String val) {
              widget.onChanged();
              widget.onPanelOpacityEndChanged(val);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildTypographySection(Color accent, Color onSurface) {
    return _settingsCard(
      title: "Typography",
      subtitle: "Custom fonts for general UI and data entries.",
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Expanded(
              child: _fontPreviewTile(
                "UI Font",
                "Sets the main font used across the application.",
                widget.currentColors.uiFontFamily,
                widget.currentColors.uiFontWeight,
                widget.currentColors.uiFontItalic,
                (PickerFont font) {
                  widget.onChanged();
                  widget.currentColors.uiFontFamily = font.fontFamily;
                  widget.currentColors.uiFontWeight = font.fontWeight.value;
                  widget.currentColors.uiFontItalic = font.fontStyle == FontStyle.italic;
                  Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                  setState(() {});
                },
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _fontPreviewTile(
                "Entry Font",
                "Overrides typography for taskbar items and headers.",
                widget.currentColors.entryFontFamily,
                widget.currentColors.entryFontWeight,
                widget.currentColors.entryFontItalic,
                (PickerFont font) {
                  widget.onChanged();
                  widget.currentColors.entryFontFamily = font.fontFamily;
                  widget.currentColors.entryFontWeight = font.fontWeight.value;
                  widget.currentColors.entryFontItalic = font.fontStyle == FontStyle.italic;
                  Globals.themeChangeNotifier.value = !Globals.themeChangeNotifier.value;
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _fontPreviewTile(
      String title, String subtitle, String family, int weight, bool italic, ValueChanged<PickerFont> onFontChanged) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
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
                const SizedBox(height: 10),
                Text(
                  "Preview text using $family",
                  style: TextStyle(
                    fontFamily: family,
                    fontWeight: AppTheme.getFontWeight(weight),
                    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
                    fontSize: 15,
                    color: onSurface,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton(
            onPressed: () => _openFontPicker(family, onFontChanged),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              minimumSize: Size.zero,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text("Change", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  void _openFontPicker(String initialFamily, ValueChanged<PickerFont> onFontChanged) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).colorScheme.surface,
          surfaceTintColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          content: SizedBox(
            width: 400,
            height: 500,
            child: Theme(
              data: Theme.of(context).copyWith(),
              child: FontPicker(
                initialFontFamily: initialFamily,
                showInDialog: true,
                onFontChanged: (PickerFont font) {
                  onFontChanged(font);
                  // Navigator.of(context).pop();
                },
              ),
            ),
          ),
        );
      },
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

  Widget _buildDesignTile(
      String title, String subtitle, QuickMenuDesigns current, ValueChanged<QuickMenuDesigns> onSelected) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    final Color accent = globalSettings.themeColors.accentColor.withValues(alpha: 1.0);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.62))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Theme(
            data: Theme.of(context).copyWith(
              hoverColor: accent.withValues(alpha: 0.05),
            ),
            child: PopupMenuButton<QuickMenuDesigns>(
              initialValue: current,
              tooltip: "Select Design",
              onSelected: onSelected,
              offset: const Offset(0, 40),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              itemBuilder: (BuildContext context) => QuickMenuDesigns.values.map((QuickMenuDesigns design) {
                return PopupMenuItem<QuickMenuDesigns>(
                  value: design,
                  child: Row(
                    children: <Widget>[
                      Icon(
                        design == current ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                        size: 16,
                        color: design == current ? accent : onSurface.withValues(alpha: 0.5),
                      ),
                      const SizedBox(width: 10),
                      Text(design.name, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                );
              }).toList(),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent.withValues(alpha: 0.15)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      current.name,
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent),
                    ),
                    const SizedBox(width: 4),
                    Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: accent),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSliderTile(String title, String subtitle, Color accent, Color onSurface, double value, double max,
      TextEditingController controller, Function(double) onChanged,
      {double min = 0.0}) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
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
                    min: min,
                    max: max,
                    value: value.clamp(min, max),
                    onChanged: (double e) {
                      onChanged(e);
                      final String newVal = max == 1.0 ? (e * 100).toInt().toString() : e.toInt().toString();
                      if (controller.text != newVal) {
                        controller.text = newVal;
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
                  controller: controller,
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
                    double? val = double.tryParse(v);
                    if (val != null) {
                      if (max == 1.0) {
                        if (val < (min * 100)) val = (min * 100);
                        if (val > 100) {
                          val = 100;
                          controller.text = "100";
                        }
                        onChanged(val / 100.0);
                      } else {
                        if (val < min) val = min;
                        if (val > max) {
                          val = max;
                          controller.text = max.toInt().toString();
                        }
                        onChanged(val);
                      }
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

  Widget _buildAppearanceCard(Color accent, Color onSurface) {
    return _settingsCard(
      title: "Global Appearance",
      subtitle: "Define the core behavior of Tabame's dark/light modes.",
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Expanded(
              child: _buildThemeModeSelector(accent, onSurface),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _buildDesignTile(
                "Design Type",
                "Quickly switch between predefined interface styles.",
                globalSettings.currentQuickMenuDesign,
                (QuickMenuDesigns design) {
                  widget.onDesignChanged(design);
                  setState(() {});
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemeModeSelector(Color accent, Color onSurface) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.start,
                    children: <Widget>[
                      const Text("Theme Mode", style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 3),
                      Text(
                        switch (globalSettings.themeType) {
                          ThemeType.system => "Following Windows settings",
                          ThemeType.light => "Always use light theme",
                          ThemeType.dark => "Always use dark theme",
                          ThemeType.schedule => "Switching at custom hours",
                        },
                        style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.62)),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Align(
                  alignment: Alignment.center,
                  child: Theme(
                    data: Theme.of(context).copyWith(
                      hoverColor: accent.withValues(alpha: 0.05),
                    ),
                    child: PopupMenuButton<ThemeType>(
                      initialValue: globalSettings.themeType,
                      tooltip: "Select Theme Mode",
                      onSelected: _setThemeType,
                      offset: const Offset(0, 40),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      itemBuilder: (BuildContext context) => ThemeType.values.map((ThemeType type) {
                        return PopupMenuItem<ThemeType>(
                          value: type,
                          child: Row(
                            children: <Widget>[
                              Icon(
                                type == globalSettings.themeType
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_off_rounded,
                                size: 16,
                                color: type == globalSettings.themeType ? accent : onSurface.withValues(alpha: 0.5),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                switch (type) {
                                  ThemeType.system => "System",
                                  ThemeType.light => "Light",
                                  ThemeType.dark => "Dark",
                                  ThemeType.schedule => "Scheduled",
                                },
                                style: const TextStyle(fontSize: 13),
                              ),
                            ],
                          ),
                        );
                      }).toList(),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: accent.withValues(alpha: 0.15)),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: <Widget>[
                            Text(
                              switch (globalSettings.themeType) {
                                ThemeType.system => "System",
                                ThemeType.light => "Light",
                                ThemeType.dark => "Dark",
                                ThemeType.schedule => "Scheduled",
                              },
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accent),
                            ),
                            const SizedBox(width: 4),
                            Icon(Icons.keyboard_arrow_down_rounded, size: 14, color: accent),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (globalSettings.themeType == ThemeType.schedule) ...<Widget>[
            const SizedBox(height: 8),
            _buildScheduleTimes(accent, onSurface),
          ],
        ],
      ),
    );
  }

  Widget _buildScheduleTimes(Color accent, Color onSurface) {
    return Container(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          _timeChipRedesigned("From", globalSettings.themeScheduleMin.formatTime(), _pickThemeStart, accent, onSurface),
          const SizedBox(width: 16),
          _timeChipRedesigned("To", globalSettings.themeScheduleMax.formatTime(), _pickThemeEnd, accent, onSurface),
        ],
      ),
    );
  }

  Widget _timeChipRedesigned(String label, String value, VoidCallback onTap, Color accent, Color onSurface) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: accent.withValues(alpha: 0.1)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(label,
                style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: onSurface.withValues(alpha: 0.5))),
            Text(value, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w900, color: accent)),
          ],
        ),
      ),
    );
  }

  Widget _buildBackdropSection(Color accent, Color onSurface) {
    return _settingsCard(
      title: "Backdrop Theme",
      subtitle: "Customize the randomized background layer.",
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: _buildChoiceTile(
                  "Source",
                  "Pick between built-in gradients or custom images.",
                  widget.currentColors.backdropType,
                  <String, String>{
                    '': 'None',
                    'builtIn': 'Built-in Gradients',
                    'custom': 'Custom Set',
                  },
                  (String val) {
                    widget.onChanged();
                    widget.currentColors.backdropType = val;
                    setState(() {});
                  },
                  accent,
                  onSurface,
                ),
              ),
            ],
          ),
          if (widget.currentColors.backdropType == 'custom') ...<Widget>[
            const SizedBox(height: 16),
            const Text("Image Set", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            if (widget.currentColors.backdropImages.isEmpty)
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: onSurface.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: onSurface.withValues(alpha: 0.06)),
                ),
                child: Center(
                  child: Column(
                    children: <Widget>[
                      Icon(Icons.image_search_rounded, size: 32, color: onSurface.withValues(alpha: 0.2)),
                      const SizedBox(height: 8),
                      Text("No custom images added", style: TextStyle(color: onSurface.withValues(alpha: 0.4))),
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
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                  childAspectRatio: 1.5,
                ),
                itemCount: widget.currentColors.backdropImages.length,
                itemBuilder: (BuildContext context, int index) {
                  final String path = widget.currentColors.backdropImages[index];
                  return Stack(
                    children: <Widget>[
                      Positioned.fill(
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.file(
                            File(path),
                            cacheWidth: 230,
                            fit: BoxFit.cover,
                            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => Container(
                              color: Colors.grey.withAlpha(50),
                              child: const Icon(Icons.broken_image_rounded),
                            ),
                          ),
                        ),
                      ),
                      Positioned(
                        top: 4,
                        right: 4,
                        child: InkWell(
                          onTap: () async {
                            widget.onChanged();
                            final List<String> newList = List<String>.from(widget.currentColors.backdropImages);
                            final String removedPath = newList.removeAt(index);
                            widget.currentColors.backdropImages = newList;
                            if (File(removedPath).existsSync()) {
                              try {
                                await File(removedPath).delete();
                              } catch (e) {
                                Debug.add("Theme Setup Error deleting file: $e");
                              }
                            }
                            setState(() {});
                          },
                          child: Container(
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(color: Colors.black45, shape: BoxShape.circle),
                            child: const Icon(Icons.close_rounded, size: 14, color: Colors.white),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            const SizedBox(height: 12),
            if (_isBackdropProcessing) ...<Widget>[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.16)),
                ),
                child: Row(
                  children: <Widget>[
                    SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: accent.withValues(alpha: 0.8),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        "Converted backdrops $_backdropProcessingConverted / $_backdropProcessingTotal",
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w700,
                          color: onSurface.withValues(alpha: 0.82),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              LinearProgressIndicator(
                value: _backdropProcessingTotal == 0 ? null : _backdropProcessingCompleted / _backdropProcessingTotal,
                minHeight: 3,
                borderRadius: BorderRadius.circular(999),
                color: accent,
                backgroundColor: accent.withValues(alpha: 0.14),
              ),
              const SizedBox(height: 12),
            ],
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isBackdropProcessing ? null : _addBackdropImages,
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  side: BorderSide(color: accent.withValues(alpha: 0.3)),
                ),
                icon: Icon(
                  _isBackdropProcessing ? Icons.hourglass_top_rounded : Icons.add_photo_alternate_rounded,
                  size: 18,
                ),
                label: Text(
                  _isBackdropProcessing ? "Converting Images..." : "Add Custom Images",
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          if (widget.currentColors.backdropType != '')
            _buildSliderTile(
              "Backdrop Opacity",
              "Adjust the intensity of the background image overlay.",
              accent,
              onSurface,
              widget.currentColors.backdropOpacity,
              1.0,
              backdropOpacityController,
              (double v) {
                widget.onChanged();
                widget.onBackdropOpacityChanged(v);
              },
              min: 0.0,
            ),
        ],
      ),
    );
  }

  Widget _buildChoiceTile(
    String title,
    String subtitle,
    String current,
    Map<String, String> options,
    ValueChanged<String> onSelected,
    Color accent,
    Color onSurface,
  ) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withValues(alpha: 0.06)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Text(title, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                const SizedBox(height: 3),
                Text(subtitle, style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.62))),
              ],
            ),
          ),
          const SizedBox(width: 10),
          ToggleButtons(
            isSelected: options.keys.map((String key) => key == current).toList(),
            onPressed: (int index) => onSelected(options.keys.elementAt(index)),
            borderRadius: BorderRadius.circular(8),
            selectedColor: accent,
            fillColor: accent.withValues(alpha: 0.1),
            children: options.values
                .map((String val) => Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(val, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                    ))
                .toList(),
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

Future<void> _resizeAndSaveBackdrop(Map<String, String> args) async {
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
    Debug.add("Async Backdrop Processor Error: $e");
    // Fallback to direct copy if image processing fails
    if (sourceFile.existsSync()) {
      await sourceFile.copy(targetPath);
    }
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final Color accent;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.onPressed,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;
    return CustomTooltip(
      message: label,
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: accent.withValues(alpha: 0.2)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(icon, size: 18, color: accent),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: onSurface.withValues(alpha: 0.9),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
