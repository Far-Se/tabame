import 'dart:async';

import '../logic/error_handler.dart';
import '../models/settings.dart';
import '../pages/launcher/plugins/plugin_gallery.dart';
import '../pages/launcher/plugins/plugin_manifest.dart';
import '../pages/launcher/plugins/plugin_registry.dart';
import 'extension_policy.dart';

class PluginUpdateResult {
  const PluginUpdateResult({required this.name, required this.version});

  final String name;
  final String version;

  String get versionLabel {
    final String trimmed = version.trim();
    return trimmed.toLowerCase().startsWith('v') ? 'v${trimmed.substring(1)}' : 'v$trimmed';
  }

  String get reminder => 'Plugin $name has been updated to version $versionLabel';
}

/// Checks gallery-installed plugins once after the launcher is first opened.
abstract final class PluginAutoUpdateService {
  static Future<List<PluginUpdateResult>>? _firstLauncherCheck;

  static Future<List<PluginUpdateResult>> checkOnFirstLauncher() {
    return _firstLauncherCheck ??= _checkForUpdates();
  }

  static Future<List<PluginUpdateResult>> _checkForUpdates() async {
    if (!user.autoUpdatePlugins) return const <PluginUpdateResult>[];

    final ExtensionPolicy policy = ExtensionPolicy.current;
    if (!policy.canFetchPluginGallery || !policy.canInstallRemotePlugins) {
      return const <PluginUpdateResult>[];
    }

    try {
      final List<PluginGalleryEntry> entries = await PluginGallery.fetchIndex(
        force: true,
        extensionPolicy: policy,
      );
      final Map<String, PluginManifest> installedById = <String, PluginManifest>{
        for (final PluginManifest manifest in PluginRegistry.manifests) manifest.id.toLowerCase(): manifest,
      };
      final Set<String> processedIds = <String>{};
      final List<PluginUpdateResult> updates = <PluginUpdateResult>[];

      for (final PluginGalleryEntry entry in entries) {
        final String normalizedId = entry.id.toLowerCase();
        if (!processedIds.add(normalizedId)) continue;

        final PluginManifest? installed = installedById[normalizedId];
        if (installed == null || !entry.installable) continue;
        if (!_isRemoteVersionGreater(entry.version, installed.version)) continue;

        final String? error = await PluginGallery.install(entry, extensionPolicy: policy);
        if (error == null) {
          updates.add(PluginUpdateResult(name: entry.name, version: entry.version));
        } else {
          unawaited(ErrorLogger.log('PluginAutoUpdate', 'Update ${entry.id} failed: $error', StackTrace.current));
        }
      }
      return updates;
    } catch (error, stack) {
      unawaited(ErrorLogger.log('PluginAutoUpdate', 'Could not check the plugin gallery: $error', stack));
      return const <PluginUpdateResult>[];
    }
  }

  static bool _isRemoteVersionGreater(String remoteVersion, String installedVersion) {
    final List<int>? remoteParts = _parsePluginVersion(remoteVersion);
    final List<int>? installedParts = _parsePluginVersion(installedVersion);
    if (remoteParts == null || installedParts == null) return false;

    final int length = remoteParts.length > installedParts.length ? remoteParts.length : installedParts.length;
    for (int index = 0; index < length; index++) {
      final int remotePart = index < remoteParts.length ? remoteParts[index] : 0;
      final int installedPart = index < installedParts.length ? installedParts[index] : 0;
      if (remotePart != installedPart) return remotePart > installedPart;
    }
    return false;
  }

  static List<int>? _parsePluginVersion(String version) {
    final String normalized = version.trim().replaceFirst(RegExp(r'^[vV]'), '');
    if (normalized.isEmpty) return null;

    final List<int> parts = <int>[];
    for (final String part in normalized.split('.')) {
      final int? number = int.tryParse(part);
      if (number == null || number < 0) return null;
      parts.add(number);
    }
    return parts;
  }
}
