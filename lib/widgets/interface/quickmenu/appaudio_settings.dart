import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/util/app_opacity.dart';
import '../../widgets/text_input.dart';
import '../../widgets/windows_scroll.dart';

class QuickmenuAppAudioSettingsPage extends StatefulWidget {
  const QuickmenuAppAudioSettingsPage({super.key});

  @override
  State<QuickmenuAppAudioSettingsPage> createState() => _QuickmenuAppAudioSettingsPageState();
}

class _QuickmenuAppAudioSettingsPageState extends State<QuickmenuAppAudioSettingsPage> {
  static const int _maxControls = 5;

  List<AppAudioControl> appAudioControls = Boxes.appAudioControls;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth > 800;
        final double horizontalPadding = isWide ? 16 : 8;

        return WindowsScrollView(
          padding: EdgeInsets.symmetric(horizontal: horizontalPadding, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 800),
                child: Column(
                  children: <Widget>[
                    _buildOverviewCard(),
                    const SizedBox(height: 16),
                    _buildControlsCard(),
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

  Widget _buildOverviewCard() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool canAddMore = appAudioControls.length < _maxControls;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: scheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.graphic_eq_rounded, color: scheme.primary, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "App Audio Interface",
                      style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      "Provision isolated media controls for specific applications. Mapped controls populate the system interface slots (1-$_maxControls).",
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              FilledButton.icon(
                onPressed: canAddMore ? _addNewControl : null,
                icon: const Icon(Icons.add_rounded, size: 16),
                label: const Text("Provision"),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: <Widget>[
              _buildStatChip("CAPACITY", "${appAudioControls.length}/$_maxControls"),
              _buildStatChip(
                "ENGINE",
                appAudioControls.any((AppAudioControl e) => e.showAnimation) ? "ANIMATED" : "STATIC",
              ),
              _buildStatChip("SEQUENCE", "MANUAL"),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildControlsCard() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Column(
        children: <Widget>[
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                Icon(Icons.tune_rounded, size: 18, color: theme.hintColor),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      const Text(
                        "Active Configurations",
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        appAudioControls.isEmpty
                            ? "No active controlsprovisioned."
                            : "Adjust sequence and interface mappings",
                        style: TextStyle(
                          fontSize: 12,
                          color: theme.hintColor.withValues(alpha: 0.6),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: theme.dividerColor.withValues(alpha: 0.05)),
          if (appAudioControls.isEmpty)
            Padding(
              padding: const EdgeInsets.all(48),
              child: Column(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: scheme.onSurface.withValues(alpha: 0.03),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.music_off_rounded, size: 32, color: theme.hintColor.withValues(alpha: 0.3)),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    "System Idle",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "Provision your first isolated control to start",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.hintColor.withValues(alpha: 0.5), fontSize: 11),
                  ),
                ],
              ),
            )
          else
            ReorderableListView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              dragStartBehavior: DragStartBehavior.down,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: appAudioControls.length,
              itemBuilder: (BuildContext context, int index) {
                final AppAudioControl control = appAudioControls[index];
                return _buildControlCard(control, index);
              },
              onReorder: (int oldIndex, int newIndex) {
                if (oldIndex < newIndex) newIndex -= 1;
                final AppAudioControl item = appAudioControls.removeAt(oldIndex);
                appAudioControls.insert(newIndex, item);
                Boxes.appAudioControls = appAudioControls;
                setState(() {});
              },
            ),
        ],
      ),
    );
  }

  Widget _buildControlCard(AppAudioControl control, int index) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      key: ValueKey<String>("app_audio_${control.name}_$index"),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _editAction(index),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(top: 8, right: 12),
                  child: Icon(Icons.drag_indicator_rounded, size: 20, color: theme.hintColor.withValues(alpha: 0.3)),
                ),
              ),
              _buildControlIcon(control, scheme),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            control.name.isEmpty ? "UNNAMED INTERFACE" : control.name,
                            style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildMiniChip(
                          control.showAnimation ? "ANIMATED" : "STATIC",
                          control.showAnimation ? scheme.primary : theme.hintColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      control.exe.isEmpty ? "NO TARGET EXECUTABLE" : control.exe,
                      style: TextStyle(fontSize: 11, color: theme.hintColor.withValues(alpha: 0.5)),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        _buildBindingChip("TAP", control.hotkeyPause),
                        _buildBindingChip("NEXT", control.hotkeyNext),
                        _buildBindingChip("PREV", control.hotkeyPrev),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.settings_outlined, size: 18),
                    onPressed: () => _editAction(index),
                    visualDensity: VisualDensity.compact,
                  ),
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error.withValues(alpha: 0.7)),
                    onPressed: () {
                      appAudioControls.removeAt(index);
                      Boxes.appAudioControls = appAudioControls;
                      setState(() {});
                    },
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlIcon(AppAudioControl control, ColorScheme scheme) {
    return Container(
      width: 42,
      height: 42,
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: control.iconPath.isNotEmpty && File(control.iconPath).existsSync()
          ? ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: Image.file(
                File(control.iconPath),
                width: 28,
                height: 28,
                fit: BoxFit.cover,
              ),
            )
          : Icon(
              IconData(control.iconCodePoint, fontFamily: 'MaterialIcons'),
              size: 22,
              color: scheme.primary,
            ),
    );
  }

  Widget _buildStatChip(String label, String value) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Text(
            "$label: ",
            style: TextStyle(
              color: theme.hintColor,
              fontSize: 12,
            ),
          ),
          Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }

  Widget _buildBindingChip(String label, String value) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.12),
        ),
      ),
      child: Text(
        "$label: ${value.isEmpty ? 'Not set' : value}",
        style: TextStyle(
          fontSize: 11,
          color: theme.hintColor,
        ),
      ),
    );
  }

  void _addNewControl() {
    if (appAudioControls.length >= _maxControls) return;
    appAudioControls.add(
      AppAudioControl(
        name: "New Control",
        exe: "",
        path: "",
        iconPath: "",
        iconCodePoint: Icons.music_note.codePoint,
        hotkeyForward: "{#SHIFT}{#WIN}{#ALT}{F11}",
        hotkeyRewind: "{#SHIFT}{#WIN}{#ALT}{F10}",
        hotkeyNext: "{#SHIFT}{#WIN}{#ALT}{F6}",
        hotkeyPrev: "{#SHIFT}{#WIN}{#ALT}{F8}",
        hotkeyPause: "{#SHIFT}{#WIN}{#ALT}{F7}",
      ),
    );
    Boxes.appAudioControls = appAudioControls;
    setState(() {});
  }

  void _editAction(int index) {
    showDialog<void>(
      context: context,
      builder: (BuildContext dialogContext) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 580,
              maxHeight: 800,
            ),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: AppOpacity.border)),
              ),
              child: QuickmenuAppAudioEdit(
                control: AppAudioControl.fromMap(appAudioControls[index].toMap()),
                onSaved: (AppAudioControl updated) {
                  appAudioControls[index] = updated;
                  Boxes.appAudioControls = appAudioControls;
                  setState(() {});
                },
              ),
            ),
          ),
        );
      },
    );
  }
}

class QuickmenuAppAudioEdit extends StatefulWidget {
  const QuickmenuAppAudioEdit({
    super.key,
    required this.control,
    required this.onSaved,
  });

  final AppAudioControl control;
  final void Function(AppAudioControl ctl) onSaved;

  @override
  State<QuickmenuAppAudioEdit> createState() => _QuickmenuAppAudioEditState();
}

class _QuickmenuAppAudioEditState extends State<QuickmenuAppAudioEdit> {
  final List<IconData> _predefinedIcons = const <IconData>[
    Icons.music_note,
    Icons.music_video,
    Icons.audiotrack,
    Icons.queue_music,
    Icons.library_music,
    Icons.album,
    Icons.radio,
    Icons.speaker,
    Icons.headset,
    Icons.play_circle,
    Icons.fast_forward,
    Icons.volume_up,
    Icons.surround_sound,
  ];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(Icons.graphic_eq_rounded, size: 20, color: scheme.primary),
                ),
                const SizedBox(width: 16),
                const Text(
                  "App Audio Interface",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Visual Header
            Container(
              height: 80,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: <Color>[
                    scheme.primary.withValues(alpha: 0.1),
                    scheme.primary.withValues(alpha: 0.02),
                  ],
                ),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: scheme.primary.withValues(alpha: 0.15)),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    right: -10,
                    bottom: -10,
                    child: Icon(
                      Icons.graphic_eq_rounded,
                      size: 80,
                      color: scheme.primary.withValues(alpha: 0.05),
                    ),
                  ),
                  Center(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: <Widget>[
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: scheme.surface,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: Colors.black.withValues(alpha: 0.1),
                                blurRadius: 10,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                          alignment: Alignment.center,
                          child: widget.control.iconPath.isNotEmpty && File(widget.control.iconPath).existsSync()
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: Image.file(
                                    File(widget.control.iconPath),
                                    width: 32,
                                    height: 32,
                                    fit: BoxFit.cover,
                                  ),
                                )
                              : Icon(
                                  IconData(widget.control.iconCodePoint, fontFamily: 'MaterialIcons'),
                                  color: scheme.primary,
                                  size: 28,
                                ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            _buildSectionCard(
              title: "APP IDENTITY",
              child: Column(
                children: <Widget>[
                  TextInput(
                    labelText: "Display Name",
                    onChanged: (String value) {
                      setState(() {
                        widget.control.name = value;
                      });
                    },
                    value: widget.control.name,
                  ),
                  const SizedBox(height: 16),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: TextInput(
                          labelText: "App Path (.exe)",
                          onChanged: (String value) {
                            setState(() {
                              widget.control.path = value;
                              widget.control.exe = value.split('\\').last;
                            });
                          },
                          value: widget.control.path,
                        ),
                      ),
                      const SizedBox(width: 12),
                      FilledButton.tonalIcon(
                        onPressed: _pickExecutable,
                        icon: const Icon(Icons.folder_open_rounded, size: 16),
                        label: const Text("Browse"),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _buildToggleRow(
                    "Show Playing Animation",
                    "Animate this control while media is playing",
                    widget.control.showAnimation,
                    (bool value) {
                      setState(() {
                        widget.control.showAnimation = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: "ICON CONFIGURATION",
              child: Row(
                children: <Widget>[
                  FilledButton.tonalIcon(
                    onPressed: _pickPngIcon,
                    icon: const Icon(Icons.image_outlined, size: 16),
                    label: const Text("Load PNG"),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton.tonalIcon(
                    onPressed: _pickMaterialIcon,
                    icon: const Icon(Icons.grid_view_rounded, size: 16),
                    label: const Text("Select Icon"),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectionCard(
              title: "HOTKEY BINDINGS",
              child: Column(
                children: <Widget>[
                  _buildDenseField(
                      "Play / Pause", widget.control.hotkeyPause, (String v) => widget.control.hotkeyPause = v),
                  const SizedBox(height: 12),
                  _buildDenseField(
                      "Next Track", widget.control.hotkeyNext, (String v) => widget.control.hotkeyNext = v),
                  const SizedBox(height: 12),
                  _buildDenseField(
                      "Previous Track", widget.control.hotkeyPrev, (String v) => widget.control.hotkeyPrev = v),
                ],
              ),
            ),
            const SizedBox(height: 32),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: () {
                    widget.onSaved(widget.control);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text("Apply Interface"),
                  style: FilledButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildToggleRow(String title, String subtitle, bool value, ValueChanged<bool> onChanged) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
                Text(subtitle, style: TextStyle(fontSize: 11, color: theme.hintColor.withValues(alpha: 0.6))),
              ],
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(value: value, onChanged: onChanged),
          ),
        ],
      ),
    );
  }

  Widget _buildDenseField(String label, String value, Function(String) onChanged) {
    return TextInput(
      labelText: label,
      onChanged: onChanged,
      value: value,
    );
  }

  Widget _buildSectionCard({
    required String title,
    required Widget child,
  }) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: AppOpacity.border),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.5,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  void _pickExecutable() {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'Executable (*.exe)': '*.exe',
      }
      ..defaultFilterIndex = 0
      ..defaultExtension = 'exe'
      ..title = 'Select the App Executable';

    final File? result = file.getFile();
    if (result == null) return;

    setState(() {
      widget.control.path = result.path;
      widget.control.exe = result.path.split('\\').last;
    });
  }

  void _pickPngIcon() {
    final OpenFilePicker file = OpenFilePicker()
      ..filterSpecification = <String, String>{
        'PNG Image (*.png)': '*.png',
      }
      ..defaultExtension = 'png'
      ..title = 'Select Icon';

    final File? result = file.getFile();
    if (result == null) return;

    setState(() {
      widget.control.iconPath = result.path;
    });
  }

  void _pickMaterialIcon() {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        final ColorScheme scheme = Theme.of(context).colorScheme;
        return Dialog(
          backgroundColor: Colors.transparent,
          child: Container(
            width: 440,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: scheme.surface,
              borderRadius: BorderRadius.circular(28),
              border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: AppOpacity.border)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                const Text("Select Reference Icon", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                const SizedBox(height: 24),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: _predefinedIcons.map((IconData icon) {
                    final bool selected =
                        widget.control.iconCodePoint == icon.codePoint && widget.control.iconPath.isEmpty;

                    return InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () {
                        setState(() {
                          widget.control.iconCodePoint = icon.codePoint;
                          widget.control.iconPath = "";
                        });
                        Navigator.of(context).pop();
                      },
                      child: Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: selected
                              ? scheme.primary.withValues(alpha: 0.1)
                              : scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: selected ? scheme.primary : scheme.outline.withValues(alpha: 0.1),
                          ),
                        ),
                        child: Icon(icon, color: selected ? scheme.primary : scheme.onSurface.withValues(alpha: 0.6)),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text("Close"),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
