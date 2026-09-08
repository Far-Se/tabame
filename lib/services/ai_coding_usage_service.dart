import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/classes/boxes/quick_menu_box.dart';
import '../models/globals.dart';
import 'claude_usage_service.dart';
import 'codex_usage_service.dart';

/// Keeps selected providers subscribed even while the menu is hidden or its
/// buttons have scrolled out of view. Provider services own polling and throttles.
class AiCodingUsageService extends ChangeNotifier with QuickMenuTriggers {
  AiCodingUsageService._();

  static final AiCodingUsageService instance = AiCodingUsageService._();
  Set<String> _agents = <String>{};
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
    final Set<String> selected = agents.where((String agent) => agent == 'codex' || agent == 'claude').toSet();
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
    notifyListeners();
  }

  void _onClaude(ClaudeUsageRecord? record) {
    claudeLoading = false;
    notifyListeners();
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
