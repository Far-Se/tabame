import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/globals.dart';
import '../../../models/utils.dart';
import '../../../models/win32/win32.dart';

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
  final AudioInfo audioInfo = AudioInfo();
  final AudioInfo micInfo = AudioInfo();
  Timer? timerData;
  Timer? timerMixer;
  List<ProcessVolume> audioMixer = <ProcessVolume>[];
  Map<int, Uint8List> audioMixerIcons = <int, Uint8List>{};
  Map<int, String> audioMixerNames = <int, String>{};

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() {
    PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    if (timerMixer != null) timerMixer?.cancel();
    if (timerData != null) timerMixer?.cancel();

    fetchData();
    fetchAudioMixerData();
    timerData = Timer.periodic(const Duration(milliseconds: 1000), (Timer timer) {
      if (Globals.audioBoxVisible) fetchData();
    });
    timerMixer = Timer.periodic(const Duration(milliseconds: 100), (Timer timer) {
      if (Globals.audioBoxVisible) fetchAudioMixerData();
    });
  }

  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    timerData?.cancel();
    timerMixer?.cancel();
    super.dispose();
  }

  void fetchData() async {
    audioInfo.devices = await Audio.enumDevices(AudioDeviceType.output) ?? <AudioDevice>[];
    audioInfo.defaultDevice = await Audio.getDefaultDevice(AudioDeviceType.output) ?? AudioDevice();
    audioInfo.isMuted = await Audio.getMuteAudioDevice(AudioDeviceType.output);
    audioInfo.volume = await Audio.getVolume(AudioDeviceType.output);

    micInfo.devices = await Audio.enumDevices(AudioDeviceType.input) ?? <AudioDevice>[];
    micInfo.defaultDevice = await Audio.getDefaultDevice(AudioDeviceType.input) ?? AudioDevice();
    micInfo.isMuted = await Audio.getMuteAudioDevice(AudioDeviceType.input);
    micInfo.volume = await Audio.getVolume(AudioDeviceType.input);

    for (AudioInfo inputType in <AudioInfo>[audioInfo, micInfo]) {
      for (AudioDevice device in inputType.devices) {
        if (inputType.icons.containsKey(device.id)) continue;

        Uint8List? icon = await WinUtils.getCachedIcon(device.iconPath, iconID: device.iconID);
        inputType.icons[device.id] = icon;
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> fetchAudioMixerData() async {
    audioMixer = await Audio.enumAudioMixer() ?? <ProcessVolume>[];
    for (ProcessVolume device in audioMixer) {
      if (audioMixerIcons.containsKey(device.processId)) continue;
      Uint8List? icon;
      final int hWnd = await findTopWindow(device.processId);
      //? Basic Way
      if (hWnd == 0) {
        audioMixerIcons[device.processId] = (await WinUtils.getCachedIcon(device.processPath));
        audioMixerNames[device.processId] = Win32.extractFileNameFromPath(device.processPath).capitalize();
        continue;
      }
      //? Fancy Way
      final HwndInfo processPath = HwndPath.getFullPath(hWnd);
      if (processPath.isAppx) {
        final String appxLogo = Win32.getManifestIcon(processPath.path);
        if (File(appxLogo).existsSync()) {
          icon = File(appxLogo).readAsBytesSync();
        } else {
          icon = await WinUtils.getCachedIcon(device.processPath);
        }
      } else {
        icon = await WinUtils.getCachedIcon(processPath.path);
      }
      audioMixerIcons[device.processId] = icon;
      audioMixerNames[device.processId] = Win32.extractFileNameFromPath(processPath.path).capitalize();
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
    Map<int, Widget> output = <int, Widget>{};

    for (AudioDeviceType device in AudioDeviceType.values) {
      AudioInfo deviceVar = audioInfo;
      if (device == AudioDeviceType.input) {
        deviceVar = micInfo;
      }
      output[device.index] = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(device.name.toUpperCase(), style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w400, color: Colors.black)),
          Flexible(
            fit: FlexFit.loose,
            //2 Mute Button and Slider
            child: Row(
              children: <Widget>[
                InkWell(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 5),
                    child: Icon(
                      deviceVar.isMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                      size: 14,
                      color: Colors.black54,
                    ),
                  ),
                  onTap: () {
                    Audio.setMuteAudioDevice(!deviceVar.isMuted, device);
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
                    onChanged: (double e) async {
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
              children: <Widget>[
                const SizedBox(
                  height: 10,
                ),
                Flexible(
                  fit: FlexFit.loose,
                  child: InkWell(
                    onTap: () {
                      WinUtils.runPowerShell(<String>["mmsys.cpl"]);
                      Navigator.pop(context);
                    },
                    child: Wrap(
                      verticalDirection: VerticalDirection.up,
                      children: <Widget>[
                        const Icon(Icons.tune, size: 14, color: Colors.black45),
                        Text("Devices:", style: TextStyle(fontSize: 13, color: Colors.lightBlue.shade600)),
                      ],
                    ),
                  ),
                ),
                const Divider(
                  thickness: 1,
                  height: 5,
                  color: Colors.black12,
                ),
                //#h red
                //3 Devices List
                Container(
                  constraints: const BoxConstraints(minWidth: 280, maxHeight: 80),
                  child: SingleChildScrollView(
                    child: Column(
                      children: <Widget>[
                        for (final AudioDevice device in deviceVar.devices)
                          Material(
                            type: MaterialType.transparency,
                            child: InkWell(
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 2,
                                  vertical: 2,
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.start,
                                  children: <Widget>[
                                    Flexible(
                                      fit: FlexFit.loose,
                                      child: deviceVar.icons.containsKey(device.id)
                                          ? Image.memory(deviceVar.icons[device.id]!, width: 18, gaplessPlayback: true)
                                          : const Icon(Icons.audiotrack, size: 18),
                                    ),
                                    Expanded(
                                      flex: 4,
                                      child: Text(
                                        device.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            fontSize: 12, fontWeight: device.id == deviceVar.defaultDevice.id ? FontWeight.w500 : FontWeight.normal, color: Colors.black),
                                      ),
                                    ),
                                    if (device.id == deviceVar.defaultDevice.id)
                                      const Flexible(
                                        fit: FlexFit.loose,
                                        child: Padding(
                                          padding: EdgeInsets.symmetric(horizontal: 4.0),
                                          child: Icon(Icons.check, size: 18, color: Colors.black45),
                                        ),
                                      )
                                  ],
                                ),
                              ),
                              onTap: () {
                                Audio.setDefaultDevice(device.id);
                                fetchData();
                              },
                            ),
                          ),
                        const SizedBox(
                          height: 5,
                        )
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

    return Material(
      type: MaterialType.transparency,
      child: Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: double.infinity,
          width: 280,
          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 300),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(5),
            border: Border.all(color: Colors.grey, width: 1),
            color: Colors.white,
          ),
          child: Padding(
            padding: const EdgeInsets.all(8.0),
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5.0),
                overlayShape: SliderComponentShape.noOverlay,
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
                        children: <Widget>[
                          //1 Ouput
                          (audioInfo.devices.isEmpty)
                              ? const SizedBox()
                              : Flexible(
                                  fit: FlexFit.loose,
                                  child: output[AudioDeviceType.output.index]!,
                                ),
                          //1 Input
                          (micInfo.devices.isEmpty)
                              ? const SizedBox()
                              : Flexible(
                                  fit: FlexFit.loose,
                                  child: output[AudioDeviceType.input.index]!,
                                ),
                        ],
                      ),
                    ),
                    const Divider(
                      thickness: 1,
                      height: 5,
                      color: Colors.black12,
                    ),
                    //1 Mixer
                    (audioMixer.isEmpty)
                        ? const SizedBox()
                        : Flexible(
                            fit: FlexFit.loose,
                            child: Container(
                              child: Wrap(
                                children: <Widget>[
                                  const Align(
                                    alignment: Alignment.centerLeft,
                                    child: Padding(
                                      padding: EdgeInsets.all(2),
                                      child: Text(
                                        "Mixer:",
                                        style: TextStyle(fontSize: 14, color: Colors.black, fontWeight: FontWeight.w400),
                                      ),
                                    ),
                                  ),
                                  Container(
                                    constraints: const BoxConstraints(minWidth: 280, maxHeight: 80),
                                    child: SingleChildScrollView(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisSize: MainAxisSize.min,
                                        children: <Widget>[
                                          //#h white
                                          for (ProcessVolume mix in audioMixer)
                                            Flexible(
                                              fit: FlexFit.loose,
                                              child: Row(
                                                crossAxisAlignment: CrossAxisAlignment.center,
                                                mainAxisAlignment: MainAxisAlignment.start,
                                                children: <Widget>[
                                                  Padding(
                                                    padding: const EdgeInsets.all(5),
                                                    child: Tooltip(
                                                      message: audioMixerNames[mix.processId] ?? "",
                                                      child: audioMixerIcons.containsKey(mix.processId)
                                                          ? Image.memory(
                                                              audioMixerIcons[mix.processId]!,
                                                              width: 18,
                                                              gaplessPlayback: true,
                                                            )
                                                          : const Icon(Icons.audiotrack, size: 18),
                                                    ),
                                                  ),
                                                  Flexible(
                                                    fit: FlexFit.loose,
                                                    child: Stack(
                                                      children: <Widget>[
                                                        Container(
                                                          height: 20,
                                                          child: SliderTheme(
                                                            data: SliderTheme.of(context).copyWith(
                                                                thumbShape: const RoundSliderThumbShape(
                                                                  enabledThumbRadius: 4.0,
                                                                  elevation: 0,
                                                                ),
                                                                overlayShape: SliderComponentShape.noOverlay),
                                                            child: Slider(
                                                              value: mix.maxVolume,
                                                              min: 0,
                                                              max: 1,
                                                              divisions: 25,
                                                              onChanged: (double e) {
                                                                Audio.setAudioMixerVolume(mix.processId, e);
                                                                mix.maxVolume = e;
                                                                setState(() {});
                                                              },
                                                            ),
                                                          ),
                                                        ),
                                                        Positioned(
                                                          top: 6,
                                                          child: SliderTheme(
                                                            data: SliderTheme.of(context).copyWith(
                                                                // activeTrackColor: Colors.white,
                                                                thumbShape: const RoundSliderThumbShape(
                                                                  enabledThumbRadius: 4.0,
                                                                  elevation: 0,
                                                                ),
                                                                overlayShape: SliderComponentShape.noOverlay),
                                                            child: IgnorePointer(
                                                              child: Slider(
                                                                value: (mix.peakVolume * mix.maxVolume).clamp(0, 0.9),
                                                                min: 0,
                                                                max: 1,

                                                                // divisions: 25,
                                                                activeColor: Colors.blue.shade800,
                                                                inactiveColor: Colors.transparent,
                                                                thumbColor: Colors.transparent,
                                                                onChanged: (double e) {
                                                                  Audio.setAudioMixerVolume(mix.processId, e);
                                                                  mix.maxVolume = e;
                                                                  setState(() {});
                                                                },
                                                              ),
                                                            ),
                                                          ),
                                                        ),
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
