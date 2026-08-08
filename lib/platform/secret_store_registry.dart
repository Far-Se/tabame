import 'dart:io';

import 'macos/macos_secret_store.dart';
import 'linux/linux_secret_store.dart';
import 'secret_store.dart';
import 'windows_secret_store.dart';

/// Selects the platform-bound secret adapter while keeping unavailable targets
/// explicit and safe.
class SecretStores {
  SecretStores._();

  static SecretStore _instance = _selectDefault();

  static SecretStore get instance => _instance;

  static void register(SecretStore store) {
    _instance = store;
  }

  static SecretStore _selectDefault() {
    if (Platform.isWindows) return WindowsSecretStore.instance;
    if (Platform.isMacOS) return MacOSSecretStore.instance;
    if (Platform.isLinux) return LinuxSecretStore.instance;
    return const UnavailableSecretStore();
  }
}
