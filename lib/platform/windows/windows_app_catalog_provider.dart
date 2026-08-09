import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:path/path.dart' as p;

import '../app_catalog_service.dart';
import '../../services/native_integration_coordinator.dart';
import 'tabamewin32_api.dart' as native;

/// Windows adapter for the neutral application catalog.
///
/// AUMIDs, `shell:AppsFolder` targets, and parsing names stay in this adapter
/// as opaque Windows metadata. Shared catalog consumers only see the neutral
/// [AppCatalogRecord] shape.
class WindowsAppCatalogProvider implements AppCatalogProvider {
  static const String _appsFolderPrefix = r'shell:AppsFolder\';

  @override
  bool get isAvailable => Platform.isWindows;

  @override
  String get unavailableReason => isAvailable ? '' : 'The Windows application catalog is unavailable on this platform.';

  @override
  Future<AppCatalogSnapshot> discover() async {
    if (!isAvailable) {
      return AppCatalogSnapshot(records: const <AppCatalogRecord>[], complete: false, error: unavailableReason);
    }

    if (!NativeIntegrationCoordinator.instance.canStart(NativeIntegrationId.processActions)) {
      return AppCatalogSnapshot(
        records: const <AppCatalogRecord>[],
        complete: false,
        error: NativeIntegrationCoordinator.instance.denialReason(NativeIntegrationId.processActions) ??
            'Installed-app discovery is disabled until the process capability is enabled.',
      );
    }

    try {
      final List<native.AppInfo> apps = _dedupe(await native.AppEnumeration.getAllApps());
      final List<AppCatalogRecord> records = apps.map(_recordFor).toList(growable: false)
        ..sort((AppCatalogRecord a, AppCatalogRecord b) {
          final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
          return byName == 0 ? a.appUserModelId.toLowerCase().compareTo(b.appUserModelId.toLowerCase()) : byName;
        });
      return AppCatalogSnapshot(records: records, complete: true);
    } catch (error) {
      return AppCatalogSnapshot(
        records: const <AppCatalogRecord>[],
        complete: false,
        error: '$error',
      );
    }
  }

  @override
  Future<bool> launch(AppCatalogRecord record) async {
    if (!isAvailable || record.launchTarget.trim().isEmpty) return false;
    if (!await NativeIntegrationCoordinator.instance.authorizeInvocation(NativeIntegrationId.processActions))
      return false;
    try {
      await Process.start('explorer.exe', <String>[record.launchTarget], mode: ProcessStartMode.detached);
      return true;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<bool> cacheIcon(AppCatalogRecord record, String destinationPath) async {
    final String parsingName = record.parsingName.trim();
    if (!isAvailable || parsingName.isEmpty || destinationPath.trim().isEmpty) return false;

    try {
      final native.AppIconData? icon = await native.AppEnumeration.getAppIcon(parsingName, size: 128);
      if (icon == null || icon.width <= 0 || icon.height <= 0 || icon.pixels.isEmpty) return false;

      final ByteData? pngBytes = await _convertIconToPng(icon);
      if (pngBytes == null) return false;
      await File(destinationPath).writeAsBytes(pngBytes.buffer.asUint8List(), flush: true);
      return true;
    } catch (_) {
      return false;
    }
  }

  List<native.AppInfo> _dedupe(List<native.AppInfo> apps) {
    final Map<String, native.AppInfo> byAumid = <String, native.AppInfo>{};
    for (final native.AppInfo app in apps) {
      final String aumid = app.appUserModelId.trim();
      if (aumid.isEmpty) continue;

      final native.AppInfo? existing = byAumid[aumid];
      if (existing == null || _isRicher(existing, app)) byAumid[aumid] = app;
    }
    return byAumid.values.toList(growable: false);
  }

  bool _isRicher(native.AppInfo existing, native.AppInfo candidate) {
    return (existing.parsingName.trim().isEmpty && candidate.parsingName.trim().isNotEmpty) ||
        (existing.executable.trim().isEmpty && candidate.executable.trim().isNotEmpty);
  }

  AppCatalogRecord _recordFor(native.AppInfo app) {
    final String appUserModelId = app.appUserModelId.trim();
    final String name = app.name.trim().isEmpty ? appUserModelId : app.name.trim();
    final String executable = app.executable.trim();
    final String subtitle = executable.isNotEmpty ? executable : appUserModelId;
    final String stableIdentity = _stableIdentity(app);
    return AppCatalogRecord(
      stableId: 'windows:aumid:$appUserModelId',
      name: name,
      launchTarget: buildLaunchTarget(appUserModelId),
      sourcePath: app.parsingName.trim().isNotEmpty ? app.parsingName.trim() : executable,
      subtitle: subtitle,
      appUserModelId: appUserModelId,
      parsingName: app.parsingName,
      executable: app.executable,
      arguments: app.arguments,
      stableIdentity: stableIdentity,
    );
  }

  static String buildLaunchTarget(String appUserModelId) => '$_appsFolderPrefix$appUserModelId';

  String _stableIdentity(native.AppInfo app) {
    final String executableName = app.executable.trim().isNotEmpty
        ? p.basenameWithoutExtension(app.executable.trim())
        : p.basenameWithoutExtension(app.parsingName.trim());
    return <String>[
      _normalizeIdentityPart(app.name),
      _normalizeIdentityPart(executableName),
      _normalizeIdentityPart(app.arguments),
    ].join('|');
  }

  String _normalizeIdentityPart(String value) => value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

  Future<ByteData?> _convertIconToPng(native.AppIconData icon) {
    final Completer<ByteData?> completer = Completer<ByteData?>();
    ui.decodeImageFromPixels(
      icon.pixels,
      icon.width,
      icon.height,
      ui.PixelFormat.bgra8888,
      (ui.Image image) async {
        try {
          completer.complete(await image.toByteData(format: ui.ImageByteFormat.png));
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        } finally {
          image.dispose();
        }
      },
    );
    return completer.future;
  }
}
