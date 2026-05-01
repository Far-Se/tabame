import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../../../models/win32/win_utils.dart';
import '../../launcher_search_models.dart';
import 'launcher_search_context.dart';
import 'search_utils.dart';

class DesktopSearchHandler {
  static void handle(LauncherSearchContext context) {
    context.setSearching(true);
    Timer(const Duration(milliseconds: 150), () async {
      if (!context.isActiveSearch(context.requestId, context.query, trimLeft: true)) return;

      final String desktopPath = WinUtils.getKnownFolderCLSID(0x0000);
      final List<Map<String, Object?>> desktopSearchFolders = <Map<String, Object?>>[
        <String, Object?>{
          'path': desktopPath,
          'includeFolders': true,
          'includeFiles': true,
          'allowedExtensions': const <String>[],
          'maxDepth': context.lowerQuery.isEmpty ? 0 : null,
        }
      ];

      List<Map<String, Object?>> serializedMatches = <Map<String, Object?>>[];
      try {
        serializedMatches = await compute(
          searchAndSyncFileMatchesInBackground,
          <String, Object?>{
            'query': context.lowerQuery,
            'maxMatches': maxLauncherMatches,
            'searchFolders': desktopSearchFolders,
          },
        );
      } catch (_) {}

      if (!context.isActiveSearch(context.requestId, context.query, trimLeft: true)) return;

      List<LauncherSearchResultItem> results = deserializeFileMatches(serializedMatches);
      results = results.where((LauncherSearchResultItem result) {
        final FileSystemEntity? entity = result.entity;
        if (entity == null) return true;
        return entity.uri.pathSegments.isEmpty || entity.uri.pathSegments.last.toLowerCase() != 'desktop.ini';
      }).toList(growable: false);

      context.setResults(results, isSearching: false, resetSelection: false);
    });
  }
}
