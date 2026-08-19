import 'dart:async';

import '../../../logic/error_handler.dart';
import 'plugin_gallery.dart';
import 'plugin_manifest.dart';
import 'plugin_registry.dart';

class PluginAutoUpdateResult {
  const PluginAutoUpdateResult({
    required this.checked,
    required this.updated,
    required this.failures,
  });

  final int checked;
  final int updated;
  final List<String> failures;
}

/// Checks the curated gallery index and upgrades installed plugins whose
/// remote numeric version is newer. Local plugins that are not in the gallery
/// are intentionally ignored.
abstract final class PluginAutoUpdater {
  static const String settingKey = 'pluginAutoUpdate';

  static Future<PluginAutoUpdateResult>? _inFlight;

  static Future<PluginAutoUpdateResult> checkAndUpdate() {
    final Future<PluginAutoUpdateResult>? running = _inFlight;
    if (running != null) return running;

    final Future<PluginAutoUpdateResult> future = _checkAndUpdate();
    _inFlight = future;
    future.whenComplete(() {
      if (identical(_inFlight, future)) _inFlight = null;
    });
    return future;
  }

  static Future<PluginAutoUpdateResult> _checkAndUpdate() async {
    try {
      await PluginRegistry.load();
      final List<PluginManifest> installed = List<PluginManifest>.of(PluginRegistry.manifests);
      if (installed.isEmpty) {
        return const PluginAutoUpdateResult(checked: 0, updated: 0, failures: <String>[]);
      }

      final Map<String, PluginManifest> installedById = <String, PluginManifest>{
        for (final PluginManifest manifest in installed) manifest.id.toLowerCase(): manifest,
      };
      final List<PluginGalleryEntry> entries = await PluginGallery.fetchIndex();
      int updated = 0;
      final List<String> failures = <String>[];

      for (final PluginGalleryEntry entry in entries) {
        final PluginManifest? manifest = installedById[entry.id.toLowerCase()];
        if (manifest == null ||
            !entry.installable ||
            !PluginGallery.isRemoteVersionGreater(entry.version, manifest.version)) {
          continue;
        }

        final String? error = await PluginGallery.install(entry);
        if (error == null) {
          updated++;
        } else {
          failures.add('${entry.name}: $error');
        }
      }

      if (failures.isNotEmpty) {
        unawaited(
          ErrorLogger.log(
            'PluginAutoUpdater',
            'Updated $updated plugin(s); ${failures.length} failed: ${failures.join('; ')}',
            null,
          ),
        );
      }
      return PluginAutoUpdateResult(checked: installed.length, updated: updated, failures: failures);
    } catch (error, stack) {
      unawaited(ErrorLogger.log('PluginAutoUpdater', 'Automatic update check failed: $error', stack));
      return PluginAutoUpdateResult(
        checked: PluginRegistry.manifests.length,
        updated: 0,
        failures: <String>[error.toString()],
      );
    }
  }
}
