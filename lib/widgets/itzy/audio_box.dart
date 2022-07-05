import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

class AudioBox extends StatefulWidget {
  const AudioBox({Key? key}) : super(key: key);

  @override
  AudioBoxState createState() => AudioBoxState();
}

class AudioInfo {
  List<AudioDevice> devices = <AudioDevice>[];
  AudioDevice defaultDevice = AudioDevice();
  Map<String, Uint8List> icons = <String, Uint8List>{};
  bool isMuted = false;
  double volume = 0.0;
}

class AudioBoxState extends State<AudioBox> {
  final audioInfo = AudioInfo();
  final micInfo = AudioInfo();

  List<ProcessVolume> audioMixer = <ProcessVolume>[];
  Map<int, Uint8List> audioMixerIcons = <int, Uint8List>{};

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() {
    fetchData();
    Timer.periodic(Duration(milliseconds: 300), (timer) {
      fetchData();
    });
  }

  void fetchData() async {
    audioInfo.devices = await Audio.enumDevices(AudioDeviceType.output) ?? [];
    audioInfo.defaultDevice = await Audio.getDefaultDevice(AudioDeviceType.output) ?? AudioDevice();
    audioInfo.isMuted = await Audio.getMuteAudioDevice(AudioDeviceType.output);
    audioInfo.volume = await Audio.getVolume(AudioDeviceType.output);

    micInfo.devices = await Audio.enumDevices(AudioDeviceType.input) ?? [];
    micInfo.defaultDevice = await Audio.getDefaultDevice(AudioDeviceType.input) ?? AudioDevice();
    micInfo.isMuted = await Audio.getMuteAudioDevice(AudioDeviceType.input);
    audioInfo.volume = await Audio.getVolume(AudioDeviceType.input);

    for (var device in audioInfo.devices) {
      if (audioInfo.icons.containsKey(device.id)) continue;
      var icon = await nativeIconToBytes(device.iconPath, iconID: device.iconID);
      audioInfo.icons[device.id] = icon!;
    }

    for (var device in micInfo.devices) {
      if (micInfo.icons.containsKey(device.id)) continue;
      var icon = await nativeIconToBytes(device.iconPath, iconID: device.iconID);
      micInfo.icons[device.id] = icon!;
    }
    audioMixer = await Audio.enumAudioMixer() ?? [];
    for (var device in audioMixer) {
      if (audioMixerIcons.containsKey(device.processId)) continue;
      var icon = await nativeIconToBytes(device.processPath);
      audioMixerIcons[device.processId] = icon!;
    }
    // print("fetching");
    // print(audioInfo.icons);
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    var outputDevicesWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Devices:", style: TextStyle(fontSize: 13)),
        Divider(
          thickness: 1,
          height: 1,
        ),
        Container(
          constraints: BoxConstraints(minWidth: 280, maxHeight: 70),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final device in audioInfo.devices)
                  ListTile(
                    visualDensity: VisualDensity(horizontal: 0, vertical: -4),
                    // visualDensity: VisualDensity.compact,
                    horizontalTitleGap: 0,
                    minVerticalPadding: 0,
                    minLeadingWidth: 20,
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                    title: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13),
                    ),
                    leading: audioInfo.icons.containsKey(device.id)
                        ? Image.memory(
                            audioInfo.icons[device.id]!,
                            // fit: BoxFit.scaleDown,
                            width: 18,
                          )
                        : Icon(Icons.audiotrack, size: 18),
                    trailing: device.id == audioInfo.defaultDevice.id
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(Icons.check, size: 18),
                          )
                        : null,
                    onTap: () {
                      Audio.setDefaultDevice(device.id);
                      fetchData();
                    },
                  ),
              ],
            ),
          ),
        )
      ],
    );
    var inputDevicesWidget = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text("Devices:", style: TextStyle(fontSize: 13)),
        Divider(
          thickness: 1,
          height: 1,
        ),
        Container(
          constraints: BoxConstraints(minWidth: 280, maxHeight: 70),
          child: SingleChildScrollView(
            child: Column(
              children: [
                for (final device in micInfo.devices)
                  ListTile(
                    visualDensity: VisualDensity(horizontal: 0, vertical: -4),
                    // visualDensity: VisualDensity.compact,
                    horizontalTitleGap: 0,
                    minVerticalPadding: 0,
                    minLeadingWidth: 20,
                    dense: true,
                    contentPadding: EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                    title: Text(
                      device.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 13),
                    ),
                    leading: micInfo.icons.containsKey(device.id)
                        ? Image.memory(
                            micInfo.icons[device.id]!,
                            // fit: BoxFit.scaleDown,
                            width: 18,
                          )
                        : Icon(Icons.audiotrack, size: 18),
                    trailing: device.id == micInfo.defaultDevice.id
                        ? Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4.0),
                            child: Icon(Icons.check, size: 18),
                          )
                        : null,
                    onTap: () {
                      Audio.setDefaultDevice(device.id);
                      fetchData();
                    },
                  ),
              ],
            ),
          ),
        )
      ],
    );
    return Container(
      height: 400,
      width: 400,
      color: Colors.white,
      constraints: BoxConstraints(maxWidth: 400, maxHeight: 400),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Flexible(
              fit: FlexFit.loose,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  //1 Ouput
                  Flexible(
                    fit: FlexFit.loose,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Output:", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400)),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Row(
                            children: [
                              InkWell(
                                // constraints: BoxConstraints(maxWidth: 20),
                                // splashRadius: 20,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 5),
                                  child: Icon(audioInfo.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 14),
                                ),
                                onTap: () {
                                  Audio.setMuteAudioDevice(!audioInfo.isMuted, AudioDeviceType.output);
                                  audioInfo.isMuted = !audioInfo.isMuted;
                                  fetchData();
                                },
                              ),
                              // Slider(
                              //   value: audioInfo.volume,
                              //   min: 0,
                              //   max: 1,
                              //   divisions: 25,
                              //   onChanged: (e) async {
                              //     await Audio.setVolume(e.toDouble(), AudioDeviceType.output);
                              //     audioInfo.volume = e;
                              //     setState(() {});
                              //   },
                              // ),
                            ],
                          ),
                        ),
                        Flexible(
                          fit: FlexFit.loose,
                          child: outputDevicesWidget,
                        ),
                        // make a scrollbar

                        // Scrollbar(child: )
                      ],
                    ),
                  ),
                  //1 Input
                  Flexible(
                    fit: FlexFit.loose,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      verticalDirection: VerticalDirection.down,
                      mainAxisAlignment: MainAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text("Input:", style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400)),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Row(
                            children: [
                              InkWell(
                                // constraints: BoxConstraints(maxWidth: 20),
                                // splashRadius: 20,
                                child: Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 5),
                                  child: Icon(audioInfo.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 14),
                                ),
                                onTap: () {
                                  Audio.setMuteAudioDevice(!audioInfo.isMuted, AudioDeviceType.output);
                                  audioInfo.isMuted = !audioInfo.isMuted;
                                  fetchData();
                                },
                              ),
                            ],
                          ),
                        ),
                        Flexible(
                          fit: FlexFit.loose,
                          child: inputDevicesWidget,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            //1 Mixer
            Flexible(
              fit: FlexFit.loose,
              child: Column(
                children: [
                  for (var mix in audioMixer)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.start,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      // mainAxisSize: MainAxisSize.max,
                      children: [
                        Padding(
                          padding: EdgeInsets.all(15),
                          child: audioMixerIcons.containsKey(mix.processId)
                              ? Image.memory(
                                  audioMixerIcons[mix.processId]!,
                                  // fit: BoxFit.scaleDown,
                                  width: 18,
                                )
                              : Icon(Icons.audiotrack, size: 18),
                        ),
                        Flexible(
                          fit: FlexFit.loose,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.start,
                            children: [
                              Align(
                                alignment: Alignment.centerLeft,
                                child: Container(
                                  color: Colors.red,
                                  height: 10,
                                  width: mix.peakVolume * 100,
                                ),
                              ),
                              Slider(
                                value: mix.maxVolume,
                                min: 0,
                                max: 1,
                                divisions: 25,
                                onChanged: (e) {
                                  Audio.setAudioMixerVolume(mix.processId, e);
                                  mix.maxVolume = e;
                                  setState(() {});
                                },
                              )
                            ],
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
