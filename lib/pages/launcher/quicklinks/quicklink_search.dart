import 'package:flutter/material.dart';

import '../core/launcher_result.dart';
import '../core/launcher_query.dart';
import 'quicklink.dart';
import 'quicklink_store.dart';

class QuicklinkSearch {
  QuicklinkSearch._();

  /// A dedicated library query or a complete alias owns these results.
  static List<LauncherSearchResultItem>? ownedResults(String query) {
    if (LauncherQuery.parse(query).mode != LauncherSearchMode.mixed) return null;
    final String trimmed = query;
    final String lower = trimmed.toLowerCase();
    if (lower == 'ql' || lower.startsWith('ql ')) {
      return results(trimmed.length > 2 ? trimmed.substring(3) : '', includeHidden: true);
    }
    try {
      final List<Quicklink> aliases = QuicklinkStore.load()
          .where((Quicklink link) =>
              link.alias.isNotEmpty &&
              (lower == link.alias.toLowerCase() || lower.startsWith('${link.alias.toLowerCase()} ')))
          .toList();
      if (aliases.isEmpty) return null;
      return aliases
          .map((Quicklink link) =>
              LauncherQuicklinkResult.link(link, argument: trimmed.substring(link.alias.length).trimLeft()))
          .toList();
    } catch (_) {
      // Ordinary launcher searches must still work if the library is damaged.
      return null;
    }
  }

  static List<LauncherSearchResultItem> results(String query, {bool includeHidden = false}) {
    final String trimmed = query.trim();
    final String lower = trimmed.toLowerCase();
    final List<LauncherSearchResultItem> commands = <LauncherSearchResultItem>[
      for (final QuicklinkCommand command in QuicklinkCommand.values)
        if (lower.isEmpty || LauncherQuicklinkResult.command(command).title.toLowerCase().contains(lower))
          LauncherQuicklinkResult.command(command),
    ];
    try {
      final List<Quicklink> matches = QuicklinkStore.load().where((Quicklink link) {
        if (link.hidden && !includeHidden) return false;
        if (lower.isEmpty || _argumentAfterName(link, trimmed) != null) return true;
        final String haystack = '${link.name} ${link.alias} ${link.tags.join(' ')} ${link.link}'.toLowerCase();
        return lower.split(RegExp(r'\s+')).every((String word) => word.startsWith('#')
            ? link.tags.any((String tag) => tag.toLowerCase() == word.substring(1))
            : haystack.contains(word));
      }).toList()
        ..sort((Quicklink a, Quicklink b) {
          final int byScore = _score(b, lower).compareTo(_score(a, lower));
          return byScore != 0 ? byScore : a.name.toLowerCase().compareTo(b.name.toLowerCase());
        });
      return <LauncherSearchResultItem>[
        ...matches.take(includeHidden ? matches.length : 100).map(
            (Quicklink link) => LauncherQuicklinkResult.link(link, argument: _argumentAfterName(link, trimmed) ?? '')),
        ...commands,
        if (includeHidden && matches.isEmpty && commands.isEmpty)
          const LauncherSearchResultItem.info(LauncherInfoResult(
              id: 'quicklinks-no-match',
              title: 'No matching quicklinks',
              subtitle: 'Search by name, alias, or #tag. Type ql to see all quicklinks.',
              icon: Icons.link_off_rounded)),
      ];
    } catch (error) {
      return <LauncherSearchResultItem>[
        ...commands,
        if (includeHidden || lower.contains('quicklink'))
          LauncherSearchResultItem.info(LauncherInfoResult(
              id: 'quicklinks-read-error',
              title: 'Could not read quicklinks',
              subtitle: error.toString(),
              icon: Icons.error_outline_rounded)),
      ];
    }
  }

  static String? _argumentAfterName(Quicklink link, String query) {
    for (final String trigger in <String>[link.name, if (link.alias.isNotEmpty) link.alias]) {
      if (query.toLowerCase().startsWith('${trigger.toLowerCase()} ')) {
        return query.substring(trigger.length).trimLeft();
      }
    }
    return null;
  }

  static int _score(Quicklink link, String query) {
    if (query.isNotEmpty && (link.alias.toLowerCase() == query || link.name.toLowerCase() == query)) return 100;
    if (_argumentAfterName(link, query) != null) return 90;
    return (link.pinned ? 20 : 0) + (query.isNotEmpty && link.name.toLowerCase().startsWith(query) ? 10 : 0);
  }
}
