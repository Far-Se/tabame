import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/utils.dart';
import '../../models/win32/win32.dart';

class Home extends StatefulWidget {
  const Home({Key? key}) : super(key: key);

  @override
  HomeState createState() => HomeState();
}

class HomeState extends State<Home> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) => ConstrainedBox(
                  constraints: BoxConstraints(
                    maxHeight: constraints.maxHeight,
                    maxWidth: constraints.maxWidth,
                    minHeight: constraints.minHeight,
                    minWidth: constraints.minWidth,
                  ),
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
                            selectedTileColor: Colors.red,
                            // tileColor: Colors.red,
                            selectedColor: Colors.red,
                          ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.start,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: <Widget>[
                          Expanded(
                            flex: 2,
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxHeight: constraints.maxHeight,
                                maxWidth: constraints.maxWidth,
                                minHeight: constraints.minHeight,
                                minWidth: constraints.minWidth,
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: <Widget>[
                                  const ListTile(title: Text("General Settings")),
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
                                  CheckboxListTile(
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
                                  RadioTheme(
                                    data: Theme.of(context).radioTheme.copyWith(visualDensity: VisualDensity.compact, splashRadius: 20),
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.start,
                                      mainAxisSize: MainAxisSize.max,
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: <Widget>[
                                        ListTile(title: Text("Volume OSD Style", style: Theme.of(context).textTheme.bodyMedium)),
                                        RadioListTile<VolumeOSDStyle>(
                                          title: const Text('Normal Volume OSD'),
                                          value: VolumeOSDStyle.normal,
                                          groupValue: globalSettings.volumeOSDStyle,
                                          onChanged: (VolumeOSDStyle? value) => setVolumeOSDStyle(value),
                                        ),
                                        RadioListTile<VolumeOSDStyle>(
                                          title: const Text('Hide Media'),
                                          value: VolumeOSDStyle.media,
                                          groupValue: globalSettings.volumeOSDStyle,
                                          onChanged: (VolumeOSDStyle? value) => setVolumeOSDStyle(value),
                                        ),
                                        RadioListTile<VolumeOSDStyle>(
                                          title: const Text('Thin'),
                                          value: VolumeOSDStyle.thin,
                                          groupValue: globalSettings.volumeOSDStyle,
                                          onChanged: (VolumeOSDStyle? value) => setVolumeOSDStyle(value),
                                        ),
                                        RadioListTile<VolumeOSDStyle>(
                                          title: const Text('Hidden'),
                                          value: VolumeOSDStyle.visible,
                                          groupValue: globalSettings.volumeOSDStyle,
                                          onChanged: (VolumeOSDStyle? value) => setVolumeOSDStyle(value),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Flexible(
                                    fit: FlexFit.loose,
                                    child: Row(
                                      children: [
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: ListTile(
                                            onTap: () async {
                                              await toggleMonitorWallpaper(true);
                                            },
                                            leading: Container(height: double.infinity, child: const Icon(Icons.wallpaper)),
                                            title: Text(
                                              "Enable Wallpaper",
                                              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                                            ),
                                          ),
                                        ),
                                        Flexible(
                                          fit: FlexFit.loose,
                                          child: ListTile(
                                            onTap: () async {
                                              print("set Color");
                                              await toggleMonitorWallpaper(false);
                                              await setWallpaperColor(0x00000000);
                                            },
                                            leading: Container(height: double.infinity, child: const Icon(Icons.color_lens)),
                                            title: Text(
                                              "Change to Black",
                                              style: TextStyle(color: Theme.of(context).colorScheme.secondary),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Text(
                                    "   This window will freeze for a bit.",
                                    style: TextStyle(fontStyle: FontStyle.italic, color: Theme.of(context).colorScheme.secondary),
                                  )
                                ],
                              ),
                            ),
                          ),
                          Expanded(
                            flex: 2,
                            child: Container(),
                          )
                        ],
                      ),
                    ),
                  ),
                )),
      ],
    );
  }

  void setVolumeOSDStyle(VolumeOSDStyle? value) async {
    globalSettings.volumeOSDStyle = value ?? VolumeOSDStyle.normal;
    WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.normal, applyStyle: true);
    WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
    await Boxes.updateSettings("volumeOSDStyle", globalSettings.volumeOSDStyle.index);
    setState(() {});
  }
}
