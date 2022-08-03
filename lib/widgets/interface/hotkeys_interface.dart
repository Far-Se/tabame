// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:win32/win32.dart' hide Point;

import '../../models/classes/boxes.dart';
import '../../models/classes/hotkeys.dart';
import '../../models/win32/win32.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/text_input.dart';

class HotkeysInterface extends StatefulWidget {
  const HotkeysInterface({Key? key}) : super(key: key);
  @override
  HotkeysInterfaceState createState() => HotkeysInterfaceState();
}

class HotkeysInterfaceState extends State<HotkeysInterface> {
  final List<Hotkeys> remap = Boxes.remap;
  final List<String> mouseButtons = <String>[];
  FocusNode focusNode = FocusNode();

  bool listeningToHotkey = false;

  List<int> unfolded = <int>[];
  @override
  void initState() {
    super.initState();
    // Boxes.pref.remove("remap");
    bool mouseButton4 = true;
    bool mouseButton5 = true;
    for (Hotkeys hotkey in remap) {
      if (hotkey.key == "MouseButton4") mouseButton4 = false;
      if (hotkey.key == "MouseButton5") mouseButton5 = false;
    }
    if (mouseButton4) mouseButtons.add("MouseButton4");
    if (mouseButton5) mouseButtons.add("MouseButton5");
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        ListTile(
          onTap: () {
            // if (1 + 1 == 2) return;
            remap.add(Hotkeys(
              key: "",
              modifiers: <String>[],
              prohibited: <String>[],
              noopScreenBusy: false,
              keymaps: <KeyMap>[
                KeyMap(
                  name: "new",
                  enabled: false,
                  boundToRegion: false,
                  region: Region(),
                  triggerType: TriggerType.press,
                  windowsInfo: <String>[],
                  windowUnderMouse: false,
                  triggerInfo: <int>[],
                  actions: <KeyAction>[],
                  variableCheck: <String>[],
                )
              ],
            ));
            Boxes.updateSettings("remap", jsonEncode(remap));
            setState(() {});
          },
          title: Text("Remap", style: Theme.of(context).textTheme.headline4),
          leading: Container(height: double.infinity, child: const Icon(Icons.add, size: 30)),
        ),
        ...List<Widget>.generate(
          remap.length,
          (int index) {
            final Hotkeys keymap = remap[index];
            return Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                ListTile(
                  leading: Container(
                    width: 80,
                    child: Row(
                      children: <Widget>[
                        SizedBox(
                          width: 40,
                          child: InkWell(
                            onTap: () {
                              showDialog(
                                  context: context,
                                  builder: (BuildContext context) {
                                    return AlertDialog(
                                      content: Container(
                                        width: 400,
                                        height: 400,
                                        child: SingleChildScrollView(
                                          controller: ScrollController(),
                                          child: HotKeySettings(hotkeyIndex: index),
                                        ),
                                      ),
                                    );
                                  });
                            },
                            child: Container(
                              height: double.infinity,
                              width: 40,
                              child: const Icon(Icons.edit),
                            ),
                          ),
                        ),
                        SizedBox(
                          width: 40,
                          child: InkWell(
                            onTap: () {
                              keymap.keymaps.add(KeyMap(
                                enabled: true,
                                windowUnderMouse: true,
                                name: "Key Trigger",
                                windowsInfo: <String>[],
                                boundToRegion: false,
                                region: Region(),
                                triggerType: TriggerType.press,
                                triggerInfo: <int>[],
                                actions: <KeyAction>[],
                                variableCheck: <String>[],
                              ));
                              setState(() {});
                            },
                            child: Container(
                              height: double.infinity,
                              width: 40,
                              child: const Icon(Icons.add),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  minLeadingWidth: 40,
                  title: Text(keymap.hotkey),
                  trailing: const Icon(Icons.expand_more),
                  onTap: () {
                    if (unfolded.contains(index)) {
                      unfolded.remove(index);
                    } else {
                      unfolded.add(index);
                    }
                    setState(() {});
                  },
                ),

                //! here
                if (unfolded.contains(index))
                  ...List<Widget>.generate(
                    keymap.keymaps.length,
                    (int index) {
                      return ListTile(
                        title: Text(keymap.keymaps[index].name),
                        leading: const Icon(Icons.edit),
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                scrollable: false,
                                content: Container(
                                  height: 600,
                                  width: 800,
                                  child: SingleChildScrollView(
                                    controller: ScrollController(),
                                    child: HotKeyAction(
                                      hotkey: keymap.keymaps[index].copyWith(),
                                      onSaved: (KeyMap hotkey) {
                                        keymap.keymaps[index] = hotkey;
                                      },
                                    ),
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      );
                    },
                  ),
                if (unfolded.contains(index)) const Divider(height: 10, thickness: 1)
              ],
            );
          },
        ),
      ],
    );
  }
}

class HotKeySettings extends StatefulWidget {
  final int hotkeyIndex;

  const HotKeySettings({
    Key? key,
    required this.hotkeyIndex,
  }) : super(key: key);
  @override
  HotKeySettingsState createState() => HotKeySettingsState();
}

class HotKeySettingsState extends State<HotKeySettings> {
  final List<Hotkeys> remap = Boxes.remap;
  final List<String> mouseButtons = <String>[];
  FocusNode focusNode = FocusNode();
  bool listeningToHotkey = false;
  late Hotkeys hotkey;
  @override
  void initState() {
    super.initState();
    hotkey = remap[widget.hotkeyIndex];
    bool mouseButton4 = true;
    bool mouseButton5 = true;
    for (Hotkeys hotkey in remap) {
      if (hotkey.key == "MouseButton4") mouseButton4 = false;
      if (hotkey.key == "MouseButton5") mouseButton5 = false;
    }
    if (mouseButton4) mouseButtons.add("MouseButton4");
    if (mouseButton5) mouseButtons.add("MouseButton5");
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Align(
          alignment: Alignment.topRight,
          child: InkWell(
            onTap: () {},
            child: const Icon(Icons.save),
          ),
        ),
        ListTile(
          title: Focus(
            focusNode: focusNode,
            onKey: (FocusNode e, RawKeyEvent k) {
              if (k.data.logicalKey.keyId < 256) {
                List<String> modifier = <String>[];
                if (k.isControlPressed) modifier.add("CTRL");
                if (k.isAltPressed) modifier.add("ALT");
                if (k.isShiftPressed) modifier.add("SHIFT");
                if (k.isMetaPressed) modifier.add("WIN");
                if (modifier.isNotEmpty) {
                  final String newKey = String.fromCharCode(k.data.logicalKey.keyId);
                  final List<String> x = remap.map((Hotkeys e) => e.hotkey).toList();
                  if (x.contains("${modifier.join('+')}+$newKey")) {
                    ScaffoldMessenger.of(context)
                        .showSnackBar(SnackBar(content: Text("Shortcut ${modifier.join('+')}+$newKey already exists! "), duration: const Duration(seconds: 2)));
                    return KeyEventResult.handled;
                  }
                  if (hotkey.key == "MouseButton4") mouseButtons.add("MouseButton4");
                  if (hotkey.key == "MouseButton5") mouseButtons.add("MouseButton5");
                  hotkey.modifiers = modifier;
                  hotkey.key = newKey;

                  FocusScope.of(context).unfocus();
                  listeningToHotkey = false;
                  setState(() {});
                }
              }
              return KeyEventResult.handled;
            },
            child: Text("Hotkey: ${hotkey.hotkey.toUpperCase()}"),
          ),
          onTap: () {
            listeningToHotkey = true;
            FocusScope.of(context).requestFocus(focusNode);
          },
          trailing: Text(listeningToHotkey ? "Press Hotkey" : "Change"),
        ),
        if (mouseButtons.isNotEmpty)
          Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: List<Widget>.generate(mouseButtons.length, (int index) {
              return Expanded(
                child: CheckBoxWidget(
                  key: UniqueKey(),
                  text: mouseButtons[index],
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  value: hotkey.key == mouseButtons[index],
                  onChanged: (bool? e) {
                    hotkey.modifiers.clear();
                    if (hotkey.key == "MouseButton4") mouseButtons.add("MouseButton4");
                    if (hotkey.key == "MouseButton5") mouseButtons.add("MouseButton5");
                    hotkey.key = mouseButtons[index];
                    mouseButtons.remove(mouseButtons[index]);
                    setState(() {});
                  },
                ),
              );
            }),
          ),
        const SizedBox(height: 20),
        const Divider(height: 10, thickness: 1),
        CheckBoxWidget(
          onChanged: (bool? e) => setState(() => hotkey.noopScreenBusy = !hotkey.noopScreenBusy),
          value: hotkey.noopScreenBusy,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
          text: "Do not execute when the screen is busy, like playing videogames",
        ),
        TextField(
          controller: TextEditingController(text: hotkey.prohibited.join(';')),
          decoration: const InputDecoration(labelText: "Do not execute when:"),
          onChanged: (String e) => setState(() => hotkey.prohibited = e.split(';').toList()),
        ),
        const SizedBox(height: 20),
        const Text("You can use class,exe,title to match a window"),
        const Text("Ex: class:.*?D3D.*?;exe:PUBG;title:D3D"),
        const Text("Will block this hotkey to execute when you play some games"),
      ],
    );
  }
}

class MouseInfoWidget extends StatefulWidget {
  final Function(AnchorType anchor) onAnchorTypeChanged;
  const MouseInfoWidget({
    Key? key,
    required this.onAnchorTypeChanged,
  }) : super(key: key);
  @override
  MouseInfoWidgetState createState() => MouseInfoWidgetState();
}

class MouseInfoWidgetState extends State<MouseInfoWidget> {
  Timer? timer;
  AnchorType anchor = AnchorType.topLeft;
  String mousePos = "";
  String windowExe = "";
  String windowTitle = "";
  String windowClass = "";
  String mouseAnchor = "";
  String mouseAnchorPercentage = "";
  bool tracking = true;
  int lastKey = 0;
  final Map<int, String> _cached = <int, String>{};

  bool trackingEnabled = false;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
      if (!trackingEnabled) return;
      final int state = GetKeyState(VK_MENU);
      if (state < 0) {
        if (lastKey != state) {
          lastKey = state;
          tracking = !tracking;
          setState(() {});
        }
      }
      if (!tracking) return;
      final Pointer<POINT> lpPoint = calloc<POINT>();
      GetCursorPos(lpPoint);
      mousePos = "X: ${lpPoint.ref.x} Y:${lpPoint.ref.y}";
      int hWnd = WindowFromPoint(lpPoint.ref);
      hWnd = GetAncestor(hWnd, 2);
      if (hWnd > 0) {
        if (!_cached.containsKey(hWnd)) {
          _cached[hWnd] = Win32.getExe(Win32.getWindowExePath(hWnd));
        }
        Pointer<RECT> lpRect = calloc<RECT>();
        GetWindowRect(hWnd, lpRect);
        windowExe = _cached[hWnd]!;
        windowTitle = Win32.getTitle(hWnd);
        windowClass = Win32.getClass(hWnd);
        int x = 0, y = 0;
        final int yTop = lpPoint.ref.y - lpRect.ref.top;
        final int yBottom = lpPoint.ref.y - lpRect.ref.bottom;
        final int xLeft = lpPoint.ref.x - lpRect.ref.left;
        final int xRight = lpPoint.ref.x - lpRect.ref.right;
        final int width = lpRect.ref.right - lpRect.ref.left;
        final int height = lpRect.ref.bottom - lpRect.ref.top;
        if (anchor == AnchorType.topLeft) {
          x = xLeft;
          y = yTop;
        } else if (anchor == AnchorType.topCenter) {
          x = xLeft - width ~/ 2;
          y = yTop;
        } else if (anchor == AnchorType.topRight) {
          x = xRight;
          y = yTop;
        } else if (anchor == AnchorType.centerLeft) {
          x = xLeft;
          y = yTop - height ~/ 2;
        } else if (anchor == AnchorType.center) {
          x = xLeft - width ~/ 2;
          y = yTop - height ~/ 2;
        } else if (anchor == AnchorType.centerRight) {
          x = xRight;
          y = yTop - height ~/ 2;
        } else if (anchor == AnchorType.bottomLeft) {
          x = xLeft;
          y = yBottom;
        } else if (anchor == AnchorType.bottomCenter) {
          x = xLeft - width ~/ 2;
          y = yBottom;
        } else if (anchor == AnchorType.bottomRight) {
          x = xRight;
          y = yBottom;
        }
        mouseAnchor = "X:$x Y:$y";
        final int percentageX = ((x / width) * 100).floor();
        final int percentageY = ((y / height) * 100).floor();
        mouseAnchorPercentage = "X:$percentageX Y:$percentageY";
        free(lpRect);
      }
      free(lpPoint);
      setState(() {});
    });
  }

  @override
  void dispose() {
    super.dispose();
    timer?.cancel();
  }

  // AnchorType anchor = AnchorType.bottomCenter;
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        CheckBoxWidget(
          onChanged: (bool e) => setState(() => trackingEnabled = !trackingEnabled),
          value: trackingEnabled,
          padding: const EdgeInsets.symmetric(vertical: 5),
          text: "Track Mouse Info. Press ALT to pause (${tracking && trackingEnabled ? "Tracking" : "Paused"})",
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            SizedBox(
              width: 100,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Tooltip(
                          message: AnchorType.topLeft.name.toString(),
                          child: Checkbox(value: anchor == AnchorType.topLeft, onChanged: (bool? e) => onAnchorChanged(AnchorType.topLeft))),
                      Tooltip(
                          message: AnchorType.topCenter.name.toString(),
                          child: Checkbox(value: anchor == AnchorType.topCenter, onChanged: (bool? e) => onAnchorChanged(AnchorType.topCenter))),
                      Tooltip(
                          message: AnchorType.topRight.name.toString(),
                          child: Checkbox(value: anchor == AnchorType.topRight, onChanged: (bool? e) => onAnchorChanged(AnchorType.topRight))),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Tooltip(
                          message: AnchorType.centerLeft.name.toString(),
                          child: Checkbox(value: anchor == AnchorType.centerLeft, onChanged: (bool? e) => onAnchorChanged(AnchorType.centerLeft))),
                      Tooltip(
                          message: AnchorType.center.name.toString(),
                          child: Checkbox(value: anchor == AnchorType.center, onChanged: (bool? e) => onAnchorChanged(AnchorType.center))),
                      Tooltip(
                          message: AnchorType.centerRight.name.toString(),
                          child: Checkbox(value: anchor == AnchorType.centerRight, onChanged: (bool? e) => onAnchorChanged(AnchorType.centerRight))),
                    ],
                  ),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Tooltip(
                          message: AnchorType.bottomLeft.name.toString(),
                          child: Checkbox(value: anchor == AnchorType.bottomLeft, onChanged: (bool? e) => onAnchorChanged(AnchorType.bottomLeft))),
                      Tooltip(
                          message: AnchorType.bottomCenter.name.toString(),
                          child: Checkbox(value: anchor == AnchorType.bottomCenter, onChanged: (bool? e) => onAnchorChanged(AnchorType.bottomCenter))),
                      Tooltip(
                          message: AnchorType.bottomRight.name.toString(),
                          child: Checkbox(value: anchor == AnchorType.bottomRight, onChanged: (bool? e) => onAnchorChanged(AnchorType.bottomRight))),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text("Mouse Position:"),
                  SelectableText(mousePos),
                  const Text("Position Anchored:"),
                  SelectableText(mouseAnchor),
                  const Text("As Percentage:"),
                  SelectableText(mouseAnchorPercentage),
                  const Text("Window exe:"),
                  SelectableText(windowExe, maxLines: null),
                  const Text("Window class:"),
                  SelectableText(windowClass, maxLines: null),
                  const Text("Window title:"),
                  SelectableText(windowTitle, maxLines: null),
                ],
              ),
            ),
          ],
        ),
        Markdown(
          shrinkWrap: true,
          selectable: true,
          data: '''
Info about sendKeys:

You can send multiple hotkeys or keystrokes.
Use # to hold a key and ^ to release.
All Special keys need to be put between {}.
To release all previous keys use {|}.

```{#CTRL}{#SHIFT}{ESCAPE}{|}{#SHIFT}{TAB}{^SHIFT}{RIGHT}```

Will open Task Manager And move to Performance Tab.

[Here you can find all special keys name](here)
''',
          onTapLink: (String e, String? e1, String e2) {
            WinUtils.open("https://github.com/Far-Se/tabame/blob/master/lib/models/keys.dart#L158");
          },
        )
      ],
    );
  }

  onAnchorChanged(AnchorType newAnchor) {
    anchor = newAnchor;
    widget.onAnchorTypeChanged(newAnchor);
    setState(() {});
  }
}

class HotKeyAction extends StatefulWidget {
  final KeyMap hotkey;
  final void Function(KeyMap hotkey) onSaved;
  const HotKeyAction({Key? key, required this.hotkey, required this.onSaved}) : super(key: key);
  @override
  HotKeyActionState createState() => HotKeyActionState();
}

class HotKeyActionState extends State<HotKeyAction> {
  FocusNode focusNode = FocusNode();
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
    focusNode.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                CheckBoxWidget(
                  onChanged: (bool e) => setState(() => widget.hotkey.enabled != widget.hotkey.enabled),
                  value: widget.hotkey.enabled,
                  text: "Enabled",
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                ),
                TextInput(labelText: "Name", value: widget.hotkey.name, onChanged: (String e) => setState(() => widget.hotkey.name = e)),
                CheckBoxWidget(
                  onChanged: (bool e) => setState(() => widget.hotkey.windowUnderMouse != widget.hotkey.windowUnderMouse),
                  value: widget.hotkey.windowUnderMouse,
                  text: "Activate window under mouse",
                  padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                ),
                DropdownButton<String>(
                  value: widget.hotkey.windowsInfo[0],
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_downward),
                  onChanged: (String? newValue) => setState(() => widget.hotkey.windowsInfo = <String>[newValue ?? "any", ""]),
                  items: HotKeyInfo.windowInfoNames.entries.map<DropdownMenuItem<String>>((MapEntry<String, String> value) {
                    return DropdownMenuItem<String>(value: value.key, child: Text(value.value), alignment: Alignment.center);
                  }).toList(),
                ),
                if (HotKeyInfo.windowInfo.indexOf(widget.hotkey.windowsInfo[0]) > 0)
                  TextField(
                    onChanged: (String e) => widget.hotkey.windowsInfo[1] = e,
                    controller: TextEditingController(text: widget.hotkey.windowsInfo[1]),
                    decoration: const InputDecoration(hintText: "Contains (regex aware)", labelText: "Contains (regex aware)"),
                  ),
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          CheckBoxWidget(
                              padding: const EdgeInsets.symmetric(horizontal: 0, vertical: 5),
                              onChanged: (bool e) => setState(() => widget.hotkey.boundToRegion = !widget.hotkey.boundToRegion),
                              value: widget.hotkey.boundToRegion,
                              text: "Bound to region"),
                          if (widget.hotkey.boundToRegion)
                            Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Padding(
                                  padding: const EdgeInsets.only(left: 5.0, right: 10),
                                  child: DropdownButton<String>(
                                    isExpanded: true,
                                    value: widget.hotkey.region.anchorType.name,
                                    icon: const Icon(Icons.arrow_downward),
                                    onChanged: (String? newValue) => setState(
                                        () => widget.hotkey.region.anchorType = AnchorType.values.where((AnchorType element) => element.name == newValue!).first),
                                    items: AnchorType.values.map<DropdownMenuItem<String>>((AnchorType value) {
                                      return DropdownMenuItem<String>(value: value.name, child: Text(value.name), alignment: Alignment.center);
                                    }).toList(),
                                  ),
                                ),
                                CheckBoxWidget(
                                    onChanged: (bool e) => setState(() => widget.hotkey.region.asPercentage = !widget.hotkey.region.asPercentage),
                                    value: widget.hotkey.region.asPercentage,
                                    text: "As percentage"),
                              ],
                            )
                        ],
                      ),
                    ),
                    if (widget.hotkey.boundToRegion)
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: TextInput(
                                      key: UniqueKey(),
                                      labelText: "min X",
                                      value: widget.hotkey.region.x1.toString(),
                                      onChanged: (String e) => e.isEmpty ? null : setState(() => widget.hotkey.region.x1 = int.tryParse(e) ?? 0)),
                                ),
                                Expanded(
                                  child: TextInput(
                                      key: UniqueKey(),
                                      labelText: "min Y",
                                      value: widget.hotkey.region.y1.toString(),
                                      onChanged: (String e) => e.isEmpty ? null : setState(() => widget.hotkey.region.y1 = int.tryParse(e) ?? 0)),
                                ),
                              ],
                            ),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: <Widget>[
                                Expanded(
                                  child: TextInput(
                                      key: UniqueKey(),
                                      labelText: "max X",
                                      value: widget.hotkey.region.x2.toString(),
                                      onChanged: (String e) => e.isEmpty ? null : setState(() => widget.hotkey.region.x2 = int.tryParse(e) ?? 0)),
                                ),
                                Expanded(
                                  child: TextInput(
                                      key: UniqueKey(),
                                      labelText: "max Y",
                                      value: widget.hotkey.region.y2.toString(),
                                      onChanged: (String e) => e.isEmpty ? null : setState(() => widget.hotkey.region.y2 = int.tryParse(e) ?? 0)),
                                ),
                              ],
                            )
                          ],
                        ),
                      ),
                  ],
                ),
                const Divider(height: 5, thickness: 1),
                const Text("Trigger:"),
                DropdownButton<String>(
                  value: HotKeyInfo.triggers[widget.hotkey.triggerType.index],
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_downward),
                  onChanged: (String? newValue) => setState(() => widget.hotkey.triggerType = TriggerType.values[HotKeyInfo.triggers.indexOf(newValue ?? "Press")]),
                  items: HotKeyInfo.triggers.map<DropdownMenuItem<String>>((String value) {
                    return DropdownMenuItem<String>(value: value, child: Text(value), alignment: Alignment.center);
                  }).toList(),
                ),
                if (widget.hotkey.triggerType == TriggerType.duration)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        child: TextInput(labelText: "Min (miliseconds)", onChanged: (String e) => setState(() => widget.hotkey.triggerInfo[0] = int.tryParse(e) ?? 0)),
                      ),
                      Expanded(
                        child: TextInput(labelText: "Max (miliseconds)", onChanged: (String e) => setState(() => widget.hotkey.triggerInfo[1] = int.tryParse(e) ?? 0)),
                      ),
                    ],
                  ),
                if (widget.hotkey.triggerType == TriggerType.movement)
                  Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      DropdownButton<String>(
                        value: HotKeyInfo.mouseDirections[widget.hotkey.triggerInfo[0]],
                        isExpanded: true,
                        icon: const Icon(Icons.arrow_downward),
                        onChanged: (String? newValue) => setState(() => widget.hotkey.triggerInfo[0] = HotKeyInfo.mouseDirections.indexOf(newValue ?? "Right")),
                        items: HotKeyInfo.mouseDirections.map<DropdownMenuItem<String>>((String value) {
                          return DropdownMenuItem<String>(value: value, child: Text(value), alignment: Alignment.center);
                        }).toList(),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Expanded(
                            child: TextInput(labelText: "Min (in pixels)", onChanged: (String e) => setState(() => widget.hotkey.triggerInfo[1] = int.tryParse(e) ?? 0)),
                          ),
                          Expanded(
                            child: TextInput(labelText: "Max (in pixels)", onChanged: (String e) => setState(() => widget.hotkey.triggerInfo[2] = int.tryParse(e) ?? 0)),
                          ),
                        ],
                      ),
                    ],
                  ),
                const Text("Execute if variable equals:"),
                Focus(
                  onFocusChange: (bool e) {
                    if (!e) setState(() {});
                  },
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: <Widget>[
                      IgnorePointer(child: Checkbox(value: widget.hotkey.variableCheck[0].isNotEmpty, onChanged: (bool? e) {})),
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: widget.hotkey.variableCheck[0]),
                          decoration: const InputDecoration(hintText: "Var Name", labelText: "Var Name"),
                          onChanged: (String e) => widget.hotkey.variableCheck[0] = e,
                        ),
                      ),
                      Expanded(
                        child: TextField(
                          controller: TextEditingController(text: widget.hotkey.variableCheck[1]),
                          decoration: const InputDecoration(hintText: "Var Value", labelText: "Var Value"),
                          onChanged: (String e) => widget.hotkey.variableCheck[1] = e,
                        ),
                      )
                    ],
                  ),
                ),
                const SizedBox(height: 15),
                ListTile(
                  leading: const Icon(Icons.add),
                  title: Text("Actions", style: Theme.of(context).textTheme.headline6),
                  onTap: () {
                    widget.hotkey.actions.add(KeyAction(type: ActionType.sendKeys, value: "ALT+SHIFT+F"));
                    setState(() {});
                  },
                ),
                //#e

                //#h yellow
                ...List<Widget>.generate(
                  widget.hotkey.actions.length,
                  (int index) {
                    final KeyAction action = widget.hotkey.actions[index];
                    final Widget selectAction = Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: <Widget>[
                        SizedBox(
                          width: 40,
                          child: Padding(
                            padding: const EdgeInsets.only(right: 5.0),
                            child: InkWell(
                                onTap: () {
                                  widget.hotkey.actions.removeAt(index);
                                  setState(() {});
                                },
                                child: const Icon(Icons.delete)),
                          ),
                        ),
                        Expanded(
                          child: DropdownButton<String>(
                            value: action.type.index.toString(),
                            isExpanded: true,
                            icon: const Icon(Icons.arrow_downward),
                            onChanged: (String? newValue) => setState(() {
                              action.type = ActionType.values[int.tryParse(newValue ?? "0") ?? 0];
                              if (action.type == ActionType.sendClick) {
                                action.value = ClickAction(anchorType: AnchorType.topLeft, currentWindow: true, percentage: true, x: 50, y: 50).toJson();
                              } else if (action.type == ActionType.setVar) {
                                action.value = jsonEncode(<String>["var", "value"]);
                              } else if (action.type == ActionType.hotkey) {
                                action.value = "ALT+F";
                              } else if (action.type == ActionType.sendKeys) {
                                action.value = "{#CTRL}A{^CTRL}{DELETE}deleted";
                              } else if (action.type == ActionType.tabameFunction) {
                                action.value = "0";
                              }
                            }),
                            items: ActionType.values.map<DropdownMenuItem<String>>((ActionType value) {
                              return DropdownMenuItem<String>(value: value.index.toString(), child: Text(value.name), alignment: Alignment.center);
                            }).toList(),
                          ),
                        ),
                      ],
                    );

                    if (action.type == ActionType.sendClick) {
                      late ClickAction clickAction;
                      if (action.value.isNotEmpty) {
                        clickAction = ClickAction.fromJson(action.value);
                      } else {
                        clickAction = ClickAction(anchorType: AnchorType.topLeft, currentWindow: true, percentage: true, x: 50, y: 50);
                      }
                      action.value = clickAction.toJson();
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          selectAction,
                          DropdownButton<String>(
                            isExpanded: true,
                            value: clickAction.anchorType.name,
                            icon: const Icon(Icons.arrow_downward),
                            onChanged: (String? newValue) {
                              clickAction.anchorType = AnchorType.values.where((AnchorType element) => element.name == newValue!).first;
                              action.value = clickAction.toJson();

                              setState(() {});
                            },
                            items: AnchorType.values.map<DropdownMenuItem<String>>((AnchorType value) {
                              return DropdownMenuItem<String>(value: value.name, child: Text(value.name), alignment: Alignment.center);
                            }).toList(),
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                child: CheckBoxWidget(
                                  value: clickAction.currentWindow,
                                  text: 'On Active Window',
                                  onChanged: (bool? e) {
                                    clickAction.currentWindow = !clickAction.currentWindow;
                                    action.value = clickAction.toJson();
                                    setState(() {});
                                  },
                                ),
                              ),
                              Expanded(
                                child: CheckBoxWidget(
                                  value: clickAction.percentage,
                                  text: 'As percentage',
                                  onChanged: (bool? e) {
                                    clickAction.percentage = !clickAction.percentage;
                                    action.value = clickAction.toJson();
                                    setState(() {});
                                  },
                                ),
                              )
                            ],
                          ),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.start,
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              Expanded(
                                  child: TextField(
                                controller: TextEditingController(text: clickAction.x.toString()),
                                decoration: const InputDecoration(labelText: "X:"),
                                onChanged: (String e) {
                                  clickAction.x = int.tryParse(e) ?? 0;
                                  action.value = clickAction.toJson();
                                },
                              )),
                              Expanded(
                                child: TextField(
                                  controller: TextEditingController(text: clickAction.y.toString()),
                                  decoration: const InputDecoration(labelText: "Y:"),
                                  onChanged: (String e) {
                                    clickAction.y = int.tryParse(e) ?? 0;
                                    action.value = clickAction.toJson();
                                  },
                                ),
                              )
                            ],
                          ),
                        ],
                      );
                    }
                    if (action.type == ActionType.setVar) {
                      final List<String> varInfo = jsonDecode(action.value);
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          selectAction,
                          Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: <Widget>[
                              Expanded(
                                child: TextField(
                                  controller: TextEditingController(text: varInfo[0]),
                                  decoration: const InputDecoration(hintText: "Var Name", labelText: "Var Name"),
                                  onChanged: (String e) {
                                    varInfo[0] = e;
                                    action.value = jsonEncode(varInfo);
                                  },
                                ),
                              ),
                              Expanded(
                                child: TextField(
                                  controller: TextEditingController(text: varInfo[1]),
                                  decoration: const InputDecoration(hintText: "Var Value", labelText: "Var Value"),
                                  onChanged: (String e) {
                                    varInfo[1] = e;
                                    action.value = jsonEncode(varInfo);
                                  },
                                ),
                              )
                            ],
                          )
                        ],
                      );
                    }
                    if (action.type == ActionType.hotkey) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          selectAction,
                          ListTile(
                            title: Focus(
                              focusNode: focusNode,
                              onKey: (FocusNode e, RawKeyEvent k) {
                                if (k.data.logicalKey.keyId < 256) {
                                  List<String> modifier = <String>[];
                                  if (k.isControlPressed) modifier.add("CTRL");
                                  if (k.isAltPressed) modifier.add("ALT");
                                  if (k.isShiftPressed) modifier.add("SHIFT");
                                  if (k.isMetaPressed) modifier.add("WIN");
                                  if (modifier.isNotEmpty) {
                                    final String newKey = String.fromCharCode(k.data.logicalKey.keyId);
                                    action.value = "${modifier.join("+")}+$newKey";
                                    FocusScope.of(context).unfocus();
                                    setState(() {});
                                  }
                                }
                                return KeyEventResult.handled;
                              },
                              child: Text("Hotkey: ${action.value.toUpperCase()}"),
                            ),
                            onTap: () {
                              FocusScope.of(context).requestFocus(focusNode);
                            },
                            trailing: const Text("Change"),
                          ),
                        ],
                      );
                    }
                    if (action.type == ActionType.sendKeys) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          selectAction,
                          TextField(
                            controller: TextEditingController(text: action.value),
                            decoration: const InputDecoration(labelText: "Send there keys:"),
                            onChanged: (String e) {
                              action.value = e;
                            },
                          ),
                        ],
                      );
                    }
                    if (action.type == ActionType.tabameFunction) {
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          selectAction,
                          DropdownButton<String>(
                            isExpanded: true,
                            value: HotKeyInfo.tabameFunctions[int.tryParse(action.value) ?? 1],
                            icon: const Icon(Icons.arrow_downward),
                            onChanged: (String? newValue) {
                              action.value = HotKeyInfo.tabameFunctions.indexOf(newValue!).toString();
                              setState(() {});
                            },
                            items: HotKeyInfo.tabameFunctions
                                .map<DropdownMenuItem<String>>((String value) => DropdownMenuItem<String>(value: value, child: Text(value), alignment: Alignment.center))
                                .toList(),
                          ),
                          const Divider(height: 10, thickness: 2),
                        ],
                      );
                    }
                    return selectAction;
                  },
                ),
              ],
            ),
          ),
        ),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Align(
                alignment: Alignment.topRight,
                child: ElevatedButton(
                  onPressed: () {},
                  child: Container(
                    width: 70,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const Icon(Icons.save),
                        const Text("Save"),
                      ],
                    ),
                  ),
                ),
              ),
              MouseInfoWidget(
                onAnchorTypeChanged: (AnchorType anchor) {
                  setState(() {});
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
