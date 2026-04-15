import 'dart:io';

import 'package:filepicker_windows/filepicker_windows.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';

class QuickmenuAppAudioSettingsPage extends StatefulWidget {
  const QuickmenuAppAudioSettingsPage({super.key});

  @override
  State<QuickmenuAppAudioSettingsPage> createState() =>
      _QuickmenuAppAudioSettingsPageState();
}

class _QuickmenuAppAudioSettingsPageState
    extends State<QuickmenuAppAudioSettingsPage> {
  static const int _maxControls = 5;

  List<AppAudioControl> appAudioControls = Boxes.appAudioControls;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: ScrollController(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildOverviewCard(),
            const SizedBox(height: 20),
            _buildControlsCard(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildOverviewCard() {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool canAddMore = appAudioControls.length < _maxControls;

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(
                    Icons.graphic_eq_rounded,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        "App Audio Controls",
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Create custom media controls for apps like MusicBee or VLC. They appear as AppAudioControl1 to 5 in top bar actions.",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.icon(
                  onPressed: canAddMore ? _addNewControl : null,
                  icon: const Icon(Icons.add_rounded, size: 18),
                  label: const Text("Add"),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                _buildStatChip("Configured", "${appAudioControls.length}/$_maxControls"),
                _buildStatChip(
                  "Animation",
                  appAudioControls.any((AppAudioControl e) => e.showAnimation)
                      ? "Enabled"
                      : "Off",
                ),
                _buildStatChip("Reorder", "Drag cards"),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlsCard() {
    final ThemeData theme = Theme.of(context);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: theme.dividerColor.withValues(alpha: 0.1),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.tune_rounded),
              title: const Text(
                "Configured Controls",
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
              subtitle: Text(
                appAudioControls.isEmpty
                    ? "No app audio controls yet."
                    : "Tap a card to edit. Drag the grip to reorder.",
              ),
            ),
            const Divider(),
            if (appAudioControls.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerHighest
                        .withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Column(
                    children: <Widget>[
                      Icon(
                        Icons.music_off_rounded,
                        size: 28,
                        color: theme.hintColor,
                      ),
                      const SizedBox(height: 10),
                      const Text(
                        "Nothing configured yet",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Add your first app audio control to bind media hotkeys and show it in the quick menu.",
                        textAlign: TextAlign.center,
                        style: TextStyle(color: theme.hintColor),
                      ),
                    ],
                  ),
                ),
              )
            else
              ReorderableListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
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
                  final AppAudioControl item =
                      appAudioControls.removeAt(oldIndex);
                  appAudioControls.insert(newIndex, item);
                  Boxes.appAudioControls = appAudioControls;
                  setState(() {});
                },
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlCard(AppAudioControl control, int index) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      key: ValueKey<String>("app_audio_${control.name}_$index"),
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.16),
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _editAction(index),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(top: 10, right: 10),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 20,
                    color: theme.hintColor,
                  ),
                ),
              ),
              _buildControlIcon(control, scheme),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Expanded(
                          child: Text(
                            control.name.isEmpty
                                ? "Unnamed Control"
                                : control.name,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        _buildMiniChip(
                          control.showAnimation ? "Animated" : "Static",
                          control.showAnimation
                              ? scheme.primary
                              : theme.hintColor,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      control.exe.isEmpty
                          ? "No executable selected"
                          : control.exe,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.hintColor,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (control.path.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 2),
                      Text(
                        control.path,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.hintColor.withValues(alpha: 0.9),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: <Widget>[
                        _buildBindingChip("Tap", control.hotkeyPause),
                        _buildBindingChip("Next", control.hotkeyNext),
                        _buildBindingChip("Prev", control.hotkeyPrev),
                        _buildBindingChip("Forward", control.hotkeyForward),
                        _buildBindingChip("Rewind", control.hotkeyRewind),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                children: <Widget>[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: "Edit",
                    onPressed: () => _editAction(index),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.delete_outline,
                      size: 20,
                      color: Colors.redAccent,
                    ),
                    tooltip: "Remove",
                    onPressed: () {
                      appAudioControls.removeAt(index);
                      Boxes.appAudioControls = appAudioControls;
                      setState(() {});
                    },
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
        return AlertDialog(
          clipBehavior: Clip.antiAlias,
          insetPadding: const EdgeInsets.all(20),
          contentPadding: EdgeInsets.zero,
          content: SizedBox(
            width: 560,
            child: QuickmenuAppAudioEdit(
              control: AppAudioControl.fromMap(appAudioControls[index].toMap()),
              onSaved: (AppAudioControl updated) {
                appAudioControls[index] = updated;
                Boxes.appAudioControls = appAudioControls;
                setState(() {});
              },
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

    return Container(
      color: scheme.surface,
      child: SingleChildScrollView(
        controller: ScrollController(),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  alignment: Alignment.center,
                  child: widget.control.iconPath.isNotEmpty &&
                          File(widget.control.iconPath).existsSync()
                      ? ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.file(
                            File(widget.control.iconPath),
                            width: 34,
                            height: 34,
                            fit: BoxFit.cover,
                          ),
                        )
                      : Icon(
                          IconData(
                            widget.control.iconCodePoint,
                            fontFamily: 'MaterialIcons',
                          ),
                          color: scheme.primary,
                        ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        "Edit App Audio Control",
                        style: theme.textTheme.titleLarge?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        "Configure the target executable, icon, and media bindings for this quick menu control.",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.hintColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 18),
            _buildSectionCard(
              title: "App",
              subtitle: "Identity and executable target",
              child: Column(
                children: <Widget>[
                  _buildField(
                    label: "Display Name",
                    initialValue: widget.control.name,
                    onChanged: (String value) {
                      setState(() {
                        widget.control.name = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: <Widget>[
                      Expanded(
                        child: _buildField(
                          label: "App Path (.exe)",
                          initialValue: widget.control.path,
                          onChanged: (String value) {
                            setState(() {
                              widget.control.path = value;
                              widget.control.exe = value.split('\\').last;
                            });
                          },
                        ),
                      ),
                      const SizedBox(width: 10),
                      FilledButton.tonalIcon(
                        onPressed: _pickExecutable,
                        icon: const Icon(Icons.folder_open_rounded, size: 18),
                        label: const Text("Browse"),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text("Show Playing Animation"),
                    subtitle: const Text(
                      "Animate this control while media is playing",
                    ),
                    value: widget.control.showAnimation,
                    onChanged: (bool value) {
                      setState(() {
                        widget.control.showAnimation = value;
                      });
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: "Icon",
              subtitle: "Use a PNG asset or a built-in quick icon",
              child: Column(
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: scheme.surfaceContainerHighest
                              .withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(14),
                        ),
                        alignment: Alignment.center,
                        child: widget.control.iconPath.isNotEmpty &&
                                File(widget.control.iconPath).existsSync()
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.file(
                                  File(widget.control.iconPath),
                                  width: 38,
                                  height: 38,
                                  fit: BoxFit.cover,
                                ),
                              )
                            : Icon(
                                IconData(
                                  widget.control.iconCodePoint,
                                  fontFamily: 'MaterialIcons',
                                ),
                                size: 28,
                                color: scheme.primary,
                              ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          widget.control.iconPath.isNotEmpty
                              ? widget.control.iconPath
                              : "Using built-in material icon",
                          style: TextStyle(color: theme.hintColor),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: <Widget>[
                      FilledButton.tonalIcon(
                        onPressed: _pickPngIcon,
                        icon: const Icon(Icons.image_outlined, size: 18),
                        label: const Text("Pick PNG"),
                      ),
                      FilledButton.tonalIcon(
                        onPressed: _pickMaterialIcon,
                        icon: const Icon(Icons.grid_view_rounded, size: 18),
                        label: const Text("Pick Icon"),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            _buildSectionCard(
              title: "Hotkeys",
              subtitle: "Map mouse gestures to media shortcuts",
              child: Column(
                children: <Widget>[
                  _buildField(
                    label: "Play / Pause",
                    hint: "Tap action",
                    initialValue: widget.control.hotkeyPause,
                    onChanged: (String value) {
                      widget.control.hotkeyPause = value;
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    label: "Next Track",
                    hint: "Right click",
                    initialValue: widget.control.hotkeyNext,
                    onChanged: (String value) {
                      widget.control.hotkeyNext = value;
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    label: "Previous Track",
                    hint: "Middle click",
                    initialValue: widget.control.hotkeyPrev,
                    onChanged: (String value) {
                      widget.control.hotkeyPrev = value;
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    label: "Seek Forward",
                    hint: "Scroll up",
                    initialValue: widget.control.hotkeyForward,
                    onChanged: (String value) {
                      widget.control.hotkeyForward = value;
                    },
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    label: "Seek Rewind",
                    hint: "Scroll down",
                    initialValue: widget.control.hotkeyRewind,
                    onChanged: (String value) {
                      widget.control.hotkeyRewind = value;
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                OutlinedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text("Cancel"),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () {
                    widget.onSaved(widget.control);
                    Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.save_outlined, size: 18),
                  label: const Text("Save"),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionCard({
    required String title,
    required String subtitle,
    required Widget child,
  }) {
    final ThemeData theme = Theme.of(context);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: theme.dividerColor.withValues(alpha: 0.12),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.hintColor,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildField({
    required String label,
    required String initialValue,
    required ValueChanged<String> onChanged,
    String? hint,
  }) {
    final ThemeData theme = Theme.of(context);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          hint == null ? label : "$label  ·  $hint",
          style: theme.textTheme.labelMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 6),
        TextFormField(
          initialValue: initialValue,
          onChanged: onChanged,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
      ],
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
        return AlertDialog(
          title: const Text("Select Icon"),
          content: SizedBox(
            width: 360,
            child: Wrap(
              spacing: 10,
              runSpacing: 10,
              children: _predefinedIcons.map((IconData icon) {
                final bool selected =
                    widget.control.iconCodePoint == icon.codePoint &&
                    widget.control.iconPath.isEmpty;

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
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(
                      color: selected
                          ? Theme.of(context)
                              .colorScheme
                              .primary
                              .withValues(alpha: 0.14)
                          : Theme.of(context)
                              .colorScheme
                              .surfaceContainerHighest
                              .withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context)
                                .dividerColor
                                .withValues(alpha: 0.12),
                      ),
                    ),
                    child: Icon(icon),
                  ),
                );
              }).toList(),
            ),
          ),
        );
      },
    );
  }
}
