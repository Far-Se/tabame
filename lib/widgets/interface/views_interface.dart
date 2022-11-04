import 'dart:convert';
import 'dart:typed_data';

import 'package:flex_color_picker/flex_color_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../models/win32/mixed.dart';
import '../../models/win32/win32.dart';
import '../../models/win32/window.dart';
import '../../models/window_watcher.dart';
import '../widgets/info_text.dart';
import '../widgets/text_input.dart';

class ViewsInterface extends StatefulWidget {
  const ViewsInterface({Key? key}) : super(key: key);

  @override
  ViewsInterfaceState createState() => ViewsInterfaceState();
}

class ViewsInterfaceState extends State<ViewsInterface> {
  List<PredefinedSizes> predefinedSizes = Boxes.predefinedSizes;
  final ViewsSettings settings = ViewsSettings();
  final List<Workspaces> workspaces = Boxes.workspaces;
  Workspaces newWorkspace = Workspaces(name: 'name', hooks: const <int, List<int>>{}, windows: <WorkspaceWindow>[]);
  WorkspaceWindow? currentWorkspaceWindow;
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
          title: Text("Grid View", style: Theme.of(context).textTheme.headline6),
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
                            title: Text("Reset Previous Size", style: Theme.of(context).textTheme.button),
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
        const Divider(height: 10, thickness: 1),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text("Workspaces", style: Theme.of(context).textTheme.headline6),
              const SizedBox(height: 5),
              const InfoText("With Workspaces you can save current position and size of specific windows, so you can load them easily from QuickMenu QuickActions"),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    flex: 5,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text("Create new Workspace:", style: Theme.of(context).textTheme.headline6),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: TextInput(
                                labelText: "Name:",
                                key: UniqueKey(),
                                value: newWorkspace.name,
                                onChanged: (String v) {
                                  newWorkspace.name = v;
                                  setState(() {});
                                },
                              ),
                            ),
                            Expanded(
                              child: newWorkspace.windows.isEmpty
                                  ? const SizedBox()
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text("Total: ${newWorkspace.windows.length}"),
                                        OutlinedButton(
                                            onPressed: () {
                                              workspaces.add(newWorkspace.copyWith());
                                              newWorkspace = Workspaces(name: 'name', hooks: const <int, List<int>>{}, windows: <WorkspaceWindow>[]);
                                              Boxes.updateSettings("workspaces", jsonEncode(workspaces));
                                              setState(() {});
                                            },
                                            child: const Text("Save")),
                                      ],
                                    ),
                            )
                          ],
                        ),
                        const Divider(height: 5, thickness: 0.5),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Expanded(
                              child: currentWorkspaceWindow == null
                                  ? const Text("Select a window from right")
                                  : Column(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: <Widget>[
                                        Text("Position: [${currentWorkspaceWindow!.posX}:${currentWorkspaceWindow!.posX}]\n"
                                            "Size: [${currentWorkspaceWindow!.width}:${currentWorkspaceWindow!.height}]\n"
                                            "Executable: ${currentWorkspaceWindow!.exe}\nTitle Like (opt):"),
                                        TextInput(
                                          key: UniqueKey(),
                                          labelText: "Title(regex aware):",
                                          value: currentWorkspaceWindow!.title,
                                          onChanged: (String v) {
                                            currentWorkspaceWindow!.title = v;
                                            setState(() {});
                                          },
                                        ),
                                        OutlinedButton(
                                            onPressed: () {
                                              newWorkspace.windows.add(currentWorkspaceWindow!.copyWith());
                                              currentWorkspaceWindow = null;
                                              setState(() {});
                                            },
                                            child: const Text("Add"))
                                      ],
                                    ),
                            ),
                            Expanded(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  OutlinedButton(
                                    onPressed: () async {
                                      await WindowWatcher.fetchWindows();
                                      setState(() {});
                                    },
                                    child: const Text("Refresh Windows"),
                                  ),
                                  Container(
                                    height: 130,
                                    child: ListView.builder(
                                      controller: ScrollController(),
                                      itemCount: WindowWatcher.list.length,
                                      itemBuilder: (BuildContext context, int index) {
                                        final Window win = WindowWatcher.list.elementAt(index);
                                        return InkWell(
                                          onTap: () {
                                            final Square rect = Win32.getWindowRect(hwnd: win.hWnd);
                                            currentWorkspaceWindow = WorkspaceWindow(
                                              exe: win.process.exe,
                                              title: "",
                                              monitorID: win.monitor ?? 0,
                                              posX: rect.x,
                                              posY: rect.y,
                                              width: rect.width,
                                              height: rect.height,
                                            );
                                            setState(() {});
                                          },
                                          child: Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: <Widget>[
                                                SizedBox(
                                                  width: 25,
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                                                    child: ((WindowWatcher.icons.containsKey(win.hWnd))
                                                        ? Image.memory(
                                                            WindowWatcher.icons[win.hWnd] ?? Uint8List(0),
                                                            width: 16,
                                                            height: 16,
                                                            gaplessPlayback: true,
                                                            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => const Icon(
                                                              Icons.check_box_outline_blank,
                                                              size: 16,
                                                            ),
                                                          )
                                                        : const Icon(Icons.web_asset_sharp, size: 20)),
                                                  ),
                                                ),
                                                Expanded(
                                                  child: Text(
                                                    win.title,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.fade,
                                                    softWrap: false,
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text("Workspaces:", style: Theme.of(context).textTheme.headline6),
                        ...List<Widget>.generate(workspaces.length, (int index) {
                          return ListTile(
                            onTap: () {
                              workspaces.removeAt(index);
                              Boxes.updateSettings("workspaces", jsonEncode(workspaces));
                              setState(() {});
                            },
                            dense: true,
                            title: Text("${workspaces.elementAt(index).name}"),
                            trailing: const Icon(Icons.delete, size: 17),
                          );
                        })
                      ],
                    ),
                  )
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Divider(height: 10, thickness: 1),
                        ListTile(title: Text("Hooks", style: Theme.of(context).textTheme.headline6)),
                        const SizedBox(height: 5),
                        const InfoText(
                            "Hooks is part of Views. With hooks you can bind windows together, so when you focus the main one, others will appear on screen as well. Open QuickMenu and right click a window, then select other windows."),
                        const SizedBox(height: 20),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        const Divider(height: 10, thickness: 1),
                        ListTile(
                          title: Text("Predefined Sizes", style: Theme.of(context).textTheme.headline6),
                          onTap: () {
                            predefinedSizes.add(PredefinedSizes(name: "new", width: 0, height: 0, x: -1, y: -1));
                            Boxes.updateSettings("predefinedSizes", jsonEncode(predefinedSizes));
                            setState(() {});
                          },
                          trailing: const Icon(Icons.add),
                        ),
                        const SizedBox(height: 5),
                        const InfoText(
                            "You can set a specific size to a window. Right Click the window in QuickMenu then select a predefined size. Set -1 to not change the value."),
                        if (predefinedSizes.isNotEmpty)
                          Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: List<Widget>.generate(
                              predefinedSizes.length,
                              (int index) => Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: <Widget>[
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.start,
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: <Widget>[
                                      Expanded(
                                        flex: 1,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Column(
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: <Widget>[
                                                TextInput(
                                                  key: UniqueKey(),
                                                  labelText: "Title",
                                                  onChanged: (String e) {
                                                    if (e.isEmpty) e = "New";
                                                    predefinedSizes.elementAt(index).name = e;
                                                    Boxes.updateSettings("predefinedSizes", jsonEncode(predefinedSizes));
                                                    setState(() {});
                                                  },
                                                  value: predefinedSizes.elementAt(index).name,
                                                ),
                                                IconButton(
                                                  onPressed: () {
                                                    predefinedSizes.removeAt(index);
                                                    Boxes.updateSettings("predefinedSizes", jsonEncode(predefinedSizes));
                                                    setState(() {});
                                                  },
                                                  icon: const Icon(Icons.delete),
                                                  splashRadius: 20,
                                                )
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Column(
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: <Widget>[
                                                TextInput(
                                                  key: UniqueKey(),
                                                  labelText: "Width",
                                                  onChanged: (String e) {
                                                    predefinedSizes.elementAt(index).width = int.tryParse(e) ?? 0;
                                                    Boxes.updateSettings("predefinedSizes", jsonEncode(predefinedSizes));
                                                  },
                                                  value: predefinedSizes.elementAt(index).width.toString(),
                                                ),
                                                TextInput(
                                                  key: UniqueKey(),
                                                  labelText: "Height",
                                                  onChanged: (String e) {
                                                    predefinedSizes.elementAt(index).height = int.tryParse(e) ?? 0;
                                                    Boxes.updateSettings("predefinedSizes", jsonEncode(predefinedSizes));
                                                  },
                                                  value: predefinedSizes.elementAt(index).height.toString(),
                                                )
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                      Expanded(
                                        flex: 1,
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Column(
                                              mainAxisAlignment: MainAxisAlignment.start,
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: <Widget>[
                                                TextInput(
                                                  key: UniqueKey(),
                                                  labelText: "X",
                                                  onChanged: (String e) {
                                                    predefinedSizes.elementAt(index).x = int.tryParse(e) ?? 0;
                                                    Boxes.updateSettings("predefinedSizes", jsonEncode(predefinedSizes));
                                                  },
                                                  value: predefinedSizes.elementAt(index).x.toString(),
                                                ),
                                                TextInput(
                                                  key: UniqueKey(),
                                                  labelText: "Y",
                                                  onChanged: (String e) {
                                                    predefinedSizes.elementAt(index).y = int.tryParse(e) ?? 0;
                                                    Boxes.updateSettings("predefinedSizes", jsonEncode(predefinedSizes));
                                                  },
                                                  value: predefinedSizes.elementAt(index).y.toString(),
                                                )
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                  const Divider(
                                    height: 1,
                                    thickness: 2,
                                  )
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
                  )
                ],
              ),
            ],
          ),
        ),
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
        subheading: Text('Select color shade', style: Theme.of(context).textTheme.subtitle1),
      ),
    );
  }
}
