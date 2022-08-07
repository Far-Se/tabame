// ignore_for_file: public_member_api_docs, sort_constructors_first
// ignore_for_file: non_constant_identifier_names

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import './const.win.dart';

import 'tabamewin32.dart';

enum HookTypes {
  noHook,
  eventHook,
  mouseHook,
}

enum MouseEvent { control, watch }

class WinEventStruct {
  int event = 0;
  int hWnd = 0;
  int idObject = 0;
  int idChild = 0;
  int dwEventThread = 0;
  int dwmsEventTime = 0;

  @override
  String toString() {
    return 'EventStruct(event: $event, hWnd: $hWnd, idObject: $idObject, idChild: $idChild, dwEventThread: $dwEventThread, dwmsEventTime: $dwmsEventTime)';
  }
}

class MouseStruct {
  MouseButtons button = MouseButtons.Left;
  bool down = false;
  bool up = false;
  MouseEvent type = MouseEvent.watch;
  @override
  String toString() {
    return 'MouseStruct(button: $button, down: $down, up: $up, type: $type)';
  }
}

abstract class WinHookEventListener {
  void onMouseInfoReceived(MouseStruct mouse) {}
  void onWinEventInfoReceived(WinEventStruct event) {}
}

class WinHooks {
  final MethodChannel methodChannel = audioMethodChannel;
  final ObserverList<WinHookEventListener> _winHookListeners = ObserverList<WinHookEventListener>();
  bool hookRunning = false;

  int hookMouseID = 0;
  int hookEventID = 0;

  int eventMin = 0;
  int eventMax = 0;
  int eventFilters = WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS;

  List<MouseButtons> mouseWatchButtons = <MouseButtons>[];
  List<MouseButtons> mouseControlButtons = <MouseButtons>[];

  WinHooks() {
    methodChannel.setMethodCallHandler(_methodCallHandler);
  }

  Future<void> _methodCallHandler(MethodCall call) async {
    if (call.method != "onEvent") return;
    if (call.arguments["hookType"] == HookTypes.mouseHook.index && call.arguments["hookID"] != hookMouseID) {
      uninstallSpecificHookID(call.arguments['hookID'] as int, HookTypes.mouseHook);
      return;
    }
    if (call.arguments["hookType"] == HookTypes.eventHook.index && call.arguments["hookID"] != hookEventID) {
      uninstallSpecificHookID(call.arguments['hookID'] as int, HookTypes.eventHook);
      return;
    }
    if (call.arguments["hookType"] == HookTypes.eventHook.index) {
      final WinEventStruct event = WinEventStruct();
      event.event = call.arguments["event"] as int;
      event.hWnd = call.arguments["hWnd"] as int;
      event.idObject = call.arguments["idObject"] as int;
      event.idChild = call.arguments["idChild"] as int;
      event.dwEventThread = call.arguments["dwEventThread"] as int;
      event.dwmsEventTime = call.arguments["dwmsEventTime"] as int;
      for (final WinHookEventListener listener in listeners) {
        if (!_winHookListeners.contains(listener)) {
          return;
        }
        listener.onWinEventInfoReceived(event);
      }
    }
    if (call.arguments["hookType"] == HookTypes.mouseHook.index) {
      final MouseStruct mouse = MouseStruct();
      mouse.button = MouseButtons.values[call.arguments["button"]];
      mouse.down = call.arguments["state"];
      mouse.up = !mouse.down;
      mouse.type = call.arguments["type"] == "control" ? MouseEvent.control : MouseEvent.watch;
      for (final WinHookEventListener listener in listeners) {
        if (!_winHookListeners.contains(listener)) {
          return;
        }
        listener.onMouseInfoReceived(mouse);
      }
    }
  }

  List<WinHookEventListener> get listeners {
    final List<WinHookEventListener> localListeners = List<WinHookEventListener>.from(_winHookListeners);
    return localListeners;
  }

  bool get hasListeners {
    return _winHookListeners.isNotEmpty;
  }

  /// Add EventListener to the list of listeners.
  void addListener(WinHookEventListener listener) {
    _winHookListeners.add(listener);
  }

  void removeListener(WinHookEventListener listener) {
    _winHookListeners.remove(listener);
  }

  /// Sets WinEvent Hook Parameters
  /// [eventMin] - Values from [WinHookEvent]. The minimum event ID to watch. It can be ORed
  /// [eventMax] - Values from [WinHookEvent]. The maximum event ID to watch. It can be ORed
  /// [eventFilters] - The event filters to watch. It can be ORed
  Future<bool?> setWinEventParameters(
      {required WinHookEvent minEvent,
      WinHookEvent maxEvent = WinHookEvent.DISABLED,
      int filters = WINEVENT_OUTOFCONTEXT | WINEVENT_SKIPOWNPROCESS,
      bool reinstallHooks = false}) async {
    eventMin = WinHookEventValues[minEvent.name] ?? 0;
    eventMax = WinHookEventValues[maxEvent.name] ?? 0;
    if (eventMin > 0 && eventMax == 0) eventMax = eventMin;

    eventFilters = filters;
    if (reinstallHooks) return await installWinHook();
    return true;
  }

  /// Sets Mouse Hook Parameters
  /// [button] - The mouse button to watch.
  /// [mouseEvent] - The mouse event to watch. Hold to block propagation, watch to not block.
  Future<bool?> addMouseHook({required MouseButtons button, MouseEvent mouseEvent = MouseEvent.control, bool reinstallHooks = false}) async {
    await methodChannel.invokeMethod('manageMouseHook', <String, dynamic>{
      "method": "add",
      "button": button.index,
      "mouseEvent": mouseEvent.index == 0 ? "hold" : "watch",
    });
    if (reinstallHooks) return await installWinHook();

    return true;
  }

  /// Removes Mouse Hook Parameters
  /// [button] - The mouse button to watch.
  /// [mouseEvent] - The mouse event to watch. Hold to block propagation, watch to not block.
  Future<bool?> removeMouseHook({required MouseButtons button, MouseEvent mouseEvent = MouseEvent.control, bool reinstallHooks = false}) async {
    await methodChannel.invokeMethod('manageMouseHook', <String, dynamic>{
      "method": "remove",
      "button": button.index,
      "mouseEvent": mouseEvent.index == 0 ? "hold" : "watch",
    });
    if (reinstallHooks) return await installWinHook();
    return true;
  }

  /// Installs the WinHook.
  Future<bool?> installWinHook() async {
    await uninstallWinHook();
    hookRunning = true;

    Map<String, int> dataToSend = <String, int>{
      'eventMin': eventMin,
      'eventMax': eventMax,
      'eventFilters': eventFilters,
    };
    final Map<dynamic, dynamic> result = await methodChannel.invokeMethod('installHooks', dataToSend);
    hookMouseID = result['mouseHookID'];
    hookEventID = result['eventHookID'];

    return true;
  }

  /// Cleans Mouse Hook and eventHook properties.
  /// Good when you restart/reload your app.
  Future<bool> cleanHooks() async {
    eventMin = 0;
    eventMax = 0;
    eventFilters = 0;

    await methodChannel.invokeMethod('cleanHooks');
    return true;
  }

  /// Uninstalls the WinHook.
  Future<bool> uninstallWinHook() async {
    hookRunning = false;
    await methodChannel.invokeMethod('uninstallHooks');
    return true;
  }

  /// Uninstalls a specific WinHook.
  Future<bool> uninstallSpecificHookID(int hookID, HookTypes hookType) async {
    await methodChannel.invokeMethod('uninstallSpecificHookID', <String, int>{'hookID': hookID, 'hookType': hookType.index});
    return true;
  }
}
