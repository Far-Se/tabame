import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../../../platform/app_paths.dart';
import '../core/launcher_query.dart';
import 'quicklink.dart';

/// Separate from settings.json so the settings window and launcher cannot
/// overwrite each other's preferences. Mutations reread under a process lock.
class QuicklinkStore {
  QuicklinkStore._();

  static final ValueNotifier<int> changes = ValueNotifier<int>(0);
  static String get path => AppPaths.settingsPath('quicklinks.json', forWrite: true);
  static List<Quicklink> _cache = <Quicklink>[];
  static String? _stamp;

  static List<Quicklink> load({bool force = false}) {
    final File file = File(path);
    final FileStat stat = file.statSync();
    final String stamp = '$path:${stat.modified.microsecondsSinceEpoch}:${stat.size}:${stat.type}';
    if (!force && stamp == _stamp) return _cache;
    final List<Quicklink> next =
        stat.type == FileSystemEntityType.notFound ? <Quicklink>[] : decode(file.readAsStringSync());
    final Set<String> ids = <String>{};
    if (next.any((Quicklink link) => !ids.add(link.id)))
      throw const FormatException('Quicklinks contain duplicate IDs.');
    _cache = List<Quicklink>.unmodifiable(next);
    _stamp = stamp;
    return _cache;
  }

  static List<Quicklink> decode(String json) {
    final dynamic decoded = jsonDecode(json);
    if (decoded is! List<dynamic>) throw const FormatException('Expected a JSON array of quicklinks.');
    return decoded.map<Quicklink>((dynamic entry) {
      if (entry is! Map<String, dynamic>) throw const FormatException('Each quicklink must be a JSON object.');
      return Quicklink.fromJson(entry);
    }).toList();
  }

  static String encode(Iterable<Quicklink> links) =>
      const JsonEncoder.withIndent('  ').convert(links.map((Quicklink link) => link.toJson()).toList());

  static bool aliasIsReserved(String alias) =>
      alias.toLowerCase() == 'ql' || LauncherQuery.parse('${alias.toLowerCase()} ').mode != LauncherSearchMode.mixed;

  static void save(Quicklink link) {
    link.validate();
    _mutate((List<Quicklink> links) {
      if (link.alias.isNotEmpty &&
          (aliasIsReserved(link.alias) ||
              links.any((Quicklink existing) =>
                  existing.id != link.id && existing.alias.toLowerCase() == link.alias.toLowerCase()))) {
        throw const FormatException('That alias is already in use. Choose another word.');
      }
      final int index = links.indexWhere((Quicklink existing) => existing.id == link.id);
      if (index < 0) {
        links.add(link);
      } else {
        links[index] = link;
      }
    });
  }

  static void delete(String id) =>
      _mutate((List<Quicklink> links) => links.removeWhere((Quicklink link) => link.id == id));

  static ({int added, int skipped}) importJson(String json) {
    // Decode the entire import before writing, so one invalid entry cannot
    // leave a partially imported collection.
    final List<Quicklink> incoming = decode(json);
    int added = 0;
    int skipped = 0;
    _mutate((List<Quicklink> links) {
      for (final Quicklink link in incoming) {
        if (links.any((Quicklink existing) => existing.name == link.name && existing.link == link.link)) {
          skipped++;
          continue;
        }
        final bool aliasTaken = aliasIsReserved(link.alias) ||
            links.any((Quicklink existing) => existing.alias.toLowerCase() == link.alias.toLowerCase());
        links.add(link.copyWith(id: const Uuid().v4(), alias: aliasTaken ? '' : link.alias));
        added++;
      }
    });
    return (added: added, skipped: skipped);
  }

  static void _mutate(void Function(List<Quicklink>) change) {
    final File file = File(path);
    file.parent.createSync(recursive: true);
    final RandomAccessFile lock = File('$path.lock').openSync(mode: FileMode.append);
    try {
      lock.lockSync(FileLock.blockingExclusive);
      final List<Quicklink> next = List<Quicklink>.of(load(force: true));
      change(next);
      final File temporary = File('$path.$pid.tmp');
      try {
        temporary.writeAsStringSync(encode(next), flush: true);
        temporary.renameSync(file.path);
      } finally {
        if (temporary.existsSync()) temporary.deleteSync();
      }
      _stamp = null;
    } finally {
      lock.closeSync();
    }
    changes.value++;
  }
}
