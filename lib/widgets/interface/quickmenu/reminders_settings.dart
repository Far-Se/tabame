import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/util/app_opacity.dart';
import '../../widgets/windows_scroll.dart';

class QuickmenuRemindersSettingsPage extends StatefulWidget {
  const QuickmenuRemindersSettingsPage({super.key});

  @override
  State<QuickmenuRemindersSettingsPage> createState() => _QuickmenuRemindersSettingsPageState();
}

class _QuickmenuRemindersSettingsPageState extends State<QuickmenuRemindersSettingsPage> {
  final List<Reminder> reminders = Boxes.reminders;

  @override
  Widget build(BuildContext context) {
    final Color accent = userSettings.themeColors.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

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
                    _buildHeaderCard(context, accent, onSurface),
                    const SizedBox(height: 16),
                    if (reminders.isEmpty)
                      _buildEmptyState(context, accent, onSurface)
                    else
                      ReorderableListView.builder(
                        buildDefaultDragHandles: false,
                        shrinkWrap: true,
                        itemCount: reminders.length,
                        physics: const NeverScrollableScrollPhysics(),
                        itemBuilder: (BuildContext context, int index) {
                          final Reminder reminder = reminders[index];
                          return _ReminderCard(
                            key: ValueKey<int>(index),
                            reminder: reminder,
                            index: index,
                            accent: accent,
                            onSurface: onSurface,
                            onChanged: (bool? value) async {
                              reminder.enabled = value ?? false;
                              await _updateReminders();
                              setState(() {});
                            },
                            onTap: () => _showEditor(context, index),
                            onDelete: () => _confirmDelete(context, index),
                          );
                        },
                        onReorderItem: (int oldIndex, int newIndex) async {
                          if (oldIndex < newIndex) newIndex -= 1;
                          final Reminder item = reminders.removeAt(oldIndex);
                          reminders.insert(newIndex, item);
                          await _updateReminders();
                          setState(() {});
                        },
                      ),
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

  Widget _buildHeaderCard(BuildContext context, Color accent, Color onSurface) {
    final ThemeData theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: theme.cardColor.withValues(alpha: 0.4),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.dividerColor.withValues(alpha: AppOpacity.border)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.notification_important_rounded, color: accent, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "Active Reminders",
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                Text(
                  "Schedule voice or visual notifications for important tasks",
                  style: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.5)),
                ),
              ],
            ),
          ),
          FilledButton.icon(
            onPressed: _addNewReminder,
            icon: const Icon(Icons.add_alert_rounded, size: 18),
            label: const Text("New Reminder"),
            style: FilledButton.styleFrom(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context, Color accent, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 60),
      child: Column(
        children: <Widget>[
          Icon(Icons.notifications_off_outlined, size: 64, color: onSurface.withValues(alpha: 0.1)),
          const SizedBox(height: 24),
          Text(
            "No Reminders Scheduled",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: onSurface.withValues(alpha: 0.8)),
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40),
            child: Text(
              "Stay on track with custom notifications. Add your first reminder to get started.",
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13, color: onSurface.withValues(alpha: 0.4)),
            ),
          ),
        ],
      ),
    );
  }

  void _addNewReminder() async {
    reminders.add(
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
    await _updateReminders();
    setState(() {});
  }

  Future<void> _updateReminders() async {
    await Boxes.updateSettings("reminders", jsonEncode(reminders));
    Tasks().startReminders();
  }

  void _confirmDelete(BuildContext context, int index) {
    final Reminder reminder = reminders[index];
    showDialog<void>(
      context: context,
      builder: (BuildContext ctx) => AlertDialog(
        title: const Text("Delete Reminder?"),
        content: Text("Permanently delete '${reminder.message}'?"),
        actions: <Widget>[
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text("Cancel")),
          FilledButton(
            onPressed: () async {
              reminders.removeAt(index);
              await _updateReminders();
              if (mounted) setState(() {});
              if (context.mounted) Navigator.pop(ctx);
            },
            style: FilledButton.styleFrom(backgroundColor: Theme.of(context).colorScheme.error),
            child: const Text("Delete"),
          ),
        ],
      ),
    );
  }

  void _showEditor(BuildContext context, int index) {
    showDialog<void>(
      context: context,
      builder: (BuildContext context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 500, maxHeight: 800),
            child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: AppOpacity.border)),
              ),
              child: ReminderEditor(
                remindersIndex: index,
                onDeleted: () async {
                  reminders.removeAt(index);
                  await _updateReminders();
                  Navigator.pop(context);
                  if (mounted) setState(() {});
                },
                onSaved: (Reminder reminder) async {
                  reminders[index] = reminder.copyWith();
                  await _updateReminders();
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
}

class _ReminderCard extends StatefulWidget {
  const _ReminderCard({
    required super.key,
    required this.reminder,
    required this.index,
    required this.accent,
    required this.onSurface,
    required this.onChanged,
    required this.onTap,
    required this.onDelete,
  });

  final Reminder reminder;
  final int index;
  final Color accent;
  final Color onSurface;
  final ValueChanged<bool?> onChanged;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  State<_ReminderCard> createState() => _ReminderCardState();
}

class _ReminderCardState extends State<_ReminderCard> {
  bool _isHovering = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final bool isEnabled = widget.reminder.enabled;

    return MouseRegion(
      onEnter: (_) => setState(() => _isHovering = true),
      onExit: (_) => setState(() => _isHovering = false),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: theme.cardColor.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(16),
          border:
              Border.all(color: userSettings.themeColors.accent.withValues(alpha: _isHovering ? 0.3 : 0.08), width: 1),
        ),
        child: InkWell(
          onTap: widget.onTap,
          borderRadius: BorderRadius.circular(16),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: <Widget>[
                ReorderableDragStartListener(
                  index: widget.index,
                  child: Icon(Icons.drag_indicator_rounded, size: 20, color: widget.onSurface.withAlpha(80)),
                ),
                const SizedBox(width: 8),
                Checkbox(
                  value: isEnabled,
                  onChanged: widget.onChanged,
                  activeColor: userSettings.themeColors.accent,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          if (widget.reminder.persistent)
                            const Padding(
                              padding: EdgeInsets.only(right: 6),
                              child: Icon(Icons.priority_high_rounded, color: Colors.orange, size: 14),
                            ),
                          Expanded(
                            child: Text(
                              widget.reminder.message,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isEnabled ? widget.onSurface : widget.onSurface.withValues(alpha: 0.3),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _getFrequencyText(),
                        style: TextStyle(
                          fontSize: 11,
                          color: widget.onSurface.withValues(alpha: isEnabled ? 0.5 : 0.2),
                        ),
                      ),
                    ],
                  ),
                ),
                if (widget.reminder.voiceNotification)
                  Icon(Icons.record_voice_over_rounded,
                      size: 16, color: userSettings.themeColors.accent.withValues(alpha: 0.5)),
                const SizedBox(width: 12),
                if (_isHovering)
                  IconButton(
                    icon: Icon(Icons.delete_outline_rounded, size: 20, color: Colors.red.withValues(alpha: 0.6)),
                    onPressed: widget.onDelete,
                    visualDensity: VisualDensity.compact,
                  )
                else
                  Icon(Icons.chevron_right_rounded, color: widget.onSurface.withValues(alpha: 0.1)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _getFrequencyText() {
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

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
      child: Column(
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
      ),
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
