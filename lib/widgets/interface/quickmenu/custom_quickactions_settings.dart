import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/util/app_opacity.dart';
import '../../../models/util/quick_actions.dart';
import '../../widgets/info_text.dart';
import '../../widgets/text_input.dart';

class QuickmenuCustomQuickActionsSettingsPage extends StatefulWidget {
  const QuickmenuCustomQuickActionsSettingsPage({super.key});
  @override
  State<QuickmenuCustomQuickActionsSettingsPage> createState() => _QuickmenuCustomQuickActionsSettingsPageState();
}

class _QuickmenuCustomQuickActionsSettingsPageState extends State<QuickmenuCustomQuickActionsSettingsPage> {
  List<QuickActions> quickActions = Boxes.quickActions;

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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildNotice(context),
                    const SizedBox(height: 20),
                    _buildControlsHeader(context),
                    const SizedBox(height: 12),
                    _buildActionsList(context),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildControlsHeader(BuildContext context) {
    return Row(
      children: <Widget>[
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Text(
                "Action Library",
                style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              Text(
                "Manage and reorder your custom quick actions",
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.6),
                    ),
              ),
            ],
          ),
        ),
        _buildAddButton(context),
      ],
    );
  }

  Widget _buildNotice(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(Icons.bolt_rounded, size: 18, color: scheme.primary),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: InfoText(
              "Bind these actions to Hotkeys or Triggers in the main Hotkeys configuration panel.",
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddButton(BuildContext context) {
    return FilledButton.icon(
      onPressed: () {
        quickActions.add(QuickActions(name: "New Action", type: quickActionsType.first, value: "0"));
        Boxes.updateSettings("quickActions", jsonEncode(quickActions));
        setState(() {});
        _editAction(quickActions.length - 1);
      },
      icon: const Icon(Icons.add_rounded, size: 18),
      label: const Text("New Action"),
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 0),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  Widget _buildActionsList(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    if (quickActions.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(48),
        decoration: BoxDecoration(
          color: theme.cardColor.withValues(alpha: 0.2),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
        ),
        child: Column(
          children: <Widget>[
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: scheme.onSurface.withValues(alpha: 0.03),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.bolt_outlined, size: 32, color: scheme.onSurface.withValues(alpha: 0.2)),
            ),
            const SizedBox(height: 16),
            Text(
              "No custom actions defined",
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: scheme.onSurface.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              "Create your first action to get started",
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurface.withValues(alpha: 0.3),
              ),
            ),
          ],
        ),
      );
    }

    return ReorderableListView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      buildDefaultDragHandles: false,
      physics: const NeverScrollableScrollPhysics(),
      itemBuilder: (BuildContext context, int index) {
        final QuickActions action = quickActions[index];
        return _buildActionCard(context, index, action);
      },
      itemCount: quickActions.length,
      onReorder: (int oldIndex, int newIndex) {
        if (oldIndex < newIndex) newIndex -= 1;
        final QuickActions item = quickActions.removeAt(oldIndex);
        quickActions.insert(newIndex, item);
        setState(() {});
        Boxes.updateSettings("quickActions", jsonEncode(quickActions));
      },
    );
  }

  Widget _buildActionCard(BuildContext context, int index, QuickActions action) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return ReorderableDragStartListener(
      index: index,
      key: ValueKey<int>(index),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: theme.cardColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.dividerColor.withValues(alpha: AppOpacity.border),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _editAction(index),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: <Widget>[
                Icon(
                  Icons.drag_indicator_rounded,
                  size: 20,
                  color: scheme.onSurface.withValues(alpha: 0.25),
                ),
                const SizedBox(width: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    _QuickmenuQuickActionEditState._getStaticIconForType(action.type),
                    size: 18,
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        action.name,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        action.type,
                        style: TextStyle(
                          fontSize: 12,
                          color: scheme.onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.settings_outlined, size: 18),
                  onPressed: () => _editAction(index),
                  visualDensity: VisualDensity.compact,
                ),
                IconButton(
                  icon: Icon(Icons.delete_outline_rounded, size: 18, color: scheme.error.withValues(alpha: 0.7)),
                  onPressed: () async {
                    quickActions.removeAt(index);
                    await Boxes.updateSettings("quickActions", jsonEncode(quickActions));
                    if (mounted) setState(() {});
                  },
                  visualDensity: VisualDensity.compact,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _editAction(int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: Container(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: AppOpacity.border)),
              ),
              child: QuickmenuQuickActionEdit(
                leAction: quickActions.elementAt(index).copyWith(),
                onSaved: (QuickActions n) {
                  quickActions[index] = n.copyWith();
                  Boxes.updateSettings("quickActions", jsonEncode(quickActions));
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

class QuickmenuQuickActionEdit extends StatefulWidget {
  final QuickActions leAction;
  final void Function(QuickActions hotkey) onSaved;
  const QuickmenuQuickActionEdit({
    super.key,
    required this.leAction,
    required this.onSaved,
  });
  @override
  State<QuickmenuQuickActionEdit> createState() => _QuickmenuQuickActionEditState();
}

class _QuickmenuQuickActionEditState extends State<QuickmenuQuickActionEdit> {
  static IconData _getStaticIconForType(String type) {
    switch (type) {
      case "Spotify Controls":
        return Icons.music_note_rounded;
      case "Audio Output Devices":
        return Icons.speaker_group_rounded;
      case "Audio Input Devices":
        return Icons.mic_rounded;
      case "Set Volume":
      case "Volume Slider":
        return Icons.volume_up_rounded;
      case "Run Command":
        return Icons.settings_ethernet_rounded;
      case "Open":
        return Icons.open_in_new_rounded;
      case "Send Keys":
        return Icons.keyboard_rounded;
      default:
        return Icons.bolt_rounded;
    }
  }

  IconData _getIconForType(String type) => _getStaticIconForType(type);

  String _getHintForType(String type) {
    switch (type) {
      case "Run Command":
        return "Command to execute (e.g. powershell script)";
      case "Open":
        return "File path, app name or URL";
      case "Send Keys":
        return "Key sequence (e.g. ctrl+v)";
      case "Set Volume":
        return "Volume level (0-100)";
      default:
        return "Action identifier or specific value";
    }
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final IconData currentIcon = _getIconForType(widget.leAction.type);

    return Padding(
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
                child: Icon(Icons.bolt_rounded, size: 20, color: scheme.primary),
              ),
              const SizedBox(width: 16),
              const Text(
                "Edit Quick Action",
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
                    currentIcon,
                    size: 80,
                    color: scheme.primary.withValues(alpha: 0.05),
                  ),
                ),
                Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: scheme.primary.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Icon(currentIcon, color: scheme.primary, size: 24),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          TextInput(
            labelText: "Display Name",
            onChanged: (String v) {
              widget.leAction.name = v;
              setState(() {});
            },
            value: widget.leAction.name,
          ),
          const SizedBox(height: 24),
          _buildLabel(context, "Action Type"),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                isExpanded: true,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                value: widget.leAction.type,
                borderRadius: BorderRadius.circular(16),
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: scheme.primary),
                style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                onChanged: (String? newValue) {
                  widget.leAction.type = newValue ?? quickActionsType.first;
                  if (widget.leAction.type != quickActionsType.first) {
                    widget.leAction.value = "";
                  } else {
                    widget.leAction.value = "0";
                  }
                  setState(() {});
                },
                items: quickActionsType.map<DropdownMenuItem<String>>((String value) {
                  return DropdownMenuItem<String>(
                    value: value,
                    child: Row(
                      children: <Widget>[
                        Icon(_getIconForType(value), size: 18, color: scheme.onSurface.withValues(alpha: 0.6)),
                        const SizedBox(width: 12),
                        Text(value),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          const SizedBox(height: 24),
          if (widget.leAction.type == quickActionsType.first) ...<Widget>[
            _buildLabel(context, "Select Built-in Action"),
            const SizedBox(height: 10),
            Container(
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHighest.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<int>(
                  isExpanded: true,
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  value: int.tryParse(widget.leAction.value) ?? 0,
                  borderRadius: BorderRadius.circular(16),
                  icon: Icon(Icons.keyboard_arrow_down_rounded, color: scheme.primary),
                  onChanged: (int? newValue) {
                    widget.leAction.value = newValue.toString();
                    setState(() {});
                  },
                  items: quickActionsList.map<DropdownMenuItem<int>>((String value) {
                    return DropdownMenuItem<int>(
                      value: quickActionsList.indexOf(value),
                      child: Text(value),
                    );
                  }).toList(),
                ),
              ),
            ),
          ] else if (<int>[4, 5, 6, 8, 9]
              .any((int e) => e == quickActionsType.indexOf(widget.leAction.type))) ...<Widget>[
            TextInput(
              labelText: "Action Value",
              hintText: _getHintForType(widget.leAction.type),
              onChanged: (String e) {
                widget.leAction.value = e;
                setState(() {});
              },
              value: widget.leAction.value,
            ),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: Text(
                "Define how the selected action should behave.",
                style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.4)),
              ),
            ),
          ],
          const SizedBox(height: 36),
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
                  widget.onSaved(widget.leAction);
                  Navigator.of(context).pop();
                },
                icon: const Icon(Icons.check_rounded, size: 18),
                label: const Text("Save Action"),
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
    );
  }

  Widget _buildLabel(BuildContext context, String text) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w800,
              letterSpacing: 0.5,
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.8),
            ),
      ),
    );
  }
}
