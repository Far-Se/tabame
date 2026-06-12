import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/util/app_opacity.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/windows_scroll.dart';

// ─────────────────────────────────────────────
//  Page
// ─────────────────────────────────────────────

class InterfaceQMRemindersSettingsPage extends StatefulWidget {
  const InterfaceQMRemindersSettingsPage({super.key});

  @override
  State<InterfaceQMRemindersSettingsPage> createState() => _InterfaceQMRemindersSettingsPageState();
}

class _InterfaceQMRemindersSettingsPageState extends State<InterfaceQMRemindersSettingsPage> {
  final List<Reminder> reminders = Boxes.reminders;

  /// Which reminder is currently open in the builder panel. null = none.
  int? _selectedIndex;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;

    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool isWide = constraints.maxWidth > 720;

        if (isWide) {
          return _buildSplitLayout(context, accent);
        } else {
          return _buildNarrowLayout(context, accent);
        }
      },
    );
  }

  // ── Wide: sidebar list + persistent builder panel ──
  Widget _buildSplitLayout(BuildContext context, Color accent) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: <Widget>[
        // LEFT – list
        SizedBox(
          width: 280,
          child: _ReminderSidebar(
            reminders: reminders,
            selectedIndex: _selectedIndex,
            accent: accent,
            onSelect: (int i) => setState(() => _selectedIndex = i),
            onToggle: (int i, bool val) async {
              reminders[i].enabled = val;
              await _saveAndRefresh();
            },
            onReorder: (int oldIndex, int newIndex) async {
              if (oldIndex < newIndex) newIndex -= 1;
              final Reminder item = reminders.removeAt(oldIndex);
              reminders.insert(newIndex, item);
              if (_selectedIndex != null) {
                if (_selectedIndex == oldIndex) {
                  _selectedIndex = newIndex;
                } else if (oldIndex < _selectedIndex! && newIndex >= _selectedIndex!) {
                  _selectedIndex = _selectedIndex! - 1;
                } else if (oldIndex > _selectedIndex! && newIndex <= _selectedIndex!) {
                  _selectedIndex = _selectedIndex! + 1;
                }
              }
              await _saveAndRefresh();
            },
            onAdd: _addReminder,
          ),
        ),
        // divider
        VerticalDivider(
          width: 1,
          thickness: 1,
          color: theme.dividerColor.withValues(alpha: AppOpacity.border),
        ),
        // RIGHT – builder panel
        Expanded(
          child: _selectedIndex != null
              ? ReminderBuilder(
                  key: ValueKey<int>(_selectedIndex!),
                  remindersIndex: _selectedIndex!,
                  accent: accent,
                  onSaved: (Reminder r) async {
                    reminders[_selectedIndex!] = r.copyWith();
                    await _saveAndRefresh();
                  },
                  onDeleted: () async {
                    reminders.removeAt(_selectedIndex!);
                    _selectedIndex = reminders.isEmpty
                        ? null
                        : (_selectedIndex! >= reminders.length ? reminders.length - 1 : _selectedIndex);
                    await _saveAndRefresh();
                  },
                )
              : _buildWelcomePane(context, accent),
        ),
      ],
    );
  }

  // ── Narrow: list only, builder opens as bottom sheet ──
  Widget _buildNarrowLayout(BuildContext context, Color accent) {
    return _ReminderSidebar(
      reminders: reminders,
      selectedIndex: null,
      accent: accent,
      onSelect: (int i) => _openBottomSheet(context, i),
      onToggle: (int i, bool val) async {
        reminders[i].enabled = val;
        await _saveAndRefresh();
      },
      onReorder: (int oldIndex, int newIndex) async {
        if (oldIndex < newIndex) newIndex -= 1;
        final Reminder item = reminders.removeAt(oldIndex);
        reminders.insert(newIndex, item);
        await _saveAndRefresh();
      },
      onAdd: _addReminder,
    );
  }

  void _openBottomSheet(BuildContext context, int index) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.92,
        minChildSize: 0.5,
        maxChildSize: 0.97,
        builder: (BuildContext ctx, ScrollController sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: ReminderBuilder(
            key: ValueKey<int>(index),
            remindersIndex: index,
            accent: userSettings.themeColors.accent,
            scrollController: sc,
            onSaved: (Reminder r) async {
              reminders[index] = r.copyWith();
              await _saveAndRefresh();
              if (context.mounted) Navigator.pop(context);
            },
            onDeleted: () async {
              reminders.removeAt(index);
              await _saveAndRefresh();
              if (context.mounted) Navigator.pop(context);
            },
          ),
        ),
      ),
    );
  }

  Widget _buildWelcomePane(BuildContext context, Color accent) {
    final ThemeData theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.08),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.notifications_none_rounded, color: accent, size: 40),
          ),
          const SizedBox(height: 20),
          Text(
            reminders.isEmpty ? "No reminders yet" : "Select a reminder",
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            reminders.isEmpty ? "Tap \"New Reminder\" to get started" : "Choose one from the list to edit it",
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
            ),
          ),
          if (reminders.isEmpty) ...<Widget>[
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _addReminder,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text("New Reminder"),
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _addReminder() async {
    reminders.add(Reminder(
      enabled: true,
      weekDays: <bool>[true, true, true, true, true, true, true],
      time: 60,
      multipleTimes: <int>[],
      repetitive: true,
      interval: <int>[8 * 60, 20 * 60],
      message: "New Reminder",
      voiceNotification: false,
      voiceVolume: 100,
      persistent: false,
    ));
    await _saveAndRefresh();
    setState(() => _selectedIndex = reminders.length - 1);
  }

  Future<void> _saveAndRefresh() async {
    await Boxes.updateSettings("reminders", jsonEncode(reminders));
    Tasks().startReminders();
    if (mounted) setState(() {});
  }
}

// ─────────────────────────────────────────────
//  Sidebar (list of reminders)
// ─────────────────────────────────────────────

class _ReminderSidebar extends StatelessWidget {
  const _ReminderSidebar({
    required this.reminders,
    required this.selectedIndex,
    required this.accent,
    required this.onSelect,
    required this.onToggle,
    required this.onReorder,
    required this.onAdd,
  });

  final List<Reminder> reminders;
  final int? selectedIndex;
  final Color accent;
  final void Function(int) onSelect;
  final void Function(int, bool) onToggle;
  final void Function(int, int) onReorder;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Container(
      decoration: BoxDecoration(
        color: Design.background.withAlpha(150),
      ),
      child: Column(
        children: <Widget>[
          // top bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 12, 8),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    "Reminders",
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
                Tooltip(
                  message: "New Reminder",
                  child: FilledButton(
                    onPressed: onAdd,
                    style: FilledButton.styleFrom(
                      backgroundColor: accent,
                      minimumSize: const Size(36, 36),
                      padding: EdgeInsets.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Icon(Icons.add_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),

          // list
          Expanded(
            child: reminders.isEmpty
                ? _buildEmpty(context)
                : ReorderableListView.builder(
                    buildDefaultDragHandles: false,
                    padding: const EdgeInsets.fromLTRB(8, 0, 8, 16),
                    itemCount: reminders.length,
                    physics: const ClampingScrollPhysics(),
                    itemBuilder: (BuildContext context, int i) {
                      return _SidebarTile(
                        key: ValueKey<int>(i),
                        reminder: reminders[i],
                        index: i,
                        isSelected: selectedIndex == i,
                        accent: accent,
                        onTap: () => onSelect(i),
                        onToggle: (bool v) => onToggle(i, v),
                      );
                    },
                    onReorderItem: onReorder,
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) {
    final Color fg = Theme.of(context).colorScheme.onSurface;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          Icon(Icons.notifications_off_outlined, size: 40, color: fg.withValues(alpha: 0.12)),
          const SizedBox(height: 12),
          Text(
            "No reminders",
            style: TextStyle(
              fontSize: 13,
              color: fg.withValues(alpha: 0.4),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Sidebar tile
// ─────────────────────────────────────────────

class _SidebarTile extends StatefulWidget {
  const _SidebarTile({
    required super.key,
    required this.reminder,
    required this.index,
    required this.isSelected,
    required this.accent,
    required this.onTap,
    required this.onToggle,
  });

  final Reminder reminder;
  final int index;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;
  final ValueChanged<bool> onToggle;

  @override
  State<_SidebarTile> createState() => _SidebarTileState();
}

class _SidebarTileState extends State<_SidebarTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool enabled = widget.reminder.enabled;
    final Color fg = theme.colorScheme.onSurface;

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        margin: const EdgeInsets.only(bottom: 4),
        decoration: BoxDecoration(
          color: widget.isSelected
              ? widget.accent.withValues(alpha: 0.12)
              : (_hover ? fg.withValues(alpha: 0.04) : Colors.transparent),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: widget.isSelected ? widget.accent.withValues(alpha: 0.35) : Colors.transparent,
            width: 1,
          ),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: <Widget>[
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: Icon(
                      Icons.drag_indicator_rounded,
                      size: 16,
                      color: fg.withValues(alpha: _hover ? 0.35 : 0.15),
                    ),
                  ),
                ),
                // enable toggle
                GestureDetector(
                  onTap: () => widget.onToggle(!enabled),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    width: 18,
                    height: 18,
                    decoration: BoxDecoration(
                      color: enabled ? widget.accent.withValues(alpha: 0.15) : Colors.transparent,
                      borderRadius: BorderRadius.circular(5),
                      border: Border.all(
                        color: enabled ? widget.accent : fg.withValues(alpha: 0.2),
                        width: 1.4,
                      ),
                    ),
                    child: enabled ? Icon(Icons.check_rounded, size: 11, color: widget.accent) : null,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(children: <Widget>[
                        if (widget.reminder.persistent)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.priority_high_rounded, size: 12, color: Design.accent),
                          ),
                        if (widget.reminder.voiceNotification)
                          Padding(
                            padding: const EdgeInsets.only(right: 4),
                            child: Icon(Icons.record_voice_over_rounded,
                                size: 12, color: widget.accent.withValues(alpha: 0.7)),
                          ),
                        Expanded(
                          child: Text(
                            widget.reminder.message,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                              color: enabled ? fg : fg.withValues(alpha: 0.3),
                            ),
                          ),
                        ),
                      ]),
                      const SizedBox(height: 1),
                      Text(
                        _getScheduleLabel(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 11,
                          color: fg.withValues(alpha: enabled ? 0.45 : 0.2),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getScheduleLabel() {
    final Reminder r = widget.reminder;
    if (r.repetitive) {
      return 'Every ${r.time}min · ${r.interval[0].formatTime()}–${r.interval[1].formatTime()}';
    }
    return 'At ${r.time.formatTime()}';
  }
}

// ─────────────────────────────────────────────
//  Reminder Builder  (replaces modal editor)
// ─────────────────────────────────────────────

class ReminderBuilder extends StatefulWidget {
  const ReminderBuilder({
    super.key,
    required this.remindersIndex,
    required this.accent,
    required this.onSaved,
    required this.onDeleted,
    this.scrollController,
  });

  final int remindersIndex;
  final Color accent;
  final void Function(Reminder) onSaved;
  final VoidCallback onDeleted;
  final ScrollController? scrollController;

  @override
  State<ReminderBuilder> createState() => _ReminderBuilderState();
}

class _ReminderBuilderState extends State<ReminderBuilder> {
  late Reminder _reminder;
  late TextEditingController _msgCtrl;
  final TextEditingController _intervalDaysCtrl = TextEditingController();
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _reminder = Boxes.reminders[widget.remindersIndex].copyWith();
    _msgCtrl = TextEditingController(text: _reminder.message);
    _msgCtrl.addListener(() => setState(() => _dirty = true));
    _intervalDaysCtrl.text = _reminder.interval[1].toString();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _intervalDaysCtrl.dispose();
    super.dispose();
  }

  void _save() {
    _reminder.message = _msgCtrl.text.trim().isEmpty ? "Reminder" : _msgCtrl.text.trim();
    widget.onSaved(_reminder);
    setState(() => _dirty = false);
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = widget.accent;

    return Container(
      decoration: BoxDecoration(
        color: Design.background.withAlpha(150),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          children: <Widget>[
            // ── top bar ──
            _BuilderTopBar(
              reminder: _reminder,
              accent: accent,
              dirty: _dirty,
              onSave: _save,
              onDelete: widget.onDeleted,
            ),

            // ── scrollable body ──
            Expanded(
              child: WindowsScrollView(
                controller: widget.scrollController,
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _SectionLabel(label: "Message", accent: accent),
                    const SizedBox(height: 8),
                    _MessageField(
                      controller: _msgCtrl,
                      accent: accent,
                      persistent: _reminder.persistent,
                      onPersistentChanged: (bool v) => setState(() {
                        _reminder.persistent = v;
                        _dirty = true;
                      }),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(label: "Notification type", accent: accent),
                    const SizedBox(height: 8),
                    _NotificationTypeSelector(
                      value: _reminder.voiceNotification,
                      accent: accent,
                      voiceVolume: _reminder.voiceVolume,
                      onTypeChanged: (bool v) => setState(() {
                        _reminder.voiceNotification = v;
                        _dirty = true;
                      }),
                      onVolumeChanged: (int v) => setState(() {
                        _reminder.voiceVolume = v;
                        _dirty = true;
                      }),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(label: "Days", accent: accent),
                    const SizedBox(height: 8),
                    _DayPicker(
                      weekDays: _reminder.weekDays,
                      accent: accent,
                      onChanged: (int i) => setState(() {
                        _reminder.weekDays[i] = !_reminder.weekDays[i];
                        _dirty = true;
                      }),
                    ),
                    const SizedBox(height: 24),
                    _SectionLabel(label: "Schedule", accent: accent),
                    const SizedBox(height: 8),
                    _ScheduleModeSelector(
                      value: _reminder.repetitive,
                      accent: accent,
                      onChanged: (bool v) => setState(() {
                        _reminder.repetitive = v;
                        _dirty = true;
                      }),
                    ),
                    const SizedBox(height: 12),
                    AnimatedSwitcher(
                      duration: const Duration(milliseconds: 250),
                      switchInCurve: Curves.easeOutCubic,
                      transitionBuilder: (Widget child, Animation<double> anim) => FadeTransition(
                        opacity: anim,
                        child: SlideTransition(
                          position: Tween<Offset>(
                            begin: const Offset(0, 0.04),
                            end: Offset.zero,
                          ).animate(anim),
                          child: child,
                        ),
                      ),
                      child: _reminder.repetitive
                          ? _RepetitiveSchedule(
                              key: const ValueKey<String>('rep'),
                              reminder: _reminder,
                              accent: accent,
                              onChanged: () => setState(() => _dirty = true),
                            )
                          : _DailySchedule(
                              key: const ValueKey<String>('daily'),
                              reminder: _reminder,
                              accent: accent,
                              onChanged: () => setState(() => _dirty = true),
                            ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Builder Top Bar
// ─────────────────────────────────────────────

class _BuilderTopBar extends StatelessWidget {
  const _BuilderTopBar({
    required this.reminder,
    required this.accent,
    required this.dirty,
    required this.onSave,
    required this.onDelete,
  });

  final Reminder reminder;
  final Color accent;
  final bool dirty;
  final VoidCallback onSave;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 14, 16, 14),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.dividerColor.withValues(alpha: AppOpacity.border),
          ),
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.edit_notifications_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  reminder.message.isEmpty ? "Reminder" : reminder.message,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  dirty ? "Unsaved changes" : "Up to date",
                  style: TextStyle(
                    fontSize: 11,
                    color: dirty
                        ? Design.accent.withValues(alpha: 0.9)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            tooltip: "Delete",
            icon: Icon(Icons.delete_outline_rounded, size: 20, color: theme.colorScheme.error.withValues(alpha: 0.7)),
            onPressed: () => _confirmDelete(context),
          ),
          const SizedBox(width: 4),
          FilledButton(
            onPressed: dirty ? onSave : null,
            style: FilledButton.styleFrom(
              backgroundColor: accent,
              disabledBackgroundColor: accent.withValues(alpha: 0.15),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            ),
            child: Text(
              "Save",
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: dirty ? Colors.white : accent.withValues(alpha: 0.4),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text("Delete reminder?"),
        content: Text("\"${reminder.message}\" will be permanently removed."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            onPressed: () {
              Navigator.pop(ctx);
              onDelete();
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Section label
// ─────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.accent});
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(children: <Widget>[
      Container(
        width: 3,
        height: 13,
        decoration: BoxDecoration(
          color: accent,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
      const SizedBox(width: 8),
      Text(
        label.toUpperCase(),
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
          color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.5),
        ),
      ),
    ]);
  }
}

// ─────────────────────────────────────────────
//  Message field
// ─────────────────────────────────────────────

class _MessageField extends StatelessWidget {
  const _MessageField({
    required this.controller,
    required this.accent,
    required this.persistent,
    required this.onPersistentChanged,
  });

  final TextEditingController controller;
  final Color accent;
  final bool persistent;
  final ValueChanged<bool> onPersistentChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: <Widget>[
        TextField(
          controller: controller,
          style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w500),
          decoration: InputDecoration(
            hintText: "e.g. Take a break",
            hintStyle: TextStyle(color: theme.colorScheme.onSurface.withValues(alpha: 0.3)),
            prefixIcon: Icon(Icons.short_text_rounded, size: 20, color: accent.withValues(alpha: 0.7)),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerLow,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: accent, width: 1.5),
            ),
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          ),
        ),
        const SizedBox(height: 8),
        GestureDetector(
          onTap: () => onPersistentChanged(!persistent),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: persistent ? Design.accent.withValues(alpha: 0.08) : theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: persistent ? Design.accent.withValues(alpha: 0.4) : Colors.transparent,
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                  persistent ? Icons.priority_high_rounded : Icons.notifications_none_rounded,
                  size: 18,
                  color: persistent ? Design.accent : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        "Persistent notification",
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: persistent ? Design.accent : theme.colorScheme.onSurface,
                        ),
                      ),
                      Text(
                        "Requires manual dismissal from QuickMenu",
                        style: TextStyle(
                          fontSize: 11,
                          color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                        ),
                      ),
                    ],
                  ),
                ),
                MiniToggleSwitch(
                  value: persistent,
                  onChanged: (_) {},
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────
//  Notification type selector
// ─────────────────────────────────────────────

class _NotificationTypeSelector extends StatelessWidget {
  const _NotificationTypeSelector({
    required this.value,
    required this.accent,
    required this.voiceVolume,
    required this.onTypeChanged,
    required this.onVolumeChanged,
  });

  final bool value;
  final Color accent;
  final int voiceVolume;
  final ValueChanged<bool> onTypeChanged;
  final ValueChanged<int> onVolumeChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Column(
      children: <Widget>[
        Row(children: <Widget>[
          Expanded(
            child: _TypeCard(
              icon: Icons.visibility_rounded,
              label: "Visual",
              sublabel: "Toast notification",
              selected: !value,
              accent: accent,
              onTap: () => onTypeChanged(false),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: _TypeCard(
              icon: Icons.record_voice_over_rounded,
              label: "Voice",
              sublabel: "Spoken announcement",
              selected: value,
              accent: accent,
              onTap: () => onTypeChanged(true),
            ),
          ),
        ]),
        if (value) ...<Widget>[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: <Widget>[
                Icon(
                    voiceVolume == 0
                        ? Icons.volume_off_rounded
                        : voiceVolume < 50
                            ? Icons.volume_down_rounded
                            : Icons.volume_up_rounded,
                    size: 18,
                    color: accent),
                Expanded(
                  child: SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      activeTrackColor: accent,
                      thumbColor: accent,
                      inactiveTrackColor: accent.withValues(alpha: 0.15),
                      overlayColor: accent.withValues(alpha: 0.1),
                      trackHeight: 3,
                      thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                    ),
                    child: Slider(
                      min: 0,
                      max: 100,
                      value: voiceVolume.toDouble(),
                      onChanged: (double v) => onVolumeChanged(v.round()),
                    ),
                  ),
                ),
                SizedBox(
                  width: 36,
                  child: Text(
                    "$voiceVolume%",
                    textAlign: TextAlign.end,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({
    required this.icon,
    required this.label,
    required this.sublabel,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String sublabel;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: selected ? accent.withValues(alpha: 0.1) : theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? accent.withValues(alpha: 0.5) : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Row(
          children: <Widget>[
            Icon(icon, size: 20, color: selected ? accent : theme.colorScheme.onSurface.withValues(alpha: 0.4)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    label,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: selected ? accent : theme.colorScheme.onSurface,
                    ),
                  ),
                  Text(
                    sublabel,
                    style: TextStyle(
                      fontSize: 10,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.4),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Day picker
// ─────────────────────────────────────────────

class _DayPicker extends StatelessWidget {
  const _DayPicker({
    required this.weekDays,
    required this.accent,
    required this.onChanged,
  });

  final List<bool> weekDays;
  final Color accent;
  final ValueChanged<int> onChanged;

  static const List<String> _labels = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Row(
      children: List<Widget>.generate(7, (int i) {
        final bool on = weekDays[i];
        return Expanded(
          child: GestureDetector(
            onTap: () => onChanged(i),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 150),
              margin: EdgeInsets.only(right: i < 6 ? 5 : 0),
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: BoxDecoration(
                color: on ? accent.withValues(alpha: 0.15) : theme.colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: on ? accent.withValues(alpha: 0.5) : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  Text(
                    _labels[i][0],
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: on ? accent : theme.colorScheme.onSurface.withValues(alpha: 0.35),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }
}

// ─────────────────────────────────────────────
//  Schedule mode selector
// ─────────────────────────────────────────────

class _ScheduleModeSelector extends StatelessWidget {
  const _ScheduleModeSelector({
    required this.value,
    required this.accent,
    required this.onChanged,
  });

  final bool value;
  final Color accent;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Container(
      height: 44,
      // padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _ModeTab(
            icon: Icons.repeat_rounded,
            label: "Repeating interval",
            selected: value,
            accent: accent,
            onTap: () => onChanged(true),
          ),
          _ModeTab(
            icon: Icons.schedule_rounded,
            label: "Specific times",
            selected: !value,
            accent: accent,
            onTap: () => onChanged(false),
          ),
        ],
      ),
    );
  }
}

class _ModeTab extends StatelessWidget {
  const _ModeTab({
    required this.icon,
    required this.label,
    required this.selected,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: selected ? accent.withValues(alpha: 0.15) : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected ? accent.withValues(alpha: 0.35) : Colors.transparent,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(icon, size: 14, color: selected ? accent : theme.colorScheme.onSurface.withValues(alpha: 0.4)),
              const SizedBox(width: 6),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: selected ? accent : theme.colorScheme.onSurface.withValues(alpha: 0.5),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Repetitive schedule
// ─────────────────────────────────────────────

class _RepetitiveSchedule extends StatelessWidget {
  const _RepetitiveSchedule({
    super.key,
    required this.reminder,
    required this.accent,
    required this.onChanged,
  });

  final Reminder reminder;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _ScheduleTile(
          icon: Icons.timer_outlined,
          label: "Repeat every",
          value: "${reminder.time} minutes",
          accent: accent,
          onTap: () => _pickInterval(context, Theme.of(context)),
        ),
        const SizedBox(height: 8),
        Row(
          children: <Widget>[
            Expanded(
              child: _ScheduleTile(
                icon: Icons.play_circle_outline_rounded,
                label: "Window starts",
                value: reminder.interval[0].formatTime(),
                accent: accent,
                onTap: () => _pickBound(context, 0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _ScheduleTile(
                icon: Icons.stop_circle_outlined,
                label: "Window ends",
                value: reminder.interval[1].formatTime(),
                accent: accent,
                onTap: () => _pickBound(context, 1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickInterval(BuildContext context, ThemeData theme) async {
    int val = reminder.time;
    final TextEditingController ctrl = TextEditingController(text: val.toString());
    final int? result = await showDialog<int>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text("Repeat every"),
        content: StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setS) => Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: <Widget>[
                  SizedBox(
                    width: 80,
                    child: TextField(
                      autofocus: true,
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      style: theme.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                      controller: ctrl,
                      decoration:
                          const InputDecoration(isDense: true, contentPadding: EdgeInsets.symmetric(vertical: 8)),
                      onChanged: (String v) {
                        final int? n = int.tryParse(v);
                        if (n != null && n > 0) setS(() => val = n);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Text("minutes"),
                ],
              ),
              const SizedBox(height: 16),
              Slider(
                min: 1,
                max: 240,
                value: val.toDouble().clamp(1, 240),
                onChanged: (double v) => setS(() {
                  val = v.round();
                  ctrl.text = val.toString();
                }),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(ctx, val), child: const Text("OK")),
        ],
      ),
    );
    if (result != null) {
      reminder.time = result;
      onChanged();
    }
  }

  Future<void> _pickBound(BuildContext context, int idx) async {
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminder.interval[idx] ~/ 60, minute: reminder.interval[idx] % 60),
    );
    if (t != null) {
      reminder.interval[idx] = t.hour * 60 + t.minute;
      if (idx == 0 && reminder.interval[0] + reminder.time > reminder.interval[1]) {
        reminder.interval[1] = reminder.interval[0] + reminder.time;
      }
      onChanged();
    }
  }
}

// ─────────────────────────────────────────────
//  Daily / specific schedule
// ─────────────────────────────────────────────

class _DailySchedule extends StatelessWidget {
  const _DailySchedule({
    super.key,
    required this.reminder,
    required this.accent,
    required this.onChanged,
  });

  final Reminder reminder;
  final Color accent;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        _ScheduleTile(
          icon: Icons.alarm_rounded,
          label: "Main time",
          value: reminder.time.formatTime(),
          accent: accent,
          onTap: () => _pickMain(context),
        ),
        ...reminder.multipleTimes.asMap().entries.map(
              (MapEntry<int, int> e) => Padding(
                padding: const EdgeInsets.only(top: 8),
                child: _ScheduleTile(
                  icon: e.value < 0 ? Icons.event_rounded : Icons.alarm_add_rounded,
                  label: e.value < 0 ? "Day of month" : "Extra time",
                  value: e.value < 0 ? "Day ${e.value.abs().ordinalSuffix()}" : e.value.formatTime(),
                  accent: accent,
                  onTap: () => e.value < 0 ? _pickDay(context, e.key) : _pickExtra(context, e.key),
                  trailing: IconButton(
                    icon: Icon(Icons.close_rounded,
                        size: 16, color: Theme.of(context).colorScheme.error.withValues(alpha: 0.7)),
                    onPressed: () {
                      reminder.multipleTimes.removeAt(e.key);
                      onChanged();
                    },
                    visualDensity: VisualDensity.compact,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                  ),
                ),
              ),
            ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            if (reminder.multipleTimes.every((int t) => t >= 0))
              Expanded(
                child: _AddButton(
                  icon: Icons.more_time_rounded,
                  label: "Add time",
                  accent: accent,
                  onTap: () {
                    reminder.multipleTimes.add(DateTime.now().hour * 60 + DateTime.now().minute);
                    onChanged();
                  },
                ),
              ),
            if (reminder.multipleTimes.isNotEmpty && reminder.multipleTimes.every((int t) => t >= 0))
              const SizedBox(width: 8),
            if (reminder.multipleTimes.every((int t) => t < 0))
              Expanded(
                child: _AddButton(
                  icon: Icons.event_note_rounded,
                  label: "Add date",
                  accent: accent,
                  onTap: () {
                    reminder.multipleTimes.add(-DateTime.now().day);
                    onChanged();
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickMain(BuildContext context) async {
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminder.time ~/ 60, minute: reminder.time % 60),
    );
    if (t != null) {
      reminder.time = t.hour * 60 + t.minute;
      onChanged();
    }
  }

  Future<void> _pickExtra(BuildContext context, int i) async {
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminder.multipleTimes[i] ~/ 60, minute: reminder.multipleTimes[i] % 60),
    );
    if (t != null) {
      reminder.multipleTimes[i] = t.hour * 60 + t.minute;
      onChanged();
    }
  }

  Future<void> _pickDay(BuildContext context, int i) async {
    final DateTime now = DateTime.now();
    final DateTime? res = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, reminder.multipleTimes[i].abs().clamp(1, 28)),
      firstDate: DateTime(now.year, now.month, 1),
      lastDate: DateTime(now.year, now.month + 1, 0),
    );
    if (res != null) {
      reminder.multipleTimes[i] = -res.day;
      onChanged();
    }
  }
}

// ─────────────────────────────────────────────
//  Schedule tile
// ─────────────────────────────────────────────

class _ScheduleTile extends StatefulWidget {
  const _ScheduleTile({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
    required this.onTap,
    this.trailing,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;
  final VoidCallback onTap;
  final Widget? trailing;

  @override
  State<_ScheduleTile> createState() => _ScheduleTileState();
}

class _ScheduleTileState extends State<_ScheduleTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: _hover ? widget.accent.withValues(alpha: 0.07) : theme.colorScheme.surfaceContainerLow,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: _hover ? widget.accent.withValues(alpha: 0.25) : Colors.transparent,
            ),
          ),
          child: Row(
            children: <Widget>[
              Icon(widget.icon, size: 18, color: widget.accent.withValues(alpha: 0.8)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      widget.label,
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.4,
                        color: theme.colorScheme.onSurface.withValues(alpha: 0.45),
                      ),
                    ),
                    Text(
                      widget.value,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                    ),
                  ],
                ),
              ),
              if (widget.trailing != null)
                widget.trailing!
              else
                Icon(Icons.edit_rounded,
                    size: 14, color: theme.colorScheme.onSurface.withValues(alpha: _hover ? 0.5 : 0.2)),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Add button
// ─────────────────────────────────────────────

class _AddButton extends StatelessWidget {
  const _AddButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: Icon(icon, size: 16),
      label: Text(label),
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        foregroundColor: accent,
        side: BorderSide(color: accent.withValues(alpha: 0.35)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
      ),
    );
  }
}

// ─────────────────────────────────────────────
//  Mini toggle (read-only visual)
// ─────────────────────────────────────────────

// ─────────────────────────────────────────────
//  Helper classes
// ─────────────────────────────────────────────

class SegmentItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  const SegmentItem({required this.value, required this.label, this.icon});
}
