// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:convert';
import 'dart:math';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../main.dart';
import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/util/theme_colors.dart';
import '../../models/settings.dart';
import '../widgets/info_text.dart';

class ThemeSetup extends StatefulWidget {
  const ThemeSetup({Key? key}) : super(key: key);

  @override
  ThemeSetupState createState() => ThemeSetupState();
}

Map<ColorSwatch<Object>, String> getPredefinedColorSet(List<List<int>> predefined, int offset, {int maximum = 60}) {
  final Map<ColorSwatch<Object>, String> output = <ColorSwatch<Object>, String>{};
  final List<int> colorSet = predefined.map((List<int> e) => e[offset]).toSet().toList();
  int i = 0;
  for (int element in colorSet) {
    i++;
    output[ColorTools.createPrimarySwatch(Color(element))] = "Variant #$i";
    if (i == maximum) break;
  }
  return output;
}

class ThemeSetupState extends State<ThemeSetup> {
  final ScrollController colorScrollController = ScrollController();
  final ScrollController mainScrollControl = ScrollController();

  ThemeColors savedLightTheme = globalSettings.lightTheme;
  ThemeColors savedDarkTheme = globalSettings.darkTheme;

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
    if (lightTheme != null) savedLightTheme = ThemeColors.fromJson(lightTheme);

    final String? darkTheme = Boxes.pref.getString('darkTheme');
    if (darkTheme != null) savedDarkTheme = ThemeColors.fromJson(darkTheme);
  }

  @override
  void dispose() {
    colorScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (PointerSignalEvent ps) {
        if (ps is PointerScrollEvent) {
          double scrollEnd = mainScrollControl.offset + (ps.scrollDelta.dy > 0 ? 30 : -30);
          scrollEnd = min(mainScrollControl.position.maxScrollExtent, max(mainScrollControl.position.minScrollExtent, scrollEnd));
          mainScrollControl.jumpTo(scrollEnd);
        }
      },
      child: SingleChildScrollView(
        controller: mainScrollControl,
        physics: const NeverScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Material(
            type: MaterialType.transparency,
            child: ListTileTheme(
              data: Theme.of(context).listTileTheme.copyWith(
                    dense: true,
                    style: ListTileStyle.drawer,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                    minVerticalPadding: 0,
                    visualDensity: VisualDensity.compact,
                    horizontalTitleGap: 0,
                  ),
              child: globalSettings.themeTypeMode == ThemeType.dark
                  ? ThemeSetupWidget(
                      title: "Dark Theme",
                      constraints: const BoxConstraints(),
                      savedColors: savedDarkTheme,
                      currentColors: globalSettings.darkTheme,
                      onSaved: () async {
                        await Boxes.updateSettings("darkTheme", globalSettings.darkTheme.toJson());
                        savedDarkTheme = globalSettings.darkTheme;
                        Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                        setState(() {});
                      },
                      onGradiendChanged: (double e) {
                        globalSettings.darkTheme.gradientAlpha = e.toInt();
                        Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                      },
                      quickMenuBoldChanged: (bool e) {
                        globalSettings.darkTheme.quickMenuBoldFont = e;
                        Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                      },
                      onColorChanged: (Color color, int i) {
                        if (i == 0) globalSettings.darkTheme.background = color.value;
                        if (i == 1) globalSettings.darkTheme.textColor = color.value;
                        if (i == 2) globalSettings.darkTheme.accentColor = color.value;
                        themeChangeNotifier.value = !themeChangeNotifier.value;
                        Boxes.updateSettings("previewThemeDark", jsonDecode(globalSettings.darkTheme.toJson()));
                      },
                      predefinedColors: predefinedColorsDark,
                    )
                  : ThemeSetupWidget(
                      title: "Light Theme",
                      constraints: const BoxConstraints(),
                      savedColors: savedLightTheme,
                      currentColors: globalSettings.lightTheme,
                      onSaved: () async {
                        await Boxes.updateSettings("lightTheme", globalSettings.lightTheme.toJson());
                        savedLightTheme = globalSettings.lightTheme;
                        Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                        setState(() {});
                      },
                      onGradiendChanged: (double e) {
                        globalSettings.lightTheme.gradientAlpha = e.toInt();
                        Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                      },
                      quickMenuBoldChanged: (bool e) {
                        globalSettings.lightTheme.quickMenuBoldFont = e;
                        Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                      },
                      onColorChanged: (Color color, int i) {
                        if (i == 0) globalSettings.lightTheme.background = color.value;
                        if (i == 1) globalSettings.lightTheme.textColor = color.value;
                        if (i == 2) globalSettings.lightTheme.accentColor = color.value;
                        themeChangeNotifier.value = !themeChangeNotifier.value;
                        Boxes.updateSettings("previewThemeLight", jsonDecode(globalSettings.lightTheme.toJson()));
                      },
                      predefinedColors: predefinedColorsLight,
                    ),
            ),
          ),
        ),
      ),
    );
  }
}

class ThemeSetupWidget extends StatefulWidget {
  final String title;
  final BoxConstraints constraints;
  final Function onSaved;
  final Function(double) onGradiendChanged;
  final Function(bool) quickMenuBoldChanged;
  final Function(Color, int) onColorChanged;
  final ThemeColors savedColors;
  final ThemeColors currentColors;
  final List<Map<ColorSwatch<Object>, String>> predefinedColors;
  const ThemeSetupWidget({
    Key? key,
    required this.title,
    required this.constraints,
    required this.onSaved,
    required this.onGradiendChanged,
    required this.quickMenuBoldChanged,
    required this.onColorChanged,
    required this.savedColors,
    required this.currentColors,
    required this.predefinedColors,
  }) : super(key: key);

  @override
  State<ThemeSetupWidget> createState() => _ThemeSetupWidgetState();
}

class _ThemeSetupWidgetState extends State<ThemeSetupWidget> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          "You can switch between light theme and dark theme on Settings Tab.",
          style: TextStyle(
            fontStyle: FontStyle.italic,
            color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.6),
          ),
        ),
        Tooltip(
          message: "Save ${widget.title}",
          preferBelow: false,
          verticalOffset: 30,
          decoration: BoxDecoration(
            border: Border.all(width: 1, color: Colors.black26),
            color: Theme.of(context).backgroundColor,
          ),
          child: ListTile(
            leading: const Icon(Icons.save_outlined),
            dense: false,
            onTap: () => widget.onSaved(),
            contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            title: Text("${widget.title}", style: Theme.of(context).textTheme.titleLarge),
            subtitle: const Text("Press here to save changes"),
            trailing: const Icon(Icons.save_outlined),
          ),
        ),
        const InfoText("Do not forget to save the theme!"),
        const SizedBox(height: 10),
        SliderTheme(
          data: Theme.of(context).sliderTheme.copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0),
                overlayShape: SliderComponentShape.noOverlay,
              ),
          child: Tooltip(
            message: "Gradient Opacity in Quickmenu",
            preferBelow: true,
            child: Slider(
              min: 199,
              max: 255,
              value: widget.currentColors.gradientAlpha.toDouble(),
              onChanged: (double e) {
                widget.onGradiendChanged(e);
                setState(() {});
              },
            ),
          ),
        ),
        ColorSetup(
          savedColor: Color(widget.savedColors.background),
          predefinedColors: widget.predefinedColors[0],
          currentColor: Color(widget.currentColors.background),
          colorName: "Background Color",
          onColorChanged: (Color color) {
            widget.onColorChanged(color, 0);
            setState(() {});
          },
        ),
        ColorSetup(
          savedColor: Color(widget.savedColors.textColor),
          predefinedColors: widget.predefinedColors[1],
          currentColor: Color(widget.currentColors.textColor),
          colorName: "Text Color",
          onColorChanged: (Color color) {
            widget.onColorChanged(color, 1);
            setState(() {});
          },
        ),
        ColorSetup(
          savedColor: Color(widget.savedColors.accentColor),
          predefinedColors: widget.predefinedColors[2],
          currentColor: Color(widget.currentColors.accentColor),
          colorName: "Accent Color",
          onColorChanged: (Color color) {
            widget.onColorChanged(color, 2);
            setState(() {});
          },
        ),
        AppsWrittenInbold(widget: widget)
      ],
    );
  }
}

class AppsWrittenInbold extends StatefulWidget {
  const AppsWrittenInbold({
    Key? key,
    required this.widget,
  }) : super(key: key);

  final ThemeSetupWidget widget;

  @override
  State<AppsWrittenInbold> createState() => _AppsWrittenInboldState();
}

class _AppsWrittenInboldState extends State<AppsWrittenInbold> {
  @override
  Widget build(BuildContext context) {
    return CheckboxListTile(
      value: widget.widget.currentColors.quickMenuBoldFont,
      controlAffinity: ListTileControlAffinity.leading,
      onChanged: (bool? e) {
        widget.widget.quickMenuBoldChanged(e ?? false);
        setState(() {});
      },
      title: const Text("Apps in QuickMenu written in Bold"),
    );
  }
}

class ColorSetup extends StatelessWidget {
  const ColorSetup({
    Key? key,
    required this.savedColor,
    required this.currentColor,
    required this.colorName,
    required this.predefinedColors,
    required this.onColorChanged,
  }) : super(key: key);

  final Color savedColor;
  final Color currentColor;
  final String colorName;
  final Map<ColorSwatch<Object>, String> predefinedColors;
  final Function(Color) onColorChanged;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        ListTile(
          leading: RoundColorPreview(
            color: savedColor,
            onPressed: () => onColorChanged(savedColor),
          ),
          title: Text("$colorName:", style: Theme.of(context).textTheme.bodyLarge),
        ),
        const SizedBox(height: 10),
        ListColors(
          colorsNameMap: predefinedColors,
          onColorChanged: (Color color) => onColorChanged(color),
        ),
        ListTile(
          onTap: () {
            Color? newColor;
            showDialog(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                    content: CustomColorPicker(
                  startColor: currentColor,
                  onColorChanged: (Color color) {
                    newColor = color;
                  },
                ));
              },
            ).then((_) {
              if (newColor == null) return;
              onColorChanged(newColor!);
            });
          },
          title: const Text("Pick a color"),
          leading: RoundColorPreview(
            color: currentColor,
            onPressed: () {},
          ),
          trailing: const Icon(Icons.colorize),
        ),
        const Divider(height: 20, thickness: 2)
      ],
    );
  }
}

class RoundColorPreview extends StatelessWidget {
  const RoundColorPreview({
    Key? key,
    required this.color,
    required this.onPressed,
  }) : super(key: key);

  final Color color;
  final Function()? onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Tooltip(
        message: "Saved Color",
        child: ElevatedButton(
          onPressed: onPressed,
          child: const SizedBox(),
          style: ElevatedButton.styleFrom(
            shape: const CircleBorder(),
            padding: const EdgeInsets.all(0),
            primary: color,
            fixedSize: const Size(5, 5),
          ),
        ),
      ),
    );
  }
}

class CustomColorPicker extends StatelessWidget {
  const CustomColorPicker({
    Key? key,
    required this.startColor,
    required this.onColorChanged,
  }) : super(key: key);
  final Color startColor;
  final Function(Color) onColorChanged;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      child: ColorPicker(
        columnSpacing: 15,
        padding: const EdgeInsets.symmetric(horizontal: 0),
        heading: null,
        showColorName: true,
        showColorCode: true,
        colorCodeHasColor: true,
        actionButtons: const ColorPickerActionButtons(
          okButton: true,
          okTooltip: "Test Color",
        ),
        copyPasteBehavior: const ColorPickerCopyPasteBehavior(
          copyFormat: ColorPickerCopyFormat.hexRRGGBB,
          pasteButton: true,
          editFieldCopyButton: false,
        ),
        pickersEnabled: <ColorPickerType, bool>{
          ColorPickerType.custom: true,
          ColorPickerType.wheel: true,
          ColorPickerType.primary: true,
          ColorPickerType.accent: true,
        },
        color: startColor,
        onColorChanged: onColorChanged,
        width: 20,
        height: 20,
        borderRadius: 22,
        subheading: Text('Select color shade', style: Theme.of(context).textTheme.subtitle1),
      ),
    );
  }
}

class ListColors extends StatelessWidget {
  ListColors({
    Key? key,
    required this.colorsNameMap,
    required this.onColorChanged,
  }) : super(key: key);

  final ScrollController colorScrollController = ScrollController();
  final Map<ColorSwatch<Object>, String> colorsNameMap;
  final Function(Color) onColorChanged;
  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerSignal: (PointerSignalEvent pointerSignal) {
        if (pointerSignal is PointerScrollEvent) {
          if (pointerSignal.scrollDelta.dy < 0) {
            colorScrollController.animateTo(colorScrollController.offset - 190, duration: const Duration(milliseconds: 200), curve: Curves.ease);
          } else {
            colorScrollController.animateTo(colorScrollController.offset + 190, duration: const Duration(milliseconds: 200), curve: Curves.ease);
          }
        }
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Stack(
          children: <Widget>[
            ShaderMask(
              shaderCallback: (Rect rect) {
                return const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: <Color>[Colors.transparent, Colors.transparent, Color.fromARGB(255, 0, 0, 0)],
                  stops: <double>[0.0, 0.93, 1.0],
                ).createShader(rect);
              },
              blendMode: BlendMode.dstOut,
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                controller: colorScrollController,
                child: Row(
                  children: <Widget>[
                    ColorPicker(
                      columnSpacing: 15,
                      padding: const EdgeInsets.symmetric(horizontal: 0),
                      heading: null,
                      copyPasteBehavior: const ColorPickerCopyPasteBehavior(
                        copyFormat: ColorPickerCopyFormat.hexRRGGBB,
                        pasteButton: false,
                        editFieldCopyButton: false,
                      ),
                      pickersEnabled: <ColorPickerType, bool>{
                        ColorPickerType.custom: true,
                        ColorPickerType.primary: false,
                        ColorPickerType.accent: false,
                      },
                      customColorSwatchesAndNames: colorsNameMap,
                      color: Color(globalSettings.darkTheme.textColor),
                      enableShadesSelection: false,
                      onColorChanged: (Color color) => onColorChanged(color),
                      width: 20,
                      height: 20,
                      borderRadius: 22,
                      subheading: Text('Select color shade', style: Theme.of(context).textTheme.subtitle1),
                    ),
                    const SizedBox(width: 50)
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
