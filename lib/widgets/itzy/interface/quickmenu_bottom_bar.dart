import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/tray_watcher.dart';
import '../../../models/utils.dart';
import '../../../models/win32/win32.dart';

class QuickmenuBottomBar extends StatefulWidget {
  const QuickmenuBottomBar({Key? key}) : super(key: key);

  @override
  QuickmenuBottomBarState createState() => QuickmenuBottomBarState();
}

class QuickmenuBottomBarState extends State<QuickmenuBottomBar> {
  List<PowerShellScript> powerShellScripts = Boxes().getPowerShellScripts();
  final List<TextEditingController> powerShellNameController = <TextEditingController>[];
  @override
  void initState() {
    super.initState();

    for (final PowerShellScript item in powerShellScripts) {
      powerShellNameController.add(TextEditingController(text: item.name));
    }
  }

  @override
  void dispose() {
    for (TextEditingController item in powerShellNameController) {
      item.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      TooltipTheme(
        data: Theme.of(context).tooltipTheme.copyWith(
                decoration: BoxDecoration(
              border: Border.all(color: Colors.white38),
              color: Theme.of(context).backgroundColor,
            )),
        child: ListTileTheme(
          data: Theme.of(context).listTileTheme.copyWith(
                dense: true,
                style: ListTileStyle.drawer,
                contentPadding: const EdgeInsets.symmetric(horizontal: 10),
                minVerticalPadding: 0,
                visualDensity: VisualDensity.compact,
                horizontalTitleGap: 0,
              ),
          child: LayoutBuilder(
            builder: (BuildContext e, BoxConstraints constraints) => ConstrainedBox(
              constraints: BoxConstraints(maxHeight: constraints.maxHeight, minHeight: 100, minWidth: 100, maxWidth: constraints.maxWidth),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Expanded(
                        flex: 2,
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.start,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: <Widget>[
                            CheckboxListTile(
                              title: const Text("Show System Usage"),
                              controlAffinity: ListTileControlAffinity.leading,
                              value: globalSettings.showSystemUsage,
                              onChanged: (bool? newValue) async {
                                globalSettings.showSystemUsage = newValue ?? false;
                                await Boxes.updateSettings("showSystemUsage", globalSettings.showSystemUsage);
                                if (!mounted) return;
                                setState(() {});
                              },
                            ),
                            CheckboxListTile(
                              title: const Text("Show Weather"),
                              value: globalSettings.showWeather,
                              controlAffinity: ListTileControlAffinity.leading,
                              onChanged: (bool? newValue) async {
                                globalSettings.showWeather = newValue ?? true;
                                await Boxes.updateSettings("showWeather", globalSettings.showWeather);
                                if (!mounted) return;
                                setState(() {});
                              },
                              secondary: InkWell(
                                onTap: () {
                                  WinUtils.open("https://wttr.in");
                                },
                                child: Tooltip(message: "It uses wttr.in by chubin", child: Icon(Icons.info_outline, color: Theme.of(context).toggleableActiveColor)),
                              ),
                            ),
                            //! Weather.
                            if (globalSettings.showWeather)
                              Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: <Widget>[
                                    CheckboxListTile(
                                      title: const Text("Use Celsius"),
                                      controlAffinity: ListTileControlAffinity.leading,
                                      value: globalSettings.weatherUnit == "m",
                                      onChanged: (bool? newValue) async {
                                        globalSettings.weatherUnit = newValue == true ? "m" : "u";
                                        await Boxes.updateSettings("weather", globalSettings.weather);
                                        if (!mounted) return;
                                        setState(() {});
                                      },
                                    ),
                                    ListTile(
                                      title: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: TextField(
                                          decoration: const InputDecoration(
                                              labelText: "City and Country", hintText: "City and Country", border: InputBorder.none, isDense: false),
                                          controller: TextEditingController(text: globalSettings.weatherCity.toUpperCaseEach()),
                                          toolbarOptions: const ToolbarOptions(paste: true, cut: true, copy: true, selectAll: true),
                                          style: const TextStyle(fontSize: 14),
                                          enableInteractiveSelection: true,
                                          onSubmitted: (String e) {
                                            if (e == "") return;
                                            globalSettings.weatherCity = e;
                                            Boxes.updateSettings("weather", globalSettings.weather);
                                            if (!mounted) return;
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ),
                                    ListTile(
                                      trailing: InkWell(
                                        onTap: () {
                                          WinUtils.open(
                                              "https://github.com/chubin/wttr.in#:~:text=To%20specify%20your%20own%20custom%20output%20format%2C%20use%20the%20special%20%25%2Dnotation%3A");
                                        },
                                        child: Tooltip(message: "See format info", child: Icon(Icons.info_outline, color: Theme.of(context).toggleableActiveColor)),
                                      ),
                                      title: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 10),
                                        child: TextField(
                                          decoration:
                                              const InputDecoration(labelText: "Weather Format", hintText: "Weather Format", border: InputBorder.none, isDense: false),
                                          controller: TextEditingController(text: globalSettings.weatherFormat),
                                          toolbarOptions: const ToolbarOptions(paste: true, cut: true, copy: true, selectAll: true),
                                          style: const TextStyle(fontSize: 14),
                                          enableInteractiveSelection: true,
                                          onSubmitted: (String e) {
                                            if (e == "") return;
                                            globalSettings.weatherFormat = e;
                                            Boxes.updateSettings("weather", globalSettings.weather);
                                            if (!mounted) return;
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
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
                            CheckboxListTile(
                              controlAffinity: ListTileControlAffinity.leading,
                              title: const Text("Tray Bar"),
                              value: globalSettings.showTrayBar,
                              onChanged: (bool? newValue) async {
                                globalSettings.showTrayBar = newValue ?? true;
                                await Boxes.updateSettings("showTrayBar", globalSettings.showTrayBar);
                                if (!mounted) return;
                                setState(() {});
                              },
                              secondary: Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: InkWell(
                                  child: const Icon(Icons.refresh),
                                  onTap: () {
                                    globalSettings.showTrayBar = false;
                                    setState(() {});
                                    globalSettings.showTrayBar = true;
                                    setState(() {});
                                  },
                                ),
                              ),
                            ),
                            if (globalSettings.showTrayBar)
                              FutureBuilder<bool>(
                                future: Tray.fetchTray(sort: false),
                                builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
                                  if (!snapshot.hasData) return Container();
                                  List<TrayBarInfo> trayList = <TrayBarInfo>[...Tray.trayList.where((TrayBarInfo element) => element.processExe != "explorer.exe")];
                                  return LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
                                    return ConstrainedBox(
                                      constraints: BoxConstraints(maxHeight: 200, minHeight: 100, maxWidth: constraints.maxWidth),
                                      child: SingleChildScrollView(
                                        controller: ScrollController(),
                                        child: Column(
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          crossAxisAlignment: CrossAxisAlignment.stretch,
                                          mainAxisSize: MainAxisSize.max,
                                          children: <Widget>[
                                            for (TrayBarInfo item in trayList)
                                              MouseRegion(
                                                cursor: item.processExe == "" ? SystemMouseCursors.noDrop : SystemMouseCursors.basic,
                                                // opaque: true,
                                                child: IgnorePointer(
                                                  ignoring: item.processExe == "",
                                                  child: Padding(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                                    child: SingleChildScrollView(
                                                      controller: ScrollController(),
                                                      scrollDirection: Axis.horizontal,
                                                      child: Row(
                                                        mainAxisAlignment: MainAxisAlignment.start,
                                                        crossAxisAlignment: CrossAxisAlignment.center,
                                                        children: <Widget>[
                                                          ToggleButtons(
                                                            constraints: const BoxConstraints(minHeight: 25, minWidth: 25),
                                                            children: <Widget>[
                                                              const Tooltip(message: "Pin", child: Icon(Icons.push_pin, size: 13)),
                                                              const Tooltip(message: "Hide", child: Icon(Icons.visibility_off, size: 13)),
                                                              // const Tooltip(message: "Normal", child: Icon(Icons.reorder, size: 13)),
                                                            ],
                                                            onPressed: (int index) async {
                                                              // isSelected[index] = !isSelected[index];
                                                              final List<String> pinned = Boxes.pref.getStringList("pinnedTray") ?? <String>[];
                                                              final List<String> hidden = Boxes.pref.getStringList("hiddenTray") ?? <String>[];
                                                              if (index == 0 && !pinned.contains(item.processExe)) {
                                                                pinned.add(item.processExe);
                                                                if (hidden.contains(item.processExe)) hidden.remove(item.processExe);
                                                              } else if (index == 1 && !hidden.contains(item.processExe)) {
                                                                hidden.add(item.processExe);
                                                                if (pinned.contains(item.processExe)) pinned.remove(item.processExe);
                                                              } else {
                                                                if (pinned.contains(item.processExe)) pinned.remove(item.processExe);
                                                                if (hidden.contains(item.processExe)) hidden.remove(item.processExe);
                                                              }
                                                              await Boxes.updateSettings("pinnedTray", pinned);
                                                              await Boxes.updateSettings("hiddenTray", hidden);
                                                              setState(() {});
                                                            },
                                                            isSelected: <bool>[item.isPinned, !item.isVisible],
                                                          ),
                                                          const SizedBox(width: 5),
                                                          ToggleButtons(
                                                            constraints: const BoxConstraints(minHeight: 25, minWidth: 25),
                                                            children: <Widget>[
                                                              const Tooltip(message: "Simulate Click", child: Icon(Icons.mouse, size: 13)),
                                                              const Tooltip(
                                                                  message: "Left opens .exe\nRight sends close message", child: Icon(Icons.open_in_new, size: 13)),
                                                            ],
                                                            onPressed: (int index) async {
                                                              // isSelected[index] = !isSelected[index];
                                                              final List<String> action = Boxes.pref.getStringList("actionTray") ?? <String>[];
                                                              if (index == 1 && !action.contains(item.processExe)) {
                                                                action.add(item.processExe);
                                                              } else if (action.contains(item.processExe)) {
                                                                action.remove(item.processExe);
                                                              }
                                                              await Boxes.updateSettings("actionTray", action);
                                                              setState(() {});
                                                            },
                                                            isSelected: <bool>[!item.clickOpensExe, item.clickOpensExe],
                                                          ),
                                                          Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Image.memory(item.iconData, width: 20)),
                                                          Padding(
                                                            padding: const EdgeInsets.symmetric(horizontal: 10),
                                                            child: item.processExe == ""
                                                                ? Text(
                                                                    "Permission denied",
                                                                    style: TextStyle(
                                                                      fontSize: 14,
                                                                      fontStyle: FontStyle.italic,
                                                                      color: Theme.of(context).hintColor,
                                                                    ),
                                                                    overflow: TextOverflow.ellipsis,
                                                                  )
                                                                : Text(item.processExe, style: const TextStyle(fontSize: 14)),
                                                          ),
                                                        ],
                                                      ),
                                                    ),
                                                  ),
                                                ),
                                              )
                                          ],
                                        ),
                                      ),
                                    );
                                  });
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: 300,
                    child: ListTile(
                      dense: true,
                      style: ListTileStyle.drawer,
                      title: CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Text("PowerShell Scripts", style: Theme.of(context).textTheme.headline6),
                        value: globalSettings.showPowerShell,
                        onChanged: (bool? newValue) async {
                          globalSettings.showPowerShell = newValue ?? false;
                          await Boxes.updateSettings("showPowerShell", globalSettings.showPowerShell);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      trailing: globalSettings.showPowerShell
                          ? IconButton(
                              icon: const Icon(Icons.add),
                              onPressed: () async {
                                powerShellScripts.add(PowerShellScript(command: "dir", name: "Name", showTerminal: true));
                                powerShellNameController.add(TextEditingController(text: "Name"));
                                await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                                setState(() {});
                                // FilePickerResult? result = await FilePicker.platform.pickFiles();
                              },
                            )
                          : null,
                    ),
                  ),
                  if (globalSettings.showPowerShell && powerShellScripts.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: SingleChildScrollView(
                        child: ListView.builder(
                          itemCount: powerShellScripts.length,
                          controller: ScrollController(),
                          clipBehavior: Clip.hardEdge,
                          shrinkWrap: true,
                          itemBuilder: (BuildContext context, int index) {
                            // final PowerShellScript script = powerShellScripts[index];
                            return Column(
                              children: <Widget>[
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: <Widget>[
                                    SizedBox(
                                      width: 40,
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.center,
                                        children: <Widget>[
                                          Tooltip(
                                            message: "Enable",
                                            child: Checkbox(
                                              value: !powerShellScripts[index].disabled,
                                              onChanged: (bool? value) async {
                                                powerShellScripts[index].disabled = !(value ?? true);
                                                await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                                                setState(() {});
                                              },
                                            ),
                                          ),
                                          const SizedBox(height: 10),
                                          Tooltip(
                                            message: "Show Terminal",
                                            child: InkWell(
                                              child: Icon(
                                                Icons.terminal,
                                                color: !powerShellScripts[index].showTerminal ? Colors.grey : Theme.of(context).colorScheme.primary,
                                                size: 22,
                                              ),
                                              onTap: () async {
                                                powerShellScripts[index].showTerminal = !powerShellScripts[index].showTerminal;
                                                await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                                                setState(() {});
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    Expanded(
                                      child: Wrap(
                                        // mainAxisAlignment: MainAxisAlignment.start,
                                        children: <Widget>[
                                          TextField(
                                            decoration: const InputDecoration(
                                              labelText: "Name",
                                              hintText: "Name",
                                              isDense: true,
                                              border: InputBorder.none,
                                            ),
                                            controller: powerShellNameController[index],
                                            style: const TextStyle(fontSize: 14),
                                          ),
                                          TextField(
                                            decoration: const InputDecoration(
                                              labelText: "Command (press Enter to change)",
                                              hintText: "Command",
                                              isDense: true,
                                              border: InputBorder.none,
                                            ),
                                            controller: TextEditingController(text: powerShellScripts[index].command),
                                            style: const TextStyle(fontSize: 14),
                                            onSubmitted: (String command) async {
                                              final String name = powerShellNameController[index].value.text.toString();
                                              powerShellScripts[index].name = name;
                                              powerShellScripts[index].command = command;
                                              await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                                              setState(() {});
                                            },
                                          ),
                                        ],
                                      ),
                                    ),
                                    SizedBox(
                                      width: 40,
                                      height: 40,
                                      child: Padding(
                                        padding: const EdgeInsets.only(right: 10),
                                        child: IconButton(
                                          icon: const Icon(Icons.delete),
                                          onPressed: () async {
                                            powerShellScripts.remove(powerShellScripts[index]);
                                            powerShellNameController.removeAt(index);
                                            await Boxes.updateSettings("powerShellScripts", jsonEncode(powerShellScripts));
                                            setState(() {});
                                          },
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                if (index < powerShellScripts.length - 1)
                                  const Divider(
                                    thickness: 2,
                                    height: 20,
                                    indent: 10,
                                    endIndent: 10,
                                    color: Colors.transparent,
                                  ),
                              ],
                            );
                          },
                        ),
                      ),
                    ),
                  const SizedBox(height: 50),
                ],
              ),
            ),
          ),
        ),
      )
    ]);
  }
}
