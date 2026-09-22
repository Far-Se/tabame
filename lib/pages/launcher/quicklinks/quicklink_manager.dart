part of 'quicklink_ui.dart';

class _QuicklinkManager extends StatefulWidget {
  const _QuicklinkManager();

  @override
  State<_QuicklinkManager> createState() => _QuicklinkManagerState();
}

class _QuicklinkManagerState extends State<_QuicklinkManager> {
  final TextEditingController _search = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final FocusNode _tagFocus = FocusNode();
  final FocusNode _searchFocus = FocusNode();
  List<Quicklink> _links = <Quicklink>[];
  List<LauncherQuicklinkResult> _visible = <LauncherQuicklinkResult>[];
  String? _error;
  String? _tag;
  int _active = 0;

  @override
  void initState() {
    super.initState();
    QuicklinkStore.changes.addListener(_reload);
    _load();
  }

  @override
  void dispose() {
    QuicklinkStore.changes.removeListener(_reload);
    _search.dispose();
    _scroll.dispose();
    _tagFocus.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void _load() {
    try {
      _links = QuicklinkStore.load(force: true);
      _error = null;
      if (_tag != null && !_links.any((Quicklink link) => link.tags.contains(_tag))) _tag = null;
    } catch (error) {
      _error = error.toString();
    }
  }

  void _reload() {
    if (mounted) setState(_load);
  }

  void _move(int delta) {
    if (_visible.isEmpty) return;
    setState(() => _active = (_active + delta).clamp(0, _visible.length - 1));
    if (_scroll.hasClients) {
      _scroll.jumpTo((_active * 54.0).clamp(0, _scroll.position.maxScrollExtent));
    }
  }

  Future<void> _openActive() async {
    if (_visible.isEmpty) return;
    final LauncherQuicklinkResult selected = _visible[_active];
    final bool opened = await QuicklinkUi.open(context, selected.quicklink!, argument: selected.argument);
    if (opened && mounted) Navigator.pop(context);
  }

  Future<void> _actions() async {
    if (_visible.isEmpty) return;
    final bool opened = await QuicklinkUi.showActions(context, _visible[_active]);
    if (opened && mounted) Navigator.pop(context);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _move(1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _move(-1);
      return KeyEventResult.handled;
    }
    if (event.logicalKey == LogicalKeyboardKey.enter || event.logicalKey == LogicalKeyboardKey.numpadEnter) {
      if (event is KeyDownEvent) unawaited(_openActive());
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final LauncherModalTokens tokens = LauncherModalTokens.of(context);
    final List<String> tags = _links.expand((Quicklink link) => link.tags).toSet().toList()..sort();
    _visible = QuicklinkSearch.results(_search.text, includeHidden: true)
        .whereType<LauncherQuicklinkResult>()
        .where((LauncherQuicklinkResult result) =>
            result.quicklink != null && (_tag == null || result.quicklink!.tags.contains(_tag)))
        .toList();
    _active = _active.clamp(0, math.max(0, _visible.length - 1));
    return CallbackShortcuts(
      bindings: <ShortcutActivator, VoidCallback>{
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): _actions,
        const SingleActivator(LogicalKeyboardKey.keyN, control: true): () => unawaited(QuicklinkUi.edit(context)),
        const SingleActivator(LogicalKeyboardKey.keyP, control: true): _tagFocus.requestFocus,
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): _searchFocus.requestFocus,
      },
      child: _QuicklinkDialog(
        title: 'Quicklinks',
        subtitle: '${_links.length} saved · Enter to open · Ctrl+K for actions',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Padding(
                padding: const EdgeInsets.all(12),
                child: Row(children: <Widget>[
                  Expanded(
                      child: Focus(
                          onKeyEvent: _onKey,
                          child: TextField(
                            controller: _search,
                            focusNode: _searchFocus,
                            autofocus: true,
                            decoration: const InputDecoration(
                                hintText: 'Search name, alias, or #tag',
                                prefixIcon: Icon(Icons.search_rounded, size: 18)),
                            onChanged: (_) => setState(() => _active = 0),
                          ))),
                  if (tags.isNotEmpty) ...<Widget>[
                    const SizedBox(width: 8),
                    SizedBox(
                        width: 140,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey<String?>(_tag),
                          initialValue: _tag ?? '',
                          focusNode: _tagFocus,
                          isExpanded: true,
                          decoration: const InputDecoration(labelText: 'Tag · Ctrl+P'),
                          items: <DropdownMenuItem<String>>[
                            const DropdownMenuItem<String>(value: '', child: Text('All tags')),
                            ...tags.map((String tag) => DropdownMenuItem<String>(
                                value: tag, child: Text(tag, overflow: TextOverflow.ellipsis))),
                          ],
                          onChanged: (String? tag) => setState(() {
                            _tag = tag == '' ? null : tag;
                            _active = 0;
                          }),
                        )),
                  ],
                ])),
            Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: <Widget>[
                    FilledButton.icon(
                        onPressed: () => QuicklinkUi.edit(context),
                        icon: const Icon(Icons.add_rounded, size: 16),
                        label: const Text('Create Quicklink')),
                    TextButton.icon(
                        onPressed: () => QuicklinkUi.showLibrary(context),
                        icon: const Icon(Icons.library_add_outlined, size: 16),
                        label: const Text('Add from Library')),
                    PopupMenuButton<QuicklinkCommand>(
                      tooltip: 'Import or export',
                      icon: const Icon(Icons.more_horiz_rounded),
                      onSelected: (QuicklinkCommand command) =>
                          QuicklinkUi.execute(context, LauncherQuicklinkResult.command(command)),
                      itemBuilder: (_) => const <PopupMenuEntry<QuicklinkCommand>>[
                        PopupMenuItem<QuicklinkCommand>(
                            value: QuicklinkCommand.importFile, child: Text('Import JSON…')),
                        PopupMenuItem<QuicklinkCommand>(
                            value: QuicklinkCommand.exportFile, child: Text('Export JSON…')),
                      ],
                    ),
                  ],
                )),
            const SizedBox(height: 8),
            if (_error != null)
              Padding(
                  padding: const EdgeInsets.all(16),
                  child: SelectableText(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))
            else if (_visible.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                child: Column(children: <Widget>[
                  Icon(Icons.add_link_rounded, size: 28, color: tokens.accent),
                  const SizedBox(height: 12),
                  Text(_links.isEmpty ? 'Your everyday destinations, one search away.' : 'No matching quicklinks.',
                      style: tokens.text(fontSize: 14, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 8),
                  Text(
                      _links.isEmpty
                          ? 'Save a website, project folder, or search. Start with a template from the library.'
                          : 'Try a different name, alias, or tag.',
                      textAlign: TextAlign.center,
                      style: tokens.text(fontSize: 12, color: tokens.dim)),
                ]),
              )
            else
              Flexible(
                child: ListView.builder(
                  controller: _scroll,
                  shrinkWrap: true,
                  itemCount: _visible.length,
                  itemBuilder: (_, int index) {
                    final LauncherQuicklinkResult result = _visible[index];
                    final Quicklink link = result.quicklink!;
                    return Row(children: <Widget>[
                      Expanded(
                          child: LauncherResultRow(
                        isSelected: index == _active,
                        isRepeating: false,
                        accent: tokens.accent,
                        onSurface: tokens.onSurface,
                        icon: Icon(QuicklinkUi.iconFor(result), size: 18, color: tokens.accent),
                        title: result.title,
                        subtitle: <String>[
                          if (link.hidden) 'Hidden from root',
                          ...link.tags.map((String tag) => '#$tag'),
                          result.subtitle
                        ].join(' · '),
                        badge: link.pinned ? Icon(Icons.push_pin_outlined, size: 13, color: tokens.dim) : null,
                        onHover: () => setState(() => _active = index),
                        onTap: () {
                          setState(() => _active = index);
                          unawaited(_openActive());
                        },
                      )),
                      IconButton(
                          tooltip: 'Actions (Ctrl+K)',
                          icon: Icon(Icons.more_horiz_rounded, color: tokens.dim, size: 18),
                          onPressed: () {
                            setState(() => _active = index);
                            _actions();
                          }),
                    ]);
                  },
                ),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}
