import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../widgets/info_text.dart';
import '../widgets/text_input.dart';

class ViewsInterface extends StatefulWidget {
  const ViewsInterface({super.key});

  @override
  ViewsInterfaceState createState() => ViewsInterfaceState();
}

class ViewsInterfaceState extends State<ViewsInterface> {
  final ViewsSettings settings = ViewsSettings();
  @override
  void initState() {
    settings.load();
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CheckboxListTile(
          value: globalSettings.views,
          controlAffinity: ListTileControlAffinity.leading,
          onChanged: (bool? e) => setState(
            () {
              globalSettings.views = !globalSettings.views;
              Boxes.updateSettings("views", globalSettings.views);
            },
          ),
          title: Text("Grid View", style: Theme.of(context).textTheme.titleLarge),
          subtitle: const InfoText("With Grid View, you can organize windows on your screen based on a grid"),
        ),
        if (globalSettings.views)
          Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                      child: Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          CheckboxListTile(
                            value: settings.setPreviousSize,
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged: (bool? e) => setState(
                              () {
                                settings.setPreviousSize = !settings.setPreviousSize;
                                settings.save();
                              },
                            ),
                            title: Text("Reset Previous Size", style: Theme.of(context).textTheme.labelLarge),
                            subtitle: const Text("When you move the window after you set it on grid, it will regain it's original size"),
                          ),
                          ListTile(
                            onTap: () {
                              Color? newColor;
                              showDialog(
                                context: context,
                                builder: (BuildContext context) {
                                  return AlertDialog(
                                      content: CustomColorPicker(
                                    startColor: settings.bgColor,
                                    onColorChanged: (Color color) {
                                      newColor = color;
                                    },
                                  ));
                                },
                              ).then((_) {
                                if (newColor == null) return;
                                settings.bgColor = newColor!;
                                settings.save();
                                setState(() {});
                                // onColorChanged(newColor!);
                              });
                            },
                            title: const Text("Background color"),
                            leading: RoundColorPreview(
                              color: settings.bgColor,
                              onPressed: () {},
                            ),
                            trailing: const Icon(Icons.colorize),
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 5),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text("Scale", style: Theme.of(context).textTheme.bodyLarge),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: TextInput(
                                    key: UniqueKey(),
                                    labelText: "Width",
                                    value: settings.scaleW.toString(),
                                    onChanged: (String e) {
                                      settings.scaleW = int.tryParse(e) ?? 15;
                                      settings.save();
                                    },
                                  ),
                                ),
                                Expanded(
                                  child: TextInput(
                                    key: UniqueKey(),
                                    labelText: "Height",
                                    value: settings.scaleH.toString(),
                                    onChanged: (String e) {
                                      settings.scaleH = int.tryParse(e) ?? 15;
                                      settings.save();
                                    },
                                  ),
                                ),
                              ],
                            ),

                            ///

                            Text("Scroll Step", style: Theme.of(context).textTheme.bodyLarge),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: TextInput(
                                    key: UniqueKey(),
                                    labelText: "Width",
                                    value: settings.scrollStepW.toString(),
                                    onChanged: (String e) {
                                      settings.scrollStepW = int.tryParse(e) ?? 15;
                                      settings.save();
                                    },
                                  ),
                                ),
                                Expanded(
                                  child: TextInput(
                                    key: UniqueKey(),
                                    labelText: "Height",
                                    value: settings.scrollStepH.toString(),
                                    onChanged: (String e) {
                                      settings.scrollStepH = int.tryParse(e) ?? 15;
                                      settings.save();
                                    },
                                  ),
                                ),
                              ],
                            ),

                            ///

                            Text("Width Clamp", style: Theme.of(context).textTheme.bodyLarge),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: TextInput(
                                    key: UniqueKey(),
                                    labelText: "Min",
                                    value: settings.minW.toString(),
                                    onChanged: (String e) {
                                      settings.minW = int.tryParse(e) ?? 15;
                                      settings.save();
                                    },
                                  ),
                                ),
                                Expanded(
                                  child: TextInput(
                                    key: UniqueKey(),
                                    labelText: "Max",
                                    value: settings.maxW.toString(),
                                    onChanged: (String e) {
                                      settings.maxW = int.tryParse(e) ?? 15;
                                      settings.save();
                                    },
                                  ),
                                ),
                              ],
                            ),

                            ///

                            Text("Height Clamp", style: Theme.of(context).textTheme.bodyLarge),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: TextInput(
                                    key: UniqueKey(),
                                    labelText: "Min",
                                    value: settings.minH.toString(),
                                    onChanged: (String e) {
                                      settings.minH = int.tryParse(e) ?? 15;
                                      settings.save();
                                    },
                                  ),
                                ),
                                Expanded(
                                  child: TextInput(
                                    key: UniqueKey(),
                                    labelText: "Max",
                                    value: settings.maxH.toString(),
                                    onChanged: (String e) {
                                      settings.maxH = int.tryParse(e) ?? 15;
                                      settings.save();
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  )),
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.all(8.0),
                      child: Markdown(
                        shrinkWrap: true,
                        data: """If you changed your screen DPI, this won't work properly. You can use PowerToys FancyZone.

This can use this when presets do not give you enough flexibility.

## How to use:
  - When moving a window, press right click.
  - Scroll up or down to change the grid to your desired size.
  - Move the mouse where you want then hold right click and select an area.
  - Release right click and left click.

  """,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
      ],
    );
  }
}

class RoundColorPreview extends StatelessWidget {
  const RoundColorPreview({
    super.key,
    required this.color,
    required this.onPressed,
  });

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
            backgroundColor: color,
            padding: const EdgeInsets.all(0),
            fixedSize: const Size(5, 5),
          ),
        ),
      ),
    );
  }
}

class CustomColorPicker extends StatelessWidget {
  const CustomColorPicker({
    super.key,
    required this.startColor,
    required this.onColorChanged,
  });
  final Color startColor;
  final Function(Color) onColorChanged;
  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
        child:
            Container() /* ColorPicker(
        columnSpacing: 15,
        padding: const EdgeInsets.symmetric(horizontal: 0),
        heading: null,
        showColorName: true,
        showColorCode: true,
        colorCodeHasColor: true,
        actionButtons: const ColorPickerActionButtons(
          okButton: true,
          okTooltip: "Save Color",
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
        subheading: Text('Select color shade', style: Theme.of(context).textTheme.titleMedium),
      ), */
        );
  }
}
