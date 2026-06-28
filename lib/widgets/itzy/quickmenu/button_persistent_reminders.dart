import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class PersistentRemindersWidget extends StatefulWidget {
  const PersistentRemindersWidget({super.key});

  @override
  State<PersistentRemindersWidget> createState() => _PersistentRemindersWidgetState();
}

class _PersistentRemindersWidgetState extends State<PersistentRemindersWidget> with QuickMenuTriggers {
  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> refreshQuickMenu() async {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final int count = user.persistentReminders.length;
    return ModalButton(
      actionName: "Reminders",
      onSecondaryTap: () {
        user.persistentReminders.clear();
        Boxes.pref.setStringList("persistentReminders", user.persistentReminders);
        QuickMenuFunctions.refreshQuickMenu();
        setState(() {});
      },
      icon: count > 0
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 5),
              child: Badge.count(
                offset: const Offset(8, -5),
                count: count,
                backgroundColor: Colors.transparent,
                textStyle: const TextStyle(fontSize: 9),
                textColor: Colors.white,
                child: const Icon(Icons.warning_rounded, color: Colors.red),
              ),
            )
          : const Icon(Icons.warning_rounded, color: Colors.red),
      child: () => const RemindersPanel(),
    );
  }
}

class RemindersPanel extends StatefulWidget {
  const RemindersPanel({super.key});
  @override
  RemindersPanelState createState() => RemindersPanelState();
}

class RemindersPanelState extends State<RemindersPanel> {
  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return Column(
      children: <Widget>[
        const PanelHeader(
          title: "REMINDERS",
          icon: Icons.warning_rounded,
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: user.persistentReminders.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 40),
                      child: Opacity(
                        opacity: 0.5,
                        child: Text(
                          "No active reminders",
                          style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface),
                        ),
                      ),
                    ),
                  )
                : Material(
                    type: MaterialType.transparency,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: <Widget>[
                        _buildSectionLabel(
                          label: "Active",
                          accent: accent,
                          onSurface: onSurface,
                          count: user.persistentReminders.length,
                          icon: Icons.notifications_active_outlined,
                        ),
                        const SizedBox(height: 10),
                        ...List<Widget>.generate(
                          user.persistentReminders.length,
                          (int index) => _buildReminderCard(
                            index: index,
                            text: user.persistentReminders.elementAt(index),
                            accent: accent,
                            onSurface: onSurface,
                          ),
                        ),
                      ],
                    ),
                  ),
          ),
        ),
        if (user.persistentReminders.isNotEmpty)
          _buildFixedBottomBar(
            context: context,
            accent: Colors.redAccent,
            label: "CLEAR ALL REMINDERS",
            onTap: () {
              user.persistentReminders.clear();
              Boxes.pref.setStringList("persistentReminders", user.persistentReminders);
              QuickMenuFunctions.refreshQuickMenu();
              setState(() {});
            },
          ),
      ],
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
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: onSurface,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(
            color: accent.withAlpha(28),
            borderRadius: BorderRadius.circular(99),
          ),
          child: Text("$count", style: TextStyle(fontSize: Design.baseFontSize, color: accent)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: onSurface.withAlpha(20))),
      ],
    );
  }

  Widget _buildReminderCard({
    required int index,
    required String text,
    required Color accent,
    required Color onSurface,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withAlpha(16)),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          user.persistentReminders.removeAt(index);
          Boxes.pref.setStringList("persistentReminders", user.persistentReminders);
          QuickMenuFunctions.refreshQuickMenu();
          setState(() {});
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            children: <Widget>[
              Icon(Icons.circle, size: 6, color: accent.withAlpha(180)),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text,
                  style: TextStyle(
                    fontSize: Design.baseFontSize + 2,
                    color: onSurface,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              Icon(Icons.chevron_right_rounded, size: 16, color: onSurface.withAlpha(100)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFixedBottomBar({
    required BuildContext context,
    required Color accent,
    required String label,
    required VoidCallback onTap,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withAlpha(100),
        border: Border(top: BorderSide(color: Theme.of(context).colorScheme.onSurface.withAlpha(15))),
      ),
      child: Center(
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 32),
            constraints: const BoxConstraints(minWidth: double.infinity),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withAlpha(28),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withAlpha(80), width: 1),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: accent,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
