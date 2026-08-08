import 'macos_platform_channel.dart';

class MacOSPermissionService {
  MacOSPermissionService({MacOSPlatformChannel? channel}) : channel = channel ?? MacOSPlatformChannel.instance;

  static final MacOSPermissionService instance = MacOSPermissionService();

  final MacOSPlatformChannel channel;

  Future<MacOSPermissionSnapshot> refresh() => channel.permissionStates();

  Future<MacOSPermissionState> request(MacOSPermission permission) {
    return channel.requestPermission(permission);
  }

  Future<bool> openSettings(MacOSPermission permission) {
    return channel.openPermissionSettings(permission);
  }
}
