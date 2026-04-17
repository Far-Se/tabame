import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';
import '../../models/util/app_opacity.dart';
import '../../models/win32/win32.dart';
import '../../pages/interface.dart';
import 'interface_quickmenu.dart';

class AudioInterface extends StatefulWidget {
  const AudioInterface({super.key});
  @override
  AudioInterfaceState createState() => AudioInterfaceState();
}

class AudioInterfaceState extends State<AudioInterface> {
  final Color _accent = Color(globalSettings.themeColors.accentColor);

  void setVolumeOSDStyle(VolumeOSDStyle? value) async {
    globalSettings.volumeOSDStyle = value ?? VolumeOSDStyle.normal;
    WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.normal, applyStyle: true);
    WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
    await Boxes.updateSettings("volumeOSDStyle", globalSettings.volumeOSDStyle.index);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 80),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          // Page Header
          Padding(
            padding: const EdgeInsets.only(bottom: 24),
            child: Row(
              children: <Widget>[
                Icon(Icons.volume_up_rounded, size: 28, color: _accent),
                const SizedBox(width: 12),
                Text(
                  "Audio & Sound",
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        letterSpacing: -0.5,
                      ),
                ),
              ],
            ),
          ),

          if (!Audio.canRunAudioModule)
            _buildWarningCard(context, "Audio Module unavailable on this Windows install. Investigating..."),

          // --- Default Device Targeting ---
          _buildSectionCard(
            context,
            "Default Device Targeting",
            Icons.speaker_group_rounded,
            <Widget>[
              _buildSwitchTile(
                "Multimedia",
                globalSettings.audioMultimedia,
                (bool v) {
                  globalSettings.audioMultimedia = v;
                  Boxes.updateSettings("audio", globalSettings.audio);
                  setState(() {});
                },
              ),
              _buildSwitchTile(
                "Console",
                globalSettings.audioConsole,
                (bool v) {
                  globalSettings.audioConsole = v;
                  Boxes.updateSettings("audio", globalSettings.audio);
                  setState(() {});
                },
              ),
              _buildSwitchTile(
                "Communications",
                globalSettings.audioCommunications,
                (bool v) {
                  globalSettings.audioCommunications = v;
                  Boxes.updateSettings("audio", globalSettings.audio);
                  setState(() {});
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // --- Create custom Quick Action for Media players ---
          _buildSectionCard(
            context,
            "Custom Media Controls",
            Icons.ads_click_rounded,
            <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    Text(
                      "Need specialized controls for non-standard media players? Create isolated interfaces with custom hotkeys.",
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                    const SizedBox(height: 12),
                    FilledButton.icon(
                      onPressed: () {
                        final InterfaceState? state = context.findAncestorStateOfType<InterfaceState>();
                        if (state != null) {
                          QuickmenuSettings.pendingPage = 7; // App Audio index in QuickmenuSettings
                          final int qmIndex =
                              state.pages.indexWhere((PageClass p) => p.title?.toLowerCase() == "quickmenu");
                          state.setState(() {
                            state.currentPage = qmIndex != -1 ? qmIndex : 4;
                          });
                        }
                      },
                      icon: const Icon(Icons.settings_input_component_rounded, size: 18),
                      label: const Text("Create custom Quick Action for Media players"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),

          const SizedBox(height: 16),

          // --- Music Integration ---
          _buildSectionCard(
            context,
            "Music App Behavior (Spotify)",
            Icons.music_note_rounded,
            <Widget>[
              _buildSwitchTile(
                "Pause Spotify on other sounds",
                globalSettings.pauseSpotifyWhenNewSound,
                (bool v) {
                  globalSettings.pauseSpotifyWhenNewSound = v;
                  Boxes.updateSettings("pauseSpotifyWhenNewSound", v);
                  setState(() {});
                },
              ),
              _buildSwitchTile(
                "Pause Spotify when another app is focused",
                globalSettings.pauseSpotifyWhenPlaying,
                (bool v) {
                  globalSettings.pauseSpotifyWhenPlaying = v;
                  Boxes.updateSettings("pauseSpotifyWhenPlaying", v);
                  setState(() {});
                },
              ),
            ],
          ),

          const SizedBox(height: 16),

          // --- QuickMenu Media Control ---
          _buildSectionCard(
            context,
            "QuickMenu Integration",
            Icons.dashboard_customize_rounded,
            <Widget>[
              _buildSwitchTile(
                "Show Media Control for each App",
                globalSettings.showMediaControlForApp,
                (bool v) async {
                  globalSettings.showMediaControlForApp = v;
                  await Boxes.updateSettings("showMediaControlForApp", v);
                  setState(() {});
                },
              ),
              if (globalSettings.showMediaControlForApp)
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: TextField(
                    decoration: _modernInputDecoration(
                      context,
                      "Predefined Media apps (e.g. Spotify, MusicBee)",
                      _accent,
                      Icons.app_registration_rounded,
                    ),
                    controller: TextEditingController(text: Boxes.mediaControls.join(", ")),
                    onSubmitted: (String e) {
                      if (e.trim().isEmpty) {
                        Boxes.mediaControls = <String>[];
                      } else {
                        Boxes.mediaControls =
                            e.split(",").map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList();
                      }
                      Boxes.updateSettings("mediaControls", Boxes.mediaControls);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Media apps saved")));
                      setState(() {});
                    },
                  ),
                ),
            ],
          ),

          const SizedBox(height: 16),

          // --- Volume OSD (Win 10 Only) ---
          if (globalSettings.isWindows10)
            _buildSectionCard(
              context,
              "Volume OSD Style (Win 10)",
              Icons.visibility_off_rounded,
              <Widget>[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: RadioGroup<VolumeOSDStyle>(
                    groupValue: globalSettings.volumeOSDStyle,
                    onChanged: setVolumeOSDStyle,
                    child: Column(
                      children: <Widget>[
                        _buildRadioTile("Normal Volume OSD", VolumeOSDStyle.normal),
                        _buildRadioTile("Hide Media Only", VolumeOSDStyle.media),
                        _buildRadioTile("Modern/Thin Style", VolumeOSDStyle.thin),
                        _buildRadioTile("Completely Hidden", VolumeOSDStyle.visible),
                      ],
                    ),
                  ),
                ),
              ],
            ),

          const SizedBox(height: 16),

          // --- Automated Volume Rules ---
          _AutomatedVolumeCard(accent: _accent),
        ],
      ),
    );
  }

  Widget _buildSectionCard(BuildContext context, String title, IconData icon, List<Widget> children) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: AppOpacity.surfaceOverlay),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _accent.withValues(alpha: AppOpacity.border), width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: Colors.black.withValues(alpha: AppOpacity.subtle), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: <Widget>[
                Icon(icon, size: 20, color: _accent),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ],
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  Widget _buildSwitchTile(String title, bool value, ValueChanged<bool> onChanged) {
    return SwitchListTile(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: value,
      onChanged: onChanged,
      activeThumbColor: _accent,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
    );
  }

  Widget _buildRadioTile(String title, VolumeOSDStyle style) {
    return RadioListTile<VolumeOSDStyle>(
      title: Text(title, style: const TextStyle(fontSize: 14)),
      value: style,
      activeColor: _accent,
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildWarningCard(BuildContext context, String msg) {
    return Container(
      margin: const EdgeInsets.only(bottom: 20),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer.withValues(alpha: AppOpacity.accentFaint),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Theme.of(context).colorScheme.error.withValues(alpha: AppOpacity.surfaceOverlay)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: Theme.of(context).colorScheme.error),
          const SizedBox(width: 12),
          Expanded(child: Text(msg, style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer))),
        ],
      ),
    );
  }

  InputDecoration _modernInputDecoration(BuildContext context, String label, Color accent, IconData? icon) {
    return InputDecoration(
      labelText: label,
      hintText: label,
      prefixIcon: icon != null ? Icon(icon, size: 18, color: accent) : null,
      filled: true,
      fillColor: accent.withValues(alpha: AppOpacity.subtle),
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent.withValues(alpha: AppOpacity.border), width: 1)),
      focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10), borderSide: BorderSide(color: accent, width: 1.5)),
      contentPadding: EdgeInsets.symmetric(horizontal: icon != null ? 0 : 16, vertical: 14),
      labelStyle: TextStyle(
          fontSize: 13, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: AppOpacity.textSecondary)),
    );
  }
}

class _AutomatedVolumeCard extends StatefulWidget {
  const _AutomatedVolumeCard({required this.accent});
  final Color accent;

  @override
  State<_AutomatedVolumeCard> createState() => _AutomatedVolumeCardState();
}

class _AutomatedVolumeCardState extends State<_AutomatedVolumeCard> {
  final List<DefaultVolume> volumes = Boxes.defaultVolume;

  @override
  Widget build(BuildContext context) {
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: AppOpacity.surfaceOverlay),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: widget.accent.withValues(alpha: AppOpacity.border), width: 1),
        boxShadow: <BoxShadow>[
          BoxShadow(
              color: Colors.black.withValues(alpha: AppOpacity.subtle), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Icon(Icons.auto_awesome_rounded, size: 20, color: widget.accent),
                    const SizedBox(width: 8),
                    const Text("App Volume Rules", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ],
                ),
                TextButton.icon(
                  onPressed: () {
                    volumes.add(DefaultVolume(type: "exe", match: "rocket.exe", volume: 20));
                    Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
                    setState(() {});
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text("Add Rule"),
                  style: TextButton.styleFrom(foregroundColor: widget.accent),
                ),
              ],
            ),
          ),
          SwitchListTile(
            title: const Text("Restore volume when app loses focus", style: TextStyle(fontSize: 13)),
            value: globalSettings.volumeSetBack,
            onChanged: (bool v) {
              globalSettings.volumeSetBack = v;
              Boxes.updateSettings("volumeSetBack", v);
              setState(() {});
            },
            activeThumbColor: widget.accent,
            dense: true,
          ),
          const Divider(height: 1),
          if (volumes.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24.0),
              child: Center(
                  child: Text("No automated rules yet.",
                      style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey))),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: volumes.length,
              separatorBuilder: (BuildContext ctx, int idx) => const Divider(height: 1),
              itemBuilder: (BuildContext ctx, int index) {
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  child: Row(
                    children: <Widget>[
                      // Match Type
                      SizedBox(
                        width: 100,
                        child: DropdownButtonFormField<String>(
                          initialValue: volumes[index].type,
                          decoration: _miniDecoration("Match By"),
                          style: TextStyle(fontSize: 12, color: onSurface, fontWeight: FontWeight.bold),
                          items: const <DropdownMenuItem<String>>[
                            DropdownMenuItem<String>(value: "exe", child: Text("EXE File")),
                            DropdownMenuItem<String>(value: "class", child: Text("Win Class")),
                            DropdownMenuItem<String>(value: "title", child: Text("Win Title")),
                          ],
                          onChanged: (String? v) {
                            if (v != null) {
                              volumes[index].type = v;
                              Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
                              setState(() {});
                            }
                          },
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Regex Match
                      Expanded(
                        child: TextField(
                          onChanged: (String v) {
                            if (v.trim().isEmpty) return;
                            volumes[index].match = v;
                            Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
                          },
                          decoration: _miniDecoration("Match (Regex)").copyWith(hintText: "^Spotify.*"),
                          style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
                          controller: TextEditingController(text: volumes[index].match),
                        ),
                      ),
                      const SizedBox(width: 12),
                      // Volume
                      SizedBox(
                        width: 70,
                        child: TextField(
                          keyboardType: TextInputType.number,
                          onChanged: (String v) {
                            final int? val = int.tryParse(v);
                            if (val != null && val >= 0 && val <= 100) {
                              volumes[index].volume = val;
                              Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
                            }
                          },
                          decoration: _miniDecoration("Vol").copyWith(suffixText: "%"),
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                          controller: TextEditingController(text: volumes[index].volume.toString()),
                        ),
                      ),
                      const SizedBox(width: 4),
                      IconButton(
                        onPressed: () {
                          volumes.removeAt(index);
                          Boxes.updateSettings("defaultVolume", jsonEncode(volumes));
                          setState(() {});
                        },
                        icon: const Icon(Icons.delete_sweep_rounded, size: 20, color: Colors.grey),
                        splashRadius: 24,
                        tooltip: "Remove rule",
                      )
                    ],
                  ),
                );
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  InputDecoration _miniDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: const TextStyle(fontSize: 11),
    );
  }
}
