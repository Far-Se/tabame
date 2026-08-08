import 'platform_models.dart';

/// Platform-neutral lifecycle for other application windows.
abstract class WindowService {
  static WindowService _instance = const UnavailableWindowService();

  static WindowService get instance => _instance;

  static void register(WindowService service) {
    _instance = service;
  }

  const WindowService();

  bool get isAvailable;
  String get unavailableReason;

  /// Window enumeration and activation have separate permission surfaces on
  /// platforms such as macOS. The default keeps existing adapters compatible.
  bool get isActivationAvailable => isAvailable;
  String get activationUnavailableReason => unavailableReason;

  Future<List<PlatformWindow>> enumerate();
  Future<bool> activate(PlatformWindow window);

  /// Captures the currently frontmost non-Tabame application before showing the
  /// quick menu. The returned value is opaque to shared code.
  Future<String?> captureFocus();

  Future<bool> restoreFocus(String? token);
}

class UnavailableWindowService extends WindowService {
  const UnavailableWindowService();

  @override
  bool get isAvailable => false;

  @override
  String get unavailableReason => 'Window enumeration and activation are unavailable on this platform.';

  @override
  Future<List<PlatformWindow>> enumerate() async => const <PlatformWindow>[];

  @override
  Future<bool> activate(PlatformWindow window) async => false;

  @override
  Future<String?> captureFocus() async => null;

  @override
  Future<bool> restoreFocus(String? token) async => false;
}
