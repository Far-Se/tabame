import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/classes/boxes.dart';
import '../models/globals.dart';
import '../models/win32/win_utils.dart';
import 'claude_usage_service.dart';
import 'codex_usage_service.dart';

/// Keeps selected providers subscribed even while the menu is hidden or its
/// buttons have scrolled out of view. Provider services own polling and throttles.
class AiCodingUsageService extends ChangeNotifier with QuickMenuTriggers {
  AiCodingUsageService._();

  static final AiCodingUsageService instance = AiCodingUsageService._();
  Set<String> _agents = <String>{};
  List<String> _selectedAgents = <String>[];
  final Map<String, _ResetAlert> _alerts = <String, _ResetAlert>{};
  Future<void> _pendingSave = Future<void>.value();
  bool codexLoading = false;
  bool claudeLoading = false;

  void configureTopBar(List<String> widgets) {
    final Set<String> active = widgets.takeWhile((String name) => name != 'Deactivated:').toSet();
    configure(<String>[
      if (active.contains('CodexUsageButton')) 'codex',
      if (active.contains('ClaudeUsageButton')) 'claude',
    ]);
  }

  void configure(List<String> agents) {
    _restoreAlerts();
    _selectedAgents = List<String>.of(agents);
    final Set<String> selected = <String>{
      ...agents.where((String agent) => agent == 'codex' || agent == 'claude'),
      for (final MapEntry<String, _ResetAlert> entry in _alerts.entries)
        if (entry.value.enabled) entry.key,
    };
    if (setEquals(selected, _agents)) return;
    if (_agents.isEmpty && selected.isNotEmpty) QuickMenuFunctions.addListener(this);
    if (_agents.isNotEmpty && selected.isEmpty) QuickMenuFunctions.removeListener(this);
    if (_agents.contains('codex') && !selected.contains('codex')) {
      CodexUsageService.instance.removeListener(_onCodex);
    }
    if (_agents.contains('claude') && !selected.contains('claude')) {
      ClaudeUsageService.instance.removeListener(_onClaude);
    }
    final Set<String> added = selected.difference(_agents);
    _agents = selected;
    if (added.contains('codex')) {
      codexLoading = CodexUsageService.instance.latest == null;
      CodexUsageService.instance.addListener(_onCodex);
    }
    if (added.contains('claude')) {
      claudeLoading = ClaudeUsageService.instance.latest == null;
      ClaudeUsageService.instance.addListener(_onClaude);
    }
    notifyListeners();
  }

  void _onCodex(CodexUsageRecord? record) {
    codexLoading = false;
    if (record != null) {
      _syncAlert('codex', record.fiveHourResetDateTime, record.fiveHourRemaining, record.fetchedAt);
    }
    notifyListeners();
  }

  void _onClaude(ClaudeUsageRecord? record) {
    claudeLoading = false;
    if (record != null) {
      _syncAlert('claude', DateTime.tryParse(record.fiveResetAt ?? ''), 100 - record.fiveHour, record.fetchedAt);
    }
    notifyListeners();
  }

  bool resetAlertEnabled(bool codex) => _alerts[codex ? 'codex' : 'claude']?.enabled ?? false;

  void toggleResetAlert(bool codex) {
    _restoreAlerts();
    final String agent = codex ? 'codex' : 'claude';
    final _ResetAlert alert = _alerts[agent]!;
    alert.enabled = !alert.enabled;
    alert.timer?.cancel();
    alert.target = null;
    alert.observedAt = null;
    _saveAlerts();
    configure(_selectedAgents);
    if (codex) {
      _onCodex(CodexUsageService.instance.latest);
    } else {
      _onClaude(ClaudeUsageService.instance.latest);
    }
  }

  void _restoreAlerts() {
    if (_alerts.isNotEmpty) return;
    for (final String agent in <String>['codex', 'claude']) {
      final _ResetAlert alert = _ResetAlert();
      try {
        final dynamic saved = jsonDecode(Boxes.pref.getString('aiResetAlert_$agent') ?? '{}');
        if (saved is Map) {
          alert.enabled = saved['enabled'] == true;
          alert.target = DateTime.tryParse(saved['target']?.toString() ?? '');
          alert.lastNotified = DateTime.tryParse(saved['lastNotified']?.toString() ?? '');
        }
      } on FormatException {
        // Ignore malformed saved alarm data.
      }
      _alerts[agent] = alert;
      if (alert.enabled && alert.target != null) _scheduleAlert(agent, alert);
    }
  }

  void _saveAlerts() {
    final Map<String, String> saved = <String, String>{
      for (final MapEntry<String, _ResetAlert> entry in _alerts.entries)
        entry.key: jsonEncode(<String, dynamic>{
          'enabled': entry.value.enabled,
          'target': entry.value.target?.toIso8601String(),
          'lastNotified': entry.value.lastNotified?.toIso8601String(),
        }),
    };
    _pendingSave = _pendingSave.then((_) async {
      for (final MapEntry<String, String> entry in saved.entries) {
        await Boxes.updateSettings('aiResetAlert_${entry.key}', entry.value);
      }
    }).catchError((Object error) {
      debugPrint('Could not save usage reset alerts: $error');
    });
  }

  void _syncAlert(String agent, DateTime? reset, double? remaining, DateTime fetchedAt) {
    final _ResetAlert? alert = _alerts[agent];
    if (alert == null || !alert.enabled) return;
    final DateTime now = DateTime.now();
    // Deliver an elapsed active window before a refresh replaces it with an idle one.
    if (alert.target != null && !alert.target!.isAfter(now)) _fireAlert(agent, alert);
    if (alert.observedAt != null && !fetchedAt.isAfter(alert.observedAt!)) return;
    alert.observedAt = fetchedAt;
    if (reset == null || remaining == null || now.difference(fetchedAt) > const Duration(minutes: 10)) return;
    // Empty windows can slide forward on every recheck until the first prompt.
    // Keep the subscription enabled, but only arm windows with actual usage.
    final DateTime? target =
        remaining < 100 && reset.isAfter(now) && (alert.lastNotified == null || reset.isAfter(alert.lastNotified!))
            ? reset
            : null;
    if (target == alert.target) return;
    alert.timer?.cancel();
    alert.target = target;
    if (target != null) _scheduleAlert(agent, alert);
    _saveAlerts();
  }

  void _scheduleAlert(String agent, _ResetAlert alert) {
    alert.timer?.cancel();
    final Duration delay = alert.target!.difference(DateTime.now());
    alert.timer = Timer(delay.isNegative ? Duration.zero : delay, () => _fireAlert(agent, alert));
  }

  void _fireAlert(String agent, _ResetAlert alert) {
    final DateTime? target = alert.target;
    if (!alert.enabled || target == null) return;
    if (target.isAfter(DateTime.now())) {
      _scheduleAlert(agent, alert);
      return;
    }
    alert.timer?.cancel();
    alert.target = null;
    final bool alreadyNotified = alert.lastNotified != null && !target.isAfter(alert.lastNotified!);
    if (!alreadyNotified) alert.lastNotified = target;
    _saveAlerts();
    if (!alreadyNotified) unawaited(_speakReset(agent));
    notifyListeners();
  }

  Future<void> _speakReset(String agent) async {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return;
    }
    try {
      await WinUtils.textToSpeech('${agent == 'codex' ? 'Codex' : 'Claude'} Usage Reseted');
    } on Object catch (error) {
      debugPrint('Could not speak usage reset alert: $error');
    }
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (!visible || type != QuickMenuPage.quickMenu) return;
    // QuickMenu awaits its listeners before revealing the window. Fetch in the
    // background so a CLI/network request never delays opening the menu.
    if (_agents.contains('codex')) unawaited(CodexUsageService.instance.refresh(force: true));
    if (_agents.contains('claude')) unawaited(ClaudeUsageService.instance.refresh());
  }
}

class _ResetAlert {
  bool enabled = false;
  DateTime? target;
  DateTime? lastNotified;
  DateTime? observedAt;
  Timer? timer;
}
