import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/win32/win32.dart';

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
  late Timer timerData;
  late Timer timerMixer;
  List<ProcessVolume> audioMixer = <ProcessVolume>[];
  Map<int, Uint8List> audioMixerIcons = <int, Uint8List>{};

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() {
    fetchData();
    fetchAudioMixerData();
    timerData = Timer.periodic(Duration(milliseconds: 1000), (timer) {
      timerData = timer;
      fetchData();
    });
    timerMixer = Timer.periodic(Duration(milliseconds: 100), (timer) {
      timerMixer = timer;
      fetchAudioMixerData();
    });
  }

  @override
  void dispose() {
    timerData.cancel();
    timerMixer.cancel();
    super.dispose();
  }

  void fetchData() async {
    audioInfo.devices = await Audio.enumDevices(AudioDeviceType.output) ?? [];
    audioInfo.defaultDevice = await Audio.getDefaultDevice(AudioDeviceType.output) ?? AudioDevice();
    audioInfo.isMuted = await Audio.getMuteAudioDevice(AudioDeviceType.output);
    audioInfo.volume = await Audio.getVolume(AudioDeviceType.output);

    micInfo.devices = await Audio.enumDevices(AudioDeviceType.input) ?? [];
    micInfo.defaultDevice = await Audio.getDefaultDevice(AudioDeviceType.input) ?? AudioDevice();
    micInfo.isMuted = await Audio.getMuteAudioDevice(AudioDeviceType.input);
    micInfo.volume = await Audio.getVolume(AudioDeviceType.input);

    for (var inputType in [audioInfo, micInfo]) {
      for (var device in inputType.devices) {
        if (inputType.icons.containsKey(device.id)) continue;

        var icon = await nativeIconToBytes(device.iconPath, iconID: device.iconID);
        inputType.icons[device.id] = icon!;
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future fetchAudioMixerData() async {
    audioMixer = await Audio.enumAudioMixer() ?? [];
    for (var device in audioMixer) {
      if (audioMixerIcons.containsKey(device.processId)) continue;

      var icon = await nativeIconToBytes(device.processPath);
      audioMixerIcons[device.processId] = icon!;
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (audioInfo.devices.isEmpty) {
      return Container();
    }
    var output = <int, Widget>{};

    for (var device in AudioDeviceType.values) {
      var deviceVar = audioInfo;
      if (device == AudioDeviceType.input) {
        deviceVar = micInfo;
      }
      output[device.index] = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(device.name.toUpperCase(), style: TextStyle(fontSize: 17, fontWeight: FontWeight.w400)),
          Flexible(
            fit: FlexFit.loose,
            //2 Mute Button and Slider
            child: Row(
              children: [
                InkWell(
                  // constraints: BoxConstraints(maxWidth: 20),
                  // splashRadius: 20,
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(deviceVar.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded, size: 14),
                  ),
                  onTap: () {
                    Audio.setMuteAudioDevice(!deviceVar.isMuted, device);
                    print(device);
                    deviceVar.isMuted = !deviceVar.isMuted;
                    fetchData();
                  },
                ),
                //3 Slider
                Container(
                  width: 100,
                  child: Slider(
                    value: deviceVar.volume,
                    min: 0,
                    max: 1,
                    divisions: 25,
                    onChanged: (e) async {
                      Audio.setVolume(e.toDouble(), device);
                      deviceVar.volume = e;
                      setState(() {});
                    },
                  ),
                ),
                //#e
              ],
            ),
          ),
          //2 Devices
          Flexible(
            fit: FlexFit.loose,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                InkWell(
                  onTap: () {
                    WinUtils.runPowerShell(["mmsys.cpl"]);
                    Navigator.pop(context);
                  },
                  child: Text.rich(
                    TextSpan(
                      children: [
                        WidgetSpan(
                          alignment: PlaceholderAlignment.middle,
                          child: Icon(Icons.tune, size: 13),
                        ),
                        TextSpan(text: "Devices:", style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                ),
                Divider(
                  thickness: 1,
                  height: 1,
                ),
                //#h red
                //3 Devices List
                Container(
                  constraints: BoxConstraints(minWidth: 280, maxHeight: 80),
                  child: SingleChildScrollView(
                    child: Column(
                      children: [
                        for (final device in deviceVar.devices)
                          Material(
                            type: MaterialType.transparency,
                            child: ListTile(
                              visualDensity: VisualDensity(horizontal: 0, vertical: -4),
                              // visualDensity: VisualDensity.compact,
                              horizontalTitleGap: 0,
                              minVerticalPadding: 0,
                              minLeadingWidth: 20,
                              dense: true,
                              selected: device.id == deviceVar.defaultDevice.id ? true : false,
                              selectedTileColor: Color.fromARGB(10, 0, 0, 0),
                              selectedColor: Theme.of(context).textTheme.bodySmall?.color,
                              contentPadding: EdgeInsets.symmetric(horizontal: 3, vertical: 0),
                              title: Text(
                                device.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 13, fontWeight: device.id == deviceVar.defaultDevice.id ? FontWeight.w500 : FontWeight.normal),
                              ),
                              leading: deviceVar.icons.containsKey(device.id) ? Image.memory(deviceVar.icons[device.id]!, width: 18) : Icon(Icons.audiotrack, size: 18),
                              trailing: device.id == deviceVar.defaultDevice.id
                                  ? Padding(padding: const EdgeInsets.symmetric(horizontal: 4.0), child: Icon(Icons.check, size: 18))
                                  : null,
                              onTap: () {
                                Audio.setDefaultDevice(device.id);
                                fetchData();
                              },
                            ),
                          ),
                      ],
                    ),
                  ),
                )
                //#e
              ],
            ),
          ),
        ],
      );
    }

    // print(output);
    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: double.infinity,
          width: 280,
          // color: Colors.white,
          constraints: BoxConstraints(maxWidth: 280, maxHeight: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.grey, width: 1),
            color: Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                // activeTrackColor: Colors.white,
                thumbShape: RoundSliderThumbShape(enabledThumbRadius: 5.0),
                overlayShape: SliderComponentShape.noOverlay, //(overlayRadius: 3.0),
              ),
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
                          (audioInfo.devices.isEmpty)
                              ? SizedBox()
                              : Flexible(
                                  fit: FlexFit.loose,
                                  child: output[AudioDeviceType.output.index]!,
                                ),
                          //1 Input
                          (micInfo.devices.isEmpty)
                              ? SizedBox()
                              : Flexible(
                                  fit: FlexFit.loose,
                                  child: output[AudioDeviceType.input.index]!,
                                ),
                        ],
                      ),
                    ),
                    Divider(thickness: 1, height: 1, color: Colors.grey.shade300),
                    SizedBox(height: 5),
                    //1 Mixer
                    (audioMixer.isEmpty)
                        ? SizedBox()
                        : Flexible(
                            fit: FlexFit.loose,
                            child: Container(
                              // height: 80,
                              // constraints: BoxConstraints(minWidth: 280, maxHeight: 80),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                children: [
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: EdgeInsets.all(8) - EdgeInsets.only(top: 8),
                                      child: Text(
                                        "Mixer:",
                                        style: TextStyle(fontSize: 13),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    constraints: BoxConstraints(minWidth: 280, maxHeight: 80),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // SizedBox(height: 20),
                                          //#h white
                                          for (var mix in audioMixer)
                                            Flexible(
                                              fit: FlexFit.loose,
                                              child: Row(
                                                // mainAxisAlignment: MainAxisAlignment.start,
                                                // crossAxisAlignment: CrossAxisAlignment.center,
                                                // mainAxisSize: MainAxisSize.max,
                                                children: [
                                                  Padding(
                                                    padding: EdgeInsets.all(5),
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
                                                        Container(
                                                          // color: Colors.red,
                                                          // height: 10,
                                                          // width: mix.peakVolume * 100,
                                                          child: SliderTheme(
                                                            data: SliderTheme.of(context).copyWith(
                                                                // activeTrackColor: Colors.white,
                                                                thumbShape: RoundSliderThumbShape(
                                                                  enabledThumbRadius: 5.0,
                                                                  elevation: 0,
                                                                ),
                                                                overlayShape: SliderComponentShape.noOverlay //(overlayRadius: 3.0),
                                                                ),
                                                            child: AbsorbPointer(
                                                              child: Slider(
                                                                value: (mix.peakVolume * mix.maxVolume).clamp(0, 0.9),
                                                                min: 0,
                                                                max: 1,

                                                                // divisions: 25,
                                                                activeColor: Colors.grey,
                                                                inactiveColor: Colors.grey.shade50,
                                                                thumbColor: Colors.transparent,
                                                                onChanged: (e) {
                                                                  Audio.setAudioMixerVolume(mix.processId, e);
                                                                  mix.maxVolume = e;
                                                                  setState(() {});
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                        ),
                                                        Container(
                                                          height: 20,
                                                          child: Slider(
                                                            value: mix.maxVolume,
                                                            min: 0,
                                                            max: 1,
                                                            divisions: 25,
                                                            onChanged: (e) {
                                                              Audio.setAudioMixerVolume(mix.processId, e);
                                                              mix.maxVolume = e;
                                                              setState(() {});
                                                            },
                                                          ),
                                                        )
                                                      ],
                                                    ),
                                                  ),
                                                  //#e
                                                ],
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),
                                  )
                                ],
                              ),
                            ),
                          ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class CustomTrackShape extends RoundedRectSliderTrackShape {
  @override
  Rect getPreferredRect({
    required RenderBox parentBox,
    Offset offset = Offset.zero,
    required SliderThemeData sliderTheme,
    bool isEnabled = false,
    bool isDiscrete = false,
  }) {
    final double trackHeight = sliderTheme.trackHeight!;
    final double trackLeft = offset.dx;
    final double trackTop = offset.dy + (parentBox.size.height - trackHeight) / 2;
    final double trackWidth = parentBox.size.width;
    return Rect.fromLTWH(trackLeft, trackTop, trackWidth, trackHeight);
  }
}
