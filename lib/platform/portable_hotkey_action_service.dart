import 'hotkey_action_service.dart';

/// Small action executor for the portable shell's explicitly supported hotkeys.
/// Native key injection, window targeting, clicks, and Windows-only pages remain
/// unavailable instead of being reported as successful no-ops.
class PortableHotkeyActionService extends HotkeyActionService {
  PortableHotkeyActionService({required this.onAction});

  static const Set<String> supportedFunctions = <String>{
    'ToggleQuickMenu',
    'ShowQuickMenuInCenter',
    'OpenLauncher',
  };

  final Future<void> Function(String action) onAction;

  @override
  bool get isAvailable => true;

  @override
  String get unavailableReason => '';

  @override
  Future<void> execute(PlatformHotkeyExecution execution) async {
    if (execution.windowUnderCursor || !_matchesAnyWindow(execution.windowMatch)) return;
    if (execution.variableCheck.isNotEmpty && execution.variableCheck[0].trim().isNotEmpty) return;

    for (final PlatformHotkeyAction action in execution.actions) {
      switch (action.type) {
        case 'wait':
          final int? milliseconds = int.tryParse(action.value);
          if (milliseconds == null || milliseconds < 0) return;
          await Future<void>.delayed(Duration(milliseconds: milliseconds));
        case 'tabameFunction':
          if (!supportedFunctions.contains(action.value)) return;
          await onAction(action.value);
        default:
          return;
      }
    }
  }

  bool _matchesAnyWindow(List<String> windowMatch) {
    return windowMatch.isEmpty || windowMatch[0].trim().isEmpty || windowMatch[0].toLowerCase() == 'any';
  }
}
