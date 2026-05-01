import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:tabamewin32/tabamewin32.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/theme.dart';
import '../../../models/util/app_opacity.dart';
import '../../../models/win32/win_utils.dart';
import '../interface_quickmenu.dart';

class QuickmenuAudioSettingsPage extends StatefulWidget {
  const QuickmenuAudioSettingsPage({super.key});

  @override
  State<QuickmenuAudioSettingsPage> createState() => _QuickmenuAudioSettingsPageState();
}

class _QuickmenuAudioSettingsPageState extends State<QuickmenuAudioSettingsPage> {
  late final TextEditingController _mediaAppsController;
  Timer? _mediaAppsDebounce;
  bool _mediaAppsDirty = false;
  bool _mediaAppsSaving = false;
  String? _mediaAppsStatus;
  late List<DefaultVolume> _volumeRules;

  @override
  void initState() {
    super.initState();
    _mediaAppsController = TextEditingController(text: Boxes.mediaControls.join(', '));
    _mediaAppsController.addListener(_onMediaAppsChanged);
    _volumeRules = Boxes.defaultVolume;
  }

  @override
  void dispose() {
    _mediaAppsDebounce?.cancel();
    _mediaAppsController.removeListener(_onMediaAppsChanged);
    _mediaAppsController.dispose();
    super.dispose();
  }

  void _onMediaAppsChanged() {
    if (_mediaAppsSaving) return;
    _mediaAppsDirty = true;
    _mediaAppsDebounce?.cancel();
    _mediaAppsDebounce = Timer(const Duration(milliseconds: 450), _saveMediaApps);
    if (mounted) setState(() {});
  }

  Future<void> _saveMediaApps() async {
    if (!_mediaAppsDirty || _mediaAppsSaving) return;

    final List<String> apps = _parseMediaApps(_mediaAppsController.text);
    _mediaAppsSaving = true;
    _mediaAppsDirty = false;

    Boxes.mediaControls = apps;
    await Boxes.updateSettings('mediaControls', apps);

    if (!mounted) return;
    setState(() {
      _mediaAppsSaving = false;
      _mediaAppsStatus = apps.isEmpty ? 'Saved empty list' : 'Saved ${apps.length} app${apps.length == 1 ? '' : 's'}';
    });

    _mediaAppsDebounce?.cancel();
    _mediaAppsDebounce = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() => _mediaAppsStatus = null);
    });
  }

  List<String> _parseMediaApps(String raw) {
    return raw.split(',').map((String s) => s.trim()).where((String s) => s.isNotEmpty).toList(growable: false);
  }

  Future<void> _setVolumeOSDStyle(VolumeOSDStyle? value) async {
    globalSettings.volumeOSDStyle = value ?? VolumeOSDStyle.normal;
    WinUtils.setVolumeOSDStyle(type: VolumeOSDStyle.normal, applyStyle: true);
    WinUtils.setVolumeOSDStyle(type: globalSettings.volumeOSDStyle, applyStyle: true);
    await Boxes.updateSettings('volumeOSDStyle', globalSettings.volumeOSDStyle.index);
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildToggleSetting({
    required String title,
    required String subtitle,
    required bool value,
    required Future<void> Function(bool) onChanged,
  }) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    return InkWell(
      onTap: () => onChanged(!value),
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(title, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.60)),
                  ),
                ],
              ),
            ),
            Switch(
              value: value,
              onChanged: onChanged,
              activeThumbColor: theme.colorScheme.primary,
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required List<Widget> children,
  }) {
    final ThemeData theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(icon, size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.60),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.05)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMediaAppsField() {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    final Color accent = theme.colorScheme.primary;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text(
          'Predefined Media Apps',
          style: TextStyle(
            fontSize: 10,
            fontWeight: FontWeight.bold,
            letterSpacing: 1.1,
            color: accent.withValues(alpha: 0.65),
          ),
        ),
        const SizedBox(height: 10),
        TextField(
          controller: _mediaAppsController,
          onSubmitted: (_) => _saveMediaApps(),
          onEditingComplete: _saveMediaApps,
          decoration: InputDecoration(
            labelText: 'Play/Pause button will be always visible for',
            hintText: 'Spotify.exe, MusicBee.exe',
            helperText: 'Separate apps with commas. Example: Spotify.exe, MusicBee.exe, chrome.exe',
            helperMaxLines: 2,
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: onSurface.withValues(alpha: 0.12)),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: accent.withValues(alpha: 0.50)),
            ),
            filled: true,
            fillColor: theme.cardColor.withValues(alpha: 0.28),
            suffixIcon: _mediaAppsSaving
                ? const Padding(
                    padding: EdgeInsets.all(12),
                    child: SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : IconButton(
                    tooltip: 'Save media apps',
                    onPressed: _saveMediaApps,
                    icon: Icon(Icons.save_rounded, color: accent),
                  ),
          ),
          style: TextStyle(
            fontFamily: globalSettings.themeColors.entryFontFamily,
            fontWeight: AppTheme.getFontWeight(globalSettings.themeColors.entryFontWeight),
            fontStyle: globalSettings.themeColors.entryFontItalic ? FontStyle.italic : FontStyle.normal,
            fontSize: 14,
          ),
          minLines: 1,
          maxLines: 2,
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Icon(
              _mediaAppsDirty ? Icons.edit_rounded : Icons.check_circle_rounded,
              size: 14,
              color: _mediaAppsDirty ? accent : onSurface.withValues(alpha: 0.45),
            ),
            const SizedBox(width: 6),
            Text(
              _mediaAppsStatus ?? (_mediaAppsDirty ? 'Unsaved changes' : 'Saved'),
              style: TextStyle(fontSize: 11, color: onSurface.withValues(alpha: 0.55)),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTargetingCard() {
    return _buildCard(
      icon: Icons.speaker_group_rounded,
      title: 'Default Device Targeting',
      subtitle: 'Which Windows audio roles your actions should affect',
      children: <Widget>[
        _buildToggleSetting(
          title: 'Multimedia',
          subtitle: 'Apply volume and mute actions to the main playback device',
          value: globalSettings.audioMultimedia,
          onChanged: (bool value) async {
            globalSettings.audioMultimedia = value;
            await Boxes.updateSettings('audio', globalSettings.audio);
            if (mounted) setState(() {});
          },
        ),
        _buildToggleSetting(
          title: 'Console',
          subtitle: 'Include the system console role when changing volume',
          value: globalSettings.audioConsole,
          onChanged: (bool value) async {
            globalSettings.audioConsole = value;
            await Boxes.updateSettings('audio', globalSettings.audio);
            if (mounted) setState(() {});
          },
        ),
        _buildToggleSetting(
          title: 'Communications',
          subtitle: 'Include call-oriented devices in global audio actions',
          value: globalSettings.audioCommunications,
          onChanged: (bool value) async {
            globalSettings.audioCommunications = value;
            await Boxes.updateSettings('audio', globalSettings.audio);
            if (mounted) setState(() {});
          },
        ),
      ],
    );
  }

  Widget _buildMediaIntegrationCard() {
    return _buildCard(
      icon: Icons.graphic_eq_rounded,
      title: 'Media Integration',
      subtitle: 'QuickMenu media controls and custom player mapping',
      children: <Widget>[
        _buildToggleSetting(
          title: 'Show media control for each app',
          subtitle: 'Expose media controls directly from QuickMenu app entries',
          value: globalSettings.showMediaControlForApp,
          onChanged: (bool value) async {
            globalSettings.showMediaControlForApp = value;
            await Boxes.updateSettings('showMediaControlForApp', value);
            if (mounted) setState(() {});
          },
        ),
        if (globalSettings.showMediaControlForApp)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: _buildMediaAppsField(),
          ),
      ],
    );
  }

  Widget _buildVolumeOsdCard() {
    return _buildCard(
      icon: Icons.visibility_off_rounded,
      title: 'Volume OSD',
      subtitle: 'Windows 10 overlay behavior',
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: RadioGroup<VolumeOSDStyle>(
            groupValue: globalSettings.volumeOSDStyle,
            onChanged: _setVolumeOSDStyle,
            child: Column(
              children: <Widget>[
                _buildRadioTile('Normal volume OSD', 'Keep the standard Windows overlay', VolumeOSDStyle.normal),
                _buildRadioTile(
                    'Hide media only', 'Hide the media panel but keep the volume OSD', VolumeOSDStyle.media),
                _buildRadioTile(
                    'Modern / thin style', 'Use the slimmer Windows 11-style presentation', VolumeOSDStyle.thin),
                _buildRadioTile('Completely hidden', 'Suppress the volume OSD entirely', VolumeOSDStyle.visible),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRadioTile(String title, String subtitle, VolumeOSDStyle style) {
    final ThemeData theme = Theme.of(context);
    return RadioListTile<VolumeOSDStyle>(
      title: Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
      subtitle: Text(
        subtitle,
        style: TextStyle(fontSize: 11, color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.60)),
      ),
      value: style,
      activeColor: theme.colorScheme.primary,
      dense: true,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildVolumeRulesCard() {
    return _QuickmenuVolumeRulesCard(
      volumes: _volumeRules,
      onChanged: () {
        setState(() {});
      },
      onOpenAppAudio: () {
        final QuickmenuSettingsState? state = context.findAncestorStateOfType<QuickmenuSettingsState>();
        if (state != null) {
          state.openPage(5);
        }
      },
    );
  }

  Widget _buildWarningCard(String message) {
    final ThemeData theme = Theme.of(context);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.colorScheme.errorContainer.withValues(alpha: AppOpacity.accentFaint),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.error.withValues(alpha: AppOpacity.border)),
      ),
      child: Row(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: theme.colorScheme.error),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(color: theme.colorScheme.onErrorContainer, fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth > 800;
        final double horizontalPadding = isWide ? 16 : 8;

        return SingleChildScrollView(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: <Widget>[
                    if (!Audio.canRunAudioModule) ...<Widget>[
                      _buildWarningCard('Audio Module unavailable on this Windows install. Investigating...'),
                      const SizedBox(height: 16),
                    ],
                    _buildTargetingCard(),
                    const SizedBox(height: 16),
                    _buildMediaIntegrationCard(),
                    if (globalSettings.isWindows10) ...<Widget>[
                      const SizedBox(height: 16),
                      _buildVolumeOsdCard(),
                    ],
                    const SizedBox(height: 16),
                    _buildVolumeRulesCard(),
                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _QuickmenuVolumeRulesCard extends StatefulWidget {
  const _QuickmenuVolumeRulesCard({
    required this.volumes,
    required this.onChanged,
    required this.onOpenAppAudio,
  });

  final List<DefaultVolume> volumes;
  final VoidCallback onChanged;
  final VoidCallback onOpenAppAudio;

  @override
  State<_QuickmenuVolumeRulesCard> createState() => _QuickmenuVolumeRulesCardState();
}

class _QuickmenuVolumeRulesCardState extends State<_QuickmenuVolumeRulesCard> {
  Future<void> _persistRules() async {
    await Boxes.updateSettings('defaultVolume', jsonEncode(widget.volumes));
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.40),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.auto_awesome_rounded, size: 20, color: theme.colorScheme.primary),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text('Automation & Rules', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
                      Text(
                        'Player shortcuts and per-app volume automation',
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.60),
                        ),
                      ),
                    ],
                  ),
                ),
                TextButton.icon(
                  onPressed: () {
                    widget.volumes.add(DefaultVolume(type: 'exe', match: 'rocket.exe', volume: 20));
                    _persistRules();
                  },
                  icon: const Icon(Icons.add_rounded, size: 16),
                  label: const Text('Add Rule'),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.05)),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                InkWell(
                  onTap: () async {
                    globalSettings.volumeSetBack = !globalSettings.volumeSetBack;
                    await Boxes.updateSettings('volumeSetBack', globalSettings.volumeSetBack);
                    if (mounted) setState(() {});
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: <Widget>[
                              const Text(
                                'Restore volume when app loses focus',
                                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                              ),
                              Text(
                                'Revert the temporary rule volume after the matched window stops being active',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.60),
                                ),
                              ),
                            ],
                          ),
                        ),
                        Switch(
                          value: globalSettings.volumeSetBack,
                          onChanged: (bool value) async {
                            globalSettings.volumeSetBack = value;
                            await Boxes.updateSettings('volumeSetBack', value);
                            if (mounted) setState(() {});
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                if (widget.volumes.isEmpty)
                  Padding(
                    padding: const EdgeInsets.all(20),
                    child: Center(
                      child: Text(
                        'No automated rules yet.',
                        style: TextStyle(
                          fontStyle: FontStyle.italic,
                          color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.60),
                        ),
                      ),
                    ),
                  )
                else
                  ListView.separated(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    itemCount: widget.volumes.length,
                    separatorBuilder: (BuildContext context, int index) => Divider(
                      height: 1,
                      color: theme.dividerColor.withValues(alpha: 0.05),
                    ),
                    itemBuilder: (BuildContext context, int index) {
                      final DefaultVolume volume = widget.volumes[index];
                      return Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: <Widget>[
                            SizedBox(
                              width: 110,
                              child: DropdownButtonFormField<String>(
                                initialValue: volume.type,
                                decoration: _miniDecoration(context, 'Match By'),
                                style: TextStyle(fontSize: 12, color: onSurface, fontWeight: FontWeight.bold),
                                items: const <DropdownMenuItem<String>>[
                                  DropdownMenuItem<String>(value: 'exe', child: Text('EXE File')),
                                  DropdownMenuItem<String>(value: 'class', child: Text('Win Class')),
                                  DropdownMenuItem<String>(value: 'title', child: Text('Win Title')),
                                ],
                                onChanged: (String? value) {
                                  if (value == null) return;
                                  volume.type = value;
                                  _persistRules();
                                },
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: TextFormField(
                                initialValue: volume.match,
                                onChanged: (String value) {
                                  volume.match = value;
                                  Boxes.updateSettings('defaultVolume', jsonEncode(widget.volumes));
                                },
                                decoration: _miniDecoration(context, 'Match (Regex)').copyWith(hintText: '^Spotify.*'),
                                style: const TextStyle(fontSize: 12, fontFamily: 'Consolas'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            SizedBox(
                              width: 78,
                              child: TextFormField(
                                initialValue: volume.volume.toString(),
                                keyboardType: TextInputType.number,
                                onChanged: (String value) {
                                  final int? parsed = int.tryParse(value);
                                  if (parsed == null || parsed < 0 || parsed > 100) return;
                                  volume.volume = parsed;
                                  Boxes.updateSettings('defaultVolume', jsonEncode(widget.volumes));
                                },
                                decoration: _miniDecoration(context, 'Vol').copyWith(suffixText: '%'),
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              onPressed: () {
                                widget.volumes.removeAt(index);
                                _persistRules();
                              },
                              icon: const Icon(Icons.delete_sweep_rounded, size: 20),
                              tooltip: 'Remove rule',
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: TextButton.icon(
                      onPressed: widget.onOpenAppAudio,
                      icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                      label: const Text('Open App Audio'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _miniDecoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
      labelStyle: TextStyle(
        fontSize: 11,
        color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.70),
      ),
    );
  }
}
