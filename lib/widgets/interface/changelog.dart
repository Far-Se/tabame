import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';

class _ChangelogRelease {
  const _ChangelogRelease({this.date, required this.content});

  final String? date;
  final String content;
}

class Changelog extends StatefulWidget {
  const Changelog({super.key, this.showTitle = true, this.maxVersions});

  final bool showTitle;
  final int? maxVersions;

  @override
  State<Changelog> createState() => _ChangelogState();
}

class _ChangelogState extends State<Changelog> {
  late Future<Map<String, _ChangelogRelease>> _changelog;

  Future<Map<String, _ChangelogRelease>> _loadChangelog() async {
    final String markdown = await rootBundle.loadString('CHANGELOG.md');
    // Each release starts with "# v<version> - <date>"; the date is optional.
    final List<RegExpMatch> headings = RegExp(
      r'^# v(\d+(?:\.\d+)*)(?: - ([^\r\n]+))?\r?$',
      multiLine: true,
    ).allMatches(markdown).toList();
    if (headings.isEmpty) {
      throw const FormatException('No releases found in CHANGELOG.md');
    }
    final Map<String, _ChangelogRelease> releases = <String, _ChangelogRelease>{};
    for (int i = 0; i < headings.length; i++) {
      final RegExpMatch heading = headings[i];
      releases.putIfAbsent(
        heading.group(1)!,
        () => _ChangelogRelease(
          date: heading.group(2)?.trim(),
          content:
              markdown.substring(heading.end, i + 1 < headings.length ? headings[i + 1].start : markdown.length).trim(),
        ),
      );
    }
    return releases;
  }

  @override
  void initState() {
    super.initState();
    _changelog = _loadChangelog();
    if (user.lastChangelog != Globals.version) {
      user.lastChangelog = Globals.version;
      Boxes.updateSettings("lastChangelog", user.lastChangelog);
      if (Globals.quickMenuPage == QuickMenuPage.quickMenu) {
        QuickMenuFunctions.refreshQuickMenu();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, _ChangelogRelease>>(
      future: _changelog,
      builder: (BuildContext context, AsyncSnapshot<Map<String, _ChangelogRelease>> snapshot) {
        return _buildChangelog(context, snapshot);
      },
    );
  }

  Widget _buildChangelog(BuildContext context, AsyncSnapshot<Map<String, _ChangelogRelease>> snapshot) {
    return Padding(
      padding: const EdgeInsets.all(10.0),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          if (widget.showTitle) ...<Widget>[
            Text("Changelog", style: Theme.of(context).textTheme.headlineMedium),
            const SizedBox(height: 15),
          ],
          if (snapshot.hasError)
            const Text('Unable to load the changelog.')
          else if (!snapshot.hasData)
            const Center(child: CircularProgressIndicator())
          else
            ...snapshot.data!.entries
                .take(widget.maxVersions ?? snapshot.data!.length)
                .map((MapEntry<String, _ChangelogRelease> entry) {
              return Container(
                margin: const EdgeInsets.only(bottom: 24),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            "v${entry.key}",
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  color: Theme.of(context).colorScheme.primary,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                          ),
                        ),
                        if (entry.value.date != null) ...<Widget>[
                          const SizedBox(width: 8),
                          Text(
                            entry.value.date!,
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface.withAlpha(160),
                                ),
                          ),
                        ],
                        const SizedBox(width: 12),
                        Expanded(
                          child: Container(
                            height: 1,
                            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    MarkdownBody(
                      shrinkWrap: true,
                      data: entry.value.content,
                      styleSheet: MarkdownStyleSheet(
                        h2: Theme.of(context).textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                        h3: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: Theme.of(context).colorScheme.secondary,
                            ),
                        listBullet: TextStyle(color: Theme.of(context).colorScheme.primary),
                        p: Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.5),
                        strong: const TextStyle(fontWeight: FontWeight.bold),
                        blockSpacing: 12,
                        listIndent: 20,
                      ),
                    ),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }
}
