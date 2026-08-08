/// Capability snapshot consumed by feature gates and diagnostics.
class PlatformCapabilities {
  const PlatformCapabilities({
    this.globalHotkeys = false,
    this.windowEnumeration = false,
    this.windowActivation = false,
    this.inputInjection = false,
    this.clipboardMonitoring = false,
    this.richClipboard = false,
    this.screenCapture = false,
    this.ocr = false,
    this.screenRecording = false,
    this.systemNotifications = false,
    this.audioDeviceControl = false,
    this.perProcessAudio = false,
    this.mediaSessions = false,
    this.secureMachineStorage = false,
    this.monitorGeometry = false,
    this.quickSnap = false,
    this.quickSnapDrag = false,
    this.filesystemWatching = false,
    this.desktopFileDiscovery = false,
    this.x11 = false,
    this.wayland = false,
  });

  static PlatformCapabilities _current = const PlatformCapabilities();

  static PlatformCapabilities get current => _current;

  static void register(PlatformCapabilities capabilities) {
    _current = capabilities;
  }

  final bool globalHotkeys;
  final bool windowEnumeration;
  final bool windowActivation;
  final bool inputInjection;
  final bool clipboardMonitoring;
  final bool richClipboard;
  final bool screenCapture;
  final bool ocr;
  final bool screenRecording;
  final bool systemNotifications;
  final bool audioDeviceControl;
  final bool perProcessAudio;
  final bool mediaSessions;
  final bool secureMachineStorage;
  final bool monitorGeometry;
  final bool quickSnap;
  final bool quickSnapDrag;
  final bool filesystemWatching;
  final bool desktopFileDiscovery;
  final bool x11;
  final bool wayland;

  PlatformCapabilities copyWith({
    bool? globalHotkeys,
    bool? windowEnumeration,
    bool? windowActivation,
    bool? inputInjection,
    bool? clipboardMonitoring,
    bool? richClipboard,
    bool? screenCapture,
    bool? ocr,
    bool? screenRecording,
    bool? systemNotifications,
    bool? audioDeviceControl,
    bool? perProcessAudio,
    bool? mediaSessions,
    bool? secureMachineStorage,
    bool? monitorGeometry,
    bool? quickSnap,
    bool? quickSnapDrag,
    bool? filesystemWatching,
    bool? desktopFileDiscovery,
    bool? x11,
    bool? wayland,
  }) {
    return PlatformCapabilities(
      globalHotkeys: globalHotkeys ?? this.globalHotkeys,
      windowEnumeration: windowEnumeration ?? this.windowEnumeration,
      windowActivation: windowActivation ?? this.windowActivation,
      inputInjection: inputInjection ?? this.inputInjection,
      clipboardMonitoring: clipboardMonitoring ?? this.clipboardMonitoring,
      richClipboard: richClipboard ?? this.richClipboard,
      screenCapture: screenCapture ?? this.screenCapture,
      ocr: ocr ?? this.ocr,
      screenRecording: screenRecording ?? this.screenRecording,
      systemNotifications: systemNotifications ?? this.systemNotifications,
      audioDeviceControl: audioDeviceControl ?? this.audioDeviceControl,
      perProcessAudio: perProcessAudio ?? this.perProcessAudio,
      mediaSessions: mediaSessions ?? this.mediaSessions,
      secureMachineStorage: secureMachineStorage ?? this.secureMachineStorage,
      monitorGeometry: monitorGeometry ?? this.monitorGeometry,
      quickSnap: quickSnap ?? this.quickSnap,
      quickSnapDrag: quickSnapDrag ?? this.quickSnapDrag,
      filesystemWatching: filesystemWatching ?? this.filesystemWatching,
      desktopFileDiscovery: desktopFileDiscovery ?? this.desktopFileDiscovery,
      x11: x11 ?? this.x11,
      wayland: wayland ?? this.wayland,
    );
  }
}
