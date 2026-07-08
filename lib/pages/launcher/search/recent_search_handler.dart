import 'dart:async';
import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:win32/win32.dart';

import 'launcher_search_context.dart';
import 'search_utils.dart';

/// Searches Windows' recently-used items (`%AppData%\Microsoft\Windows\Recent`)
/// — the same list Explorer's "Recent files" and app jump lists feed on. Each
/// entry is a .lnk shortcut named after its target; targets are resolved via
/// IShellLink and dead entries are skipped.
class RecentSearchHandler {
  static void handle(LauncherSearchContext context) {
    context.setSearching(true);
    Timer(const Duration(milliseconds: 100), () async {
      if (!context.isActiveSearch(context.requestId, context.query, trimLeft: true)) {
        context.setSearching(false);
        return;
      }

      List<Map<String, Object?>> serialized = <Map<String, Object?>>[];
      try {
        serialized = await compute(
          _listRecentFilesInBackground,
          <String, Object?>{
            'query': context.lowerQuery,
            'maxMatches': maxLauncherMatches,
            'recentDir': _recentFolderPath(),
          },
        );
      } catch (_) {}

      if (!context.isActiveSearch(context.requestId, context.query, trimLeft: true)) {
        context.setSearching(false);
        return;
      }

      context.setResults(
        deserializeFileMatches(serialized),
        isSearching: false,
        resetSelection: false,
      );
    });
  }

  static String _recentFolderPath() {
    final String appData = Platform.environment['APPDATA'] ?? '';
    return '$appData\\Microsoft\\Windows\\Recent';
  }
}

List<Map<String, Object?>> _listRecentFilesInBackground(Map<String, Object?> args) {
  final String query = (args['query'] ?? '') as String;
  final int maxMatches = (args['maxMatches'] ?? maxLauncherMatches) as int;
  final String recentDir = args['recentDir'] as String;

  final Directory dir = Directory(recentDir);
  if (!dir.existsSync()) return <Map<String, Object?>>[];

  // Collect shortcuts newest-first; the folder typically holds ~150 entries.
  final List<MapEntry<File, DateTime>> links = <MapEntry<File, DateTime>>[];
  try {
    for (final FileSystemEntity entity in dir.listSync(followLinks: false)) {
      if (entity is! File || !entity.path.toLowerCase().endsWith('.lnk')) continue;
      DateTime modified = DateTime.fromMillisecondsSinceEpoch(0);
      try {
        modified = entity.lastModifiedSync();
      } catch (_) {}
      links.add(MapEntry<File, DateTime>(entity, modified));
    }
  } catch (_) {
    return <Map<String, Object?>>[];
  }
  links.sort((MapEntry<File, DateTime> a, MapEntry<File, DateTime> b) => b.value.compareTo(a.value));

  final int hrInit = CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);
  final bool comInitialized = hrInit >= 0;

  final List<Map<String, Object?>> results = <Map<String, Object?>>[];
  final Set<String> seenTargets = <String>{};
  try {
    for (final MapEntry<File, DateTime> link in links) {
      if (results.length >= maxMatches) break;

      // The shortcut is named after its target ("report.docx.lnk"), so the
      // cheap stem filter avoids resolving shortcuts that can't match anyway.
      final String stem = link.key.uri.pathSegments.last.replaceFirst(RegExp(r'\.lnk$', caseSensitive: false), '');
      if (query.isNotEmpty && !stem.toLowerCase().contains(query)) continue;

      final String? target = _resolveLnkTarget(link.key.path);
      if (target == null) continue;

      final String lowerTarget = target.toLowerCase();
      if (!seenTargets.add(lowerTarget)) continue;

      final bool isDirectory = Directory(target).existsSync();
      if (!isDirectory && !File(target).existsSync()) continue;

      results.add(<String, Object?>{
        'path': target,
        'isDirectory': isDirectory,
      });
    }
  } finally {
    if (comInitialized) CoUninitialize();
  }
  return results;
}

/// Resolves a .lnk shortcut to its filesystem target, or null when the
/// shortcut has no path target (e.g. virtual shell items) or loading fails.
String? _resolveLnkTarget(String lnkPath) {
  final Pointer<Utf16> lnkPtr = lnkPath.toNativeUtf16();
  final Pointer<Utf16> buffer = wsalloc(MAX_PATH);
  String? target;
  try {
    final ShellLink shellLink = ShellLink.createInstance();
    try {
      final IPersistFile persistFile = IPersistFile(shellLink.toInterface(IID_IPersistFile));
      try {
        if (persistFile.load(lnkPtr, STGM_READ) == S_OK) {
          if (shellLink.getPath(buffer, MAX_PATH, nullptr, 0) == S_OK) {
            final String resolved = buffer.toDartString();
            if (resolved.isNotEmpty) target = resolved;
          }
        }
      } finally {
        persistFile.release();
      }
    } finally {
      shellLink.release();
    }
  } catch (_) {
    return null;
  } finally {
    free(buffer);
    free(lnkPtr);
  }
  return target;
}
