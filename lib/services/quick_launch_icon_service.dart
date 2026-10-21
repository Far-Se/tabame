import 'dart:io';

import 'package:path/path.dart' as p;

import '../models/quick_launch.dart';
import '../platform/app_catalog_service.dart';
import '../platform/app_paths.dart';

/// Resolves protocol launch targets back to shortcuts so the existing icon
/// extractor can read their IconFile and IconIndex fields.
class QuickLaunchIconService {
  static Future<Map<String, String>>? _shortcuts;
  static Future<AppCatalogSnapshot>? _catalog;

  static String appIconSource(AppCatalogRecord app) {
    for (final String path in <String>[app.sourcePath, app.parsingName]) {
      if (path.toLowerCase().endsWith('.url') || path.toLowerCase().endsWith('.lnk')) return path;
    }
    return app.executable.isNotEmpty ? app.executable : app.sourcePath;
  }

  static String _protocolTarget(String target) {
    const String prefix = 'shell:AppsFolder\\';
    return target.toLowerCase().startsWith(prefix.toLowerCase()) ? target.substring(prefix.length) : target;
  }

  static Future<String> resolve(QuickLaunchEntry entry) async {
    if (!Platform.isWindows) {
      //TODO: Implement multiplatform
      return entry.iconPath;
    }
    final String target = _protocolTarget(entry.target);
    if (entry.kind != QuickLaunchKind.app && target == entry.target) return entry.iconPath;

    // AppResultIcon in the launcher renders this PNG directly. In particular,
    // Epic app IDs can have a shell-provided icon without a discoverable .url.
    final String cacheName = p.join('icon_cache', 'app_${target.hashCode}.png');
    final File cachedIcon = File(AppPaths.cachePath(cacheName));
    if (await cachedIcon.exists() && await cachedIcon.length() > 0) return cachedIcon.path;

    try {
      final AppCatalogSnapshot catalog = await (_catalog ??= AppCatalogService.instance.discover());
      if (!catalog.complete) _catalog = null;
      for (final AppCatalogRecord app in catalog.records) {
        if (_protocolTarget(app.launchTarget) != target) continue;
        // Use the same native shell icon provider as LauncherAppCatalogService
        // when the launcher has not populated its cache yet.
        final File iconFile = File(AppPaths.cachePath(cacheName, forWrite: true));
        await iconFile.parent.create(recursive: true);
        if (await AppCatalogService.instance.cacheIcon(app, iconFile.path)) return iconFile.path;
        final String source = appIconSource(app);
        if (source.toLowerCase().endsWith('.url') && await File(source).exists()) return source;
      }
    } catch (_) {
      _catalog = null;
    }

    if (entry.iconPath.toLowerCase().endsWith('.url') && await File(entry.iconPath).exists()) return entry.iconPath;
    if (!target.contains('://')) return entry.iconPath;

    // Some AppsFolder records retain only the URI, not the .url parsing path.
    // Share one asynchronous scan between all visible QuickLaunch icons.
    final Map<String, String> shortcuts = await (_shortcuts ??= _readShortcuts());
    final String? path = shortcuts[target];
    if (path != null && await File(path).exists()) return path;
    _shortcuts = null; // Allow a later opening to discover newly installed games.
    return entry.iconPath;
  }

  static Future<Map<String, String>> _readShortcuts() async {
    final Map<String, String> paths = <String, String>{};
    final Map<String, String> env = Platform.environment;
    final Set<String> roots = <String>{
      if (env['APPDATA'] != null) '${env['APPDATA']}\\Microsoft\\Windows\\Start Menu\\Programs',
      if (env['PROGRAMDATA'] != null) '${env['PROGRAMDATA']}\\Microsoft\\Windows\\Start Menu\\Programs',
      if (env['USERPROFILE'] != null) '${env['USERPROFILE']}\\Desktop',
      if (env['PUBLIC'] != null) '${env['PUBLIC']}\\Desktop',
      if (env['OneDrive'] != null) '${env['OneDrive']}\\Desktop',
    };
    for (final String root in roots) {
      try {
        await for (final FileSystemEntity file
            in Directory(root).list(recursive: true, followLinks: false).handleError((Object error) {})) {
          if (file is! File || !file.path.toLowerCase().endsWith('.url')) continue;
          try {
            for (final String line in await file.readAsLines()) {
              final String value = line.trim();
              if (value.toLowerCase().startsWith('url=')) {
                paths.putIfAbsent(value.substring(4).trim(), () => file.path);
                break;
              }
            }
          } catch (_) {
            // Ignore unreadable shortcuts; other entries can still resolve.
          }
        }
      } catch (_) {
        // A standard shortcut directory may not exist on this installation.
      }
    }
    return paths;
  }
}
