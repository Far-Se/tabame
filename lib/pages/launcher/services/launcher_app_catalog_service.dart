import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:pool/pool.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:tabamewin32/tabamewin32.dart' as native;

import '../../../models/db/file_index_db.dart';
import '../../../models/win32/win_utils.dart';

class LauncherAppCatalogService {
  LauncherAppCatalogService._();

  static final LauncherAppCatalogService instance = LauncherAppCatalogService._();

  static const String _iconPrefix = 'app_';
  static const String _appsFolderPrefix = r'shell:AppsFolder\';

  bool _isSyncing = false;

  static String buildLaunchTarget(String appUserModelId) => '$_appsFolderPrefix$appUserModelId';

  Future<void> sync() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final Database db = await FileIndexDb.instance.database;
      final Directory iconCacheDirectory = await _ensureIconCacheDirectory();
      final List<native.AppInfo> apps = _dedupe(await native.AppEnumeration.getAllApps());

      final int rootId = FileIndexDb.instance.findNode(null, FileIndexDb.launcherAppsRootName) ??
          FileIndexDb.instance.insertNode(
            null,
            FileIndexDb.launcherAppsRootName,
            true,
            isSearchable: false,
            entryType: SearchResultEntryType.app,
          );

      final List<SearchResultNode> existingNodes =
          FileIndexDb.instance.getChildNodes(rootId).where((SearchResultNode node) => node.isApp).toList();
      final Map<String, SearchResultNode> existingByAumid = <String, SearchResultNode>{
        for (final SearchResultNode node in existingNodes)
          if ((node.appUserModelId ?? '').isNotEmpty) node.appUserModelId!: node,
      };
      final Map<String, List<SearchResultNode>> existingByStableIdentity = <String, List<SearchResultNode>>{};
      for (final SearchResultNode node in existingNodes) {
        final String stableIdentity = node.stableIdentity ?? '';
        if (stableIdentity.isEmpty) continue;
        existingByStableIdentity.putIfAbsent(stableIdentity, () => <SearchResultNode>[]).add(node);
      }

      final Set<int> matchedNodeIds = <int>{};
      final Set<String> expectedIconFiles = <String>{
        for (final native.AppInfo app in apps) _iconFileName(app.appUserModelId),
      };

      db.execute('BEGIN IMMEDIATE TRANSACTION');
      try {
        for (final native.AppInfo app in apps) {
          final String name = app.name.trim().isEmpty ? app.appUserModelId : app.name.trim();
          final String subtitle = app.executable.trim().isNotEmpty ? app.executable.trim() : app.appUserModelId;
          final String stableIdentity = _stableIdentity(app);
          final String launchTarget = buildLaunchTarget(app.appUserModelId);

          SearchResultNode? existingNode = existingByAumid[app.appUserModelId];
          if (existingNode == null && stableIdentity.isNotEmpty) {
            final List<SearchResultNode>? candidates = existingByStableIdentity[stableIdentity];
            while (candidates != null && candidates.isNotEmpty) {
              final SearchResultNode candidate = candidates.removeAt(0);
              if (matchedNodeIds.contains(candidate.id)) continue;
              existingNode = candidate;
              break;
            }
          }

          if (existingNode == null) {
            final int nodeId = FileIndexDb.instance.insertAppNode(
              rootId,
              name: name,
              launchTarget: launchTarget,
              parsingName: app.parsingName,
              appUserModelId: app.appUserModelId,
              subtitle: subtitle,
              stableIdentity: stableIdentity,
            );
            matchedNodeIds.add(nodeId);
            continue;
          }

          matchedNodeIds.add(existingNode.id);
          FileIndexDb.instance.updateAppNode(
            id: existingNode.id,
            parentId: rootId,
            name: name,
            launchTarget: launchTarget,
            parsingName: app.parsingName,
            appUserModelId: app.appUserModelId,
            subtitle: subtitle,
            stableIdentity: stableIdentity,
          );
        }

        for (final SearchResultNode node in existingNodes) {
          if (matchedNodeIds.contains(node.id)) continue;
          FileIndexDb.instance.deleteNode(node.id);
        }

        db.execute('COMMIT');
      } catch (_) {
        db.execute('ROLLBACK');
        rethrow;
      }

      await _cacheMissingIcons(apps, iconCacheDirectory);
      await _removeStaleIcons(iconCacheDirectory, expectedIconFiles);
    } catch (error, stackTrace) {
      debugPrint('Launcher: Failed to sync AppEnumeration catalog: $error');
      debugPrintStack(stackTrace: stackTrace);
    } finally {
      _isSyncing = false;
    }
  }

  List<native.AppInfo> _dedupe(List<native.AppInfo> apps) {
    final Map<String, native.AppInfo> byAumid = <String, native.AppInfo>{};

    for (final native.AppInfo app in apps) {
      final String aumid = app.appUserModelId.trim();
      if (aumid.isEmpty) continue;

      final native.AppInfo? existing = byAumid[aumid];
      if (existing == null ||
          (existing.parsingName.trim().isEmpty && app.parsingName.trim().isNotEmpty) ||
          (existing.executable.trim().isEmpty && app.executable.trim().isNotEmpty)) {
        byAumid[aumid] = app;
      }
    }

    final List<native.AppInfo> deduped = byAumid.values.toList(growable: false);
    deduped.sort((native.AppInfo a, native.AppInfo b) {
      final int byName = a.name.toLowerCase().compareTo(b.name.toLowerCase());
      if (byName != 0) return byName;
      return a.appUserModelId.toLowerCase().compareTo(b.appUserModelId.toLowerCase());
    });
    return deduped;
  }

  Future<Directory> _ensureIconCacheDirectory() async {
    final Directory directory = Directory(p.join(WinUtils.getTabameAppDataFolder(), 'cache', 'icon_cache'));
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }
    return directory;
  }

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

  String _normalizeIdentityPart(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  String _iconFileName(String appUserModelId) => '$_iconPrefix${appUserModelId.hashCode}.png';

  Future<void> _cacheMissingIcons(List<native.AppInfo> apps, Directory iconCacheDirectory) async {
    final Pool pool = Pool(3);

    await Future.wait(apps.map((native.AppInfo app) async {
      final File iconFile = File(p.join(iconCacheDirectory.path, _iconFileName(app.appUserModelId)));
      if (await iconFile.exists()) return;

      await pool.withResource(() => _cacheIcon(app, iconFile));
    }));

    await pool.close();
  }

  Future<void> _cacheIcon(native.AppInfo app, File iconFile) async {
    if (app.parsingName.trim().isEmpty) return;

    try {
      final native.AppIconData? icon = await native.AppEnumeration.getAppIcon(app.parsingName, size: 128);
      if (icon == null || icon.width <= 0 || icon.height <= 0 || icon.pixels.isEmpty) return;

      final ByteData? pngBytes = await _convertIconToPng(icon);
      if (pngBytes == null) return;

      await iconFile.writeAsBytes(pngBytes.buffer.asUint8List(), flush: true);
    } catch (error, stackTrace) {
      debugPrint('Launcher: Failed to cache icon for ${app.appUserModelId}: $error');
      debugPrintStack(stackTrace: stackTrace);
    }
  }

  Future<ByteData?> _convertIconToPng(native.AppIconData icon) {
    final Completer<ByteData?> completer = Completer<ByteData?>();

    ui.decodeImageFromPixels(
      icon.pixels,
      icon.width,
      icon.height,
      ui.PixelFormat.bgra8888,
      (ui.Image image) async {
        try {
          final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
          completer.complete(data);
        } catch (error, stackTrace) {
          completer.completeError(error, stackTrace);
        } finally {
          image.dispose();
        }
      },
    );

    return completer.future;
  }

  Future<void> _removeStaleIcons(Directory iconCacheDirectory, Set<String> expectedIconFiles) async {
    if (!await iconCacheDirectory.exists()) return;

    await for (final FileSystemEntity entity in iconCacheDirectory.list()) {
      if (entity is! File) continue;
      final String fileName = p.basename(entity.path);
      if (!fileName.startsWith(_iconPrefix) || !fileName.endsWith('.png')) continue;
      if (expectedIconFiles.contains(fileName)) continue;

      try {
        await entity.delete();
      } catch (_) {}
    }
  }
}
