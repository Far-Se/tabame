import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_catalog_service.dart';
import 'macos/macos_platform_channel.dart';

/// Discovers direct `.app` bundles from the standard macOS application roots.
///
/// The Phase 5 adapter delegates launch and icon rasterization to LaunchServices
/// in the native runner, while retaining the filesystem path for testable
/// discovery and reduced-mode fallback.
class MacOSAppCatalogProvider implements AppCatalogProvider {
  MacOSAppCatalogProvider({
    List<String>? applicationRoots,
    bool? available,
    MacOSPlatformChannel? platform,
  })  : applicationRoots = applicationRoots ?? _defaultApplicationRoots(),
        _availableOverride = available,
        platform = platform ?? MacOSPlatformChannel.instance,
        _useNativeApis = applicationRoots == null;

  final List<String> applicationRoots;
  final bool? _availableOverride;
  final MacOSPlatformChannel platform;
  final bool _useNativeApis;

  @override
  bool get isAvailable => _availableOverride ?? Platform.isMacOS;

  @override
  String get unavailableReason => isAvailable ? '' : 'The macOS application catalog is unavailable on this platform.';

  @override
  Future<AppCatalogSnapshot> discover() async {
    if (!isAvailable) {
      return AppCatalogSnapshot(records: const <AppCatalogRecord>[], complete: false, error: unavailableReason);
    }

    final Map<String, AppCatalogRecord> records = <String, AppCatalogRecord>{};
    bool complete = true;
    String? error;
    for (final String rootPath in applicationRoots) {
      final Directory root = Directory(rootPath);
      if (!root.existsSync()) continue;
      try {
        await for (final FileSystemEntity entity in root.list(followLinks: false)) {
          if (entity is! Directory || !entity.path.toLowerCase().endsWith('.app')) continue;
          final AppCatalogRecord? record = _recordFor(entity.path);
          if (record != null) records.putIfAbsent(record.stableId, () => record);
        }
      } catch (caught) {
        complete = false;
        error = '$caught';
      }
    }

    final List<AppCatalogRecord> sorted = records.values.toList(growable: false)
      ..sort((AppCatalogRecord a, AppCatalogRecord b) {
        final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        return byName == 0 ? a.stableId.compareTo(b.stableId) : byName;
      });
    return AppCatalogSnapshot(records: sorted, complete: complete, error: error);
  }

  @override
  Future<bool> launch(AppCatalogRecord record) async {
    if (!isAvailable) return false;
    if (_useNativeApis && platform.isAvailable) {
      final bool launched = await platform.launchApplication(
        bundleIdentifier: record.appUserModelId,
        path: record.launchTarget,
      );
      if (launched) return true;
    }
    try {
      await Process.start('/usr/bin/open', <String>[record.launchTarget], mode: ProcessStartMode.detached);
      return true;
    } on ProcessException {
      return false;
    }
  }

  @override
  Future<bool> cacheIcon(AppCatalogRecord record, String destinationPath) async {
    if (!_useNativeApis || !platform.isAvailable || record.sourcePath.trim().isEmpty) return false;
    return platform.writeApplicationIcon(
      path: record.sourcePath,
      destinationPath: destinationPath,
    );
  }

  AppCatalogRecord? _recordFor(String bundlePath) {
    final String normalizedPath = p.normalize(bundlePath);
    final Directory contents = Directory(p.join(normalizedPath, 'Contents'));
    final File infoPlist = File(p.join(contents.path, 'Info.plist'));
    String bundleId = '';
    String displayName = p.basenameWithoutExtension(normalizedPath);
    if (infoPlist.existsSync()) {
      try {
        final String xml = infoPlist.readAsStringSync();
        bundleId = _plistString(xml, 'CFBundleIdentifier') ?? '';
        displayName = _plistString(xml, 'CFBundleDisplayName') ?? _plistString(xml, 'CFBundleName') ?? displayName;
      } catch (_) {
        // Binary or malformed plists are valid reasons to use the bundle name.
      }
    }

    final String identityPart = bundleId.trim().isNotEmpty ? bundleId.trim() : normalizedPath;
    return AppCatalogRecord(
      stableId: 'macos:$identityPart',
      name: displayName.trim().isEmpty ? p.basenameWithoutExtension(normalizedPath) : displayName.trim(),
      launchTarget: normalizedPath,
      sourcePath: normalizedPath,
      subtitle: normalizedPath,
      appUserModelId: bundleId,
      executable: normalizedPath,
      stableIdentity: 'macos:$identityPart',
      iconPath: _findIcon(contents),
    );
  }

  String? _findIcon(Directory contents) {
    final Directory resources = Directory(p.join(contents.path, 'Resources'));
    if (!resources.existsSync()) return null;
    try {
      for (final File file in resources.listSync(followLinks: false).whereType<File>()) {
        if (p.extension(file.path).toLowerCase() == '.icns') return file.path;
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  String? _plistString(String xml, String key) {
    final RegExp expression = RegExp('<key>${RegExp.escape(key)}</key>\\s*<string>([^<]*)</string>');
    final Match? match = expression.firstMatch(xml);
    if (match == null) return null;
    return match.group(1)?.replaceAll('&amp;', '&').replaceAll('&lt;', '<').replaceAll('&gt;', '>');
  }

  static List<String> _defaultApplicationRoots() {
    final String home = Platform.environment['HOME'] ?? Directory.current.path;
    return <String>[
      '/Applications',
      p.join(home, 'Applications'),
      '/System/Applications',
    ];
  }
}
