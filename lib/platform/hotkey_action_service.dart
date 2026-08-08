import 'dart:async';

/// A serializable action description used by the shared hotkey dispatcher.
class PlatformHotkeyAction {
  const PlatformHotkeyAction({required this.type, required this.value});

  final String type;
  final String value;
}

/// All context required by an adapter to execute a configured keymap.
class PlatformHotkeyExecution {
  const PlatformHotkeyExecution({
    required this.name,
    required this.windowUnderCursor,
    required this.windowMatch,
    required this.variableCheck,
    required this.actions,
    required this.trigger,
  });

  final String name;
  final bool windowUnderCursor;
  final List<String> windowMatch;
  final List<String> variableCheck;
  final List<PlatformHotkeyAction> actions;
  final String trigger;
}

/// Executes configured actions without making the persisted hotkey model know
/// about a native API.
abstract class HotkeyActionService {
  static HotkeyActionService _instance = const UnavailableHotkeyActionService();

  static HotkeyActionService get instance => _instance;

  static void register(HotkeyActionService service) {
    _instance = service;
  }

  const HotkeyActionService();

  bool get isAvailable;
  String get unavailableReason;

  Future<void> execute(PlatformHotkeyExecution execution);
}

class UnavailableHotkeyActionService extends HotkeyActionService {
  const UnavailableHotkeyActionService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'Configured hotkey actions are unavailable on this platform.';

  @override
  Future<void> execute(PlatformHotkeyExecution execution) async {}
}

/// Registry for action names shown by the shared editor.
///
/// The names are portable data. Only the Windows adapter installs callbacks for
/// actions that require Windows shell behavior; unsupported platforms retain
/// the names for import compatibility but do not invoke native behavior.
class HotkeyActionRegistry {
  HotkeyActionRegistry._();

  static final Map<String, Function> _callbacks = <String, Function>{};

  static const List<String> functionNames = <String>[
    'ToggleQuickMenu',
    'ShowQuickMenuInCenter',
    'OpenLauncher',
    'ToggleTaskbar',
    'OpenColorPicker',
    'OpenQuickSnapStandalone',
    'OpenScreenDraw',
    'OpenScreenRecording',
    'OpenSpotlight',
    'OpenLiveFancyShot',
    'OpenFrozenFancyShot',
    'OpenColorPickerInstant',
    'OpenEmojiPicker',
    'OpenQuickClick',
    'BlockKeyboard',
    'ShowStartMenu',
    'ShowLastActiveWindow',
    'ShowSecondWindowUnderCursor',
    'ShowLastWindowUnderCursor',
    'ToggleAlwaysOnTopForWindow',
    'ExpandSnippet',
    'ToggleHiddenFiles',
    'ToggleDesktopFiles',
    'SwitchAudioOutput',
    'SwitchMicrophoneInput',
    'ToggleMicrophone',
    'SwitchDesktopToRight',
    'SwitchDesktopToLeft',
    'ToggleWallpaper',
  ];

  static Map<String, Function> get functions => <String, Function>{
        for (final String name in functionNames) name: _callbacks[name] ?? _unsupported,
      };

  static void register(Map<String, Function> callbacks) {
    _callbacks
      ..clear()
      ..addAll(callbacks);
  }

  static Future<void> invoke(String name) async {
    final Function? callback = _callbacks[name];
    if (callback == null) return;
    final dynamic result = Function.apply(callback, const <dynamic>[]);
    if (result is Future<dynamic>) await result;
  }

  static void _unsupported() {}
}
