import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../models/win32/win32.dart';
import '../widgets/checkbox_widget.dart';
import '../widgets/info_widget.dart';
import '../widgets/popup_dialog.dart';
import '../widgets/text_input.dart';

class AudioInterface extends StatefulWidget {
  const AudioInterface({Key? key}) : super(key: key);
  @override
  AudioInterfaceState createState() => AudioInterfaceState();
}

class AudioInterfaceState extends State<AudioInterface> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  void setVolumeOSDStyle(VolumeOSDStyle? value) async {
    globalSettings.volumeOSDStyle = value ?? VolumeOSDStyle.normal;
    WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.normal, applyStyle: true);
    WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
    await Boxes.updateSettings("volumeOSDStyle", globalSettings.volumeOSDStyle.index);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListTileTheme(
      data: Theme.of(context).listTileTheme.copyWith(
            dense: true,
            style: ListTileStyle.drawer,
            contentPadding: const EdgeInsets.symmetric(horizontal: 10),
            minVerticalPadding: 0,
            visualDensity: VisualDensity.compact,
            horizontalTitleGap: 0,
          ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 20),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            if (!Audio.canRunAudioModule)
              Text(
                "\nSorry but Audio Module is bugged on your Windows install, I am trying to figure it out why it doesn't work for some people.\n\n",
                style: Theme.of(context).textTheme.headline6,
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
                      ListTile(title: Text("Setting Default device:", style: Theme.of(context).textTheme.headline6)),
                      CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Multimedia"),
                        value: globalSettings.audioMultimedia,
                        onChanged: (bool? newValue) async {
                          globalSettings.audioMultimedia = !globalSettings.audioMultimedia;
                          Boxes.updateSettings("audio", globalSettings.audio);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Console"),
                        value: globalSettings.audioConsole,
                        onChanged: (bool? newValue) async {
                          globalSettings.audioConsole = !globalSettings.audioConsole;
                          Boxes.updateSettings("audio", globalSettings.audio);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Communications"),
                        value: globalSettings.audioCommunications,
                        onChanged: (bool? newValue) async {
                          globalSettings.audioCommunications = !globalSettings.audioCommunications;
                          Boxes.updateSettings("audio", globalSettings.audio);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      const Divider(height: 10, thickness: 1),
                      ListTile(title: Text("Spotify Settings", style: Theme.of(context).textTheme.headline6)),
                      CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Pause Spotify when sound comes from other sources"),
                        value: globalSettings.pauseSpotifyWhenNewSound,
                        onChanged: (bool? newValue) async {
                          globalSettings.pauseSpotifyWhenNewSound = !globalSettings.pauseSpotifyWhenNewSound;
                          Boxes.updateSettings("pauseSpotifyWhenNewSound", globalSettings.pauseSpotifyWhenNewSound);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Pause Spotify when you play a different app."),
                        value: globalSettings.pauseSpotifyWhenPlaying,
                        onChanged: (bool? newValue) async {
                          globalSettings.pauseSpotifyWhenPlaying = !globalSettings.pauseSpotifyWhenPlaying;
                          Boxes.updateSettings("pauseSpotifyWhenPlaying", globalSettings.pauseSpotifyWhenPlaying);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      const Divider(height: 10, thickness: 1),
                      ListTile(title: Text("QuickMenu Audio", style: Theme.of(context).textTheme.headline6)),
                      CheckboxListTile(
                        controlAffinity: ListTileControlAffinity.leading,
                        title: const Text("Show Media Control for each App"),
                        value: globalSettings.showMediaControlForApp,
                        onChanged: (bool? newValue) async {
                          globalSettings.showMediaControlForApp = newValue ?? false;
                          await Boxes.updateSettings("showMediaControlForApp", globalSettings.showMediaControlForApp);
                          if (!mounted) return;
                          setState(() {});
                        },
                      ),
                      if (globalSettings.showMediaControlForApp)
                        ListTile(
                          title: TextField(
                            decoration: const InputDecoration(
                              labelText: "Predefined Media apps (press Enter to save)",
                              hintText: "Predefined apps",
                              border: InputBorder.none,
                              isDense: false,
                            ),
                            controller: TextEditingController(text: Boxes.mediaControls.join(", ")),
                            toolbarOptions: const ToolbarOptions(
                              paste: true,
                              cut: true,
                              copy: true,
                              selectAll: true,
                            ),
                            style: const TextStyle(fontSize: 14),
                            enableInteractiveSelection: true,
                            onSubmitted: (String e) {
                              if (e == "") {
                                Boxes.mediaControls = <String>[];
                                Boxes.updateSettings("mediaControls", Boxes.mediaControls);
                              } else {
                                Boxes.mediaControls = e.replaceAll(',,', ',').split(",");
                                for (int i = 0; i < Boxes.mediaControls.length; i++) {
                                  Boxes.mediaControls[i] = Boxes.mediaControls[i].trim();
                                  if (Boxes.mediaControls[i] == "") {
                                    Boxes.mediaControls.removeAt(i);
                                    i--;
                                  }
                                }
                                Boxes.updateSettings("mediaControls", Boxes.mediaControls);
                              }
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Saved"), duration: Duration(seconds: 2)));
                              if (!mounted) return;
                              setState(() {});
                            },
                          ),
                        ),
                      const Divider(height: 10, thickness: 1),
                      if (globalSettings.isWindows10)
                        RadioTheme(
                          data: Theme.of(context).radioTheme.copyWith(visualDensity: VisualDensity.compact, splashRadius: 20),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            mainAxisSize: MainAxisSize.max,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: <Widget>[
                              ListTile(title: Text("Volume OSD Style", style: Theme.of(context).textTheme.headline6)),
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
                    ],
                  ),
                ),
                const Expanded(child: DefaultVolumePerApp())
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class DefaultVolumePerApp extends StatefulWidget {
  const DefaultVolumePerApp({Key? key}) : super(key: key);
  @override
  DefaultVolumePerAppState createState() => DefaultVolumePerAppState();
}

class DefaultVolumePerAppState extends State<DefaultVolumePerApp> {
  final List<DefaultVolume> volumes = Boxes.defaultVolume;
  @override
  void initState() {
    super.initState();
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
        const SizedBox(height: 2),
        ListTile(
          onTap: () {
            volumes.add(DefaultVolume(type: "exe", match: "rocket", volume: 24));
            Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
            setState(() {});
          },
          leading: Container(width: 20, height: double.infinity, child: const Icon(Icons.add)),
          title: Text(
            "Default Volume for app",
            style: Theme.of(context).textTheme.headline6?.copyWith(height: 1),
          ),
          trailing: InfoWidget(
            "Press",
            onTap: () {
              popupDialog(context, "You can set the default volume when a specific app is focused\nIt's good for games.");
            },
          ),
        ),
        CheckBoxWidget(
          onChanged: (bool e) {
            globalSettings.volumeSetBack = !globalSettings.volumeSetBack;
            Boxes.updateSettings("volumeSetBack", globalSettings.volumeSetBack);
            setState(() {});
          },
          value: globalSettings.volumeSetBack,
          text: "Set previous volume back when unfocus the app",
        ),
        ...List<Widget>.generate(volumes.length, (int index) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              SizedBox(
                width: 70,
                child: TextInput(
                  key: UniqueKey(),
                  labelText: "Match by:",
                  value: volumes[index].type,
                  onChanged: (String e) {
                    if (!const <String>["exe", "class", "title"].contains(e)) {
                      popupDialog(context, "Only exe, class and title");
                      return;
                    }
                    volumes[index].type = e;
                    Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
                    setState(() {});
                  },
                ),
              ),
              const VerticalDivider(width: 10, thickness: 5),
              Expanded(
                child: TextInput(
                  key: UniqueKey(),
                  labelText: "Match:",
                  value: volumes[index].match,
                  onChanged: (String e) {
                    if (e.isEmpty) return;
                    try {
                      RegExp(e).hasMatch("ciulama");
                    } catch (e) {
                      popupDialog(context, "Regex error:\n$e");
                      return;
                    }
                    volumes[index].match = e;
                    Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
                    setState(() {});
                  },
                ),
              ),
              SizedBox(
                width: 50,
                child: TextInput(
                  key: UniqueKey(),
                  labelText: "Volume:",
                  value: volumes[index].volume.toString(),
                  onChanged: (String e) {
                    if (e.isEmpty) return;
                    if (!(int.tryParse(e) ?? -1).isBetweenEqual(0, 100)) {
                      popupDialog(context, "Volume can be only between 0 and 100");
                    }
                    volumes[index].volume = int.parse(e);
                    Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
                    setState(() {});
                  },
                ),
              ),
              const SizedBox(width: 20),
              Container(
                width: 40,
                height: 40,
                child: InkWell(
                  onTap: () {
                    volumes.removeAt(index);
                    Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
                    setState(() {});
                  },
                  child: const Icon(Icons.delete),
                ),
              ),
            ],
          );
        }),
      ],
    );
  }
}
