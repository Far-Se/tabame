import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../win32/win_utils.dart';

/// A single Windows power/session command (shutdown, restart, log off, …).
///
/// Shared between the QuickMenu settings-button right-click modal
/// ([SystemPowerWidget]) and the launcher `$sys` function command so both
/// surfaces stay in sync.
class SystemPowerAction {
  const SystemPowerAction({
    required this.id,
    required this.label,
    required this.description,
    required this.icon,
    required this.command,
    this.aliases = const <String>[],
    this.isDestructive = false,
  });

  /// Stable id, also the primary token typed after `$sys ` (e.g. `shutdown`).
  final String id;
  final String label;
  final String description;
  final IconData icon;

  /// The raw command handed to `powershell -NoProfile`.
  final String command;

  /// Extra tokens that resolve to this action in the launcher / search.
  final List<String> aliases;

  /// Destructive actions close the session (shutdown/restart/logoff/hibernate)
  /// and are only fired for real in release mode.
  final bool isDestructive;

  bool matchesToken(String token) {
    final String value = token.toLowerCase();
    return value == id || aliases.contains(value);
  }

  bool matchesQuery(String query) {
    final String lower = query.toLowerCase();
    return id.contains(lower) ||
        label.toLowerCase().contains(lower) ||
        description.toLowerCase().contains(lower) ||
        aliases.any((String alias) => alias.contains(lower));
  }

  void execute() {
    // Guard the irreversible ones while developing so a stray click/keystroke
    // never tears down the dev machine. Lock/sleep are harmless, so they run.
    if (!kReleaseMode && isDestructive) {
      WinUtils.msgBox(label, 'Release mode would run: $command');
      return;
    }
    WinUtils.runPowerShell(<String>[command]);
  }

  static const List<SystemPowerAction> all = <SystemPowerAction>[
    SystemPowerAction(
      id: 'shutdown',
      label: 'Shut Down',
      description: 'Power off the computer',
      icon: Icons.power_settings_new_rounded,
      command: 'shutdown /s /t 0',
      aliases: <String>['poweroff', 'off'],
      isDestructive: true,
    ),
    SystemPowerAction(
      id: 'restart',
      label: 'Restart',
      description: 'Reboot the computer',
      icon: Icons.restart_alt_rounded,
      command: 'shutdown /r /t 0',
      aliases: <String>['reboot'],
      isDestructive: true,
    ),
    SystemPowerAction(
      id: 'logoff',
      label: 'Log Off',
      description: 'Sign out of the current session',
      icon: Icons.logout_rounded,
      command: 'shutdown /l',
      aliases: <String>['logout', 'signout'],
      isDestructive: true,
    ),
    SystemPowerAction(
      id: 'lock',
      label: 'Lock',
      description: 'Lock the workstation',
      icon: Icons.lock_outline_rounded,
      command: 'rundll32.exe user32.dll,LockWorkStation',
      isDestructive: false,
    ),
    SystemPowerAction(
      id: 'sleep',
      label: 'Sleep',
      description: 'Suspend the computer',
      icon: Icons.bedtime_outlined,
      command: 'rundll32.exe powrprof.dll,SetSuspendState 0,1,0',
      aliases: <String>['suspend'],
      isDestructive: false,
    ),
    SystemPowerAction(
      id: 'hibernate',
      label: 'Hibernate',
      description: 'Save session to disk and power off',
      icon: Icons.battery_saver_rounded,
      command: 'shutdown /h',
      isDestructive: true,
    ),
  ];

  static SystemPowerAction? byToken(String token) {
    for (final SystemPowerAction action in all) {
      if (action.matchesToken(token)) return action;
    }
    return null;
  }
}
