// ignore_for_file: public_member_api_docs, sort_constructors_first
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'dart:ui' as ui;

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

    return other is AudioDevice && other.id == id && other.name == name && other.iconPath == iconPath && other.iconID == iconID && other.isActive == isActive;
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

    return other is ProcessVolume && other.processId == processId && other.processPath == processPath && other.maxVolume == maxVolume && other.peakVolume == peakVolume;
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

const MethodChannel audioMethodChannel = MethodChannel('tabamewin32');

class Audio {
  /// Returns a Future list of audio devices of a specified type.
  /// The type is specified by the [AudioDeviceType] enum.
  ///
  static Future<List<AudioDevice>?> enumDevices(AudioDeviceType audioDeviceType) async {
    final Map<String, dynamic> arguments = <String, int>{'deviceType': audioDeviceType.index};
    final Map<dynamic, dynamic> map = await audioMethodChannel.invokeMethod('enumAudioDevices', arguments);
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
    final Map<String, dynamic> arguments = <String, int>{'deviceType': audioDeviceType.index};
    final Map<dynamic, dynamic> map = await audioMethodChannel.invokeMethod('getDefaultDevice', arguments);
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
  static Future<int> setDefaultDevice(String deviceID) async {
    final Map<String, dynamic> arguments = <String, String>{'deviceID': deviceID};
    final int? result = await audioMethodChannel.invokeMethod<int>('setDefaultAudioDevice', arguments);
    return result as int;
  }

  /// Returns the current volume for the given audio device type.
  /// The type is specified by the [AudioDeviceType] enum.
  static Future<double> getVolume(AudioDeviceType audioDeviceType) async {
    final Map<String, dynamic> arguments = <String, int>{'deviceType': audioDeviceType.index};
    final double? result = await audioMethodChannel.invokeMethod<double>('getAudioVolume', arguments);
    return result as double;
  }

  /// This function sets the volume of the specified audio device type. The volume level is a number between 0 and 1, with 1 being the maximum volume.
  /// The type is specified by the [AudioDeviceType] enum.
  ///
  static Future<int> setVolume(double volume, AudioDeviceType audioDeviceType) async {
    if (volume > 1) volume = (volume / 100).toDouble();
    final Map<String, dynamic> arguments = <String, dynamic>{'deviceType': audioDeviceType.index, 'volumeLevel': volume};
    final int? result = await audioMethodChannel.invokeMethod<int>('setAudioVolume', arguments);
    return result as int;
  }

  static Future<int> setMuteAudioDevice(bool muteState, AudioDeviceType audioDeviceType) async {
    final Map<String, dynamic> arguments = <String, dynamic>{'deviceType': audioDeviceType.index, 'muteState': muteState};
    final int? result = await audioMethodChannel.invokeMethod<int>('setMuteAudioDevice', arguments);
    return result as int;
  }

  static Future<bool> getMuteAudioDevice(AudioDeviceType audioDeviceType) async {
    final Map<String, dynamic> arguments = <String, dynamic>{
      'deviceType': audioDeviceType.index,
    };
    final bool? result = await audioMethodChannel.invokeMethod<bool>('getMuteAudioDevice', arguments);
    return result!;
  }

  /// This function switches the audio device to the specified type. The type is specified by the [AudioDeviceType] enum.
  static Future<bool> switchDefaultDevice(AudioDeviceType audioDeviceType) async {
    final Map<String, dynamic> arguments = <String, dynamic>{'deviceType': audioDeviceType.index};
    final bool? result = await audioMethodChannel.invokeMethod<bool>('switchDefaultDevice', arguments);
    return result as bool;
  }

  /// Returns a Future with a list of ProcessVolume objects containing information about all audio mixers.
  static Future<List<ProcessVolume>?> enumAudioMixer() async {
    final Map<dynamic, dynamic> map = await audioMethodChannel.invokeMethod('enumAudioMixer');
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
    if (volume > 1) volume = (volume / 100).toDouble();
    final Map<String, dynamic> arguments = <String, dynamic>{'processID': processID, 'volumeLevel': volume};
    final Map<dynamic, dynamic> map = await audioMethodChannel.invokeMethod('setAudioMixerVolume', arguments);
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

resizeImage(Uint8List data) {
  ui.decodeImageFromList(data, (ui.Image image) {});
}

/// This function converts a native icon location to bytes.
/// The icon location is the path to the icon file.
/// The icon ID is the icon ID of the icon file.
/// The icon ID can be obtained by calling the enumAudioDevices function.
Map<String, Uint8List> ___kCacheIcons = <String, Uint8List>{};
Future<Uint8List?> nativeIconToBytes(String iconLocation, {int iconID = 0}) async {
  if (___kCacheIcons.containsKey(iconLocation) && iconID == 0) return ___kCacheIcons[iconLocation];
  final Map<String, dynamic> arguments = <String, dynamic>{'iconLocation': iconLocation, 'iconID': iconID};
  final Uint8List? result = await audioMethodChannel.invokeMethod<Uint8List>('iconToBytes', arguments);
  ___kCacheIcons[iconLocation] = result!;
  return result;
}

Future<Uint8List?> getExecutableIcon(String iconlocation, {int iconID = 0}) async {
  return nativeIconToBytes(iconlocation, iconID: iconID);
}

Future<Uint8List?> getWindowIcon(int hWnd) async {
  final Map<String, dynamic> arguments = <String, dynamic>{'hWnd': hWnd};
  final Uint8List? result = await audioMethodChannel.invokeMethod<Uint8List>('getWindowIcon', arguments);
  return result;
}

Future<Uint8List?> getIconPng(int hIcon) async {
  final Map<String, dynamic> arguments = <String, dynamic>{'hIcon': hIcon};
  final Uint8List? result = await audioMethodChannel.invokeMethod<Uint8List>('getIconPng', arguments);
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
    return toolTip.hashCode ^ isVisible.hashCode ^ processID.hashCode ^ hWnd.hashCode ^ uID.hashCode ^ uCallbackMessage.hashCode;
  }
}

Future<List<TrayInfo>> enumTrayIcons({bool filter = false}) async {
  final Map<dynamic, dynamic> map = await audioMethodChannel.invokeMethod('enumTrayIcons');
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

Future<String> getHwndName(int hWnd) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'hWnd': hWnd,
  };
  final String result = await audioMethodChannel.invokeMethod<String>('getHwndName', arguments) ?? "-";
  return result;
}

Future<int> findTopWindow(int processID) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'processID': processID,
  };
  final int result = await audioMethodChannel.invokeMethod<int>('findTopWindow', arguments) ?? 0;
  return result;
}

Future<void> setTaskbarVisibility(bool state) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'state': state,
  };
  await audioMethodChannel.invokeMethod('toggleTaskbar', arguments);
}

Future<int> getFlutterMainWindow() async {
  final int result = await audioMethodChannel.invokeMethod<int>('getMainHandle') ?? 0;
  return result;
}

Future<void> setWindowAsTransparent() async {
  await audioMethodChannel.invokeMethod('setTransparent');
}

Future<bool> moveWindowToDesktopMethod({required int hWnd, required DesktopDirection direction}) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'hWnd': hWnd,
    'direction': direction.index,
  };
  final bool result = await audioMethodChannel.invokeMethod<bool>('moveWindowToDesktop', arguments) ?? false;
  return result;
}

Future<bool> moveDesktopMethod(DesktopDirection direction) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'hWnd': 0,
    'direction': direction.index,
  };
  final bool result = await audioMethodChannel.invokeMethod<bool>('moveWindowToDesktop', arguments) ?? false;
  return result;
}

Future<bool> setSkipTaskbar({required int hWnd, required bool skip}) async {
  final Map<String, dynamic> arguments = <String, dynamic>{
    'hWnd': hWnd,
    'skip': skip,
  };
  final bool result = await audioMethodChannel.invokeMethod<bool>('setSkipTaskbar', arguments) ?? false;
  return result;
}

enum DesktopDirection {
  left,
  right,
}
