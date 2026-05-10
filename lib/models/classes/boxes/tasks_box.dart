import 'dart:async';

import '../../settings.dart';
import '../../win32/win_utils.dart';
import '../boxes.dart';
import '../saved_maps.dart';

// --------------------------------------------------------------------------
// Tasks
// --------------------------------------------------------------------------

class Tasks {
  final Map<Reminder, int> remindersTime = <Reminder, int>{};

  void processReminders({bool reset = false}) {
    if (reset) remindersTime.clear();
    if (remindersTime.isEmpty) {
      for (Reminder reminder in Boxes.reminders) {
        if (!reminder.enabled) continue;
        remindersTime[reminder] = reminder.time;
      }
    }
  }

  Timer? _timer;

  void initReminders() {
    _timer?.cancel();
    final DateTime now = DateTime.now();

    Timer(Duration(seconds: 60 - now.second, milliseconds: 60 - now.millisecond), () {
      void callback() {
        final DateTime now = DateTime.now();
        final int nowInMinutes = now.hour * 60 + now.minute;

        for (final Reminder reminder in Boxes.reminders) {
          if (!reminder.enabled) continue;

          if (reminder.repetitive) {
            if (!(nowInMinutes.isBetweenEqual(reminder.interval[0], reminder.interval[1]) &&
                reminder.weekDays[DateTime.now().weekday - 1])) {
              continue;
            }

            int timerInMinutes = 0;
            while (timerInMinutes < nowInMinutes) {
              timerInMinutes += reminder.time;
            }
            if (timerInMinutes == nowInMinutes) triggerReminder(reminder);
          } else {
            if (!reminder.weekDays[DateTime.now().weekday - 1]) continue;

            if (nowInMinutes == reminder.time) {
              if (reminder.multipleTimes.isNotEmpty) {
                if (reminder.multipleTimes[0] < 0) {
                  final int day = -DateTime.now().day;
                  if (reminder.multipleTimes.contains(day)) triggerReminder(reminder);
                } else {
                  triggerReminder(reminder);
                }
              } else {
                triggerReminder(reminder);
              }
            }

            for (int rem in reminder.multipleTimes) {
              if (rem > 0 && nowInMinutes == rem) triggerReminder(reminder);
            }
          }
        }
      }

      callback();
      _timer = Timer.periodic(const Duration(minutes: 1), (Timer timer) => callback());
    });
  }

  void startReminders() {
    initReminders();
  }

  void triggerReminder(Reminder reminder) {
    if (reminder.voiceNotification) {
      WinUtils.textToSpeech(reminder.message, repeat: -1, volume: reminder.voiceVolume);
    } else {
      WinUtils.showWindowsNotification(
        title: "Tabame Reminder",
        body: "Reminder: ${reminder.message}",
        onClick: () {},
      );
    }
    if (reminder.persistent) {
      userSettings.persistentReminders.add(
        "${reminder.message} ${DateTime.now().hour.formatZeros()}:${DateTime.now().minute.formatZeros()}",
      );
      Boxes.pref.setStringList("persistentReminders", userSettings.persistentReminders);
      QuickMenuFunctions.refreshQuickMenu();
    }
  }

  void reminderPeriodic(Reminder reminder) {
    if (!reminder.enabled) return;
    final int now = DateTime.now().hour * 60 + DateTime.now().minute;

    if (now.isBetweenEqual(reminder.interval[0], reminder.interval[1]) &&
        reminder.weekDays[DateTime.now().weekday - 1]) {
      if (reminder.voiceNotification) {
        WinUtils.textToSpeech(reminder.message, repeat: -1, volume: reminder.voiceVolume);
      } else {
        WinUtils.showWindowsNotification(
          title: "Tabame Reminder",
          body: "Reminder: ${reminder.message}",
          onClick: () {},
        );
      }
      if (reminder.persistent) {
        userSettings.persistentReminders.add(
          "${reminder.message} ${DateTime.now().hour.formatZeros()}:${DateTime.now().minute.formatZeros()}",
        );
        Boxes.pref.setStringList("persistentReminders", userSettings.persistentReminders);
        QuickMenuFunctions.refreshQuickMenu();
      }
    }

    reminder.timer = Timer(Duration(minutes: reminder.time), () => reminderPeriodic(reminder));
  }

  void reminderDaily(Reminder reminder) {
    if (!reminder.enabled) return;
    bool correctDay = reminder.weekDays[DateTime.now().weekday - 1];

    // Note: negative interval[0] encodes a recurring-day-of-month schedule (intentional design).
    if (correctDay && reminder.interval[0] < 0) {
      if (reminder.interval[1] <= 0) reminder.interval[1] = 1;
      final DateTime day = DateTime.fromMillisecondsSinceEpoch(reminder.interval[0].abs());
      final DateTime today = DateTime.now();
      DateTime span = day;
      int ticks = 0;
      while (span.millisecondsSinceEpoch < today.millisecondsSinceEpoch) {
        span = span.add(Duration(days: reminder.interval[1]));
        if (++ticks > 5000) break;
      }
      if (span.day != today.day) correctDay = false;
    }

    if (correctDay) {
      if (reminder.voiceNotification) {
        WinUtils.textToSpeech(reminder.message, repeat: -1, volume: reminder.voiceVolume);
      } else {
        WinUtils.showWindowsNotification(
          title: "Tabame Reminder",
          body: "Reminder: ${reminder.message}",
          onClick: () {},
        );
      }
      if (reminder.persistent) {
        userSettings.persistentReminders.add("${reminder.message} at ${reminder.time.formatTime()}");
        Boxes.pref.setStringList("persistentReminders", userSettings.persistentReminders);
        QuickMenuFunctions.refreshQuickMenu();
      }
    }

    reminder.timer = Timer(const Duration(days: 1), () => reminderDaily(reminder));
  }
}
