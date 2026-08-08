import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import 'app_paths.dart';
import 'portable_actions.dart';
import 'linux/linux_file_watcher.dart';

class PortableFileResult {
  const PortableFileResult({required this.path, required this.name, required this.isDirectory});

  final String path;
  final String name;
  final bool isDirectory;
}

/// Bounded filesystem search for the portable launcher.
///
/// It uses standard Dart directory APIs, skips hidden/build-heavy folders, and
/// exposes a directory watcher for future incremental index updates.
class PortableFileSearchService {
  const PortableFileSearchService();

  static List<String> defaultRoots({String? homeDirectory}) {
    final String home =
        homeDirectory ?? Platform.environment['HOME'] ?? Platform.environment['USERPROFILE'] ?? Directory.current.path;
    final List<String> candidates = <String>[
      p.join(home, 'Desktop'),
      p.join(home, 'Documents'),
      p.join(home, 'Downloads'),
      home,
    ];
    final Set<String> seen = <String>{};
    return <String>[
      for (final String path in candidates)
        if (seen.add(p.normalize(path)) && Directory(path).existsSync()) path
    ];
  }

  Future<List<PortableFileResult>> search(
    String query, {
    List<String>? roots,
    int maxResults = 40,
    int maxDepth = 4,
  }) async {
    final String normalizedQuery = query.trim().toLowerCase();
    if (normalizedQuery.isEmpty) return const <PortableFileResult>[];

    final List<PortableFileResult> found = <PortableFileResult>[];
    final List<_SearchDirectory> pending = <_SearchDirectory>[
      for (final String root in roots ?? defaultRoots()) _SearchDirectory(Directory(root), 0),
    ];
    final Set<String> visited = <String>{};
    final String? appDataRoot = AppPaths.isInitialized ? p.normalize(AppPaths.root) : null;

    while (pending.isNotEmpty && found.length < maxResults) {
      final _SearchDirectory current = pending.removeAt(0);
      final String normalizedPath = p.normalize(current.directory.path);
      if (!visited.add(normalizedPath)) continue;
      if (!current.directory.existsSync()) continue;

      try {
        await for (final FileSystemEntity entity in current.directory.list(followLinks: false)) {
          if (found.length >= maxResults) break;
          final String name = p.basename(entity.path);
          if (_skipName(name)) continue;
          final String lowerName = name.toLowerCase();
          if (lowerName.contains(normalizedQuery)) {
            found.add(PortableFileResult(path: entity.path, name: name, isDirectory: entity is Directory));
          }
          if (entity is Directory && current.depth < maxDepth && !_skipDirectory(entity.path, appDataRoot)) {
            pending.add(_SearchDirectory(entity, current.depth + 1));
          }
        }
      } on FileSystemException {
        // Permission-denied folders do not make the launcher unusable.
      }
    }

    found.sort((PortableFileResult a, PortableFileResult b) {
      final int aPrefix = a.name.toLowerCase().startsWith(normalizedQuery) ? 0 : 1;
      final int bPrefix = b.name.toLowerCase().startsWith(normalizedQuery) ? 0 : 1;
      final int byPrefix = aPrefix.compareTo(bPrefix);
      return byPrefix == 0 ? a.name.toLowerCase().compareTo(b.name.toLowerCase()) : byPrefix;
    });
    return found;
  }

  StreamSubscription<FileSystemEvent>? watch(String root, void Function(FileSystemEvent event) onEvent) {
    if (Platform.isLinux) return LinuxFileWatcher().watch(root, onEvent);
    try {
      final Directory directory = Directory(root);
      if (!directory.existsSync()) return null;
      return directory.watch(recursive: true).listen(onEvent);
    } on FileSystemException {
      return null;
    }
  }

  Future<bool> open(PortableFileResult result) => PortableActions.openExternal(result.path);

  bool _skipDirectory(String path, String? appDataRoot) {
    final String normalized = p.normalize(path);
    if (appDataRoot != null && normalized == appDataRoot) return true;
    final Set<String> segments = p.split(normalized).map((String segment) => segment.toLowerCase()).toSet();
    return segments.contains('.git') || segments.contains('node_modules');
  }

  bool _skipName(String name) => name.startsWith('.') || name == 'build' || name == 'target' || name == 'node_modules';
}

class _SearchDirectory {
  const _SearchDirectory(this.directory, this.depth);

  final Directory directory;
  final int depth;
}
