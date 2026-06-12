import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win32.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/extracted_icon.dart';
import '../../widgets/panel_header.dart';

class AudioBox extends StatefulWidget {
  const AudioBox({super.key});

  @override
  AudioBoxState createState() => AudioBoxState();
}

class AudioInfo {
  List<AudioDevice> devices = <AudioDevice>[];
  AudioDevice defaultDevice = AudioDevice();
  Map<String, ExtractedIcon> icons = <String, ExtractedIcon>{};
  Map<String, double> deviceVolumes = <String, double>{};
  bool isMuted = false;
  double volume = 0.0;
}

class AudioBoxState extends State<AudioBox> {
  final AudioInfo audioInfo = AudioInfo();
  final AudioInfo micInfo = AudioInfo();
  Timer? timerData;
  Timer? timerMixer;
  List<ProcessVolume> audioMixer = <ProcessVolume>[];
  Map<int, ExtractedIcon> audioMixerIcons = <int, ExtractedIcon>{};
  Map<int, String> audioMixerNames = <int, String>{};

  @override
  void initState() {
    super.initState();
    init();
  }

  void init() {
    if (timerMixer != null) timerMixer?.cancel();
    if (timerData != null) timerData?.cancel();

    fetchData();
    fetchAudioMixerData();
    timerData = Timer.periodic(const Duration(milliseconds: 1500), (Timer timer) {
      if (Globals.audioBoxVisible) {
        fetchData();
        fetchAudioMixerData(onlyMetadata: true);
      }
    });
    timerMixer = Timer.periodic(const Duration(milliseconds: 250), (Timer timer) {
      if (Globals.audioBoxVisible) fetchAudioMixerData(onlyMetadata: false);
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
        inputType.deviceVolumes[device.id] = await Audio.getAudioDeviceVolume(device.id);
        if (inputType.icons.containsKey(device.id)) continue;
        inputType.icons[device.id] = WinUtils.extractIcon(device.iconPath, iconID: device.iconID)!;
        //inputType.icons[device.id] = (await getExecutableIcon(device.iconPath, iconID: device.iconID))!;
      }
    }
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> fetchAudioMixerData({bool onlyMetadata = false}) async {
    final List<ProcessVolume> newData = await Audio.enumAudioMixer() ?? <ProcessVolume>[];

    if (onlyMetadata) {
      bool addedAny = false;
      for (ProcessVolume device in newData) {
        // if (audioMixerIcons.containsKey(device.processId)) continue;
        addedAny = true;
        ExtractedIcon icon;
        final int hWnd = await findTopWindow(device.processId);
        if (hWnd == 0) {
          final ExtractedIcon fallbackIcon = WinUtils.extractIcon(device.processPath);
          if (fallbackIcon != null) {
            audioMixerIcons[device.processId] = fallbackIcon;
          }
          audioMixerNames[device.processId] = Win32.extractFileNameFromPath(device.processPath).toUpperCaseFirst();
          continue;
        }
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
      if (addedAny && mounted) setState(() {});
      return;
    }

    // Peak volume updates - check for changes before setState
    bool changed = newData.length != audioMixer.length;
    if (!changed) {
      for (int i = 0; i < newData.length; i++) {
        if ((newData[i].peakVolume - audioMixer[i].peakVolume).abs() > 0.02 ||
            (newData[i].maxVolume - audioMixer[i].maxVolume).abs() > 0.02) {
          changed = true;
          break;
        }
      }
    }

    if (changed) {
      audioMixer = newData;
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    if (audioInfo.devices.isEmpty && micInfo.devices.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = theme.colorScheme.onSurface;
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
            title: "Audio Settings",
            icon: Icons.volume_up_rounded,
            extraActions: <Widget>[
              IconButton(
                onPressed: () {
                  WinUtils.runPowerShell(<String>["mmsys.cpl"]);
                  Navigator.pop(context);
                },
                icon: const Icon(Icons.settings_applications_outlined),
              ),
            ],
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
          label.toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize + 0.5,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.7,
            color: onSurface.withAlpha(220),
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
              fontSize: Design.baseFontSize,
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
              Icon(typeIcon, size: 14, color: accent),
              const SizedBox(width: 6),
              Text(
                type == AudioDeviceType.output ? "OUTPUT" : "INPUT",
                style: TextStyle(
                  fontSize: Design.baseFontSize + 0.5,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.7,
                  color: onSurface.withAlpha(220),
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: accent.withAlpha(28),
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  "${info.devices.length}",
                  style: TextStyle(
                    fontSize: Design.baseFontSize,
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
              const SizedBox(width: 8),
              CustomTooltip(
                message: info.isMuted
                    ? "Unmute ${isInput ? 'Microphone' : 'Output'}"
                    : "Mute ${isInput ? 'Microphone' : 'Output'}",
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    borderRadius: BorderRadius.circular(8),
                    onTap: () {
                      Audio.setMuteAudioDevice(!info.isMuted, type);
                      info.isMuted = !info.isMuted;
                      fetchData();
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: info.isMuted ? Colors.red.withAlpha(30) : accent.withAlpha(16),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: info.isMuted ? Colors.redAccent.withAlpha(100) : accent.withAlpha(40),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        info.isMuted
                            ? Icons.volume_off_rounded
                            : (isInput ? Icons.mic_rounded : Icons.volume_up_rounded),
                        size: 14,
                        color: info.isMuted ? Colors.redAccent : accent,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 160),
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
    final String actionText = isSelected ? "Current Default" : "Set as Default";
    final String deviceType = info == micInfo ? "Microphone" : "Speaker";

    return CustomTooltip(
        message: "$actionText $deviceType",
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () {
              Audio.setDefaultDevice(
                device.id,
                console: userSettings.audioConsole,
                multimedia: userSettings.audioMultimedia,
                communications: userSettings.audioCommunications,
              );
              fetchData();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 140),
              curve: Curves.easeOut,
              padding: const EdgeInsets.fromLTRB(8, 6, 8, 4),
              decoration: BoxDecoration(
                color: isSelected ? accent.withAlpha(14) : onSurface.withAlpha(6),
                borderRadius: BorderRadius.circular(9),
                border: Border.all(
                  color: isSelected ? accent.withAlpha(50) : onSurface.withAlpha(10),
                  width: 1,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      SizedBox(
                        width: 20,
                        child: buildExtractedIcon(
                          info.icons[device.id],
                          width: 20,
                          gaplessPlayback: true,
                          errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => Icon(
                            Icons.audiotrack_rounded,
                            size: 14,
                            color: onSurface.withAlpha(120),
                          ),
                          fallback: Icon(
                            Icons.audiotrack_rounded,
                            size: 14,
                            color: onSurface.withAlpha(120),
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          device.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: Design.baseFontSize + 0.5,
                            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                            letterSpacing: 0.2,
                            color: onSurface.withAlpha(isSelected ? 255 : 200),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      if (isSelected)
                        Icon(
                          Icons.check_rounded,
                          size: 13,
                          color: accent,
                        ),
                      const SizedBox(width: 6),
                      Text(
                        "${((info.deviceVolumes[device.id] ?? 0.0) * 100).round()}%",
                        style: TextStyle(
                          fontSize: Design.baseFontSize,
                          fontWeight: FontWeight.w700,
                          fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                          color: isSelected ? accent.withAlpha(220) : onSurface.withAlpha(160),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  SizedBox(
                    height: 24,
                    child: SliderTheme(
                      data: SliderTheme.of(context).copyWith(
                        trackHeight: 1.5,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 3),
                        overlayShape: SliderComponentShape.noOverlay,
                        activeTrackColor: isSelected ? accent : onSurface.withAlpha(100),
                        inactiveTrackColor: isSelected ? accent.withAlpha(30) : onSurface.withAlpha(30),
                        thumbColor: isSelected ? accent : onSurface.withAlpha(150),
                      ),
                      child: Slider(
                        value: (info.deviceVolumes[device.id] ?? 0.0).clamp(0, 1),
                        onChanged: (double val) {
                          Audio.setAudioDeviceVolume(device.id, val);
                          info.deviceVolumes[device.id] = val;
                          setState(() {});
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ));
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
          CustomTooltip(
            message: "Open Volume Mixer Settings",
            child: InkWell(
              onTap: () => Win32.shellOpen("ms-settings:apps-volume"),
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(4), // Expanded hit area
                width: 26,
                child: buildExtractedIcon(
                  audioMixerIcons[mix.processId],
                  width: 22,
                  gaplessPlayback: true,
                  errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => Icon(
                    Icons.audiotrack_rounded,
                    size: 16,
                    color: onSurface.withAlpha(150),
                  ),
                  fallback: Icon(
                    Icons.audiotrack_rounded,
                    size: 16,
                    color: onSurface.withAlpha(150),
                  ),
                ),
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
                          fontSize: Design.baseFontSize + 0.5,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: onSurface.withAlpha(220),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      "${(mix.maxVolume * 100).round()}%",
                      style: TextStyle(
                        fontSize: Design.baseFontSize,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const <FontFeature>[FontFeature.tabularFigures()],
                        color: onSurface.withAlpha(180),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Stack(
                  children: <Widget>[
                    SizedBox(
                      height: 12,
                      child: SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 2,
                          thumbShape: const RoundSliderThumbShape(
                            enabledThumbRadius: 4.0,
                            elevation: 0,
                          ),
                          overlayShape: SliderComponentShape.noOverlay,
                        ),
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
                      bottom: 4,
                      left: 2,
                      right: 0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(1),
                        child: _AnimatedPeakProgressIndicator(
                          value: (mix.peakVolume * mix.maxVolume).clamp(0, 1),
                          backgroundColor: onSurface.withAlpha(10),
                          color: (mix.peakVolume > 0.8) ? Colors.orangeAccent : Colors.blue,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _AnimatedPeakProgressIndicator extends StatelessWidget {
  const _AnimatedPeakProgressIndicator({
    required this.value,
    required this.backgroundColor,
    required this.color,
  });

  final double value;
  final Color backgroundColor;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(end: value),
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      builder: (BuildContext context, double animatedValue, Widget? child) {
        return LinearProgressIndicator(
          value: animatedValue,
          backgroundColor: backgroundColor,
          valueColor: AlwaysStoppedAnimation<Color>(color),
        );
      },
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
