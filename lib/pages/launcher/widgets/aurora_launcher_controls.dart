part of '../../launcher.dart';

String _auroraResultGroup(LauncherSearchResultItem result) {
  if (result.isFile) return result.entity is Directory ? 'Folders' : 'Files';
  if (result.isApp) return 'Apps';
  if (result.isWindow) return 'Windows';
  if (result.isBookmark || result.isBrowserTab) return 'Web';
  if (result.isShortcut) return 'Plugins';
  return 'Commands';
}

// ignore: unused_element
class _AuroraControls extends StatelessWidget {
  const _AuroraControls(
      {required this.query,
      required this.results,
      required this.isSearching,
      required this.onQuery,
      required this.onOpen});
  final String query;
  final List<LauncherSearchResultItem> results;
  final bool isSearching;
  final ValueChanged<String> onQuery;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final LauncherQuery parsed = LauncherQuery.parse(query);
    final List<({String label, String prefix, IconData icon, LauncherSearchMode mode})> filters =
        <({String label, String prefix, IconData icon, LauncherSearchMode mode})>[
      (label: 'All', prefix: '', icon: Icons.grid_view_rounded, mode: LauncherSearchMode.mixed),
      (label: 'Files', prefix: '>', icon: Icons.insert_drive_file_outlined, mode: LauncherSearchMode.filesOnly),
      (label: 'Apps', prefix: 'app ', icon: Icons.apps_rounded, mode: LauncherSearchMode.appsOnly),
      (label: 'Commands', prefix: '/', icon: Icons.terminal_rounded, mode: LauncherSearchMode.actionsOnly),
    ];
    return Padding(
        padding: const EdgeInsets.fromLTRB(6, 0, 6, 12),
        child: Row(children: <Widget>[
          Expanded(
              child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(children: <Widget>[
                    for (final ({String label, String prefix, IconData icon, LauncherSearchMode mode}) filter
                        in filters)
                      Padding(
                          padding: const EdgeInsets.only(right: 10),
                          child: Tooltip(
                            message: filter.label == 'Files'
                                ? 'Search files and folders'
                                : 'Search ${filter.label.toLowerCase()}',
                            child: OutlinedButton(
                              onPressed: () => onQuery('${filter.prefix}${parsed.normalized}'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor:
                                    parsed.mode == filter.mode ? AuroraTokens.foreground : AuroraTokens.dim,
                                backgroundColor:
                                    parsed.mode == filter.mode ? AuroraTokens.accent.withAlpha(34) : AuroraTokens.panel,
                                side: BorderSide(
                                    color: parsed.mode == filter.mode ? AuroraTokens.accent : AuroraTokens.border),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
                              ),
                              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                                Icon(filter.icon, size: 16, color: AuroraTokens.accent),
                                const SizedBox(width: 9),
                                Text(filter.label),
                                if (parsed.mode == filter.mode) ...<Widget>[
                                  const SizedBox(width: 10),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                        color: AuroraTokens.dim.withAlpha(25), borderRadius: BorderRadius.circular(5)),
                                    child: Text(isSearching ? '...' : '${results.length}',
                                        style: AuroraTokens.font(size: 11)),
                                  )
                                ],
                              ]),
                            ),
                          )),
                  ]))),
          const SizedBox(width: 8),
          Tooltip(
              message: 'Open selected result (Enter)',
              child: IconButton(
                  onPressed: results.isEmpty ? null : onOpen,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  color: AuroraTokens.accent)),
          if (query.isNotEmpty)
            Tooltip(
                message: 'Clear search',
                child: IconButton(
                    onPressed: () => onQuery(''), icon: const Icon(Icons.close_rounded), color: AuroraTokens.dim)),
        ]));
  }
}

class _PhosphorControls extends StatelessWidget {
  const _PhosphorControls({required this.query, required this.results, required this.onQuery});
  final String query;
  final List<LauncherSearchResultItem> results;
  final ValueChanged<String> onQuery;
  @override
  Widget build(BuildContext context) {
    final LauncherQuery parsed = LauncherQuery.parse(query);
    const List<({String label, String prefix, LauncherSearchMode mode})> filters = <({String label, String prefix, LauncherSearchMode mode})>[
      (label: 'All', prefix: '', mode: LauncherSearchMode.mixed),
      (label: 'Files', prefix: '>', mode: LauncherSearchMode.filesOnly),
      (label: 'Apps', prefix: 'app ', mode: LauncherSearchMode.appsOnly),
      (label: 'Web', prefix: 'b ', mode: LauncherSearchMode.bookmarkOnly),
      (label: 'Actions', prefix: '/', mode: LauncherSearchMode.actionsOnly),
    ];
    return Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
        child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: <Widget>[
              for (final ({String label, String prefix, LauncherSearchMode mode}) filter in filters)
                Padding(
                    padding: const EdgeInsets.only(right: 14),
                    child: TextButton(
                      onPressed: () => onQuery('${filter.prefix}${parsed.normalized}'),
                      style: TextButton.styleFrom(
                          minimumSize: const Size(0, 28),
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
                          shape: const RoundedRectangleBorder(),
                          backgroundColor: parsed.mode == filter.mode ? PhosphorTokens.accent : Colors.transparent,
                          foregroundColor: parsed.mode == filter.mode ? PhosphorTokens.background : PhosphorTokens.dim,
                          textStyle: PhosphorTokens.font(size: 14)),
                      child: Text('[ ${filter.label}${parsed.mode == filter.mode ? ' (${results.length})' : ''} ]'),
                    )),
            ])));
  }
}
