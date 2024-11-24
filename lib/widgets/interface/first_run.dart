import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../main.dart';
import '../../models/classes/boxes.dart';
import '../../models/classes/hotkeys.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/main_hotkey.dart';
import '../../models/win32/win32.dart';
import '../widgets/info_widget.dart';

class FirstRun extends StatefulWidget {
  const FirstRun({super.key});
  @override
  FirstRunState createState() => FirstRunState();
}

class FirstRunState extends State<FirstRun> {
  FocusNode focusNode = FocusNode();
  final WizardlyContextMenu wizardlyContextMenu = WizardlyContextMenu();
  final PageController pageController = PageController();
  final List<Hotkeys> hokeyObj = <Hotkeys>[];

  List<String> modifiers = <String>[];
  String hotkey = "";
  bool listeningToHotkey = false;
  String data2 = """
## **The hotkey will work after you finish Setup process.**
### Info:
- If your mouse has side buttons, you can pick between **MouseButton4** and **MouseButton5**.
- If your mouse has more buttons than the standard ones, you can open your mouse's App and set it to a more obscure hotkey like **CTRL+ALT+SHIFT+F9** then press that button above.
- If you do not have any extra buttons, bind to something simple like **WIN+SHIFT+A**, it's easy for the fingers.
- You can NOT bind it to WIN + one button like WIN+Z
## Button functions:
- Normal press will open QuickMenu
- Holding the button will open Start
- Double press will focus previous active window
- Holding and moving the mouse up and down will change volume
- Pressing and moving mouse left or right will switch Virtual Desktop
- Normal press in bottom left corner will open Start, holding will open Win+X menu
- Normal press in bottom screen will toggle Taskbar
- Normal press in bottom right corner will toggle Desktop
- On Chrome/Firefox, on tab bar:
    - hold it to open a new tab
    - press to close hovered tab

## You can change and add new hotkeys or functions after this
""";

  final List<String> mouseButtons = <String>["MouseButton4", "MouseButton5"];
  @override
  void initState() {
    super.initState();
    for (Map<String, dynamic> x in mainHotkeyData) {
      hokeyObj.add(Hotkeys.fromMap(x));
    }
    WinUtils.setStartUpShortcut(true);
    // Future<void>.delayed(const Duration(seconds: 1), () => downloadTabame());
  }

  @override
  void dispose() {
    focusNode.dispose();
    pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(child: Text("First Run settings", style: Theme.of(context).textTheme.headlineSmall?.copyWith(height: 2))),
          LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
            return ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth, maxHeight: 960),
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
                            Text("Before anything, you need to set the main hotkey:", style: Theme.of(context).textTheme.labelLarge?.copyWith(height: 2)),
                            if (hotkey.isNotEmpty)
                              InkWell(
                                onTap: () async {
                                  if (kReleaseMode) {
                                    hokeyObj.first.key = hotkey;
                                    hokeyObj.first.modifiers = modifiers;
                                    Boxes.updateSettings("remap", jsonEncode(hokeyObj)); //!uncomment this.
                                  }
                                  Boxes.updateSettings("justInstalled", true);
                                  Boxes.pref.setInt("installDate", DateTime.now().millisecondsSinceEpoch);
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
                            onKeyEvent: (FocusNode e, KeyEvent k) {
                              List<String> modifier = <String>[];
                              if (HardwareKeyboard.instance.isControlPressed) modifier.add("CTRL");
                              if (HardwareKeyboard.instance.isAltPressed) modifier.add("ALT");
                              if (HardwareKeyboard.instance.isShiftPressed) modifier.add("SHIFT");
                              if (HardwareKeyboard.instance.isMetaPressed) modifier.add("WIN");
                              if (modifiers.isEmpty) return KeyEventResult.handled;
                              if (k.logicalKey.synonyms.isNotEmpty) return KeyEventResult.handled;
                              if (HardwareKeyboard.instance.isMetaPressed && modifier.length == 1) return KeyEventResult.handled;
                              if (hotkey == "MouseButton4") mouseButtons.add("MouseButton4");
                              if (hotkey == "MouseButton5") mouseButtons.add("MouseButton5");

                              hotkey = k.logicalKey.keyLabel;
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
                        Markdown(shrinkWrap: true, selectable: true, data: data2),
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
                            await WinUtils.setStartUpShortcut(true);
                          } else {
                            await WinUtils.setStartUpShortcut(false);
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
                          globalSettings.runAsAdministrator = newValue;
                          await Boxes.updateSettings("runAsAdministrator", newValue);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      const Divider(height: 20, thickness: 1),
                      Row(
                        children: <Widget>[
                          Expanded(
                            flex: 2,
                            child: CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text("Auto Update"),
                              value: globalSettings.autoUpdate,
                              onChanged: (bool? newValue) async {
                                globalSettings.autoUpdate = newValue ?? true;
                                Boxes.updateSettings("autoUpdate", globalSettings.autoUpdate);
                                if (!mounted) return;
                                setState(() {});
                              },
                            ),
                          ),
                          const Expanded(
                            flex: 4,
                            child: Padding(
                              padding: EdgeInsets.all(15.0),
                              child: Text("Auto update when there is a version so you do not have to manually install it."),
                            ),
                          )
                        ],
                      ),
                      const Divider(height: 20, thickness: 1),
                      Row(
                        children: <Widget>[
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
                        children: <Widget>[
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
                        children: <Widget>[
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

You can rename files using regex and lists, you can turn **IMG_20220725_121728.jpg** into **25 July 2022.jpg** easily.

You can also scan folder sizes and delete files that are too big."""),
                          )
                        ],
                      ),
                      Center(child: Text("Thanks for using Tabame", style: Theme.of(context).textTheme.headlineSmall?.copyWith(height: 2))),
                      const SizedBox(height: 10),
                      Center(
                          child: Text("After restarting I recommend to open settings and browse through all sidebar tabs",
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 17, height: 2))),
                      Center(
                          child: Text("Tabame has way more customizable features than the ones listed above!",
                              style: Theme.of(context).textTheme.bodyLarge?.copyWith(fontSize: 17, height: 2))),
                      const SizedBox(height: 10),
                      InkWell(
                        onTap: () async {
                          //!Save and exit
                          if (kReleaseMode) {
                            WinUtils.reloadTabameQuickMenu();
                            Future<void>.delayed(const Duration(milliseconds: 200), () => exit(0));
                          } else {
                            Globals.changingPages = true;
                            setState(() {});
                            mainPageViewController.jumpToPage(Pages.quickmenu.index);
                          }
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
                              "Save and Restart Application",
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

  void downloadTabame() async {
    final http.Response response = await http.get(Uri.parse("https://api.github.com/repos/far-se/tabame/releases"));
    if (response.statusCode != 200) return;
    final List<dynamic> json = jsonDecode(response.body);
    if (json.isEmpty) return;
    final Map<String, dynamic> lastVersion = json[0];
    String downloadLink = "";
    for (Map<String, dynamic> x in lastVersion["assets"]) {
      if (!x["name"].endsWith("zip")) continue;
      if (x.containsKey("browser_download_url")) {
        downloadLink = x["browser_download_url"];
        break;
      }
    }
    final String fileName = "${WinUtils.getTempFolder()}\\tabame_${lastVersion["tag_name"]}.zip";
    await WinUtils.downloadFile(downloadLink, fileName, () {
      final String dir = "${WinUtils.getTabameSettingsFolder()}";
      WinUtils.runPowerShell(<String>[
        'Expand-Archive -LiteralPath "$fileName" -DestinationPath "$dir" -Force;',
        'Remove-Item -LiteralPath "$fileName" -Force;',
      ]);
    });
  }
}
