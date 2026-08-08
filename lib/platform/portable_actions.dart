import 'dart:io';

/// Small cross-platform process actions used by the portable shell and plugins.
class PortableActions {
  PortableActions._();

  static Future<bool> openExternal(String target, {List<String> arguments = const <String>[]}) async {
    if (target.trim().isEmpty) return false;
    try {
      if (Platform.isMacOS) {
        await Process.start('/usr/bin/open', <String>[target, ...arguments], mode: ProcessStartMode.detached);
        return true;
      }
      if (Platform.isLinux) {
        await Process.start('xdg-open', <String>[target, ...arguments], mode: ProcessStartMode.detached);
        return true;
      }
    } on ProcessException {
      return false;
    }
    return false;
  }
}
