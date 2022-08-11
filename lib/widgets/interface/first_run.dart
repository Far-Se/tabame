// ignore_for_file: always_specify_types

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/hotkeys.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../widgets/info_widget.dart';

class FirstRun extends StatefulWidget {
  const FirstRun({Key? key}) : super(key: key);
  @override
  FirstRunState createState() => FirstRunState();
}

class FirstRunState extends State<FirstRun> {
  FocusNode focusNode = FocusNode();
  final WizardlyContextMenu wizardlyContextMenu = WizardlyContextMenu();
  final PageController pageController = PageController();
  List<Map<String, dynamic>> hotkeyMap = <Map<String, dynamic>>[
    {
      "key": "F9",
      "modifiers": ["CTRL", "ALT"],
      "keymaps": [
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Show Start Menu Rightclick menu",
          "windowsInfo": ["any", ""],
          "boundToRegion": true,
          "region": {"x1": 0, "y1": 0, "x2": 50, "y2": 50, "asPercentage": false, "anchorType": 2},
          "triggerType": 3,
          "triggerInfo": [200, 700, 0],
          "actions": [
            {"type": 0, "value": "{#WIN}X"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": true,
          "name": "Browser Open Tab",
          "windowsInfo": ["exe", "(chrome|firefox)"],
          "boundToRegion": true,
          "region": {"x1": 0, "y1": 0, "x2": 100, "y2": 6, "asPercentage": true, "anchorType": 0},
          "triggerType": 3,
          "triggerInfo": [200, 1000, 0],
          "actions": [
            {"type": 0, "value": "{#CTRL}t"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": true,
          "name": "Browser Close Tab",
          "windowsInfo": ["title", "(chrome|firefox)"],
          "boundToRegion": true,
          "region": {"x1": 0, "y1": 0, "x2": 99, "y2": 6, "asPercentage": true, "anchorType": 0},
          "triggerType": 0,
          "triggerInfo": [0, 0, 0],
          "actions": [
            {"type": 0, "value": "{MMB}"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Show Desktop",
          "windowsInfo": ["any", ""],
          "boundToRegion": true,
          "region": {"x1": 0, "y1": 0, "x2": 50, "y2": 50, "asPercentage": false, "anchorType": 3},
          "triggerType": 0,
          "triggerInfo": [0, 0, 0],
          "actions": [
            {"type": 0, "value": "{#WIN}D"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Show StartMenu",
          "windowsInfo": ["any", ""],
          "boundToRegion": true,
          "region": {"x1": 0, "y1": 0, "x2": 57, "y2": 57, "asPercentage": false, "anchorType": 2},
          "triggerType": 0,
          "triggerInfo": [0, 0, 0],
          "actions": [
            {"type": 0, "value": "{WIN}"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Toggle Taskbar",
          "windowsInfo": ["any", ""],
          "boundToRegion": true,
          "region": {"x1": 3, "y1": 0, "x2": 100, "y2": 5, "asPercentage": true, "anchorType": 2},
          "triggerType": 0,
          "triggerInfo": [0, 0, 0],
          "actions": [
            {"type": 2, "value": "ToggleTaskbar"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Move Desktop to Left",
          "windowsInfo": ["any", ""],
          "boundToRegion": false,
          "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
          "triggerType": 2,
          "triggerInfo": [0, 400, 9999],
          "actions": [
            {"type": 2, "value": "SwitchDesktopToLeft"},
            {"type": 3, "value": "[\"desktop\",\"Left\"]"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Move Desktop To Right",
          "windowsInfo": ["any", ""],
          "boundToRegion": false,
          "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
          "triggerType": 2,
          "triggerInfo": [1, 400, 9999],
          "actions": [
            {"type": 2, "value": "SwitchDesktopToRight"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Volume Down",
          "windowsInfo": ["any", ""],
          "boundToRegion": false,
          "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
          "triggerType": 2,
          "triggerInfo": [3, 30, -1],
          "actions": [
            {"type": 0, "value": "{VOLUME_DOWN}"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Volume Up",
          "windowsInfo": ["any", ""],
          "boundToRegion": false,
          "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
          "triggerType": 2,
          "triggerInfo": [2, 30, -1],
          "actions": [
            {"type": 0, "value": "{VOLUME_UP}"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Show Last Active Window",
          "windowsInfo": ["any", ""],
          "boundToRegion": false,
          "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
          "triggerType": 1,
          "triggerInfo": [0, 0, 0],
          "actions": [
            {"type": 2, "value": "ShowLastActiveWindow"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Show StartMenu Hold",
          "windowsInfo": ["any", ""],
          "boundToRegion": false,
          "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
          "triggerType": 3,
          "triggerInfo": [200, 500, 0],
          "actions": [
            {"type": 0, "value": "{WIN}"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Open Tabame",
          "windowsInfo": ["any", ""],
          "boundToRegion": false,
          "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
          "triggerType": 0,
          "triggerInfo": [0, 0, -1],
          "actions": [
            {"type": 2, "value": "ToggleQuickMenu"}
          ],
          "variableCheck": ["", ""]
        }
      ],
      "prohibited": [""],
      "noopScreenBusy": false
    },
    {
      "key": "A",
      "modifiers": ["CTRL", "ALT", "SHIFT"],
      "keymaps": [
        {
          "enabled": true,
          "windowUnderMouse": false,
          "name": "Open Audio Box",
          "windowsInfo": ["any", ""],
          "boundToRegion": false,
          "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
          "triggerType": 3,
          "triggerInfo": [0, 0, 0],
          "actions": [
            {"type": 2, "value": "ToggleTaskbar"}
          ],
          "variableCheck": ["", ""]
        },
        {
          "enabled": true,
          "windowUnderMouse": true,
          "name": "Switch Audio Output",
          "windowsInfo": ["any", ""],
          "boundToRegion": false,
          "region": {"x1": 0, "y1": 0, "x2": 0, "y2": 0, "asPercentage": false, "anchorType": 0},
          "triggerType": 0,
          "triggerInfo": [0, 0, 0],
          "actions": [
            {"type": 2, "value": "SwitchAudioOutput"}
          ],
          "variableCheck": ["", ""]
        }
      ],
      "prohibited": [],
      "noopScreenBusy": false
    }
  ];
  List<String> modifiers = <String>[];
  String hotkey = "";
  bool listeningToHotkey = false;
  String data2 = """
### Info:
If your mouse has more buttons than the standard ones, you can open your mouse's App and set it to a more obscure hotkey like **CTRL+ALT+SHIFT+F9** then press that button above.

If your mouse has side buttons, you can pick between MouseButton4 and MouseButton5.
## Button functions:
- Normal press will open QuickMenu
- Holding the button will open Start
- Double press will focus previous active window
- Holding and moving the mouse up and down will change volume
- Pressing and moving mouse left or right will switch Virtual Desktop
- Normal press in bottom left corner will open Start, holding will open Win+X menu
- Normal press in screen bottom will toggle Taskbar
- Normal press in bottom right corner will toggle Desktop
- On Chrome/Firefox, on tab bar:
    - hold it to open a new tab
    - press to close hovered tab

## You can change and add new hotkeys or functions after this.
""";

  final List<String> mouseButtons = <String>["MouseButton4", "MouseButton5"];
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    focusNode.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final List<Hotkeys> m = Boxes.remap;
    // print(m.first.toJson());

    Clipboard.setData(ClipboardData(text: m.firstWhere((element) => element.key == "A").toJson()));
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text("First Run settings", style: Theme.of(context).textTheme.headline5?.copyWith(height: 2)),
          LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: MediaQuery.of(context).size.height + 50),
              child: PageView(
                controller: pageController,
                allowImplicitScrolling: false,
                physics: const NeverScrollableScrollPhysics(),
                children: <Widget>[
                  SingleChildScrollView(
                    controller: ScrollController(),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            Text("Before anything, you need to set the main hotkey:", style: Theme.of(context).textTheme.button?.copyWith(height: 2)),
                            if (hotkey.isNotEmpty)
                              InkWell(
                                onTap: () {
                                  hotkeyMap.first["key"] = hotkey;
                                  hotkeyMap.first["modifiers"] = modifiers;
                                  // Boxes.updateSettings("remap", jsonEncode(hotkeyMap)); //!uncomment this.
                                  pageController.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeIn);
                                },
                                child: Container(
                                  height: 26,
                                  width: 100,
                                  padding: const EdgeInsets.symmetric(vertical: 5),
                                  decoration: BoxDecoration(
                                    color: const Color(0xffCE3F00).withOpacity(0.5),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: const Center(
                                    child: Text(
                                      "Continue",
                                      style: TextStyle(
                                        color: Colors.white,
                                        height: 1.001,
                                        fontSize: 14,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ),
                              )
                          ],
                        ),
                        ListTile(
                          title: Focus(
                            focusNode: focusNode,
                            onKey: (FocusNode e, RawKeyEvent k) {
                              List<String> modifier = <String>[];
                              if (k.isControlPressed) modifier.add("CTRL");
                              if (k.isAltPressed) modifier.add("ALT");
                              if (k.isShiftPressed) modifier.add("SHIFT");
                              if (k.isMetaPressed) modifier.add("WIN");
                              if (k.data.modifiersPressed.isEmpty) return KeyEventResult.handled;
                              if (k.data.logicalKey.synonyms.isNotEmpty) return KeyEventResult.handled;
                              if (hotkey == "MouseButton4") mouseButtons.add("MouseButton4");
                              if (hotkey == "MouseButton5") mouseButtons.add("MouseButton5");
                              hotkey = k.data.logicalKey.keyLabel;
                              modifiers = modifier;

                              FocusScope.of(context).unfocus();
                              listeningToHotkey = false;
                              setState(() {});
                              return KeyEventResult.handled;
                            },
                            child: Text("Hotkey: ${hotkey.isEmpty ? "Press here to set hotkey" : "${modifiers.isEmpty ? "" : "${modifiers.join("+")}+"}$hotkey"}"),
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
                                child: CheckboxListTile(
                                  key: UniqueKey(),
                                  title: Text(mouseButtons[index]),
                                  controlAffinity: ListTileControlAffinity.leading,
                                  value: hotkey == mouseButtons[index],
                                  onChanged: (bool? e) {
                                    modifiers.clear();
                                    if (hotkey == "MouseButton4") mouseButtons.add("MouseButton4");
                                    if (hotkey == "MouseButton5") mouseButtons.add("MouseButton5");
                                    hotkey = mouseButtons[index];
                                    mouseButtons.remove(mouseButtons[index]);
                                    setState(() {});
                                  },
                                ),
                              );
                            }),
                          ),
                        const SizedBox(height: 5),
                        Markdown(
                          shrinkWrap: true,
                          selectable: true,
                          data: data2,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.start,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Run on Startup"),
                        value: WinUtils.checkIfRegisterAsStartup(),
                        onChanged: (bool? newValue) async {
                          if (newValue == true) {
                            await setStartOnSystemStartup(true);
                          } else {
                            await setStartOnSystemStartup(false);
                          }
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      const Markdown(shrinkWrap: true, data: """
## For this app to function as intended it needs Administrator Privileges.

For example you can not focus or close a window that has Administrator Privileges.

Hotkeys will not function when focused window has Administrator Privileges.

You can run this without Administrator Privileges, but you will encounter issues.

So it's recommended to enable checkbox below:
"""),
                      CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Run as Administrator"),
                        value: globalSettings.runAsAdministrator,
                        onChanged: (bool? newValue) async {
                          newValue ??= false;
                          await setStartOnSystemStartup(false);
                          if (newValue == true) {
                            await setStartOnSystemStartup(true, args: "-strudel");
                          } else {
                            await setStartOnSystemStartup(true);
                          }
                          globalSettings.runAsAdministrator = newValue;
                          await Boxes.updateSettings("runAsAdministrator", newValue);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      const Divider(height: 20, thickness: 1),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text("Hide Taskbar on Startup"),
                              value: globalSettings.hideTaskbarOnStartup,
                              onChanged: (bool? newValue) async {
                                globalSettings.hideTaskbarOnStartup = newValue ?? true;
                                Boxes.updateSettings("hideTaskbarOnStartup", globalSettings.hideTaskbarOnStartup);
                                if (!mounted) return;
                                setState(() {});
                              },
                            ),
                          ),
                          const Expanded(
                            flex: 4,
                            child: Padding(
                              padding: EdgeInsets.all(15.0),
                              child: Text("QuickMenu does everything Taskbar does and it's less distracting, you can disable taskbar on startup:"),
                            ),
                          )
                        ],
                      ),
                      const Divider(height: 5, thickness: 1),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: CheckboxListTile(
                              onChanged: (bool? e) => setState(() {
                                globalSettings.trktivityEnabled = !globalSettings.trktivityEnabled;
                                Boxes.updateSettings("trktivityEnabled", globalSettings.trktivityEnabled);
                                enableTrcktivity(globalSettings.trktivityEnabled);
                              }),
                              controlAffinity: ListTileControlAffinity.leading,
                              value: globalSettings.trktivityEnabled,
                              title: const Text(
                                "Enable Trktivity",
                              ),
                              secondary: InfoWidget("Press to open folder with saved data", onTap: () {
                                WinUtils.open("${WinUtils.getTabameSettingsFolder()}\\trktivity");
                              }),
                            ),
                          ),
                          const Expanded(
                              flex: 4,
                              child: Padding(
                                padding: EdgeInsets.all(15.0),
                                child: Text("Trktivity is a utility that tracks your activity, such as key strokes, mouse pings and active window and title."
                                    " All collected data is stored locally and it's not sent anywhere."),
                              ))
                        ],
                      ),
                      const Divider(height: 5, thickness: 1),
                      Row(
                        children: [
                          Expanded(
                            flex: 2,
                            child: CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text("Add Wizardly in Folder Context Menu"),
                              value: wizardlyContextMenu.isWizardlyInstalledInContextMenu(),
                              onChanged: (bool? newValue) async {
                                wizardlyContextMenu.toggleWizardlyToContextMenu();
                                if (!mounted) return;
                                setState(() {});
                              },
                            ),
                          ),
                          const Expanded(
                            flex: 4,
                            child: Markdown(shrinkWrap: true, data: """
Wizardly is a set of tools that can be helpful. 

You can search text (regex aware) in files, including or excluding files and folders.

You can generate a Project Overview to count lines of code and group them by type.

You can rename files using regex and lists, you can turn **IMG_20220725_121728.jpg** into **25 July 2022** easily.

You can also scan folder sizes and delete files that are too big."""),
                          )
                        ],
                      ),
                      InkWell(
                        onTap: () {
                          //!Save and exit
                        },
                        child: Container(
                          height: 40,
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 5),
                          decoration: BoxDecoration(
                            color: const Color(0xffCE3F00).withOpacity(0.5),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Center(
                            child: Text(
                              "Save and Restart",
                              style: TextStyle(
                                color: Colors.white,
                                height: 1.001,
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ),
                      )
                    ],
                  )
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
