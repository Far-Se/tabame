import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/info_text.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';

class ShutDownButton extends StatefulWidget {
  const ShutDownButton({super.key});

  @override
  State<ShutDownButton> createState() => _ShutDownButtonState();
}

class _ShutDownButtonState extends State<ShutDownButton> with QuickMenuTriggers {
  @override
  void initState() {
    QuickMenuFunctions.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "ScheduleShutdown") {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return ModalButton(
        actionName: "Shutdown",
        icon: Icon(
          Icons.power_settings_new_rounded,
          color: (Boxes.pref.getBool("isShutDownScheduled") ?? false) ? Colors.red.shade300 : null,
        ),
        child: () => const ShutDownWidget());
  }
}

class ShutDownWidget extends StatefulWidget {
  const ShutDownWidget({super.key});
  @override
  ShutDownWidgetState createState() => ShutDownWidgetState();
}

class ShutDownWidgetState extends State<ShutDownWidget> with QuickMenuTriggers {
  bool isShutDownScheduled = false;
  bool isWarningActive = false;
  bool alwaysAtTime = false;
  int shutDownUnix = 0;
  String? selectedTimerType = "ShutDown at";
  final TextEditingController minutesController = TextEditingController(text: "00");
  final TextEditingController hoursController = TextEditingController(text: "00");

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "ShutDownScheduler") {
      QuickMenuFunctions.toggleQuickMenu(center: true, visible: true);
      setState(() {
        isWarningActive = true;
      });
    }
  }

  @override
  void initState() {
    QuickMenuFunctions.addListener(this);
    isShutDownScheduled = Boxes.pref.getBool("isShutDownScheduled") ?? false;
    alwaysAtTime = Boxes.pref.getBool("alwaysShutDownAtTime") ?? false;
    shutDownUnix = Boxes.pref.getInt("shutDownUnix") ?? 0;
    if (shutDownUnix != 0) {
      final DateTime scheduledTime = DateTime.fromMillisecondsSinceEpoch(shutDownUnix);
      final DateTime now = DateTime.now();
      if (scheduledTime.isBefore(now)) {
        isShutDownScheduled = false;
      } else {
        if (selectedTimerType == "ShutDown at") {
          hoursController.text = scheduledTime.hour.toString().padLeft(2, '0');
          minutesController.text = scheduledTime.minute.toString().padLeft(2, '0');
        } else {
          final Duration diff = scheduledTime.difference(now);
          hoursController.text = diff.inHours.toString().padLeft(2, '0');
          minutesController.text = (diff.inMinutes % 60).toString().padLeft(2, '0');
        }
        final Duration diff = scheduledTime.difference(now);
        if (diff.inMinutes <= 1) {
          isWarningActive = true;
        }
      }
    }
    super.initState();
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    hoursController.dispose();
    minutesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    final bool isShutdownIn = selectedTimerType == "ShutDown in";
    final DateTime scheduledTime = DateTime.fromMillisecondsSinceEpoch(shutDownUnix);
    final String scheduledLabel = "Shut Down at ${(scheduledTime.hour * 60 + scheduledTime.minute).formatTime()}";

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        PanelHeader(title: "Shutdown Scheduler", accent: scheme.primary, icon: Icons.power_settings_new_rounded),
        Flexible(
          child: SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.all(4),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _ModeButton(
                            label: "At time",
                            icon: Icons.schedule_rounded,
                            selected: !isShutdownIn,
                            onTap: () {
                              selectedTimerType = "ShutDown at";
                              if (isShutDownScheduled) {
                                final DateTime scheduledTime = DateTime.fromMillisecondsSinceEpoch(shutDownUnix);
                                hoursController.text = scheduledTime.hour.toString().padLeft(2, '0');
                                minutesController.text = scheduledTime.minute.toString().padLeft(2, '0');
                              }
                              setState(() {});
                            },
                          ),
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: _ModeButton(
                            label: "In",
                            icon: Icons.timer_outlined,
                            selected: isShutdownIn,
                            onTap: () {
                              selectedTimerType = "ShutDown in";
                              if (isShutDownScheduled) {
                                final DateTime scheduledTime = DateTime.fromMillisecondsSinceEpoch(shutDownUnix);
                                Duration diff = scheduledTime.difference(DateTime.now());
                                if (diff.isNegative) diff = Duration.zero;
                                hoursController.text = diff.inHours.toString().padLeft(2, '0');
                                minutesController.text = (diff.inMinutes % 60).toString().padLeft(2, '0');
                              }
                              setState(() {});
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(22),
                      color: scheme.surface.withValues(alpha: 0.58),
                      border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
                    ),
                    child: Row(
                      children: <Widget>[
                        Expanded(
                          child: _buildTimeField(
                            context: context,
                            controller: hoursController,
                            label: "Hours",
                            onSubmitted: (_) => setState(() {}),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Text(
                            ":",
                            style: theme.textTheme.displaySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              height: 0.9,
                              color: scheme.onSurface.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                        Expanded(
                          child: _buildTimeField(
                            context: context,
                            controller: minutesController,
                            label: "Minutes",
                            onSubmitted: (_) => setState(() {}),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 7),
                  if (!isWarningActive && !isShutdownIn) _buildAlwaysToggle(context),
                  const SizedBox(height: 7),
                  AnimatedSwitcher(
                    duration: const Duration(milliseconds: 180),
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    child: isWarningActive
                        ? _buildWarningState(context)
                        : isShutDownScheduled
                            ? _buildScheduledState(context, scheduledLabel)
                            : FilledButton.icon(
                                key: const ValueKey<String>("schedule-actions"),
                                onPressed: _scheduleShutdown,
                                icon: const Icon(Icons.bolt_rounded, size: 18),
                                label: const Text("Schedule"),
                                style: FilledButton.styleFrom(
                                  minimumSize: const Size.fromHeight(46),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                                ),
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAlwaysToggle(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;
    return InkWell(
      onTap: () {
        setState(() {
          alwaysAtTime = !alwaysAtTime;
          Boxes.pref.setBool("alwaysShutDownAtTime", alwaysAtTime);
          if (alwaysAtTime) {
            Boxes.pref.setString("savedShutDownTime", "${hoursController.text}:${minutesController.text}");
            _scheduleShutdown();
          } else {
            Boxes.pref.setString("savedShutDownTime", "");
          }
        });
      },
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
        child: Row(
          children: <Widget>[
            Icon(
              alwaysAtTime ? Icons.check_box_rounded : Icons.check_box_outline_blank_rounded,
              color: alwaysAtTime ? scheme.primary : scheme.onSurface.withValues(alpha: 0.5),
              size: 20,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    "Always shutdown at this time",
                    style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  Text(
                    "Triggers every day at the specified time",
                    style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurface.withValues(alpha: 0.6)),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildWarningState(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      key: const ValueKey<String>("warning-state"),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(22),
        color: scheme.error.withValues(alpha: 0.08),
        border: Border.all(color: scheme.error.withValues(alpha: 0.2), width: 2),
      ),
      child: Column(
        children: <Widget>[
          Icon(Icons.warning_amber_rounded, color: scheme.error, size: 48),
          const SizedBox(height: 16),
          Text(
            "SYSTEM SHUTDOWN IMMINENT",
            textAlign: TextAlign.center,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w900,
              color: scheme.error,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            "Your computer is scheduled to shut down in 1 minute. Please save your work immediately.",
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.4),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: () {
              setState(() {
                isWarningActive = false;
                isShutDownScheduled = false;
                Boxes.pref.setBool("isShutDownScheduled", false);
                Boxes.pref.setInt("shutDownUnix", 0);
                Boxes.shutDownTimer?.cancel();
                Boxes.shutDownWarningTimer?.cancel();
                QuickMenuFunctions.triggerQuickAction("ScheduleShutdown");
              });
            },
            icon: const Icon(Icons.close_rounded),
            label: const Text("CANCEL SHUTDOWN"),
            style: FilledButton.styleFrom(
              backgroundColor: scheme.error,
              foregroundColor: scheme.onError,
              minimumSize: const Size.fromHeight(50),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimeField({
    required BuildContext context,
    required TextEditingController controller,
    required String label,
    required ValueChanged<String> onSubmitted,
  }) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.42),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.12)),
      ),
      padding: const EdgeInsets.fromLTRB(12, 3, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Center(child: InfoText(label)),
          Focus(
            onFocusChange: (bool hasFocus) {
              if (!hasFocus) {
                controller.text = controller.text.padLeft(2, "0");
              }
            },
            child: TextField(
              controller: controller,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              inputFormatters: <TextInputFormatter>[
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(2),
              ],
              style: theme.textTheme.displaySmall?.copyWith(
                fontWeight: FontWeight.w700,
                height: 1,
                letterSpacing: -1,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: "00",
                hintStyle: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1,
                  letterSpacing: -1,
                  color: scheme.onSurface.withValues(alpha: 0.26),
                ),
                border: InputBorder.none,
              ),
              onSubmitted: onSubmitted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildScheduledState(BuildContext context, String scheduledLabel) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return Container(
      key: const ValueKey<String>("scheduled-state"),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        color: scheme.primary.withValues(alpha: 0.09),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(Icons.check_circle_rounded, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  "Shutdown scheduled",
                  style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            scheduledLabel,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 12),
          OutlinedButton.icon(
            onPressed: () {
              isShutDownScheduled = false;
              Boxes.pref.setBool("isShutDownScheduled", isShutDownScheduled);
              Boxes.pref.setInt("shutDownUnix", 0);
              Boxes.shutDownTimer?.cancel();
              QuickMenuFunctions.triggerQuickAction("ScheduleShutdown");
              setState(() {});
            },
            icon: const Icon(Icons.close_rounded, size: 18),
            label: const Text("Cancel schedule"),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ],
      ),
    );
  }

  void _scheduleShutdown() {
    Boxes.shutDownTimer?.cancel();
    final int hour = int.tryParse(hoursController.text) ?? 0;
    final int minute = int.tryParse(minutesController.text) ?? 0;
    final Duration duration = Duration(hours: hour, minutes: minute);

    if (selectedTimerType == "ShutDown in") {
      if (duration.inSeconds < 120) return;
      shutDownUnix = DateTime.now().millisecondsSinceEpoch + duration.inMilliseconds;
    } else {
      final DateTime now = DateTime.now();
      DateTime target = DateTime(now.year, now.month, now.day, hour, minute);
      if (target.isBefore(now)) {
        target = target.add(const Duration(days: 1));
      }
      shutDownUnix = target.millisecondsSinceEpoch;
    }

    isShutDownScheduled = true;
    Boxes.pref.setBool("isShutDownScheduled", isShutDownScheduled);
    Boxes.pref.setInt("shutDownUnix", shutDownUnix);
    if (alwaysAtTime) {
      Boxes.pref.setString(
          "savedShutDownTime", "${hoursController.text.padLeft(2, '0')}:${minutesController.text.padLeft(2, '0')}");
    }
    Boxes.shutDownScheduler();
    QuickMenuFunctions.triggerQuickAction("ScheduleShutdown");
    setState(() {});
  }
}

class _ModeButton extends StatelessWidget {
  const _ModeButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final ColorScheme scheme = theme.colorScheme;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: selected ? scheme.primary : Colors.transparent,
        boxShadow: selected
            ? <BoxShadow>[
                BoxShadow(
                  color: scheme.primary.withValues(alpha: 0.22),
                  blurRadius: 12,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                Icon(
                  icon,
                  size: 16,
                  color: selected ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.72),
                ),
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: selected ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.78),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
