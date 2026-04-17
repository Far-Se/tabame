// ignore_for_file: public_member_api_docs, sort_constructors_first, dead_code
import 'dart:convert';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/classes/saved_maps.dart';
import '../../models/settings.dart';

class TasksReminders extends StatefulWidget {
  const TasksReminders({super.key});

  @override
  TasksRemindersState createState() => TasksRemindersState();
}

class TasksRemindersState extends State<TasksReminders> {
  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(context),
        const SizedBox(height: 8),
        Expanded(
          child: Boxes.reminders.isEmpty
              ? _buildEmptyState(context)
              : ReorderableListView.builder(
                  buildDefaultDragHandles: false,
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
                  itemCount: Boxes.reminders.length,
                  onReorder: (int oldIndex, int newIndex) async {
                    setState(() {
                      if (oldIndex < newIndex) newIndex -= 1;
                      final Reminder item = Boxes.reminders.removeAt(oldIndex);
                      Boxes.reminders.insert(newIndex, item);
                    });
                    await updateReminders();
                  },
                  itemBuilder: (BuildContext context, int index) {
                    final Reminder reminder = Boxes.reminders[index];
                    return _ReminderTile(
                      key: ObjectKey(reminder),
                      reminder: reminder,
                      index: index,
                      onChanged: (bool? value) async {
                        reminder.enabled = value ?? false;
                        await updateReminders();
                        if (mounted) setState(() {});
                      },
                      onTap: () => _showEditor(context, index),
                      onDelete: () => _confirmDelete(context, index),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _confirmDelete(BuildContext context, int index) {
    final Reminder reminder = Boxes.reminders[index];
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text("Delete Reminder?"),
        content: Text("Permanently delete '${reminder.message}'? This action is irreversible."),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              Boxes.reminders.removeAt(index);
              await updateReminders();
              if (mounted) setState(() {});
              if (context.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text("Delete Permanently"),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 8, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: <Widget>[
          Text(
            "Reminders",
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.5,
                ),
          ),
          IconButton(
            onPressed: _addNewReminder,
            icon: const Icon(Icons.add_rounded),
            tooltip: "Add Reminder",
          ),
        ],
      ),
    );
  }

  Future<void> _addNewReminder() async {
    Boxes.reminders.add(
      Reminder(
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
      ),
    );
    await updateReminders();
    if (mounted) setState(() {});
  }

  Widget _buildEmptyState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40.0, vertical: 24.0),
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.notifications_active_outlined,
                  size: 80, color: Theme.of(context).primaryColor.withValues(alpha: 0.3)),
              const SizedBox(height: 24),
              Text(
                "Active Reminders",
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              Text(
                "Use reminders to stay on track. You can schedule them at specific times of the day or set repetitive intervals.\n\n"
                "Enable Persistent Mode to keep notifications on-screen until you dismiss them, perfect for important tasks like taking meds or standing up.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                      height: 1.5,
                    ),
              ),
              const SizedBox(height: 32),
              FilledButton.icon(
                onPressed: _addNewReminder,
                icon: const Icon(Icons.add_circle_outline_rounded),
                label: const Text("Create First Reminder", style: TextStyle(fontWeight: FontWeight.bold)),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
              ),
              const SizedBox(height: 140),
            ],
          ),
        ),
      ),
    );
  }

  void _showEditor(BuildContext context, int index) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500),
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
              child: ReminderEditor(
                remindersIndex: index,
                onDeleted: () async {
                  Boxes.reminders.removeAt(index);
                  await updateReminders();
                  Navigator.pop(context);
                  if (mounted) setState(() {});
                },
                onSaved: (Reminder reminder) async {
                  Boxes.reminders[index] = reminder.copyWith();
                  await updateReminders();
                  Navigator.pop(context);
                  if (mounted) setState(() {});
                },
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> updateReminders() async {
    await Boxes.updateSettings("reminders", jsonEncode(Boxes.reminders));
    Tasks().startReminders();
  }
}

class _ReminderTile extends StatefulWidget {
  final Reminder reminder;
  final int index;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  const _ReminderTile({
    required super.key,
    required this.reminder,
    required this.index,
    required this.onChanged,
    required this.onTap,
    required this.onDelete,
  });

  @override
  State<_ReminderTile> createState() => _ReminderTileState();
}

class _ReminderTileState extends State<_ReminderTile> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme colorScheme = theme.colorScheme;

    return MouseRegion(
      onEnter: (PointerEnterEvent _) => setState(() => _isHovered = true),
      onExit: (PointerExitEvent _) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface.withAlpha(80),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: colorScheme.primary.withAlpha(_isHovered ? 60 : 20),
            width: 1,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: Colors.black.withAlpha(10),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(12),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                color: _isHovered ? colorScheme.primary.withAlpha(8) : Colors.transparent,
              ),
              child: Row(
                children: <Widget>[
                  // Drag Handle
                  ReorderableDragStartListener(
                    index: widget.index,
                    child: Container(
                      padding: const EdgeInsets.only(right: 12.0),
                      child: Icon(Icons.drag_indicator_rounded, size: 20, color: colorScheme.onSurface.withAlpha(100)),
                    ),
                  ),
                  Checkbox(
                    value: widget.reminder.enabled,
                    onChanged: widget.onChanged,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Row(
                          children: <Widget>[
                            if (widget.reminder.persistent)
                              Padding(
                                padding: const EdgeInsets.only(right: 4.0),
                                child: Icon(Icons.warning_rounded, color: Colors.red.shade700, size: 16),
                              ),
                            Expanded(
                              child: Text(
                                widget.reminder.message,
                                style: theme.textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w600,
                                  color: widget.reminder.enabled
                                      ? (_isHovered ? colorScheme.primary : colorScheme.onSurface)
                                      : theme.disabledColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _getReminderFrequency(),
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.onSurface.withAlpha(150),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Hover Actions
                  AnimatedOpacity(
                    duration: const Duration(milliseconds: 150),
                    opacity: _isHovered ? 1.0 : 0.0,
                    child: Row(
                      children: <Widget>[
                        IconButton(
                          tooltip: "Delete",
                          icon: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error.withAlpha(200)),
                          onPressed: widget.onDelete,
                          splashRadius: 20,
                          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                          padding: EdgeInsets.zero,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right_rounded,
                    color: _isHovered ? colorScheme.primary : colorScheme.onSurface.withAlpha(80),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _getReminderFrequency() {
    final Reminder reminder = widget.reminder;
    final String base = reminder.repetitive
        ? 'Every ${reminder.time.formatTime()} (${reminder.interval[0].formatTime()} - ${reminder.interval[1].formatTime()})'
        : 'At ${reminder.time.formatTime()}';
    if (!reminder.repetitive && reminder.multipleTimes.isNotEmpty) {
      final String times =
          reminder.multipleTimes.map((int e) => e < 0 ? e.abs().ordinalSuffix() : e.formatTime()).join(', ');
      return '$base${reminder.multipleTimes[0] < 0 ? " on" : ", "} $times';
    }
    return base;
  }
}

class ReminderEditor extends StatefulWidget {
  final int remindersIndex;
  final void Function(Reminder reminder) onSaved;
  final void Function() onDeleted;

  const ReminderEditor({
    super.key,
    required this.remindersIndex,
    required this.onSaved,
    required this.onDeleted,
  });

  @override
  ReminderEditorState createState() => ReminderEditorState();
}

class ReminderEditorState extends State<ReminderEditor> {
  late Reminder reminder;
  late TextEditingController messageTextController;
  final TextEditingController intervalDaysController = TextEditingController();
  bool persistent = false;

  @override
  void initState() {
    reminder = Boxes.reminders[widget.remindersIndex].copyWith();
    messageTextController = TextEditingController(text: reminder.message);
    intervalDaysController.text = reminder.interval[1].toString();
    persistent = reminder.persistent;
    super.initState();
  }

  @override
  void dispose() {
    messageTextController.dispose();
    intervalDaysController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(theme),
        const SizedBox(height: 20),
        _buildMessageInput(theme),
        const SizedBox(height: 12),
        _buildNotificationSection(theme),
        const SizedBox(height: 12),
        _buildScheduleSection(theme),
        const SizedBox(height: 12),
        _buildActionButtons(theme),
      ],
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Text(
      "Reminder Properties",
      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
    );
  }

  Widget _buildMessageInput(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        TextField(
          controller: messageTextController,
          style: theme.textTheme.bodyLarge,
          decoration: _modernInputDecoration(context, "Reminder Message", theme.colorScheme.primary),
        ),
        const SizedBox(height: 8),
        SwitchListTile(
          contentPadding: const EdgeInsets.symmetric(horizontal: 8),
          visualDensity: VisualDensity.compact,
          tileColor: persistent ? theme.colorScheme.errorContainer.withValues(alpha: 0.1) : null,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          title: Text("Persistent Notification",
              style:
                  TextStyle(fontSize: 14, color: persistent ? theme.colorScheme.error : theme.colorScheme.onSurface)),
          subtitle:
              const Text("Adds a warning to QuickMenu that must be manually dismissed", style: TextStyle(fontSize: 12)),
          value: persistent,
          activeThumbColor: theme.colorScheme.error,
          onChanged: (bool value) => setState(() => persistent = value),
        ),
      ],
    );
  }

  Widget _buildNotificationSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text("Type", style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        _SegmentedSelector<bool>(
          value: reminder.voiceNotification,
          onChanged: (bool v) => setState(() => reminder.voiceNotification = v),
          items: const <SegmentItem<bool>>[
            SegmentItem<bool>(value: false, label: "Visual (Toast)", icon: Icons.visibility_rounded),
            SegmentItem<bool>(value: true, label: "Voice Announcement", icon: Icons.record_voice_over_rounded),
          ],
        ),
        if (reminder.voiceNotification) ...<Widget>[
          const SizedBox(height: 12),
          StatefulBuilder(
            builder: (BuildContext context, StateSetter setSliderState) {
              return Row(
                children: <Widget>[
                  const Icon(Icons.volume_up_rounded, size: 20),
                  Expanded(
                    child: Slider(
                      min: 0,
                      max: 100,
                      value: reminder.voiceVolume.toDouble(),
                      onChanged: (double v) {
                        setSliderState(() => reminder.voiceVolume = v.round());
                      },
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: Text(
                      "${reminder.voiceVolume}%",
                      style: theme.textTheme.bodySmall,
                      textAlign: TextAlign.end,
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ],
    );
  }

  Widget _buildScheduleSection(ThemeData theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        Text("Schedule", style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        const SizedBox(height: 6),
        _buildDaySelector(theme),
        const SizedBox(height: 16),
        _buildTypeAndInterval(theme),
      ],
    );
  }

  Widget _buildDaySelector(ThemeData theme) {
    if (reminder.interval[0] < 0) {
      return Row(
        children: <Widget>[
          const Text("Repeat every "),
          SizedBox(
            width: 50,
            child: TextField(
              controller: intervalDaysController,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(isDense: true),
              onChanged: (String v) {
                reminder.interval[1] = int.tryParse(v) ?? 1;
                if (reminder.interval[1] <= 0) reminder.interval[1] = 1;
                reminder.interval[0] = -DateTime.now().millisecondsSinceEpoch;
              },
            ),
          ),
          const Text(" days from today"),
        ],
      );
    }

    final List<String> days = <String>['M', 'T', 'W', 'T', 'F', 'S', 'S'];
    return ToggleButtons(
      borderRadius: BorderRadius.circular(8),
      constraints: const BoxConstraints(minHeight: 32, minWidth: 32),
      isSelected: reminder.weekDays,
      onPressed: (int index) => setState(() => reminder.weekDays[index] = !reminder.weekDays[index]),
      // Softer, less strident selection styling
      fillColor: theme.colorScheme.primary.withValues(alpha: 0.15),
      selectedColor: theme.colorScheme.primary,
      selectedBorderColor: theme.colorScheme.primary.withValues(alpha: 0.4),
      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
      borderColor: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
      splashColor: theme.colorScheme.primary.withValues(alpha: 0.1),
      children: days
          .map((String d) => Text(
                d,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
              ))
          .toList(),
    );
  }

  Widget _buildTypeAndInterval(ThemeData theme) {
    return Column(
      children: <Widget>[
        _SegmentedSelector<bool>(
          value: reminder.repetitive,
          onChanged: (bool v) => setState(() => reminder.repetitive = v),
          items: const <SegmentItem<bool>>[
            SegmentItem<bool>(value: true, label: "Repetitive (Interval)", icon: Icons.repeat_rounded),
            SegmentItem<bool>(value: false, label: "Daily (Specific)", icon: Icons.today_rounded),
          ],
        ),
        const SizedBox(height: 12),
        AnimatedSwitcher(
          duration: const Duration(milliseconds: 300),
          switchInCurve: Curves.easeOutCubic,
          switchOutCurve: Curves.easeInCubic,
          transitionBuilder: (Widget child, Animation<double> animation) {
            return FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(0.0, 0.05),
                  end: Offset.zero,
                ).animate(animation),
                child: child,
              ),
            );
          },
          child: reminder.repetitive
              ? _buildRepetitiveInputs(theme, key: const ValueKey<String>('repetitive'))
              : _buildDailyInputs(theme, key: const ValueKey<String>('daily')),
        ),
      ],
    );
  }

  Widget _buildRepetitiveInputs(ThemeData theme, {Key? key}) {
    return Column(
      key: key,
      children: <Widget>[
        InkWell(
          onTap: () async {
            final int? res = await _selectMinutes(theme, reminder.time);
            if (res != null) setState(() => reminder.time = res);
          },
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: theme.colorScheme.primary.withValues(alpha: 0.15),
              ),
            ),
            child: Row(
              children: <Widget>[
                Icon(Icons.timer_outlined, color: theme.colorScheme.primary, size: 18),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text("Repeat Interval",
                          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary, fontSize: 10)),
                      Text(
                        "Every ${reminder.time} minutes",
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.edit_rounded, size: 14, color: theme.colorScheme.primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            Expanded(
              child: _TimeTile(
                label: "Starts",
                time: reminder.interval[0],
                onTap: () => _pickTime(0),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _TimeTile(
                label: "Ends",
                time: reminder.interval[1],
                onTap: () => _pickTime(1),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildDailyInputs(ThemeData theme, {Key? key}) {
    return Column(
      key: key,
      children: <Widget>[
        _TimeTile(
          label: "Main Reminder",
          time: reminder.time,
          onTap: () => _pickMainTime(),
        ),
        ...reminder.multipleTimes.asMap().entries.map((MapEntry<int, int> entry) {
          final int i = entry.key;
          final int t = entry.value;
          return Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: _TimeTile(
              label: t < 0 ? "Specific Day" : "Alternate Time",
              time: t < 0 ? -1 : t,
              customText: t < 0 ? "Day ${t.abs().ordinalSuffix()}" : null,
              onTap: () => t < 0 ? _pickMonthDay(i) : _pickAlternateTime(i),
              onDelete: () => setState(() => reminder.multipleTimes.removeAt(i)),
            ),
          );
        }),
        const SizedBox(height: 12),
        Row(
          children: <Widget>[
            if (reminder.multipleTimes.every((int t) => t >= 0))
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.more_time_rounded, size: 18),
                  label: const Text("Add Time"),
                  onPressed: () {
                    setState(() => reminder.multipleTimes.add(DateTime.now().hour * 60 + DateTime.now().minute));
                  },
                ),
              ),
            const SizedBox(width: 8),
            if (reminder.multipleTimes.every((int t) => t < 0))
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.event_note_rounded, size: 18),
                  label: const Text("Add Date"),
                  onPressed: () {
                    setState(() => reminder.multipleTimes.add(-DateTime.now().day));
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildActionButtons(ThemeData theme) {
    return Row(
      children: <Widget>[
        TextButton.icon(
          onPressed: widget.onDeleted,
          icon: Icon(Icons.delete_outline_rounded, color: theme.colorScheme.error),
          label: Text("Delete", style: TextStyle(color: theme.colorScheme.error)),
        ),
        const Spacer(),
        ElevatedButton(
          onPressed: () {
            reminder.message = messageTextController.text;
            reminder.persistent = persistent;
            widget.onSaved(reminder);
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: theme.colorScheme.primaryContainer,
            foregroundColor: theme.colorScheme.onPrimaryContainer,
            elevation: 0,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
              side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.2)),
            ),
          ).copyWith(
            overlayColor: WidgetStateProperty.all(theme.colorScheme.primary.withValues(alpha: 0.1)),
          ),
          child: const Text("Apply", style: TextStyle(fontWeight: FontWeight.bold)),
        ),
      ],
    );
  }

  Future<void> _pickTime(int intervalIndex) async {
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime:
          TimeOfDay(hour: reminder.interval[intervalIndex] ~/ 60, minute: reminder.interval[intervalIndex] % 60),
    );
    if (t != null) {
      setState(() {
        reminder.interval[intervalIndex] = t.hour * 60 + t.minute;
        if (intervalIndex == 0 && reminder.interval[0] + reminder.time > reminder.interval[1]) {
          reminder.interval[1] = reminder.interval[0] + reminder.time;
        }
      });
    }
  }

  Future<void> _pickMainTime() async {
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminder.time ~/ 60, minute: reminder.time % 60),
    );
    if (t != null) setState(() => reminder.time = t.hour * 60 + t.minute);
  }

  Future<void> _pickAlternateTime(int index) async {
    final TimeOfDay? t = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: reminder.multipleTimes[index] ~/ 60, minute: reminder.multipleTimes[index] % 60),
    );
    if (t != null) setState(() => reminder.multipleTimes[index] = t.hour * 60 + t.minute);
  }

  Future<void> _pickMonthDay(int index) async {
    final DateTime now = DateTime.now();
    final DateTime? res = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year, now.month, reminder.multipleTimes[index].abs().clamp(1, 28)),
      firstDate: DateTime(now.year, now.month, 1),
      lastDate: DateTime(now.year, now.month + 1, 0),
    );
    if (res != null) setState(() => reminder.multipleTimes[index] = -res.day);
  }

  Future<int?> _selectMinutes(ThemeData theme, int current) async {
    int val = current;
    final TextEditingController controller = TextEditingController(text: val.toString());
    return showDialog<int>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text("Repeat Interval"),
        content: StatefulBuilder(
          builder: (BuildContext context, void Function(void Function()) setDimState) => Column(
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
                      style: theme.textTheme.headlineMedium?.copyWith(
                        color: theme.colorScheme.primary,
                        fontWeight: FontWeight.bold,
                      ),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      controller: controller,
                      onChanged: (String v) {
                        final int? n = int.tryParse(v);
                        if (n != null && n > 0) {
                          setDimState(() => val = n);
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text("minutes", style: theme.textTheme.bodyLarge),
                ],
              ),
              const SizedBox(height: 24),
              Slider(
                min: 1,
                max: 240,
                value: val.toDouble().clamp(1, 240),
                onChanged: (double v) => setDimState(() {
                  val = v.round();
                  controller.text = val.toString();
                }),
              ),
              Text(
                "Slide or type to adjust",
                style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.pop(context, val), child: const Text("OK")),
        ],
      ),
    );
  }

  InputDecoration _modernInputDecoration(BuildContext context, String label, Color accent) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accent.withAlpha(20), width: 1)),
      focusedBorder:
          OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: accent, width: 1.2)),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurface.withAlpha(150)),
    );
  }
}

class SegmentItem<T> {
  final T value;
  final String label;
  final IconData? icon;
  const SegmentItem({required this.value, required this.label, this.icon});
}

class _SegmentedSelector<T> extends StatelessWidget {
  final T value;
  final List<SegmentItem<T>> items;
  final ValueChanged<T> onChanged;

  const _SegmentedSelector({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return Container(
      height: 52,
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
        color: colors.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.1)),
      ),
      child: Row(
        children: items.map((SegmentItem<T> item) {
          final bool isSelected = item.value == value;
          return Expanded(
            child: _SegmentButton<T>(
              item: item,
              isSelected: isSelected,
              onTap: () => onChanged(item.value),
            ),
          );
        }).toList(),
      ),
    );
  }
}

class _SegmentButton<T> extends StatefulWidget {
  final SegmentItem<T> item;
  final bool isSelected;
  final VoidCallback onTap;

  const _SegmentButton({
    required this.item,
    required this.isSelected,
    required this.onTap,
  });

  @override
  State<_SegmentButton<T>> createState() => _SegmentButtonState<T>();
}

class _SegmentButtonState<T> extends State<_SegmentButton<T>> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ColorScheme colors = Theme.of(context).colorScheme;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 12),
          decoration: BoxDecoration(
            color: widget.isSelected
                ? colors.primary.withValues(alpha: 0.18)
                : (_isHovered ? colors.primary.withValues(alpha: 0.08) : Colors.transparent),
            borderRadius: BorderRadius.circular(7),
            border: widget.isSelected
                ? Border.all(color: colors.primary.withValues(alpha: 0.25))
                : Border.all(color: Colors.transparent),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              if (widget.item.icon != null) ...<Widget>[
                Icon(
                  widget.item.icon,
                  size: 16,
                  color: widget.isSelected ? colors.primary : colors.onSurfaceVariant,
                ),
                const SizedBox(width: 8),
              ],
              Text(
                widget.item.label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: widget.isSelected ? FontWeight.bold : FontWeight.w500,
                  color: widget.isSelected ? colors.primary : colors.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TimeTile extends StatelessWidget {
  final String label;
  final int time;
  final String? customText;
  final VoidCallback onTap;
  final VoidCallback? onDelete;

  const _TimeTile({
    required this.label,
    required this.time,
    required this.onTap,
    this.customText,
    this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Row(
          children: <Widget>[
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(label, style: theme.textTheme.labelSmall?.copyWith(fontSize: 10, height: 1)),
                  const SizedBox(height: 2),
                  Text(
                    customText ?? (time >= 0 ? time.formatTime() : "--:--"),
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold, height: 1.2),
                  ),
                ],
              ),
            ),
            if (onDelete != null)
              IconButton(
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                icon: Icon(Icons.close_rounded, size: 16, color: theme.colorScheme.error),
                onPressed: onDelete,
              )
            else
              Icon(Icons.edit_rounded, size: 14, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
          ],
        ),
      ),
    );
  }
}
