import 'dart:io';

import 'package:flutter/services.dart';

import '../app_data_locations.dart';

/// Reads package-scoped Windows.Storage.ApplicationData locations.
///
/// The method channel is registered by the Windows native plugin. Keeping this
/// adapter separate means the shared path service never hard-codes a package
/// family path and non-Windows builds retain the existing path_provider flow.
class WindowsApplicationData {
  WindowsApplicationData._();

  static const MethodChannel _channel = MethodChannel('tabamewin32');

  static Future<AppDataLocations?> resolve() async {
    if (!Platform.isWindows) return null;
    try {
      final Map<Object?, Object?>? result = await _channel.invokeMapMethod<Object?, Object?>('getApplicationDataPaths');
      if (result == null) return null;
      final String? localFolder = result['localFolder'] as String?;
      final String? localCacheFolder = result['localCacheFolder'] as String?;
      final String? temporaryFolder = result['temporaryFolder'] as String?;
      if (localFolder == null || localCacheFolder == null || temporaryFolder == null) return null;
      return AppDataLocations(
        localFolder: Directory(localFolder),
        localCacheFolder: Directory(localCacheFolder),
        temporaryFolder: Directory(temporaryFolder),
      );
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
