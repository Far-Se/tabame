import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../widgets/panel_header.dart';

class AudioBox extends StatefulWidget {
  const AudioBox({super.key});

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
    // PaintingBinding.instance.imageCache.maximumSizeBytes = 1024 * 1024 * 10;
    if (timerMixer != null) timerMixer?.cancel();
    if (timerData != null) timerData?.cancel();

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
    if (audioInfo.devices.isNotEmpty) {
      audioInfo.defaultDevice = await Audio.getDefaultDevice(AudioDeviceType.output) ?? AudioDevice();
      audioInfo.isMuted = await Audio.getMuteAudioDevice(AudioDeviceType.output);
      audioInfo.volume = await Audio.getVolume(AudioDeviceType.output);
    }
    micInfo.devices = await Audio.enumDevices(AudioDeviceType.input) ?? <AudioDevice>[];
    if (micInfo.devices.isNotEmpty) {
      micInfo.defaultDevice = await Audio.getDefaultDevice(AudioDeviceType.input) ?? AudioDevice();
      micInfo.isMuted = await Audio.getMuteAudioDevice(AudioDeviceType.input);
      micInfo.volume = await Audio.getVolume(AudioDeviceType.input);
    }

    for (AudioInfo inputType in <AudioInfo>[audioInfo, micInfo]) {
      for (AudioDevice device in inputType.devices) {
        if (inputType.icons.containsKey(device.id)) continue;
        inputType.icons[device.id] = WinUtils.extractIcon(device.iconPath, iconID: device.iconID)!;
        //inputType.icons[device.id] = (await getExecutableIcon(device.iconPath, iconID: device.iconID))!;
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
        audioMixerIcons[device.processId] = WinUtils.extractIcon(device.processPath)!;
        audioMixerNames[device.processId] = Win32.extractFileNameFromPath(device.processPath).toUpperCaseFirst();
        continue;
      }
      //? Fancy Way
      final HwndInfo processPath = HwndPath.getFullPath(hWnd);
      if (processPath.isAppx) {
        final String appxLogo = Win32.getManifestIcon(processPath.path);
        if (File(appxLogo).existsSync()) {
          icon = File(appxLogo).readAsBytesSync();
        } else {
          icon = WinUtils.extractIcon(device.processPath);
        }
      } else {
        icon = WinUtils.extractIcon(processPath.path);
      }
      audioMixerIcons[device.processId] = icon!;
      audioMixerNames[device.processId] = Win32.extractFileNameFromPath(processPath.path).toUpperCaseFirst();
    }

    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (audioInfo.devices.isEmpty && micInfo.devices.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final Color accent = Color(globalSettings.themeColors.accentColor);
    final Color onSurface = theme.colorScheme.onSurface;
    final bool boldFont = globalSettings.theme.quickMenuBoldFont;
    final List<Widget> audioCards = <Widget>[
      if (audioInfo.devices.isNotEmpty)
        _buildDeviceCard(
          context: context,
          type: AudioDeviceType.output,
          info: audioInfo,
          accent: accent,
          onSurface: onSurface,
        ),
      if (audioInfo.devices.isNotEmpty && micInfo.devices.isNotEmpty) const SizedBox(height: 8),
      if (micInfo.devices.isNotEmpty)
        _buildDeviceCard(
          context: context,
          type: AudioDeviceType.input,
          info: micInfo,
          accent: accent,
          onSurface: onSurface,
        ),
    ];

    return Material(
      type: MaterialType.transparency,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          PanelHeader(
            title: "Audio",
            accent: accent,
            boldFont: boldFont,
            icon: Icons.volume_up_rounded,
            buttonPressed: () {
              WinUtils.runPowerShell(<String>["mmsys.cpl"]);
              Navigator.pop(context);
            },
            buttonIcon: Icons.tune_rounded,
          ),
          Flexible(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackShape: CustomTrackShape(),
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(
                  enabledThumbRadius: 5,
                  elevation: 0,
                  pressedElevation: 0,
                ),
                overlayShape: SliderComponentShape.noOverlay,
              ),
              child: SingleChildScrollView(
                controller: ScrollController(),
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    ...audioCards,
                    if (audioMixer.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 8),
                      _buildSectionLabel(
                        label: "Mixer",
                        accent: accent,
                        onSurface: onSurface,
                        count: audioMixer.length,
                        icon: Icons.equalizer_rounded,
                      ),
                      const SizedBox(height: 6),
                      Container(
                        constraints: const BoxConstraints(maxHeight: 118),
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: onSurface.withAlpha(8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: onSurface.withAlpha(16)),
                        ),
                        child: ScrollbarTheme(
                          data: theme.scrollbarTheme.copyWith(
                            thumbVisibility: WidgetStateProperty.all<bool>(true),
                            trackVisibility: WidgetStateProperty.all<bool>(false),
                          ),
                          child: SingleChildScrollView(
                            controller: ScrollController(),
                            child: Column(
                              children: <Widget>[
                                for (int i = 0; i < audioMixer.length; i++) ...<Widget>[
                                  _buildMixerRow(
                                    context: context,
                                    mix: audioMixer[i],
                                    accent: accent,
                                    onSurface: onSurface,
                                  ),
                                  if (i < audioMixer.length - 1) const SizedBox(height: 4),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionLabel({
    required String label,
    required Color accent,
    required Color onSurface,
    required int count,
    required IconData icon,
  }) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: accent),
        const SizedBox(width: 6),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.45,
            color: onSurface,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: accent.withAlpha(28),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            "$count",
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: accent.withAlpha(200),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Divider(
            height: 1,
            thickness: 1,
            color: onSurface.withAlpha(18),
          ),
        ),
      ],
    );
  }

  Widget _buildDeviceCard({
    required BuildContext context,
    required AudioDeviceType type,
    required AudioInfo info,
    required Color accent,
    required Color onSurface,
  }) {
    final bool isInput = type == AudioDeviceType.input;
    final IconData typeIcon = isInput ? Icons.mic_rounded : Icons.speaker_rounded;
    final String volumeLabel = "${(info.volume * 100).round()}%";

    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withAlpha(16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: accent.withAlpha(20),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(typeIcon, size: 14, color: accent),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: <Widget>[
                    Text(
                      type.name.toUpperCase(),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.55,
                        color: accent.withAlpha(220),
                      ),
                    ),
                    Text(
                      info.defaultDevice.name.isEmpty ? "No device selected" : info.defaultDevice.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: onSurface.withAlpha(160),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              Text(
                volumeLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: onSurface.withAlpha(190),
                ),
              ),
              const SizedBox(width: 6),
              Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () {
                    Audio.setMuteAudioDevice(!info.isMuted, type);
                    info.isMuted = !info.isMuted;
                    fetchData();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(5),
                    decoration: BoxDecoration(
                      color: info.isMuted ? Colors.red.withAlpha(22) : accent.withAlpha(14),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      info.isMuted ? Icons.volume_off_rounded : (isInput ? Icons.mic_rounded : Icons.volume_up_rounded),
                      size: 14,
                      color: info.isMuted ? Colors.redAccent : accent,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 20,
            child: Slider(
              value: info.volume.clamp(0, 1),
              min: 0,
              max: 1,
              divisions: 25,
              onChanged: (double e) {
                Audio.setVolume(e, type);
                info.volume = e;
                setState(() {});
              },
            ),
          ),
          const SizedBox(height: 6),
          _buildSectionLabel(
            label: "Devices",
            accent: accent,
            onSurface: onSurface,
            count: info.devices.length,
            icon: Icons.headphones_rounded,
          ),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: SingleChildScrollView(
              controller: ScrollController(),
              child: Column(
                children: <Widget>[
                  for (int i = 0; i < info.devices.length; i++) ...<Widget>[
                    _buildDeviceRow(
                      device: info.devices[i],
                      info: info,
                      accent: accent,
                      onSurface: onSurface,
                    ),
                    if (i < info.devices.length - 1) const SizedBox(height: 4),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDeviceRow({
    required AudioDevice device,
    required AudioInfo info,
    required Color accent,
    required Color onSurface,
  }) {
    final bool isSelected = device.id == info.defaultDevice.id;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(9),
        onTap: () {
          Audio.setDefaultDevice(
            device.id,
            console: globalSettings.audioConsole,
            multimedia: globalSettings.audioMultimedia,
            communications: globalSettings.audioCommunications,
          );
          fetchData();
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: isSelected ? accent.withAlpha(18) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: isSelected ? accent.withAlpha(70) : onSurface.withAlpha(12),
              width: 1,
            ),
          ),
          child: Row(
            children: <Widget>[
              SizedBox(
                width: 18,
                child: info.icons.containsKey(device.id)
                    ? Image.memory(
                        info.icons[device.id]!,
                        width: 18,
                        gaplessPlayback: true,
                        errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => Icon(
                          Icons.audiotrack_rounded,
                          size: 15,
                          color: onSurface.withAlpha(150),
                        ),
                      )
                    : Icon(
                        Icons.audiotrack_rounded,
                        size: 15,
                        color: onSurface.withAlpha(150),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  device.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                    color: onSurface,
                  ),
                ),
              ),
              const SizedBox(width: 6),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                opacity: isSelected ? 1 : 0,
                child: Icon(
                  Icons.check_rounded,
                  size: 15,
                  color: accent,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMixerRow({
    required BuildContext context,
    required ProcessVolume mix,
    required Color accent,
    required Color onSurface,
  }) {
    final String name =
        audioMixerNames[mix.processId] ?? Win32.extractFileNameFromPath(mix.processPath).toUpperCaseFirst();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: accent.withAlpha(8),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: <Widget>[
          Tooltip(
            message: name,
            child: SizedBox(
              width: 18,
              child: audioMixerIcons.containsKey(mix.processId)
                  ? Image.memory(
                      audioMixerIcons[mix.processId]!,
                      width: 18,
                      gaplessPlayback: true,
                      errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => Icon(
                        Icons.audiotrack_rounded,
                        size: 15,
                        color: onSurface.withAlpha(150),
                      ),
                    )
                  : Icon(
                      Icons.audiotrack_rounded,
                      size: 15,
                      color: onSurface.withAlpha(150),
                    ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Expanded(
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                          color: onSurface,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      "${(mix.maxVolume * 100).round()}%",
                      style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.w700,
                        color: onSurface.withAlpha(170),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                SizedBox(
                  height: 20,
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
                              if (e == 0.0) e = 0.001;
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
              ],
            ),
          ),
        ],
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
