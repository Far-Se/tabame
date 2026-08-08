import 'dart:async';

import 'package:flutter/material.dart';

import '../../../platform/audio_system_service.dart';
import '../../../models/globals.dart';
import '../../../models/settings.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/extracted_icon.dart';
import '../../widgets/panel_header.dart';

class AudioBox extends StatefulWidget {
  const AudioBox({super.key});

  @override
  AudioBoxState createState() => AudioBoxState();
}

class AudioInfo {
  List<PlatformAudioDevice> devices = <PlatformAudioDevice>[];
  PlatformAudioDevice? defaultDevice;
  Map<String, double> deviceVolumes = <String, double>{};
  bool isMuted = false;
  double volume = 0.0;
}

class AudioBoxState extends State<AudioBox> {
  final AudioInfo audioInfo = AudioInfo();
  final AudioInfo micInfo = AudioInfo();
  Timer? timerData;
  Timer? timerMixer;
  List<PlatformAudioProcess> audioMixer = <PlatformAudioProcess>[];
  Map<String, Object?> audioMixerIcons = <String, Object?>{};
  Map<String, String> audioMixerNames = <String, String>{};

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
    final AudioSystemService service = AudioSystemService.instance;
    if (!await service.initialize()) {
      if (mounted) setState(() {});
      return;
    }
    final AudioOrchestrator orchestrator = AudioOrchestrator(service: service);
    final AudioEndpointSnapshot output = await orchestrator.readEndpoint(AudioDeviceType.output);
    final AudioEndpointSnapshot input = await orchestrator.readEndpoint(AudioDeviceType.input);
    _applyEndpoint(audioInfo, output);
    _applyEndpoint(micInfo, input);
    if (mounted) setState(() {});
  }

  void _applyEndpoint(AudioInfo info, AudioEndpointSnapshot snapshot) {
    info
      ..devices = snapshot.devices
      ..defaultDevice = snapshot.defaultDevice
      ..deviceVolumes = snapshot.deviceVolumes
      ..isMuted = snapshot.isMuted
      ..volume = snapshot.volume;
  }

  Future<void> fetchAudioMixerData({bool onlyMetadata = false}) async {
    final AudioSystemService service = AudioSystemService.instance;
    if (!service.isAvailable || !service.supportsPerProcessAudio) {
      if (audioMixer.isNotEmpty || audioMixerNames.isNotEmpty) {
        audioMixer = <PlatformAudioProcess>[];
        audioMixerNames.clear();
        audioMixerIcons.clear();
        if (mounted) setState(() {});
      }
      return;
    }
    final List<PlatformAudioProcess> newData = await service.listProcesses();

    for (final PlatformAudioProcess process in newData) {
      audioMixerNames[process.id] = process.displayName;
      audioMixerIcons[process.id] = process.iconBytes;
    }
    if (onlyMetadata) {
      if (mounted) setState(() {});
      return;
    }

    bool changed = newData.length != audioMixer.length;
    if (!changed) {
      for (int i = 0; i < newData.length; i++) {
        if (newData[i].id != audioMixer[i].id ||
            (newData[i].peakVolume - audioMixer[i].peakVolume).abs() > 0.02 ||
            (newData[i].volume - audioMixer[i].volume).abs() > 0.02) {
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
    final AudioSystemService service = AudioSystemService.instance;
    if (!service.isAvailable) {
      return Padding(
        padding: const EdgeInsets.all(18),
        child: Text(service.unavailableReason),
      );
    }
    if (audioInfo.devices.isEmpty && micInfo.devices.isEmpty && audioMixer.isEmpty) {
      return const SizedBox.shrink();
    }

    final ThemeData theme = Theme.of(context);
    final Color accent = Design.accent;
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
              if (service.supportsSystemSettings)
                IconButton(
                  onPressed: () async {
                    await service.openSystemSettings();
                    if (context.mounted) Navigator.pop(context);
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
                    onTap: () async {
                      await AudioOrchestrator(service: AudioSystemService.instance).toggleMute(type);
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
    required PlatformAudioDevice device,
    required AudioInfo info,
    required Color accent,
    required Color onSurface,
  }) {
    final bool isSelected = device.id == info.defaultDevice?.id;
    final String actionText = isSelected ? "Current Default" : "Set as Default";
    final String deviceType = info == micInfo ? "Microphone" : "Speaker";

    return CustomTooltip(
        message: "$actionText $deviceType",
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(9),
            onTap: () async {
              await AudioSystemService.instance.setDefaultDevice(
                info == micInfo ? AudioDeviceType.input : AudioDeviceType.output,
                device.id,
                targeting: AudioDeviceTargeting(
                  console: user.audioConsole,
                  multimedia: user.audioMultimedia,
                  communications: user.audioCommunications,
                ),
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
                          device.iconBytes,
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
                          AudioOrchestrator(service: AudioSystemService.instance).setDeviceVolume(
                            info == micInfo ? AudioDeviceType.input : AudioDeviceType.output,
                            device.id,
                            val,
                          );
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
    required PlatformAudioProcess mix,
    required Color accent,
    required Color onSurface,
  }) {
    final String name = audioMixerNames[mix.id] ?? mix.displayName;

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
              onTap: AudioSystemService.instance.supportsMixerSettings
                  ? () => AudioSystemService.instance.openMixerSettings()
                  : null,
              borderRadius: BorderRadius.circular(4),
              child: Container(
                padding: const EdgeInsets.all(4), // Expanded hit area
                width: 26,
                child: buildExtractedIcon(
                  audioMixerIcons[mix.id],
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
                            AudioSystemService.instance.setProcessVolume(mix.id, e);
                            audioMixer = audioMixer
                                .map((PlatformAudioProcess process) =>
                                    process.id == mix.id ? process.copyWith(volume: e) : process)
                                .toList(growable: false);
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
