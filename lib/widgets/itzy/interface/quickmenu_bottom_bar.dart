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
  @override
  Widget build(BuildContext context) {
    return Column(children: <Widget>[
      ListTileTheme(
        data: Theme.of(context).listTileTheme.copyWith(
              dense: true,
              style: ListTileStyle.drawer,
              contentPadding: const EdgeInsets.symmetric(horizontal: 10),
              minVerticalPadding: 0,
              visualDensity: VisualDensity.compact,
              horizontalTitleGap: 0,
            ),
        child: Row(
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
                      child: Tooltip(message: "It uses wttr.in by chubin", child: Icon(Icons.info_outline, color: Colors.lightBlue.shade600)),
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
                                decoration: const InputDecoration(labelText: "City and Country", hintText: "City and Country", border: InputBorder.none, isDense: false),
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
                              child: Tooltip(message: "See format info", child: Icon(Icons.info_outline, color: Colors.lightBlue.shade600)),
                            ),
                            title: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              child: TextField(
                                decoration: const InputDecoration(labelText: "Weather Format", hintText: "Weather Format", border: InputBorder.none, isDense: false),
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
                children: [
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
                  ),
                  if (globalSettings.showTrayBar)
                    FutureBuilder<bool>(
                      future: Tray.fetchTray(sort: false),
                      builder: (BuildContext context, AsyncSnapshot<Object?> snapshot) {
                        if (!snapshot.hasData) return Container();
                        List<TrayBarInfo> trayList = <TrayBarInfo>[...Tray.trayList.where((TrayBarInfo element) => element.processExe != "explorer.exe")];
                        return ConstrainedBox(
                          constraints: const BoxConstraints(maxHeight: 200, minHeight: 100),
                          child: SingleChildScrollView(
                            controller: ScrollController(),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.max,
                              children: <Widget>[
                                for (TrayBarInfo item in trayList)
                                  IgnorePointer(
                                    ignoring: item.processExe == "",
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                      child: SingleChildScrollView(
                                        controller: ScrollController(),
                                        scrollDirection: Axis.horizontal,
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.start,
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: <Widget>[
                                            Padding(padding: const EdgeInsets.symmetric(horizontal: 5), child: Image.memory(item.iconData, width: 20)),
                                            ToggleButtons(
                                                constraints: const BoxConstraints(minHeight: 25, minWidth: 25),
                                                children: <Widget>[
                                                  const Tooltip(message: "Pin", child: Icon(Icons.push_pin, size: 13)),
                                                  const Tooltip(message: "Hide", child: Icon(Icons.visibility_off, size: 13)),
                                                  const Tooltip(message: "Normal", child: Icon(Icons.reorder, size: 13)),
                                                ],
                                                onPressed: (int index) async {
                                                  // isSelected[index] = !isSelected[index];
                                                  final List<String> pinned = Boxes.pref.getStringList("pinnedTray") ?? <String>[];
                                                  final List<String> hidden = Boxes.pref.getStringList("hiddenTray") ?? <String>[];
                                                  print(pinned);
                                                  print(hidden);
                                                  print("xx");
                                                  if (index == 0 && !pinned.contains(item.processExe)) {
                                                    pinned.add(item.processExe);
                                                    if (hidden.contains(item.processExe)) hidden.remove(item.processExe);
                                                  } else if (index == 1 && !hidden.contains(item.processExe)) {
                                                    hidden.add(item.processExe);
                                                    if (pinned.contains(item.processExe)) pinned.remove(item.processExe);
                                                  } else if (index == 2) {
                                                    if (pinned.contains(item.processExe)) pinned.remove(item.processExe);
                                                    if (hidden.contains(item.processExe)) hidden.remove(item.processExe);
                                                  }
                                                  await Boxes.updateSettings("pinnedTray", pinned);
                                                  await Boxes.updateSettings("hiddenTray", hidden);
                                                  final List<String> pinnedx = Boxes.pref.getStringList("pinnedTray") ?? <String>[];
                                                  final List<String> hiddenx = Boxes.pref.getStringList("hiddenTray") ?? <String>[];
                                                  print(pinnedx);
                                                  print(hiddenx);
                                                  print(index);
                                                  setState(() {});
                                                },
                                                isSelected: <bool>[item.isPinned, !item.isVisible, item.isVisible && !item.isPinned]),
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
                                  )
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                ],
              ),
            ),
          ],
        ),
      )
    ]);
  }
}
