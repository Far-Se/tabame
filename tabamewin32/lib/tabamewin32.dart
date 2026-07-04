// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

export 'media_session.dart';

class AudioDevice {
  String id = "";
  String name = "";
  String iconPath = "";
  int iconID = 0;
  bool isActive = false;
  @override
  String toString() {
    return 'AudioDevice{id: $id, name: $name, iconPath: $iconPath, iconID: $iconID, isActive: $isActive}';
  }

  //tomap
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'iconPath': iconPath,
      'iconID': iconID,
      'isActive': isActive,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is AudioDevice &&
        other.id == id &&
        other.name == name &&
        other.iconPath == iconPath &&
        other.iconID == iconID &&
        other.isActive == isActive;
  }

  @override
  int get hashCode {
    return id.hashCode ^ name.hashCode ^ iconPath.hashCode ^ iconID.hashCode ^ isActive.hashCode;
  }
}

class ProcessVolume {
  int processId = 0;
  String processPath = "";
  double maxVolume = 1.0;
  double peakVolume = 0.0;

  @override
  String toString() {
    return "ProcessVolume{processId: $processId, processPath: $processPath, maxVolume: $maxVolume, peakVolume: $peakVolume}";
  }

  // tomap
  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'processId': processId,
      'processPath': processPath,
      'maxVolume': maxVolume,
      'peakVolume': peakVolume,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is ProcessVolume &&
        other.processId == processId &&
        other.processPath == processPath &&
        other.maxVolume == maxVolume &&
        other.peakVolume == peakVolume;
  }

  @override
  int get hashCode {
    return processId.hashCode ^ processPath.hashCode ^ maxVolume.hashCode ^ peakVolume.hashCode;
  }
}

enum AudioDeviceType {
  output,
  input,
}

const MethodChannel tabameWin32MethodChannel = MethodChannel('tabamewin32');

class Audio {
  static bool canRunAudioModule = false;
  static bool alreadySet = false;
  static Future<bool> detectAudioSupport(AudioDeviceType audioDeviceType) async {
    if (alreadySet) return canRunAudioModule;
    final Map<String, dynamic> arguments = <String, int>{'deviceType': audioDeviceType.index};
    final bool map = await tabameWin32MethodChannel.invokeMethod('canAccessAudio', arguments);
    canRunAudioModule = map;
    alreadySet = true;
    return map;
  }

  /// Returns a Future list of audio devices of a specified type.
  /// The type is specified by the [AudioDeviceType] enum.
  ///
  static Future<List<AudioDevice>?> enumDevices(AudioDeviceType audioDeviceType) async {
    if (!canRunAudioModule) {
      return <AudioDevice>[];
    }
    final Map<String, dynamic> arguments = <String, int>{'deviceType': audioDeviceType.index};
    final Map<dynamic, dynamic> map = await tabameWin32MethodChannel.invokeMethod('enumAudioDevices', arguments);
    List<AudioDevice>? audioDevices = <AudioDevice>[];
    for (String key in map.keys) {
      final AudioDevice audioDevice = AudioDevice();
      audioDevice.id = key;
      audioDevice.name = map[key]['name'];
      final List<String> iconData = map[key]['iconInfo'].split(",");
      audioDevice.iconPath = iconData[0];
      audioDevice.iconID = int.parse(iconData[1]);
      audioDevice.isActive = map[key]['isActive'];
      audioDevices.add(audioDevice);
    }
    return audioDevices;
  }

  /// Returns a Future containing the default audio device of the given type.
  /// The type is specified by the [AudioDeviceType] enum.
  ///
  static Future<AudioDevice?> getDefaultDevice(AudioDeviceType audioDeviceType) async {
    if (!canRunAudioModule) {
      return AudioDevice();
    }
    final List<AudioDevice> hasDevices = await enumDevices(audioDeviceType) ?? <AudioDevice>[];
    if (hasDevices.isEmpty) return AudioDevice();
    final Map<String, dynamic> arguments = <String, int>{'deviceType': audioDeviceType.index};
    final Map<dynamic, dynamic> map = await tabameWin32MethodChannel.invokeMethod('getDefaultDevice', arguments);
    final AudioDevice audioDevice = AudioDevice();
    audioDevice.id = map['id'];
    audioDevice.name = map['name'];
    final List<String> iconData = map['iconInfo'].split(",");
    audioDevice.iconPath = iconData[0];
    audioDevice.iconID = int.parse(iconData[1]);
    audioDevice.isActive = map['isActive'];
    return audioDevice;
  }

  /// Sets the default audio device.
  /// The type is specified by the [AudioDeviceType] enum.
  static Future<int> setDefaultDevice(String deviceID,
      {required bool console, required bool multimedia, required bool communications}) async {
    if (!canRunAudioModule) {
      return 0;
    }
    final Map<String, dynamic> arguments = <String, dynamic>{
      'deviceID': deviceID,
      'console': console,
      'multimedia': multimedia,
      'communications': communications,
    };

    final int? result = await tabameWin32MethodChannel.invokeMethod<int>('setDefaultAudioDevice', arguments);
    return result as int;
  }

  /// Returns the current volume for the given audio device type.
  /// The type is specified by the [AudioDeviceType] enum.
  static Future<double> getVolume(AudioDeviceType audioDeviceType) async {
    if (!canRunAudioModule) {
      return 0;
    }

    final List<AudioDevice> hasDevices = await enumDevices(audioDeviceType) ?? <AudioDevice>[];
    if (hasDevices.isEmpty) return 0;
    final Map<String, dynamic> arguments = <String, int>{'deviceType': audioDeviceType.index};
    final double? result = await tabameWin32MethodChannel.invokeMethod<double>('getAudioVolume', arguments);
    return result as double;
  }

  /// This function sets the volume of the specified audio device type. The volume level is a number between 0 and 1, with 1 being the maximum volume.
  /// The type is specified by the [AudioDeviceType] enum.
  ///
  static Future<int> setVolume(double volume, AudioDeviceType audioDeviceType) async {
    if (!canRunAudioModule) {
      return 0;
    }
    if (volume > 1) volume = (volume / 100).toDouble();

    final List<AudioDevice> hasDevices = await enumDevices(audioDeviceType) ?? <AudioDevice>[];
    if (hasDevices.isEmpty) return 0;
    final Map<String, dynamic> arguments = <String, dynamic>{
      'deviceType': audioDeviceType.index,
      'volumeLevel': volume
    };
    final int? result = await tabameWin32MethodChannel.invokeMethod<int>('setAudioVolume', arguments);
    return result as int;
  }

  static Future<int> setMuteAudioDevice(bool muteState, AudioDeviceType audioDeviceType) async {
    if (!canRunAudioModule) {
      return 0;
    }
    final List<AudioDevice> hasDevices = await enumDevices(audioDeviceType) ?? <AudioDevice>[];
    if (hasDevices.isEmpty) return 0;
    final Map<String, dynamic> arguments = <String, dynamic>{
      'deviceType': audioDeviceType.index,
      'muteState': muteState
    };
    final int? result = await tabameWin32MethodChannel.invokeMethod<int>('setMuteAudioDevice', arguments);
    return result as int;
  }

  static Future<bool> getMuteAudioDevice(AudioDeviceType audioDeviceType) async {
    if (!canRunAudioModule) {
      return false;
    }

    final List<AudioDevice> hasDevices = await enumDevices(audioDeviceType) ?? <AudioDevice>[];
    if (hasDevices.isEmpty) return false;
    final Map<String, dynamic> arguments = <String, dynamic>{
      'deviceType': audioDeviceType.index,
    };
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('getMuteAudioDevice', arguments);
    return result!;
  }

  /// This function switches the audio device to the specified type. The type is specified by the [AudioDeviceType] enum.
  static Future<bool> switchDefaultDevice(AudioDeviceType audioDeviceType,
      {required bool console, required bool multimedia, required bool communications}) async {
    if (!canRunAudioModule) {
      return false;
    }
    final Map<String, dynamic> arguments = <String, dynamic>{
      'deviceType': audioDeviceType.index,
      'console': console,
      'multimedia': multimedia,
      'communications': communications,
    };
    final List<AudioDevice> hasDevices = await enumDevices(audioDeviceType) ?? <AudioDevice>[];
    if (hasDevices.isEmpty) return false;
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('switchDefaultDevice', arguments);
    return result as bool;
  }

  static Future<bool> setAudioDeviceVolume(String deviceID, double volume) async {
    if (!canRunAudioModule) {
      return false;
    }
    if (volume > 1) volume = (volume / 100).toDouble();
    final Map<String, dynamic> arguments = <String, dynamic>{'deviceID': deviceID, 'volumeLevel': volume};
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('setAudioDeviceVolume', arguments);
    return result ?? false;
  }

  static Future<double> getAudioDeviceVolume(String deviceID) async {
    if (!canRunAudioModule) {
      return 0.0;
    }
    final Map<String, dynamic> arguments = <String, dynamic>{
      'deviceID': deviceID,
    };
    final double? result = await tabameWin32MethodChannel.invokeMethod<double>('getAudioDeviceVolume', arguments);
    return result ?? 0.0;
  }

  static Future<bool> setProcessVolumeByPath(String processPath, double volume) async {
    if (!canRunAudioModule) {
      return false;
    }
    if (volume > 1) volume = (volume / 100).toDouble();
    final Map<String, dynamic> arguments = <String, dynamic>{'processPath': processPath, 'volumeLevel': volume};
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('setProcessVolumeByPath', arguments);
    return result ?? false;
  }

  /// Returns a Future with a list of ProcessVolume objects containing information about all audio mixers.
  static Future<List<ProcessVolume>?> enumAudioMixer() async {
    if (!canRunAudioModule) {
      return <ProcessVolume>[];
    }
    final Map<dynamic, dynamic> map = await tabameWin32MethodChannel.invokeMethod('enumAudioMixer');
    List<ProcessVolume>? processVolumes = <ProcessVolume>[];
    for (int key in map.keys) {
      final ProcessVolume processVolume = ProcessVolume();
      processVolume.processId = key;
      processVolume.processPath = map[key]['processPath'];
      processVolume.maxVolume = map[key]['maxVolume'];
      processVolume.peakVolume = map[key]['peakVolume'];
      processVolumes.add(processVolume);
    }
    return processVolumes;
  }

  /// This function sets the audio mixer volume for the specified process ID. The volume level is a number between 0 and 1, with 1 being the maximum volume.
  /// The process ID is the process ID of the process that is using the audio mixer.
  /// The process ID can be obtained by calling the enumAudioMixer function.
  static Future<ProcessVolume> setAudioMixerVolume(int processID, double volume) async {
    if (!canRunAudioModule) {
      return ProcessVolume();
    }
    if (volume > 1) volume = (volume / 100).toDouble();
    final Map<String, dynamic> arguments = <String, dynamic>{'processID': processID, 'volumeLevel': volume};
    final Map<dynamic, dynamic> map = await tabameWin32MethodChannel.invokeMethod('setAudioMixerVolume', arguments);
    List<ProcessVolume>? processVolumes = <ProcessVolume>[];
    for (int key in map.keys) {
      final ProcessVolume processVolume = ProcessVolume();
      processVolume.processId = key;
      processVolume.processPath = map[key]['processPath'];
      processVolume.maxVolume = map[key]['maxVolume'];
      processVolume.peakVolume = map[key]['peakVolume'];
      processVolumes.add(processVolume);
    }
    return processVolumes[0];
  }
}

void resizeImage(Uint8List data) {
  ui.decodeImageFromList(data, (ui.Image image) {});
}

/// This function converts a native icon location to bytes.
/// The icon location is the path to the icon file.
/// The icon ID is the icon ID of the icon file.
/// The icon ID can be obtained by calling the enumAudioDevices function.
Map<String, Uint8List> ___kCacheIcons = <String, Uint8List>{};
Future<Uint8List?> nativeIconToBytes(String iconLocation, {int iconID = 0}) async {
  // return Uint8List.fromList([0]);
  if (___kCacheIcons.containsKey(iconLocation) && iconID == 0) {
    return ___kCacheIcons[iconLocation];
  }
  final Map<String, dynamic> arguments = <String, dynamic>{'iconLocation': iconLocation, 'iconID': iconID};
  final Uint8List? result = await tabameWin32MethodChannel.invokeMethod<Uint8List>('iconToBytes', arguments);
  ___kCacheIcons[iconLocation] = result!;
  return result;
}

Future<Uint8List?> getExecutableIcon(String iconlocation, {int iconID = 0}) async {
  // return Uint8List.fromList([0]);
  return await nativeIconToBytes(iconlocation, iconID: iconID);
}

Future<Uint8List?> getWindowIcon(int hWnd) async {
  // return Uint8List.fromList([0]);
  final Map<String, dynamic> arguments = <String, dynamic>{'hWnd': hWnd};
  final Uint8List? result = await tabameWin32MethodChannel.invokeMethod<Uint8List>('getWindowIcon', arguments);
  return result;
}

Future<Uint8List?> getIconPng(int hIcon) async {
  // return Uint8List.fromList([0]);
  final Map<String, dynamic> arguments = <String, dynamic>{'hIcon': hIcon};
  final Uint8List? result = await tabameWin32MethodChannel.invokeMethod<Uint8List>('getIconPng', arguments);
  return result;
}

class TrayInfo {
  String toolTip = "";
  bool isVisible = false;
  int processID = 0;
  int hWnd = 0;
  int uID = 0;
  int uCallbackMessage = 0;
  int hIcon = 0;
  TrayInfo();
  @override
  String toString() {
    return 'TrayInfo(toolTip: $toolTip, isVisible: $isVisible, processID: $processID, hWnd: $hWnd, uID: $uID, uCallbackMessage: $uCallbackMessage)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is TrayInfo &&
        other.toolTip == toolTip &&
        other.isVisible == isVisible &&
        other.processID == processID &&
        other.hWnd == hWnd &&
        other.uID == uID &&
        other.uCallbackMessage == uCallbackMessage;
  }

  @override
  int get hashCode {
    return toolTip.hashCode ^
        isVisible.hashCode ^
        processID.hashCode ^
        hWnd.hashCode ^
        uID.hashCode ^
        uCallbackMessage.hashCode;
  }
}

Future<List<TrayInfo>> enumTrayIcons({bool filter = false}) async {
  final Map<dynamic, dynamic> map = await tabameWin32MethodChannel.invokeMethod('enumTrayIcons');
  List<TrayInfo> trayInfos = <TrayInfo>[];
  for (int key in map.keys) {
    final TrayInfo trayInfo = TrayInfo();
    trayInfo.toolTip = map[key]['toolTip'] ?? "";
    trayInfo.isVisible = map[key]['isVisible'] > 0 ? true : false;
    trayInfo.processID = map[key]['processID'] ?? 0;
    trayInfo.hWnd = map[key]['hWnd'] ?? 0;
    trayInfo.uID = map[key]['uID'] ?? 0;
    trayInfo.uCallbackMessage = map[key]['uCallbackMessage'] ?? 0;
    trayInfo.hIcon = map[key]['hIcon'] ?? 0;
    trayInfos.add(trayInfo);
  }
  if (filter) {
    trayInfos.removeWhere((TrayInfo element) => element.isVisible);
  }
  return trayInfos;
}

Future<WinRect> getFocusedElementRect() async {
  final Map<dynamic, dynamic> result = await tabameWin32MethodChannel.invokeMethod('getFocusedElementRect');
  return WinRect.fromMap(result);
}

Future<WinRect> getFocusedElementCaretRect() async {
  final Map<dynamic, dynamic> result = await tabameWin32MethodChannel.invokeMethod('getFocusedElementCaretRect');
  return WinRect.fromMap(result);
}

/// Same detection as [getFocusedElementCaretRect], but returns every layer's
/// result individually instead of only the first one that fired. Useful for
/// debugging apps where the caret rect comes out wrong/random (e.g. why the
/// emoji picker opens at an odd spot in a given app).
Future<CaretDebugInfo> getFocusedElementCaretRectDebug() async {
  final Map<dynamic, dynamic> result = await tabameWin32MethodChannel.invokeMethod('getFocusedElementCaretRectDebug');
  return CaretDebugInfo.fromMap(result);
}

Future<String> getHwndName(int hWnd) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'hWnd': hWnd,
  };
  final String result = await tabameWin32MethodChannel.invokeMethod<String>('getHwndName', arguments) ?? "-";
  return result;
}

Future<int> findTopWindow(int processID) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'processID': processID,
  };
  final int result = await tabameWin32MethodChannel.invokeMethod<int>('findTopWindow', arguments) ?? 0;
  return result;
}

Future<void> setTaskbarVisibility(bool state) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'state': state,
  };
  await tabameWin32MethodChannel.invokeMethod('toggleTaskbar', arguments);
}

Future<int> getFlutterMainWindow() async {
  final int result = await tabameWin32MethodChannel.invokeMethod<int>('getMainHandle') ?? 0;
  return result;
}

Future<void> setWindowAsTransparent() async {
  await tabameWin32MethodChannel.invokeMethod('setTransparent');
}

class WinRect {
  int left;
  int top;
  int right;
  int bottom;

  WinRect({
    required this.left,
    required this.top,
    required this.right,
    required this.bottom,
  });

  int get width => right - left;
  int get height => bottom - top;

  /// True for the all-zero sentinel returned when no caret/element rect
  /// could be determined (e.g. [getFocusedElementCaretRect] found nothing
  /// trustworthy). Callers should fall back to something else (mouse
  /// position, last window rect, etc.) rather than positioning on this.
  bool get isEmpty => left == 0 && top == 0 && right == 0 && bottom == 0;

  factory WinRect.fromMap(Map<dynamic, dynamic> map) {
    return WinRect(
      left: map['left'] as int? ?? 0,
      top: map['top'] as int? ?? 0,
      right: map['right'] as int? ?? 0,
      bottom: map['bottom'] as int? ?? 0,
    );
  }

  @override
  String toString() => 'WinRect(left: $left, top: $top, right: $right, bottom: $bottom)';
}

/// The outcome of a single caret-detection strategy: whether it produced a
/// rect at all, and what that rect was (zeroed if [found] is false).
class CaretLayerResult {
  bool found;
  WinRect rect;

  CaretLayerResult({required this.found, required this.rect});

  factory CaretLayerResult.fromMap(Map<dynamic, dynamic> map) {
    return CaretLayerResult(
      found: map['found'] as bool? ?? false,
      rect: WinRect.fromMap(map['rect'] as Map<dynamic, dynamic>? ?? const <dynamic, dynamic>{}),
    );
  }

  @override
  String toString() => found ? rect.toString() : 'not found';
}

/// Diagnostic breakdown of [getFocusedElementCaretRectDebug]: the result of
/// every detection layer tried, plus which one was actually chosen as the
/// "best" rect (the same value [getFocusedElementCaretRect] would return).
///
/// Layers, in the priority order they're tried:
/// 1. [win32Caret] — `GetGUIThreadInfo().rcCaret`. Works for classic Win32
///    edit/richedit controls regardless of which process owns them.
/// 2. [accessibleCaret] — legacy MSAA `IAccessible` `OBJID_CARET`. Covers
///    older/non-UIA-aware controls.
/// 3. [uiaCaretRange] — UI Automation `TextPattern2.GetCaretRange`. The
///    "proper" modern API; works in UWP/WinUI/most Win32 apps that implement
///    UIA text patterns.
/// 4. [uiaSelection] — UIA `TextPattern.GetSelection` bounding rect, used
///    when there's no dedicated caret range but the (possibly empty)
///    selection range still marks the caret position.
/// 5. [imeCandidate] — `ImmGetCandidateWindow` on the focused window. This is
///    the IMM32 channel apps set (via `ImmSetCandidateWindow`) specifically
///    to anchor IME popup UI — candidate lists, and the system's own Win+.
///    emoji panel — near the caret. Cross-platform toolkits (e.g. winit's
///    `set_ime_cursor_area`, which GPUI-based editors like Zed are built on)
///    call exactly this, even for apps with no other accessibility support,
///    which is why the native emoji panel can land correctly in apps where
///    every other layer here reports "not found".
/// 6. [imeComposition] — `ImmGetCompositionWindow` on the focused window.
///    A different IMM32 channel: where actively-composed (not yet committed)
///    IME text is drawn. Useful when a field is mid IME-composition and the
///    other layers go stale.
/// 7. [uiaBoundingRect] — UIA bounding rect of the whole focused element.
///    Last-resort fallback: not a caret position, just "the control is
///    roughly here". If it ends up covering most of the focused window, the
///    native layer treats it as untrustworthy (see [found]/[chosenLayer]) -
///    that's UIA's generic "no accessibility support" passthrough, not a
///    caret.
class CaretDebugInfo {
  CaretLayerResult win32Caret;
  CaretLayerResult accessibleCaret;
  CaretLayerResult uiaCaretRange;
  CaretLayerResult uiaSelection;
  CaretLayerResult imeCandidate;
  CaretLayerResult imeComposition;
  CaretLayerResult uiaBoundingRect;

  /// Name of the layer that supplied [best], or `null` if none fired.
  String? chosenLayer;

  /// Whether any layer fired.
  bool found;

  /// The rect that [getFocusedElementCaretRect] would have returned.
  WinRect best;

  /// Whether `IUIAutomation.GetFocusedElement()` returned anything at all.
  bool hasFocusedElement;

  /// `CurrentName` of the focused UIA element, if any.
  String elementName;

  /// `CurrentClassName` of the focused UIA element, if any (often the native
  /// Win32 window class for apps with no real accessibility implementation).
  String elementClassName;

  /// Human-readable `CurrentControlType` of the focused UIA element (e.g.
  /// "Edit", "Document", "Pane"). A bare "Pane"/"Window" with none of the
  /// `supports*` flags below set is the generic passthrough every HWND gets
  /// for free — i.e. "this app implements no accessibility API".
  String elementControlType;

  /// Whether the focused element supports `TextPattern` (selection/caret via
  /// [uiaSelection]).
  bool supportsTextPattern;

  /// Whether the focused element supports `TextPattern2` (caret via
  /// [uiaCaretRange]).
  bool supportsTextPattern2;

  /// Whether the focused element supports `ValuePattern` (no caret info,
  /// just the control's current value as a whole).
  bool supportsValuePattern;

  /// Whether the focused element supports the UIA-to-MSAA bridge
  /// (`LegacyIAccessiblePattern`) — a different path to old-style
  /// `IAccessible` data than calling `AccessibleObjectFromWindow` directly.
  bool supportsLegacyIAccessible;

  CaretDebugInfo({
    required this.win32Caret,
    required this.accessibleCaret,
    required this.uiaCaretRange,
    required this.uiaSelection,
    required this.imeCandidate,
    required this.imeComposition,
    required this.uiaBoundingRect,
    required this.chosenLayer,
    required this.found,
    required this.best,
    required this.hasFocusedElement,
    required this.elementName,
    required this.elementClassName,
    required this.elementControlType,
    required this.supportsTextPattern,
    required this.supportsTextPattern2,
    required this.supportsValuePattern,
    required this.supportsLegacyIAccessible,
  });

  factory CaretDebugInfo.fromMap(Map<dynamic, dynamic> map) {
    CaretLayerResult layer(String key) =>
        CaretLayerResult.fromMap(map[key] as Map<dynamic, dynamic>? ?? const <dynamic, dynamic>{});

    final String chosen = map['chosenLayer'] as String? ?? '';
    return CaretDebugInfo(
      win32Caret: layer('win32Caret'),
      accessibleCaret: layer('accessibleCaret'),
      uiaCaretRange: layer('uiaCaretRange'),
      uiaSelection: layer('uiaSelection'),
      imeCandidate: layer('imeCandidate'),
      imeComposition: layer('imeComposition'),
      uiaBoundingRect: layer('uiaBoundingRect'),
      chosenLayer: chosen.isEmpty ? null : chosen,
      found: map['found'] as bool? ?? false,
      best: WinRect.fromMap(map['best'] as Map<dynamic, dynamic>? ?? const <dynamic, dynamic>{}),
      hasFocusedElement: map['hasFocusedElement'] as bool? ?? false,
      elementName: map['elementName'] as String? ?? '',
      elementClassName: map['elementClassName'] as String? ?? '',
      elementControlType: map['elementControlType'] as String? ?? '',
      supportsTextPattern: map['supportsTextPattern'] as bool? ?? false,
      supportsTextPattern2: map['supportsTextPattern2'] as bool? ?? false,
      supportsValuePattern: map['supportsValuePattern'] as bool? ?? false,
      supportsLegacyIAccessible: map['supportsLegacyIAccessible'] as bool? ?? false,
    );
  }

  /// All layers keyed by name, in priority order — handy for iterating/logging.
  Map<String, CaretLayerResult> get layers => <String, CaretLayerResult>{
        'Win32Caret': win32Caret,
        'AccessibleCaret': accessibleCaret,
        'UIACaretRange': uiaCaretRange,
        'UIASelection': uiaSelection,
        'ImeCandidate': imeCandidate,
        'ImeComposition': imeComposition,
        'UIABoundingRect': uiaBoundingRect,
      };

  @override
  String toString() {
    final String layersStr =
        layers.entries.map((MapEntry<String, CaretLayerResult> e) => '${e.key}: ${e.value}').join('\n');
    final String patterns = <String>[
      if (supportsTextPattern) 'TextPattern',
      if (supportsTextPattern2) 'TextPattern2',
      if (supportsValuePattern) 'ValuePattern',
      if (supportsLegacyIAccessible) 'LegacyIAccessible',
    ].join(', ');
    final String element = hasFocusedElement
        ? "name: '$elementName', class: '$elementClassName', controlType: $elementControlType, patterns: [${patterns.isEmpty ? 'none' : patterns}]"
        : 'none';
    return 'CaretDebugInfo(chosen: $chosenLayer, best: $best, focusedElement: {$element}, layers: \n{$layersStr})';
  }
}

class MonitorCapture {
  const MonitorCapture({
    required this.pixels,
    required this.width,
    required this.height,
    required this.length,
  });

  /// Raw BGRA pixels, four bytes per pixel.
  final Uint8List pixels;
  final int width;
  final int height;
  final int length;

  factory MonitorCapture._fromMap(Map<dynamic, dynamic> map) {
    final dynamic rawPixels = map['pixels'];
    final Uint8List pixels =
        rawPixels is Uint8List ? rawPixels : Uint8List.fromList((rawPixels as List<dynamic>).cast<int>());

    return MonitorCapture(
      pixels: pixels,
      width: map['width'] as int? ?? 0,
      height: map['height'] as int? ?? 0,
      length: map['length'] as int? ?? pixels.length,
    );
  }
}

enum OcrCaptureType {
  bitBlt,
  directX,
}

Future<String> getTextOCR(int x, int y, int width, int height, int type) async {
  final String? result = await tabameWin32MethodChannel.invokeMethod<String>(
    'getTextOCR',
    <String, dynamic>{
      'x': x,
      'y': y,
      'width': width,
      'height': height,
      'type': type,
    },
  );
  return result ?? '';
}

/// Runs Windows OCR over raw BGRA pixels (four bytes per pixel, straight alpha).
Future<String> recognizeBgraPixels(Uint8List pixels, int width, int height) async {
  final String? result = await tabameWin32MethodChannel.invokeMethod<String>(
    'recognizeBgraPixels',
    <String, dynamic>{
      'pixels': pixels,
      'width': width,
      'height': height,
    },
  );
  return result ?? '';
}

enum ScreenRecordingTargetType {
  region,
  monitor,
  window,
}

enum ScreenRecordingAudioMode {
  none,
  system,
  mic,
  systemAndMic,
}

extension on ScreenRecordingTargetType {
  String get wireName {
    switch (this) {
      case ScreenRecordingTargetType.region:
        return 'region';
      case ScreenRecordingTargetType.monitor:
        return 'monitor';
      case ScreenRecordingTargetType.window:
        return 'window';
    }
  }
}

extension on ScreenRecordingAudioMode {
  String get wireName {
    switch (this) {
      case ScreenRecordingAudioMode.none:
        return 'none';
      case ScreenRecordingAudioMode.system:
        return 'system';
      case ScreenRecordingAudioMode.mic:
        return 'mic';
      case ScreenRecordingAudioMode.systemAndMic:
        return 'systemAndMic';
    }
  }
}

class ScreenRecordingConfig {
  const ScreenRecordingConfig({
    required this.targetType,
    required this.outputPath,
    this.regionLeft,
    this.regionTop,
    this.regionWidth,
    this.regionHeight,
    this.monitorHandle,
    this.hWnd,
    this.frameRate = 30,
    this.videoBitrateMbps = 12,
    this.captureCursor = true,
    this.captureBorder = false,
    this.audioMode = ScreenRecordingAudioMode.none,
    this.micDeviceId,
    this.systemAudioDeviceId,
  });

  final ScreenRecordingTargetType targetType;
  final String outputPath;
  final int? regionLeft;
  final int? regionTop;
  final int? regionWidth;
  final int? regionHeight;
  final int? monitorHandle;
  final int? hWnd;
  final int frameRate;
  final int videoBitrateMbps;
  final bool captureCursor;
  final bool captureBorder;
  final ScreenRecordingAudioMode audioMode;
  final String? micDeviceId;
  final String? systemAudioDeviceId;

  Map<String, dynamic> toMap() => <String, dynamic>{
        'targetType': targetType.wireName,
        'outputPath': outputPath,
        'regionLeft': regionLeft,
        'regionTop': regionTop,
        'regionWidth': regionWidth,
        'regionHeight': regionHeight,
        'monitorHandle': monitorHandle,
        'hWnd': hWnd,
        'frameRate': frameRate,
        'videoBitrateMbps': videoBitrateMbps,
        'captureCursor': captureCursor,
        'captureBorder': captureBorder,
        'audioMode': audioMode.wireName,
        'micDeviceId': micDeviceId,
        'systemAudioDeviceId': systemAudioDeviceId,
        'recordingFormat': 'mp4',
        'encoder': 'h264',
      }..removeWhere((Object key, Object? value) => value == null);
}

class ScreenRecordingStatus {
  const ScreenRecordingStatus({
    required this.isRecording,
    required this.outputPath,
    required this.audioMode,
    required this.elapsedMs,
    required this.frameCount,
    required this.droppedFrames,
    required this.width,
    required this.height,
  });

  final bool isRecording;
  final String outputPath;
  final String audioMode;
  final int elapsedMs;
  final int frameCount;
  final int droppedFrames;
  final int width;
  final int height;

  factory ScreenRecordingStatus.fromMap(Map<dynamic, dynamic> map) {
    return ScreenRecordingStatus(
      isRecording: map['isRecording'] as bool? ?? false,
      outputPath: map['outputPath'] as String? ?? '',
      audioMode: map['audioMode'] as String? ?? 'none',
      elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
      frameCount: (map['frameCount'] as num?)?.toInt() ?? 0,
      droppedFrames: (map['droppedFrames'] as num?)?.toInt() ?? 0,
      width: (map['width'] as num?)?.toInt() ?? 0,
      height: (map['height'] as num?)?.toInt() ?? 0,
    );
  }
}

class ScreenRecordingStopResult {
  const ScreenRecordingStopResult({
    required this.success,
    required this.filePath,
    required this.durationMs,
    required this.frameCount,
  });

  final bool success;
  final String filePath;
  final int durationMs;
  final int frameCount;

  factory ScreenRecordingStopResult.fromMap(Map<dynamic, dynamic> map) {
    return ScreenRecordingStopResult(
      success: map['success'] as bool? ?? false,
      filePath: map['filePath'] as String? ?? '',
      durationMs: (map['durationMs'] as num?)?.toInt() ?? 0,
      frameCount: (map['frameCount'] as num?)?.toInt() ?? 0,
    );
  }
}

class SystemStatsInfo {
  const SystemStatsInfo({
    required this.cpuUsage,
    required this.gpuUsage,
    required this.memoryLoad,
    required this.cpuTemp,
    required this.gpuTemp,
  });

  final double cpuUsage;
  final double gpuUsage;
  final int memoryLoad;
  final double cpuTemp;
  final double gpuTemp;

  double get cpuLoadRatio => cpuUsage < 0 ? cpuUsage : cpuUsage / 100.0;

  factory SystemStatsInfo.fromMap(Map<dynamic, dynamic> map) {
    return SystemStatsInfo(
      cpuUsage: (map['cpuUsage'] as num?)?.toDouble() ?? ((map['cpuLoad'] as num?)?.toDouble() ?? 0) * 100,
      gpuUsage: (map['gpuUsage'] as num?)?.toDouble() ?? 0,
      memoryLoad: map['memoryLoad'] as int? ?? 0,
      cpuTemp: (map['cpuTemp'] as num?)?.toDouble() ?? 0,
      gpuTemp: (map['gpuTemp'] as num?)?.toDouble() ?? 0,
    );
  }

  @override
  String toString() {
    return 'SystemStatsInfo(cpuUsage: $cpuUsage, gpuUsage: $gpuUsage, memoryLoad: $memoryLoad, cpuTemp: $cpuTemp, gpuTemp: $gpuTemp)';
  }
}

class AppInfo {
  final String name;
  final String executable;
  final String arguments;
  final String appUserModelId;
  final String parsingName;

  const AppInfo({
    required this.name,
    required this.executable,
    required this.arguments,
    required this.appUserModelId,
    required this.parsingName,
  });

  factory AppInfo.fromMap(Map<Object?, Object?> map) => AppInfo(
        name: (map['name'] as String?) ?? '',
        executable: (map['executable'] as String?) ?? '',
        arguments: (map['arguments'] as String?) ?? '',
        appUserModelId: (map['appUserModelId'] as String?) ?? '',
        parsingName: (map['parsingName'] as String?) ?? '',
      );

  @override
  String toString() =>
      '\nAppInfo(name: $name, aumid: $appUserModelId, parsingName: $parsingName, executable: $executable, arguments: $arguments)';
}

class BrokenAppEntry {
  final String name;
  final String appUserModelId;
  final String parsingPath;

  const BrokenAppEntry({
    required this.name,
    required this.appUserModelId,
    required this.parsingPath,
  });

  factory BrokenAppEntry.fromMap(Map<Object?, Object?> map) => BrokenAppEntry(
        name: (map['name'] as String?) ?? '',
        appUserModelId: (map['appUserModelId'] as String?) ?? '',
        parsingPath: (map['parsingPath'] as String?) ?? '',
      );

  @override
  String toString() => 'BrokenAppEntry(name: $name, aumid: $appUserModelId, parsingPath: $parsingPath)';
}

class AppIconData {
  final Uint8List pixels;
  final int width;
  final int height;

  const AppIconData({
    required this.pixels,
    required this.width,
    required this.height,
  });
}

Future<MonitorCapture?> captureMonitor({int monitorIndex = 0}) async {
  final Map<dynamic, dynamic>? result = await tabameWin32MethodChannel.invokeMapMethod<dynamic, dynamic>(
    'captureMonitor',
    <String, dynamic>{'monitorIndex': monitorIndex},
  );
  if (result == null) return null;
  return MonitorCapture._fromMap(result);
}

Future<ScreenRecordingStatus> startScreenRecording(ScreenRecordingConfig config) async {
  final Map<dynamic, dynamic>? result = await tabameWin32MethodChannel.invokeMapMethod<dynamic, dynamic>(
    'startScreenRecording',
    config.toMap(),
  );
  return ScreenRecordingStatus.fromMap(result ?? const <String, dynamic>{});
}

Future<ScreenRecordingStopResult> stopScreenRecording() async {
  final Map<dynamic, dynamic>? result =
      await tabameWin32MethodChannel.invokeMapMethod<dynamic, dynamic>('stopScreenRecording');
  return ScreenRecordingStopResult.fromMap(result ?? const <String, dynamic>{});
}

Future<bool> cancelScreenRecording() async {
  final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('cancelScreenRecording');
  return result ?? false;
}

Future<ScreenRecordingStatus> getScreenRecordingStatus() async {
  final Map<dynamic, dynamic>? result =
      await tabameWin32MethodChannel.invokeMapMethod<dynamic, dynamic>('getScreenRecordingStatus');
  return ScreenRecordingStatus.fromMap(result ?? const <String, dynamic>{});
}

Future<MonitorCapture?> captureMonitorBitmapAlternative({required int monitorHandle}) async {
  final Map<dynamic, dynamic>? result = await tabameWin32MethodChannel.invokeMapMethod<dynamic, dynamic>(
    'captureMonitorBitmapAlternative',
    <String, dynamic>{'monitorHandle': monitorHandle},
  );
  if (result == null) return null;
  return MonitorCapture._fromMap(result);
}

Future<bool> excludeWindowFromCapture(int hWnd) async {
  final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
    'excludeWindowFromCapture',
    <String, dynamic>{'hWnd': hWnd},
  );
  return result ?? false;
}

Future<bool> includeWindowFromCapture(int hWnd) async {
  final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
    'includeWindowFromCapture',
    <String, dynamic>{'hWnd': hWnd},
  );
  return result ?? false;
}

Future<bool> startKeyboardBlocker() async {
  final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('startKeyboardBlocker');
  return result ?? false;
}

Future<void> stopKeyboardBlocker() async {
  await tabameWin32MethodChannel.invokeMethod<void>('stopKeyboardBlocker');
}

Future<bool> moveWindowToDesktopMethod({required int hWnd, required DesktopDirection direction}) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'hWnd': hWnd,
    'direction': direction.index,
  };
  final bool result = await tabameWin32MethodChannel.invokeMethod<bool>('moveWindowToDesktop', arguments) ?? false;
  return result;
}

enum DesktopDirection { left, right }

Future<bool> moveDesktopMethod(DesktopDirection direction) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'hWnd': 0,
    'direction': direction.index,
  };
  final bool result = await tabameWin32MethodChannel.invokeMethod<bool>('moveWindowToDesktop', arguments) ?? false;
  return result;
}

enum WallpaperFillMode {
  center,
  tile,
  stretch,
  fit,
  fill,
  span,
}

class Desktop {
  static Future<bool> setWallpaper(String imagePath, int monitorIndex,
      {WallpaperFillMode fillMode = WallpaperFillMode.fill}) async {
    final Map<String, dynamic> arguments = <String, dynamic>{
      'imagePath': imagePath,
      'monitorIndex': monitorIndex,
      'fillMode': fillMode.index,
    };
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('setDesktopWallpaper', arguments);
    return result ?? false;
  }
}

Future<bool> setSkipTaskbar({required int hWnd, required bool skip}) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'hWnd': hWnd,
    'skip': skip,
  };
  final bool result = await tabameWin32MethodChannel.invokeMethod<bool>('setSkipTaskbar', arguments) ?? false;
  return result;
}

Future<String> convertLinkToPath(String lnkPath) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'lnkPath': lnkPath,
  };
  final String result = await tabameWin32MethodChannel.invokeMethod<String>('convertLinkToPath', arguments) ?? "";
  return result;
}

Future<void> setStartOnSystemStartup(bool enabled, {String? exePath, int showCmd = 1, String args = ""}) async {
  exePath ??= Platform.resolvedExecutable;
  final Map<String, dynamic> arguments = <String, dynamic>{
    'exePath': exePath,
    'enabled': enabled,
    'showCmd': showCmd,
    'args': args,
  };
  await tabameWin32MethodChannel.invokeMethod('setStartOnSystemStartup', arguments);
  return;
}

Future<void> createShortcut(String exePath, String destPath,
    {bool create = true, int showCmd = 1, String args = "", String destExe = ""}) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'exePath': exePath,
    'destPath': destPath,
    'enabled': create,
    'showCmd': showCmd,
    'args': args,
    'destExe': destExe,
  };
  await tabameWin32MethodChannel.invokeMethod('createShortcut', arguments);
  return;
}

Future<void> setStartOnStartupAsAdmin(bool enabled, {String? exePath}) async {
  exePath ??= Platform.resolvedExecutable;
  final Map<String, dynamic> arguments = <String, dynamic>{
    'exePath': exePath,
    'enabled': enabled,
  };
  await tabameWin32MethodChannel.invokeMethod<int>('setStartOnStartupAsAdmin', arguments) ?? 0;
  return;
}

Future<List<dynamic>> getSystemUsage() async {
  final SystemStatsInfo result = await getSystemStats();
  return <dynamic>[result.cpuLoadRatio, result.memoryLoad];
}

Future<SystemStatsInfo> getSystemStats({bool onlyUsage = true}) async {
  final Map<dynamic, dynamic> result = await tabameWin32MethodChannel.invokeMethod(
        'getSystemUsage',
        <String, dynamic>{'onlyUsage': onlyUsage},
      ) ??
      <dynamic, dynamic>{};
  return SystemStatsInfo.fromMap(result);
}

class HardwareData {
  final double cpuUsage;
  final double cpuTemp;
  final double ramUsage;
  final double gpuUsage;
  final double gpuTemp;

  const HardwareData({
    required this.cpuUsage,
    required this.cpuTemp,
    required this.ramUsage,
    required this.gpuUsage,
    required this.gpuTemp,
  });

  factory HardwareData.fromMap(Map<dynamic, dynamic> map) {
    double toDouble(dynamic value) {
      if (value is int) return value.toDouble();
      if (value is double) return value;
      return 0.0;
    }

    return HardwareData(
      cpuUsage: toDouble(map['cpuUsage']),
      cpuTemp: toDouble(map['cpuTemp']),
      ramUsage: toDouble(map['ramUsage']),
      gpuUsage: toDouble(map['gpuUsage']),
      gpuTemp: toDouble(map['gpuTemp']),
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'cpuUsage': cpuUsage,
      'cpuTemp': cpuTemp,
      'ramUsage': ramUsage,
      'gpuUsage': gpuUsage,
      'gpuTemp': gpuTemp,
    };
  }

  @override
  String toString() {
    return 'HardwareData('
        'cpuUsage: $cpuUsage, '
        'cpuTemp: $cpuTemp, '
        'ramUsage: $ramUsage, '
        'gpuUsage: $gpuUsage, '
        'gpuTemp: $gpuTemp'
        ')';
  }
}

Future<void> toggleMonitorWallpaper(bool enabled) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'enabled': enabled,
  };
  await tabameWin32MethodChannel.invokeMethod('toggleMonitorWallpaper', arguments);
  return;
}

Future<void> setWallpaperColor(int color) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'color': color,
  };
  await tabameWin32MethodChannel.invokeMethod('setWallpaperColor', arguments);
  return;
}

Future<String> pickFolder() async {
  final String result = await tabameWin32MethodChannel.invokeMethod<String>('browseFolder') ?? "";
  return result;
}

class AppEnumeration {
  AppEnumeration._();

  static Future<List<AppInfo>> getAllApps() async {
    final List<Object?>? raw = await tabameWin32MethodChannel.invokeMethod<List<Object?>>('getAllApps');
    if (raw == null) return const <AppInfo>[];

    return raw.whereType<Map<Object?, Object?>>().map(AppInfo.fromMap).toList(growable: false);
  }

  static Future<AppIconData?> getAppIcon(
    String parsingName, {
    int size = 64,
  }) async {
    final Map<Object?, Object?>? raw = await tabameWin32MethodChannel.invokeMethod<Map<Object?, Object?>>(
      'getAppIcon',
      <String, dynamic>{'parsingName': parsingName, 'size': size},
    );
    if (raw == null) return null;

    final Object? pixels = raw['pixels'];
    final int? width = raw['width'] as int?;
    final int? height = raw['height'] as int?;

    if (pixels == null || width == null || height == null) return null;

    return AppIconData(
      // ignore: always_specify_types
      pixels: pixels is Uint8List ? pixels : Uint8List.fromList((pixels as List).cast<int>()),
      width: width,
      height: height,
    );
  }
}

Future<bool> isWindows11() async {
  final bool result = await tabameWin32MethodChannel.invokeMethod<bool>('isWindows11') ?? true;
  return result;
}

Future<bool> setWindowTheme(int type) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'type': type,
  };
  final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('setWindowTheme', arguments);
  return result ?? false;
}

//!Hooks

Future<void> enableTrcktivity(bool enabled) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'enabled': enabled,
  };
  await tabameWin32MethodChannel.invokeMethod('trcktivity', arguments);
}

Future<void> enableViews(bool enabled) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'enabled': enabled,
  };
  await tabameWin32MethodChannel.invokeMethod('views', arguments);
}

Future<void> nativeShellOpen(String path, {String arguments = "", String workingDirectory = ""}) async {
  final Map<String, dynamic> mArgs = <String, dynamic>{
    'path': path,
    'arguments': arguments,
    'workingDirectory': workingDirectory,
  };
  await tabameWin32MethodChannel.invokeMethod('shellOpen', mArgs);
}

Future<bool> launchWithExplorer(String file, {String? arguments, String workingDirectory = ""}) async {
  final Map<String, dynamic> mArgs = <String, dynamic>{
    'file': file,
    'arguments': arguments ?? "",
    'workingDirectory': workingDirectory,
  };
  final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('launchWithExplorer', mArgs);
  return result ?? false;
}

class MousePos {
  final Point<int> start;
  final Point<int> end;
  Point<int> get diff => end - start;
  MousePos({
    required this.start,
    required this.end,
  });

  @override
  String toString() => 'MousePos(start: $start, end: $end)';
}

class HotkeyTime {
  final int start;
  final int end;
  int get duration => end - start;
  HotkeyTime({
    required this.start,
    required this.end,
  });

  @override
  String toString() => 'HotkeyTime(start: $start, end: $end)';
}

class HotkeyEvent {
  final MousePos mouse;
  final HotkeyTime time;
  final String hotkey;
  String action;
  final String name;
  final int vk;
  HotkeyEvent({
    required this.mouse,
    required this.time,
    required this.hotkey,
    required this.action,
    required this.name,
    this.vk = -1,
  });

  @override
  String toString() {
    return 'HotkeyEvent(mouse: $mouse, time: $time, hotkey: $hotkey, action: $action, name: $name)';
  }
}

class MonitorEvent {
  int width;
  int height;
  int bitDepth;
  MonitorEvent({
    required this.width,
    required this.height,
    required this.bitDepth,
  });
}

enum WinEventType {
  foreground,
  nameChange,
}

enum ViewsAction {
  open,
  moveStart,
  moveEnd,
  selecting,
  selected,
  switchUp,
  switchDown,
}

abstract class TabameListener {
  void onHotKeyEvent(HotkeyEvent hotkeyInfo) {}
  void onDisplayChange(MonitorEvent hotkeyInfo) {}
  void onForegroundWindowChanged(int hWnd) {}
  void onTricktivityEvent(String action, String info) {}
  void onWinEventReceived(int hWnd, WinEventType type) {}
  void onViewsEvent(ViewsAction action, int hWnd) {}
  void onQuickClickEvent(String eventName, Map<String, String> params) {}
}

abstract class ClipboardEventListener {
  void onClipboardUpdate() {}
}

class ClipboardHooks {
  static final ObserverList<ClipboardEventListener> listenersObv = ObserverList<ClipboardEventListener>();

  static List<ClipboardEventListener> get listeners => List<ClipboardEventListener>.from(listenersObv);

  static bool get hasListeners {
    return listenersObv.isNotEmpty;
  }

  static void addListener(ClipboardEventListener listener) {
    listenersObv.add(listener);
  }

  static void removeListener(ClipboardEventListener listener) {
    listenersObv.remove(listener);
  }

  static Future<bool> start() async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('startClipboardWatcher');
    return result ?? false;
  }

  static Future<bool> stop() async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('stopClipboardWatcher');
    return result ?? false;
  }

  static void _dispatchClipboardUpdate() {
    for (final ClipboardEventListener listener in listeners) {
      if (!listenersObv.contains(listener)) continue;
      listener.onClipboardUpdate();
    }
  }
}

/// ? NativeHotkey
class NativeHooks {
  static final ObserverList<TabameListener> listenersObv = ObserverList<TabameListener>();
  static bool isRegistered = false;
  static List<TabameListener> get listeners => List<TabameListener>.from(listenersObv);

  static bool get hasListeners {
    return listenersObv.isNotEmpty;
  }

  /// Add EventListener to the list of listeners.
  static void addListener(TabameListener listener) {
    listenersObv.add(listener);
  }

  static void removeListener(TabameListener listener) {
    listenersObv.remove(listener);
  }

  static Future<void> _methodCallHandler(MethodCall call) async {
    if (!<String>[
      "HotKeyEvent",
      "TrktivityEvent",
      "ViewsEvent",
      "WinEvent",
      "ClipboardUpdate",
      "onQuickClickEvent",
      "onDisplayChange"
    ].contains(call.method)) {
      return;
    }
    if (call.method == "ClipboardUpdate") {
      ClipboardHooks._dispatchClipboardUpdate();
    }
    if (call.method == 'onDisplayChange') {
      // ignore: always_specify_types
      final Map<dynamic, dynamic> args = call.arguments as Map;
      final int width = args['width'] as int;
      final int height = args['height'] as int;
      final int bitDepth = args['bitDepth'] as int;
      // await Monitor.fetchMonitors();
      for (final TabameListener listener in listeners) {
        if (!listenersObv.contains(listener)) continue;
        listener.onDisplayChange(MonitorEvent(width: width, height: height, bitDepth: bitDepth));
      }
      // fetch once, reactively
    }
    if (call.method == "HotKeyEvent") {
      for (final TabameListener listener in listeners) {
        if (!listenersObv.contains(listener)) continue;

        listener.onHotKeyEvent(
          HotkeyEvent(
            name: call.arguments["name"],
            action: call.arguments["info"],
            hotkey: call.arguments["hotkey"],
            vk: call.arguments["vk"],
            mouse: MousePos(
              start: Point<int>(call.arguments["sX"], call.arguments["sY"]),
              end: Point<int>(call.arguments["eX"], call.arguments["eY"]),
            ),
            time: HotkeyTime(
              start: call.arguments["start"],
              end: call.arguments["end"],
            ),
          ),
        );
      }
    }
    if (call.method == "TrktivityEvent") {
      for (final TabameListener listener in listeners) {
        if (!listenersObv.contains(listener)) continue;
        listener.onTricktivityEvent(call.arguments["action"], call.arguments["info"]);
      }
    }
    if (call.method == "ViewsEvent") {
      for (final TabameListener listener in listeners) {
        if (!listenersObv.contains(listener)) continue;
        listener.onViewsEvent(
            ViewsAction.values.firstWhere((ViewsAction element) => element.name == call.arguments["action"]),
            call.arguments["hwnd"]);
      }
    }
    if (call.method == "WinEvent") {
      if (call.arguments['action'] == "foreground") {
        for (final TabameListener listener in listeners) {
          if (!listenersObv.contains(listener)) continue;
          listener.onForegroundWindowChanged(call.arguments['hwnd']);
          listener.onWinEventReceived(call.arguments['hwnd'], WinEventType.foreground);
        }
      } else if (call.arguments['action'] == "namechange") {
        for (final TabameListener listener in listeners) {
          if (!listenersObv.contains(listener)) continue;
          listener.onWinEventReceived(call.arguments['hwnd'], WinEventType.nameChange);
        }
      }
    }
    if (call.method == "onQuickClickEvent") {
      final Map<dynamic, dynamic> args = call.arguments as Map<dynamic, dynamic>;
      final String eventName = args["eventName"] as String;
      // ignore: always_specify_types
      final Map<String, String> params = args.map((key, value) => MapEntry(key.toString(), value.toString()))
        ..remove("eventName");
      QuickClick._handleEvent(eventName, params);
      for (final TabameListener listener in listeners) {
        if (!listenersObv.contains(listener)) continue;
        listener.onQuickClickEvent(eventName, params);
      }
    }
  }

  static void registerCallHandler() {
    tabameWin32MethodChannel.setMethodCallHandler(_methodCallHandler);
  }

  static Future<void> addHotkey(Map<String, dynamic> hotkey) async {
    await tabameWin32MethodChannel.invokeMethod('hotkeyAdd', hotkey);
  }

  static Future<void> resetHotkeys() async {
    await tabameWin32MethodChannel.invokeMethod('hotkeyReset');
  }

  static Future<void> hook() async {
    await tabameWin32MethodChannel.invokeMethod('hotkeyHook');
    isRegistered = true;
  }

  static Future<void> unHook() async {
    await tabameWin32MethodChannel.invokeMethod('hotkeyUnHook');
    isRegistered = false;
  }

  static Future<void> freeHotkeys() async {
    await tabameWin32MethodChannel.invokeMethod('freeHotkey');
  }

  static Future<void> runHotkeys(List<Map<String, dynamic>> hotkeys) async {
    if (isRegistered) await unHook();
    resetHotkeys();
    for (Map<String, dynamic> i in hotkeys) {
      await addHotkey(i);
    }
    hook();
  }
}

Future<bool> enableDebug(String path) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'path': path,
  };
  await tabameWin32MethodChannel.invokeMethod('enableDebug', arguments);
  return true;
}

class WinClipboard {
  Future<void> saveClipboardToPng(String path) async {
    final Map<String, dynamic> arguments = <String, dynamic>{
      'imagePath': path,
    };
    await tabameWin32MethodChannel.invokeMethod('saveClipboardImageAsPngFile', arguments);
  }

  Future<void> copyImageToClipboard(String path) async {
    final Map<String, dynamic> arguments = <String, dynamic>{
      'path': path,
    };
    await tabameWin32MethodChannel.invokeMethod('copyImageToClipboard', arguments);
  }
}

/// Metadata for a clipboard image that the native side captured, encoded, and
/// wrote to disk (see [ClipboardExtended.saveImageToFile]). The PNG bytes never
/// cross into the Dart isolate.
class ClipboardImageInfo {
  const ClipboardImageInfo({
    required this.path,
    required this.byteLength,
    required this.hash,
  });

  /// Absolute path of the PNG file the native side wrote.
  final String path;

  /// Size of the written PNG, in bytes.
  final int byteLength;

  /// MD5 hex digest of the PNG bytes (matches Dart `md5.convert`), for
  /// clipboard-history duplicate detection. Empty if hashing failed.
  final String hash;
}

class ClipboardExtended {
  ClipboardExtended._();

  static Future<bool> copy(String text) async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
      'clipboardExtendedCopy',
      <String, dynamic>{'text': text},
    );
    return result ?? false;
  }

  static Future<bool> copyRichText({String text = '', String html = ''}) async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
      'clipboardExtendedCopyRichText',
      <String, dynamic>{'text': text, 'html': html},
    );
    return result ?? false;
  }

  static Future<bool> copyMultiple({
    String? text,
    String? html,
    Uint8List? pngBytes,
  }) async {
    final Map<String, dynamic> formats = <String, dynamic>{};
    if (text != null) formats['text/plain'] = text;
    if (html != null) formats['text/html'] = html;
    if (pngBytes != null) formats['image/png'] = pngBytes; // typed data (Uint8List) — single buffer, not a boxed int list

    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
      'clipboardExtendedCopyMultiple',
      <String, dynamic>{'formats': formats},
    );
    return result ?? false;
  }

  static Future<bool> copyImage(Uint8List imageBytes) async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
      'clipboardExtendedCopyImage',
      <String, dynamic>{'imageBytes': imageBytes}, // typed data (Uint8List) — single buffer, not a boxed int list
    );
    return result ?? false;
  }

  static Future<Map<String, dynamic>> paste() async {
    final Map<dynamic, dynamic>? result = await tabameWin32MethodChannel.invokeMapMethod<dynamic, dynamic>(
      'clipboardExtendedPaste',
    );
    return Map<String, dynamic>.from(result ?? <dynamic, dynamic>{});
  }

  static Future<String> pasteText() async {
    final Map<String, dynamic> data = await paste();
    return (data['text'] as String?) ?? '';
  }

  static Future<Map<String, dynamic>> pasteRichText() async {
    final Map<dynamic, dynamic>? result = await tabameWin32MethodChannel.invokeMapMethod<dynamic, dynamic>(
      'clipboardExtendedPasteRichText',
    );
    return Map<String, dynamic>.from(result ?? <dynamic, dynamic>{});
  }

  static Future<Uint8List?> pasteImage() async {
    final Map<dynamic, dynamic>? result = await tabameWin32MethodChannel.invokeMapMethod<dynamic, dynamic>(
      'clipboardExtendedPasteImage',
    );
    final dynamic bytes = result?['imageBytes'];
    if (bytes is Uint8List) return bytes;
    if (bytes is List) return Uint8List.fromList(bytes.cast<int>());
    return null;
  }

  /// Captures the current clipboard image, encodes it to PNG, and writes it to
  /// [path] — all on a native background thread. Only small metadata crosses the
  /// method channel; the PNG bytes never enter the Dart isolate, so this does
  /// not block Flutter's platform thread (which owns the global mouse hook).
  /// Returns null when the clipboard holds no image, or throws a
  /// [PlatformException] (code `PASTE_IMAGE_ERROR` when there is no image).
  static Future<ClipboardImageInfo?> saveImageToFile(String path) async {
    final Map<dynamic, dynamic>? result = await tabameWin32MethodChannel.invokeMapMethod<dynamic, dynamic>(
      'clipboardExtendedSaveImage',
      <String, dynamic>{'path': path},
    );
    if (result == null || result['saved'] != true) return null;
    return ClipboardImageInfo(
      path: (result['path'] as String?) ?? path,
      byteLength: (result['byteLength'] as int?) ?? 0,
      hash: (result['hash'] as String?) ?? '',
    );
  }

  static Future<String> getContentType() async {
    final String? result = await tabameWin32MethodChannel.invokeMethod<String>('clipboardExtendedGetContentType');
    return result ?? 'unknown';
  }

  static Future<bool> hasData() async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('clipboardExtendedHasData');
    return result ?? false;
  }

  static Future<bool> clear() async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('clipboardExtendedClear');
    return result ?? false;
  }

  static Future<int> getDataSize() async {
    final int? result = await tabameWin32MethodChannel.invokeMethod<int>('clipboardExtendedGetDataSize');
    return result ?? 0;
  }

  static Future<bool> startMonitoring() async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('clipboardExtendedStartMonitoring');
    return result ?? false;
  }

  static Future<bool> stopMonitoring() async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('clipboardExtendedStopMonitoring');
    return result ?? false;
  }
}

Future<void> initializeGDI() async {
  await tabameWin32MethodChannel.invokeMethod('initializeGDI');
}

class TaskbarButtonInfo {
  final String helpText;

  /// UIA button label (may include "- 2 running windows").
  final String uiaName;

  const TaskbarButtonInfo({
    required this.helpText,
    required this.uiaName,
  });

  /// Convenience accessor — true when [helpText] is non-empty.
  bool get hasBadge => helpText.isNotEmpty;

  factory TaskbarButtonInfo._fromMap(Map<Object?, Object?> m) {
    return TaskbarButtonInfo(helpText: (m['helpText'] as String?) ?? '', uiaName: (m['uiaName'] as String?) ?? '');
  }

  @override
  String toString() {
    return "$uiaName : $helpText";
  }
}

class TaskbarUia {
  TaskbarUia._();

  static Future<List<TaskbarButtonInfo>> getButtonInfos() async {
    final List<dynamic>? raw = await tabameWin32MethodChannel.invokeListMethod<dynamic>('getTaskbarItemHelpTexts');
    if (raw == null) return <TaskbarButtonInfo>[];
    return raw.cast<Map<Object?, Object?>>().map(TaskbarButtonInfo._fromMap).toList();
  }

  static Future<void> shutdown() async {
    await tabameWin32MethodChannel.invokeMethod<bool>('shutdownTaskbarUia');
  }
}

enum TrayClickType {
  /// UIA InvokePattern::Invoke() — works for Win32, Qt, Electron, Appx/UWP
  left,

  /// Resolves screen coordinates via UIA then sends a real right-click via SendInput
  right,

  /// Resolves screen coordinates via UIA then sends a real middle-click via SendInput
  middle,

  /// UIA InvokePattern::Invoke() called twice with 80ms gap
  doubleClick,
}

class ExtendedTrayIcon {
  /// Tooltip text of the tray icon (may be empty).
  final String toolTip;

  /// Process ID of the owning application.
  final int processId;

  /// HWND of the owning application window.
  final int hWnd;

  /// Icon identifier — wParam of the tray callback message.
  final int uID;

  /// The private WM_* message registered by the app for tray notifications.
  final int uCallbackMsg;

  /// GDI HICON handle (as integer).
  /// Pass to [getIconPng] to retrieve pixel data on demand:
  ///   final bytes = await getIconPng(icon.hIcon);
  final int hIcon;

  /// Whether the icon is currently visible in the main tray.
  final bool isVisible;

  /// True when this icon came from the overflow / "hidden icons" popup tray.
  final bool isOverflow;

  const ExtendedTrayIcon({
    required this.toolTip,
    required this.processId,
    required this.hWnd,
    required this.uID,
    required this.uCallbackMsg,
    required this.hIcon,
    required this.isVisible,
    required this.isOverflow,
  });

  factory ExtendedTrayIcon._fromMap(Map<Object?, Object?> m) {
    return ExtendedTrayIcon(
      toolTip: (m['toolTip'] as String?) ?? '',
      processId: (m['processId'] as int?) ?? 0,
      hWnd: (m['hWnd'] as int?) ?? 0,
      uID: (m['uID'] as int?) ?? 0,
      uCallbackMsg: (m['uCallbackMsg'] as int?) ?? 0,
      hIcon: (m['hIcon'] as int?) ?? 0,
      isVisible: (m['isVisible'] as bool?) ?? false,
      isOverflow: (m['isOverflow'] as bool?) ?? false,
    );
  }

  @override
  String toString() => 'ExtendedTrayIcon(toolTip: $toolTip, pid: $processId, hWnd: $hWnd, '
      'uID: $uID, visible: $isVisible, overflow: $isOverflow)';
}

class WinTray {
  WinTray._();

  static Future<List<ExtendedTrayIcon>> enumAllIcons() async {
    final List<dynamic>? raw = await tabameWin32MethodChannel.invokeListMethod<dynamic>('enumAllTrayIcons');
    if (raw == null) return <ExtendedTrayIcon>[];
    return raw.cast<Map<Object?, Object?>>().map(ExtendedTrayIcon._fromMap).toList();
  }

  static Future<bool> click(
    ExtendedTrayIcon icon, {
    TrayClickType clickType = TrayClickType.left,
  }) async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
      'clickTrayNotifyIcon',
      <String, dynamic>{
        'tipName': icon.toolTip,
        'isOverflow': icon.isOverflow,
        'clickType': clickType.index,
      },
    );
    return result ?? false;
  }
}

class WinSystray {
  WinSystray._();

  static Future<bool> startMonitor() async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('startSystrayMonitor');
    return result ?? false;
  }

  static Future<List<ExtendedTrayIcon>> snapshotIcons() async {
    final List<dynamic>? raw = await tabameWin32MethodChannel.invokeListMethod<dynamic>('snapshotSystrayMonitorIcons');
    if (raw == null) return <ExtendedTrayIcon>[];
    return raw.cast<Map<Object?, Object?>>().map(ExtendedTrayIcon._fromMap).toList();
  }

  static Future<bool> stopMonitor() async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>('stopSystrayMonitor');
    return result ?? false;
  }
}

// class FolderWatch {
//   FolderWatch._();

//   static Future<void> buildInitialState(List<String> paths) async {
//     await addFoldersToWatchlist(paths);
//   }

//   static Future<List<String>> getChangedFolders() async {
//     final List<dynamic>? result = await tabameWin32MethodChannel.invokeListMethod<dynamic>('getChangedFolders');
//     return result?.cast<String>() ?? <String>[];
//   }

//   static Future<void> addFoldersToWatchlist(List<String> paths) async {
//     await tabameWin32MethodChannel.invokeMethod<void>(
//       'addFoldersToWatchlist',
//       <String, dynamic>{'paths': paths},
//     );
//   }

//   /// Removes folders from the internal watchlist.
//   static Future<void> removeFoldersFromWatchlist(List<String> paths) async {
//     await tabameWin32MethodChannel.invokeMethod<void>(
//       'removeFoldersFromWatchlist',
//       <String, dynamic>{'paths': paths},
//     );
//   }
// }

class QuickClickConfig {
  final String horizontalKeys;
  final String verticalKeys;
  final int nudgeAmount;
  final int shiftNudgeAmount;
  final int doubleClickThresholdMs;
  final Map<String, List<int>> extraArrowBindings;
  final int leftClickKey;
  final int rightClickKey;
  final int dragKey;
  final int scrollUpKey;
  final int scrollDownKey;
  final int scrollLeftKey;
  final int scrollRightKey;
  final int scrollDelta;
  final int escapeKey;
  final int zoneModeKey;
  final int nextMonitorKey;
  final int prevMonitorKey;
  final int toggleOverlayKey;
  final int infoKey;

  QuickClickConfig({
    this.horizontalKeys = '123456789',
    this.verticalKeys = 'qwertyuio',
    this.nudgeAmount = 5,
    this.shiftNudgeAmount = 25,
    this.doubleClickThresholdMs = 400,
    this.extraArrowBindings = const <String, List<int>>{},
    this.leftClickKey = 0x11, // VK_CONTROL
    this.rightClickKey = 0x12, // VK_MENU
    this.dragKey = 0x12, // VK_MENU
    this.scrollUpKey = 0xDB, // VK_OEM_4 ([)
    this.scrollDownKey = 0xDD, // VK_OEM_6 (])
    this.scrollLeftKey = 0xBA, // VK_OEM_1 (;)
    this.scrollRightKey = 0xDE, // VK_OEM_7 (')
    this.scrollDelta = 120, // WHEEL_DELTA
    this.escapeKey = 0x1B, // VK_ESCAPE
    this.zoneModeKey = 0,
    this.nextMonitorKey = 0,
    this.prevMonitorKey = 0,
    this.toggleOverlayKey = 0,
    this.infoKey = 0xBF, // VK_OEM_2
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'horizontalKeys': horizontalKeys,
      'verticalKeys': verticalKeys,
      'nudgeAmount': nudgeAmount,
      'shiftNudgeAmount': shiftNudgeAmount,
      'doubleClickThresholdMs': doubleClickThresholdMs,
      'extraArrowBindings': extraArrowBindings,
      'leftClickKey': leftClickKey,
      'rightClickKey': rightClickKey,
      'dragKey': dragKey,
      'scrollUpKey': scrollUpKey,
      'scrollDownKey': scrollDownKey,
      'scrollLeftKey': scrollLeftKey,
      'scrollRightKey': scrollRightKey,
      'scrollDelta': scrollDelta,
      'escapeKey': escapeKey,
      'zoneModeKey': zoneModeKey,
      'nextMonitorKey': nextMonitorKey,
      'prevMonitorKey': prevMonitorKey,
      'toggleOverlayKey': toggleOverlayKey,
      'infoKey': infoKey,
    };
  }

  factory QuickClickConfig.fromMap(Map<String, dynamic> map) {
    return QuickClickConfig(
      horizontalKeys: map['horizontalKeys'] ?? '123456789',
      verticalKeys: map['verticalKeys'] ?? 'qwertyuio',
      nudgeAmount: map['nudgeAmount'] ?? 5,
      shiftNudgeAmount: map['shiftNudgeAmount'] ?? 25,
      doubleClickThresholdMs: map['doubleClickThresholdMs'] ?? 400,
      extraArrowBindings: (map['extraArrowBindings'] as Map<dynamic, dynamic>?)?.map(
            // ignore: always_specify_types
            (key, value) => MapEntry(key.toString(), List<int>.from(value)),
          ) ??
          const <String, List<int>>{},
      leftClickKey: map['leftClickKey'] ?? 0x11,
      rightClickKey: map['rightClickKey'] ?? 0x12,
      dragKey: map['dragKey'] ?? 0x12,
      scrollUpKey: map['scrollUpKey'] ?? 0xDB,
      scrollDownKey: map['scrollDownKey'] ?? 0xDD,
      scrollLeftKey: map['scrollLeftKey'] ?? 0xBA,
      scrollRightKey: map['scrollRightKey'] ?? 0xDE,
      scrollDelta: map['scrollDelta'] ?? 120,
      escapeKey: map['escapeKey'] ?? 0x1B,
      zoneModeKey: map['zoneModeKey'] ?? 0,
      nextMonitorKey: map['nextMonitorKey'] ?? 0,
      prevMonitorKey: map['prevMonitorKey'] ?? 0,
      toggleOverlayKey: map['toggleOverlayKey'] ?? 0,
      infoKey: map['infoKey'] ?? 0xBF,
    );
  }
}

class QuickClickEvent {
  final String name;
  final Map<String, String> params;
  QuickClickEvent(this.name, this.params);

  @override
  String toString() => 'QuickClickEvent(name: $name, params: $params)';
}

class QuickClick {
  static final StreamController<QuickClickEvent> _eventController = StreamController<QuickClickEvent>.broadcast();
  static Stream<QuickClickEvent> get onQuickClickEvent => _eventController.stream;

  static void _handleEvent(String eventName, Map<String, String> params) {
    _eventController.add(QuickClickEvent(eventName, params));
  }

  static Future<void> registerQuickClick(QuickClickConfig config) async {
    await tabameWin32MethodChannel.invokeMethod('registerQuickClick', config.toMap());
  }

  static Future<void> setQuickClickHotkeys(QuickClickConfig config) async {
    await tabameWin32MethodChannel.invokeMethod('setQuickClickHotkeys', config.toMap());
  }

  static Future<void> enableQuickClick() async {
    await tabameWin32MethodChannel.invokeMethod('enableQuickClick');
  }

  static Future<void> disableQuickClick() async {
    await tabameWin32MethodChannel.invokeMethod('disableQuickClick');
  }
}

class ShellMenuItem {
  final int id;
  final String label;
  final String verb;
  final bool enabled;
  final Uint8List? iconBytes;

  const ShellMenuItem({
    required this.id,
    required this.label,
    required this.verb,
    required this.enabled,
    this.iconBytes,
  });

  factory ShellMenuItem.fromMap(Map<Object?, Object?> map) {
    final dynamic rawIconBytes = map['iconBytes'];
    final Uint8List? iconBytes = rawIconBytes is Uint8List
        ? rawIconBytes
        : (rawIconBytes is List<dynamic> ? Uint8List.fromList(rawIconBytes.cast<int>()) : null);

    return ShellMenuItem(
      id: map['id'] as int? ?? -1,
      label: map['label'] as String? ?? '',
      verb: map['verb'] as String? ?? '',
      enabled: map['enabled'] as bool? ?? false,
      iconBytes: iconBytes,
    );
  }

  @override
  String toString() => 'ShellMenuItem(id: $id, label: $label, verb: $verb, enabled: $enabled)';
}

class ShellContextMenu {
  ShellContextMenu._();

  static Future<List<ShellMenuItem>> getMenuItems(String path) async {
    final List<Object?>? raw = await tabameWin32MethodChannel.invokeMethod<List<Object?>>(
      'getShellMenuItems',
      <String, dynamic>{'path': path},
    );
    if (raw == null) return const <ShellMenuItem>[];
    return raw.whereType<Map<Object?, Object?>>().map(ShellMenuItem.fromMap).toList(growable: false);
  }

  static Future<bool> invoke(String path, int hWnd, {String verb = '', int id = -1}) async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
      'invokeShellMenuItem',
      <String, dynamic>{
        'path': path,
        'verb': verb,
        'id': id,
        'hWnd': hWnd,
      },
    );
    return result ?? false;
  }
}

/// A single open tab in a Chromium-based browser (Chrome/Edge/Brave/Opera/...),
/// discovered through UI Automation. See [BrowserTabs].
class BrowserTab {
  const BrowserTab({
    required this.browser,
    required this.hWnd,
    required this.index,
    required this.title,
  });

  /// Friendly browser name, e.g. "Chrome", "Edge", "Brave", "Opera".
  final String browser;

  /// Top-level browser window handle that owns this tab.
  final int hWnd;

  /// Position of the tab within its window's tab strip.
  final int index;

  /// The tab/page title.
  final String title;

  factory BrowserTab.fromMap(Map<Object?, Object?> map) {
    return BrowserTab(
      browser: (map['browser'] as String?) ?? '',
      hWnd: (map['hWnd'] as int?) ?? 0,
      index: (map['index'] as int?) ?? 0,
      title: (map['title'] as String?) ?? '',
    );
  }
}

/// Enumerate and activate Chromium-based browser tabs via UI Automation.
class BrowserTabs {
  /// Returns every open tab across all running Chromium-based browser windows.
  static Future<List<BrowserTab>> getTabs() async {
    final List<Object?>? raw = await tabameWin32MethodChannel.invokeMethod<List<Object?>>('getBrowserTabs');
    if (raw == null) return const <BrowserTab>[];
    return raw.whereType<Map<Object?, Object?>>().map(BrowserTab.fromMap).toList(growable: false);
  }

  /// Brings [hWnd]'s browser window to the foreground and switches to the tab
  /// identified by [index] (falling back to [title] if the strip changed).
  static Future<bool> focusTab({required int hWnd, required int index, required String title}) async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
      'focusBrowserTab',
      <String, dynamic>{
        'hWnd': hWnd,
        'index': index,
        'title': title,
      },
    );
    return result ?? false;
  }
}

/// A connected display along with its HDR (advanced color) capability/state.
class HDRDisplay {
  /// Low part of the adapter LUID — identifies the display together with
  /// [adapterIdHigh] and [id] across re-queries.
  final int adapterIdLow;

  /// High part of the adapter LUID.
  final int adapterIdHigh;

  /// Target id of the display on its adapter.
  final int id;

  /// Friendly monitor name (e.g. "DELL U2720Q"), or "Display" if unavailable.
  final String name;

  /// Whether the display reports HDR (advanced color) support.
  final bool supportsHDR;

  /// Whether HDR is currently enabled on the display.
  final bool isHDREnabled;

  const HDRDisplay({
    required this.adapterIdLow,
    required this.adapterIdHigh,
    required this.id,
    required this.name,
    required this.supportsHDR,
    required this.isHDREnabled,
  });

  factory HDRDisplay.fromMap(Map<Object?, Object?> map) {
    return HDRDisplay(
      adapterIdLow: (map['adapterIdLow'] as int?) ?? 0,
      adapterIdHigh: (map['adapterIdHigh'] as int?) ?? 0,
      id: (map['id'] as int?) ?? 0,
      name: (map['name'] as String?) ?? 'Display',
      supportsHDR: (map['supportsHDR'] as bool?) ?? false,
      isHDREnabled: (map['isHDREnabled'] as bool?) ?? false,
    );
  }
}

/// Enumerate displays and toggle HDR via the Win32 DisplayConfig API.
class HDR {
  /// Returns every active display with its HDR support/state.
  static Future<List<HDRDisplay>> getDisplays() async {
    final List<Object?>? raw = await tabameWin32MethodChannel.invokeMethod<List<Object?>>('getHDRDisplays');
    if (raw == null) return const <HDRDisplay>[];
    return raw.whereType<Map<Object?, Object?>>().map(HDRDisplay.fromMap).toList(growable: false);
  }

  /// Enables or disables HDR for the display identified by [display].
  /// Returns true when the change was applied successfully.
  static Future<bool> setState(HDRDisplay display, bool enable) async {
    final bool? result = await tabameWin32MethodChannel.invokeMethod<bool>(
      'setHDRState',
      <String, dynamic>{
        'adapterIdLow': display.adapterIdLow,
        'adapterIdHigh': display.adapterIdHigh,
        'id': display.id,
        'enable': enable,
      },
    );
    return result ?? false;
  }
}
