import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/quick_launch.dart';
import '../../../models/settings.dart';
import '../../../platform/app_catalog_service.dart';
import '../../../platform/file_picker_service.dart';
import '../../../services/quick_launch_icon_service.dart';
import '../../itzy/quickmenu/button_quick_launch.dart';

class QuickLaunchSettings extends StatefulWidget {
  const QuickLaunchSettings({super.key});

  @override
  State<QuickLaunchSettings> createState() => _QuickLaunchSettingsState();
}

class _QuickLaunchSettingsState extends State<QuickLaunchSettings> {
  final List<QuickLaunchGroup> _groups = QuickLaunchStore.read();
  late final TextEditingController _name = TextEditingController(text: _groups.first.name);
  int _selected = 0;
  bool _saving = false;
  bool _dirty = false;
  String? _error;

  QuickLaunchGroup get _group => _groups[_selected];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await QuickLaunchStore.save(_groups);
      if (mounted) setState(() => _dirty = false);
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not save: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit({int? index}) async {
    final QuickLaunchEntry? entry = await showDialog<QuickLaunchEntry>(
      context: context,
      builder: (BuildContext context) => _EntryEditor(entry: index == null ? null : _group.items[index]),
    );
    if (entry == null || !mounted) return;
    setState(() {
      if (index == null) {
        _group.items.add(entry);
      } else {
        _group.items[index] = entry;
      }
      _dirty = true;
    });
  }

  void _select(int index) => setState(() {
        _selected = index;
        _name.text = _group.name;
      });

  @override
  Widget build(BuildContext context) => AbsorbPointer(
        absorbing: _saving,
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          final bool wide = constraints.maxWidth >= 760;
          return Row(children: <Widget>[
            if (wide) ...<Widget>[
              SizedBox(width: 238, child: _sidebar()),
              VerticalDivider(width: 1, color: Design.text.withAlpha(18)),
            ],
            Expanded(
                child: Column(children: <Widget>[
              if (!wide)
                SizedBox(
                    height: 64,
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      scrollDirection: Axis.horizontal,
                      itemCount: 8,
                      separatorBuilder: (BuildContext context, int index) => const SizedBox(width: 6),
                      itemBuilder: (BuildContext context, int index) => _Action(
                        label: '${index + 1}',
                        icon: _groups[index].iconData,
                        selected: _selected == index,
                        onTap: () => _select(index),
                      ),
                    )),
              Expanded(
                  child: CustomScrollView(slivers: <Widget>[
                SliverToBoxAdapter(
                    child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 20, 20, 14),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                    Row(children: <Widget>[
                      _IconTile(icon: _group.iconData, selected: true, size: 44),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                        _SectionLabel('QUICKLAUNCH / ${(_selected + 1).toString().padLeft(2, '0')}'),
                        const SizedBox(height: 4),
                        Text(_group.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                color: Design.text, fontSize: Design.baseFontSize + 6, fontWeight: FontWeight.w600)),
                      ])),
                      _Badge('${_group.items.length} items'),
                    ]),
                    const SizedBox(height: 20),
                    _Surface(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      const _SectionLabel('GROUP IDENTITY'),
                      const SizedBox(height: 10),
                      _Field(
                          controller: _name,
                          label: 'Group name',
                          onChanged: (String value) => setState(() {
                                _group.name = value.trim().isEmpty ? 'QuickLaunch ${_selected + 1}' : value.trim();
                                _dirty = true;
                              })),
                      const SizedBox(height: 14),
                      Text('Bar icon',
                          style: TextStyle(color: Design.text.withAlpha(160), fontSize: Design.baseFontSize)),
                      const SizedBox(height: 8),
                      Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: quickLaunchIcons.entries
                              .map(
                                (MapEntry<String, IconData> icon) => Tooltip(
                                    message: icon.key,
                                    child: _IconTile(
                                      icon: icon.value,
                                      selected: _group.icon == icon.key,
                                      onTap: () => setState(() {
                                        _group.icon = icon.key;
                                        _dirty = true;
                                      }),
                                    )),
                              )
                              .toList()),
                    ])),
                    const SizedBox(height: 20),
                    Row(children: <Widget>[
                      const Expanded(child: _SectionLabel('LAUNCH ITEMS')),
                      _Action(label: 'Add item', icon: Icons.add_rounded, selected: true, onTap: () => _edit()),
                    ]),
                    const SizedBox(height: 4),
                    Text('Drag to reorder ? Click an item to edit',
                        style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(125))),
                  ]),
                )),
                if (_group.items.isEmpty)
                  SliverToBoxAdapter(
                      child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                    child: _Surface(
                        child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                          child: Column(children: <Widget>[
                        Icon(Icons.add_to_photos_outlined, size: 30, color: Design.text.withAlpha(75)),
                        const SizedBox(height: 12),
                        Text('Your shortcuts belong here',
                            style: TextStyle(color: Design.text, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 5),
                        Text('Apps, files, links and commands ? one hover away.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Design.text.withAlpha(140), fontSize: Design.baseFontSize)),
                        const SizedBox(height: 16),
                        _Action(label: 'Add first item', icon: Icons.add_rounded, onTap: () => _edit()),
                      ])),
                    )),
                  ))
                else
                  SliverPadding(
                      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
                      sliver: SliverReorderableList(
                        itemCount: _group.items.length,
                        onReorderItem: (int oldIndex, int newIndex) => setState(() {
                          _group.items.insert(newIndex, _group.items.removeAt(oldIndex));
                          _dirty = true;
                        }),
                        itemBuilder: (BuildContext context, int index) {
                          final QuickLaunchEntry entry = _group.items[index];
                          return Padding(
                            key: ObjectKey(entry),
                            padding: const EdgeInsets.only(bottom: 6),
                            child: _Surface(
                                padding: EdgeInsets.zero,
                                child: InkWell(
                                  borderRadius: BorderRadius.circular(10),
                                  hoverColor: Design.accent.withAlpha(14),
                                  onTap: () => _edit(index: index),
                                  child: Padding(
                                      padding: const EdgeInsets.fromLTRB(6, 9, 8, 9),
                                      child: Row(children: <Widget>[
                                        ReorderableDragStartListener(
                                            index: index,
                                            child: MouseRegion(
                                              cursor: SystemMouseCursors.grab,
                                              child: Padding(
                                                  padding: const EdgeInsets.all(8),
                                                  child: Icon(Icons.drag_indicator_rounded,
                                                      size: 16, color: Design.text.withAlpha(80))),
                                            )),
                                        SizedBox.square(dimension: 28, child: QuickLaunchItemIcon(entry: entry)),
                                        const SizedBox(width: 12),
                                        Expanded(
                                            child:
                                                Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                                          Text(entry.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: Design.text,
                                                  fontSize: Design.baseFontSize + 1,
                                                  fontWeight: FontWeight.w600)),
                                          const SizedBox(height: 3),
                                          Text(entry.target,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                  color: Design.text.withAlpha(120), fontSize: Design.baseFontSize)),
                                        ])),
                                        const SizedBox(width: 8),
                                        if (wide) _Badge(_kindLabel(entry.kind)),
                                        _SmallButton(
                                            icon: Icons.edit_outlined,
                                            label: 'Edit item',
                                            onTap: () => _edit(index: index)),
                                        _SmallButton(
                                            icon: Icons.close_rounded,
                                            label: 'Remove item',
                                            onTap: () => setState(() {
                                                  _group.items.removeAt(index);
                                                  _dirty = true;
                                                })),
                                      ])),
                                )),
                          );
                        },
                      )),
              ])),
              _footer(),
            ])),
          ]);
        }),
      );

  Widget _sidebar() => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        const Padding(padding: EdgeInsets.fromLTRB(20, 24, 20, 14), child: _SectionLabel('LAUNCH GROUPS')),
        Expanded(
            child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          itemCount: 8,
          separatorBuilder: (BuildContext context, int index) => const SizedBox(height: 6),
          itemBuilder: (BuildContext context, int index) {
            final QuickLaunchGroup group = _groups[index];
            final bool selected = _selected == index;
            return _Surface(
                selected: selected,
                padding: EdgeInsets.zero,
                child: InkWell(
                  onTap: () => _select(index),
                  borderRadius: BorderRadius.circular(10),
                  hoverColor: Design.accent.withAlpha(14),
                  child: Padding(
                      padding: const EdgeInsets.all(10),
                      child: Row(children: <Widget>[
                        Icon(group.iconData, size: 20, color: selected ? Design.accent : Design.text.withAlpha(140)),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                          Text(group.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  color: Design.text, fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 3),
                          Text('${group.items.length} items',
                              style: TextStyle(color: Design.text.withAlpha(115), fontSize: Design.baseFontSize)),
                        ])),
                        Text('${index + 1}'.padLeft(2, '0'),
                            style: TextStyle(
                                color: selected ? Design.accent : Design.text.withAlpha(65),
                                fontSize: Design.baseFontSize)),
                      ])),
                ));
          },
        )),
        Padding(
            padding: const EdgeInsets.all(20),
            child: Text('Pin QuickLaunch 1?8 to your bar in QuickActions.',
                style: TextStyle(color: Design.text.withAlpha(130), fontSize: Design.baseFontSize, height: 1.5))),
      ]);

  Widget _footer() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(18)))),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: <Widget>[
          if (_error != null)
            Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
          Row(children: <Widget>[
            Icon(_dirty ? Icons.circle : Icons.check_circle_outline,
                size: _dirty ? 7 : 14, color: _dirty ? Design.accent : Design.text.withAlpha(100)),
            const SizedBox(width: 8),
            Expanded(
                child: Text(_dirty ? 'Unsaved changes' : 'All changes saved',
                    style: TextStyle(color: Design.text.withAlpha(140), fontSize: Design.baseFontSize))),
            _Action(
                label: _saving ? 'Saving?' : 'Save changes',
                icon: Icons.save_outlined,
                selected: true,
                onTap: _dirty && !_saving ? _save : null),
          ]),
        ]),
      );
}

class _EntryEditor extends StatefulWidget {
  const _EntryEditor({this.entry});
  final QuickLaunchEntry? entry;

  @override
  State<_EntryEditor> createState() => _EntryEditorState();
}

class _EntryEditorState extends State<_EntryEditor> {
  late final TextEditingController _name = TextEditingController(text: widget.entry?.name ?? '');
  late final TextEditingController _target = TextEditingController(text: widget.entry?.target ?? '');
  final TextEditingController _search = TextEditingController();
  late QuickLaunchKind _kind = widget.entry?.kind ?? QuickLaunchKind.file;
  late String _iconPath = widget.entry?.iconPath ?? '';
  List<AppCatalogRecord> _apps = <AppCatalogRecord>[];
  bool _loading = false;
  bool _loaded = false;
  String? _catalogError;
  String? _error;

  @override
  void initState() {
    super.initState();
    if (_kind == QuickLaunchKind.app) _loadApps();
  }

  @override
  void dispose() {
    _name.dispose();
    _target.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> _loadApps() async {
    setState(() {
      _loading = true;
      _catalogError = null;
    });
    try {
      final AppCatalogSnapshot snapshot = await AppCatalogService.instance.discover();
      if (!mounted) return;
      setState(() {
        _apps = snapshot.records;
        _loaded = snapshot.complete;
        if (!snapshot.complete) _catalogError = snapshot.error ?? 'App discovery is unavailable.';
      });
    } catch (error) {
      if (mounted) setState(() => _catalogError = 'Could not load apps: $error');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFile() async {
    try {
      final File? file = await (OpenFilePicker()
            ..title = 'Select a file or application'
            ..filterSpecification = <String, String>{'All files': '*.*'})
          .getFileAsync();
      if (file == null || !mounted) return;
      setState(() {
        _target.text = file.path;
        _iconPath = file.path;
        if (_name.text.trim().isEmpty) _name.text = file.path.split(RegExp(r'[\\/]')).last;
      });
    } catch (error) {
      if (mounted) setState(() => _error = 'Could not pick a file: $error');
    }
  }

  void _submit() {
    String target = _target.text.trim();
    if (_name.text.trim().isEmpty || target.isEmpty) {
      setState(() => _error = 'Enter a name and a launch target.');
      return;
    }
    if (_kind == QuickLaunchKind.link) {
      if (!target.contains(':')) target = 'https://$target';
      final Uri? uri = Uri.tryParse(target);
      if (uri == null || !uri.hasScheme || (const <String>['http', 'https'].contains(uri.scheme) && uri.host.isEmpty)) {
        setState(() => _error = 'Enter a valid link.');
        return;
      }
    }
    Navigator.pop(
        context,
        QuickLaunchEntry(
            name: _name.text.trim(),
            target: target,
            kind: _kind,
            iconPath: _kind == QuickLaunchKind.file
                ? target
                : _kind == QuickLaunchKind.app
                    ? _iconPath
                    : ''));
  }

  @override
  Widget build(BuildContext context) {
    final String query = _search.text.trim().toLowerCase();
    final List<AppCatalogRecord> results =
        _apps.where((AppCatalogRecord app) => app.name.toLowerCase().contains(query)).toList();
    return Dialog(
      insetPadding: const EdgeInsets.all(24),
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14), side: BorderSide(color: Design.text.withAlpha(24))),
      clipBehavior: Clip.antiAlias,
      child: SizedBox(
          width: 560,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * .85),
            child: Column(mainAxisSize: MainAxisSize.min, children: <Widget>[
              Padding(
                  padding: const EdgeInsets.fromLTRB(20, 18, 12, 16),
                  child: Row(children: <Widget>[
                    const _IconTile(icon: Icons.add_link_rounded, selected: true),
                    const SizedBox(width: 12),
                    Expanded(
                        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
                      const _SectionLabel('QUICKLAUNCH'),
                      const SizedBox(height: 4),
                      Text(widget.entry == null ? 'New launch item' : 'Edit launch item',
                          style: TextStyle(
                              color: Design.text, fontSize: Design.baseFontSize + 5, fontWeight: FontWeight.w600)),
                    ])),
                    _SmallButton(icon: Icons.close_rounded, label: 'Close', onTap: () => Navigator.pop(context)),
                  ])),
              Divider(height: 1, color: Design.text.withAlpha(18)),
              Flexible(
                  child: ListView(shrinkWrap: true, padding: const EdgeInsets.all(20), children: <Widget>[
                const _SectionLabel('ITEM TYPE'),
                const SizedBox(height: 10),
                Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: QuickLaunchKind.values
                        .map((QuickLaunchKind kind) => _Action(
                              label: _kindLabel(kind),
                              icon: switch (kind) {
                                QuickLaunchKind.file => Icons.insert_drive_file_outlined,
                                QuickLaunchKind.link => Icons.language_rounded,
                                QuickLaunchKind.command => Icons.terminal_rounded,
                                QuickLaunchKind.app => Icons.apps_rounded,
                              },
                              selected: _kind == kind,
                              onTap: () {
                                if (_kind == kind) return;
                                setState(() {
                                  _kind = kind;
                                  _error = null;
                                  _target.clear();
                                  _iconPath = '';
                                });
                                if (kind == QuickLaunchKind.app && !_loaded && !_loading) _loadApps();
                              },
                            ))
                        .toList()),
                const SizedBox(height: 20),
                _Field(controller: _name, label: 'Display name', hint: 'A short, recognizable name'),
                const SizedBox(height: 14),
                _Field(
                  controller: _target,
                  readOnly: _kind == QuickLaunchKind.app,
                  label: switch (_kind) {
                    QuickLaunchKind.file => 'File path',
                    QuickLaunchKind.link => 'URL',
                    QuickLaunchKind.command => 'Command',
                    QuickLaunchKind.app => 'Selected app',
                  },
                  hint: switch (_kind) {
                    QuickLaunchKind.file => 'Choose a file or paste its path',
                    QuickLaunchKind.link => 'https://example.com',
                    QuickLaunchKind.command => 'Enter a command to run',
                    QuickLaunchKind.app => 'Choose an app below',
                  },
                  suffix: _kind == QuickLaunchKind.file
                      ? _SmallButton(icon: Icons.folder_open_outlined, label: 'Browse files', onTap: _pickFile)
                      : null,
                ),
                if (_kind == QuickLaunchKind.command)
                  Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text('Runs in Command Prompt. The window stays open for output.',
                          style: TextStyle(fontSize: Design.baseFontSize, color: Design.text.withAlpha(130)))),
                if (_kind == QuickLaunchKind.app) ...<Widget>[
                  const SizedBox(height: 20),
                  Row(children: <Widget>[
                    const Expanded(child: _SectionLabel('INSTALLED APPS')),
                    _Badge('${results.length}'),
                  ]),
                  const SizedBox(height: 10),
                  _Field(
                      controller: _search,
                      label: 'Search apps',
                      hint: 'Filter by name',
                      onChanged: (_) => setState(() {}),
                      prefix: Icons.search_rounded),
                  const SizedBox(height: 8),
                  if (_loading)
                    LinearProgressIndicator(
                        minHeight: 2, color: Design.accent, backgroundColor: Design.text.withAlpha(15)),
                  if (_catalogError != null)
                    Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(children: <Widget>[
                          Expanded(
                              child:
                                  Text(_catalogError!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                          _Action(label: 'Retry', icon: Icons.refresh_rounded, onTap: _loading ? null : _loadApps),
                        ])),
                  _Surface(
                      padding: EdgeInsets.zero,
                      child: SizedBox(
                        height: 190,
                        child: !_loading && _catalogError == null && results.isEmpty
                            ? Center(
                                child: Text('No matching apps', style: TextStyle(color: Design.text.withAlpha(130))))
                            : ListView.builder(
                                itemCount: results.length,
                                itemBuilder: (BuildContext context, int index) {
                                  final AppCatalogRecord app = results[index];
                                  final bool selected = _target.text == app.launchTarget;
                                  return Material(
                                    color: selected ? Design.accent.withAlpha(18) : Colors.transparent,
                                    child: InkWell(
                                      hoverColor: Design.accent.withAlpha(14),
                                      onTap: () => setState(() {
                                        _name.text = app.name;
                                        _target.text = app.launchTarget;
                                        _iconPath = QuickLaunchIconService.appIconSource(app);
                                      }),
                                      child: Padding(
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                        child: Row(children: <Widget>[
                                          Icon(Icons.apps_rounded,
                                              size: 18, color: selected ? Design.accent : Design.text.withAlpha(110)),
                                          const SizedBox(width: 10),
                                          Expanded(
                                              child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  children: <Widget>[
                                                Text(app.name,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        color: Design.text, fontSize: Design.baseFontSize + 1)),
                                                Text(app.subtitle,
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                    style: TextStyle(
                                                        color: Design.text.withAlpha(110),
                                                        fontSize: Design.baseFontSize)),
                                              ])),
                                          if (selected) Icon(Icons.check_rounded, size: 16, color: Design.accent),
                                        ]),
                                      ),
                                    ),
                                  );
                                }),
                      )),
                ],
                if (_error != null)
                  Padding(
                      padding: const EdgeInsets.only(top: 12),
                      child: Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error))),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                decoration: BoxDecoration(border: Border(top: BorderSide(color: Design.text.withAlpha(18)))),
                child: Row(mainAxisAlignment: MainAxisAlignment.end, children: <Widget>[
                  _Action(label: 'Cancel', onTap: () => Navigator.pop(context)),
                  const SizedBox(width: 8),
                  _Action(
                      label: widget.entry == null ? 'Add item' : 'Update item',
                      icon: widget.entry == null ? Icons.add_rounded : Icons.check_rounded,
                      selected: true,
                      onTap: _submit),
                ]),
              ),
            ]),
          )),
    );
  }
}

String _kindLabel(QuickLaunchKind kind) => switch (kind) {
      QuickLaunchKind.file => 'File',
      QuickLaunchKind.link => 'Link',
      QuickLaunchKind.command => 'Command',
      QuickLaunchKind.app => 'Start Menu app',
    };

class _Surface extends StatelessWidget {
  const _Surface({required this.child, this.selected = false, this.padding = const EdgeInsets.all(14)});
  final Widget child;
  final bool selected;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Design.accent.withAlpha(12) : Design.text.withAlpha(6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
            side: BorderSide(color: selected ? Design.accent.withAlpha(65) : Design.text.withAlpha(16))),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding, child: child),
      );
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(text,
      style: TextStyle(
          color: Design.text.withAlpha(120),
          fontSize: Design.baseFontSize - 1,
          fontWeight: FontWeight.w600,
          letterSpacing: 1));
}

class _Badge extends StatelessWidget {
  const _Badge(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: Design.text.withAlpha(9), borderRadius: BorderRadius.circular(5)),
        child: Text(text, style: TextStyle(color: Design.text.withAlpha(130), fontSize: Design.baseFontSize - 1)),
      );
}

class _Action extends StatelessWidget {
  const _Action({required this.label, this.icon, this.onTap, this.selected = false});
  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final bool selected;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: onTap == null ? .4 : 1,
        child: Material(
          color: selected ? Design.accent.withAlpha(20) : Design.text.withAlpha(5),
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
              side: BorderSide(color: selected ? Design.accent.withAlpha(65) : Design.text.withAlpha(22))),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(7),
            hoverColor: Design.accent.withAlpha(25),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              child: Row(mainAxisSize: MainAxisSize.min, children: <Widget>[
                if (icon != null) ...<Widget>[
                  Icon(icon, size: 16, color: selected ? Design.accent : Design.text.withAlpha(170)),
                  const SizedBox(width: 7),
                ],
                Text(label,
                    style: TextStyle(
                        color: selected ? Design.accent : Design.text.withAlpha(190),
                        fontSize: Design.baseFontSize,
                        fontWeight: FontWeight.w600)),
              ]),
            ),
          ),
        ),
      );
}

class _IconTile extends StatelessWidget {
  const _IconTile({required this.icon, this.selected = false, this.onTap, this.size = 34});
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;
  final double size;

  @override
  Widget build(BuildContext context) => Material(
        color: selected ? Design.accent.withAlpha(20) : Design.text.withAlpha(6),
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(color: selected ? Design.accent.withAlpha(70) : Design.text.withAlpha(16))),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: SizedBox.square(
              dimension: size,
              child: Icon(icon, size: 19, color: selected ? Design.accent : Design.text.withAlpha(140))),
        ),
      );
}

class _SmallButton extends StatelessWidget {
  const _SmallButton({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IconButton(
        tooltip: label,
        onPressed: onTap,
        icon: Icon(icon, size: 16),
        color: Design.text.withAlpha(130),
        hoverColor: Design.accent.withAlpha(20),
        constraints: const BoxConstraints.tightFor(width: 32, height: 32),
        padding: EdgeInsets.zero,
      );
}

class _Field extends StatelessWidget {
  const _Field(
      {required this.controller,
      required this.label,
      this.hint,
      this.onChanged,
      this.readOnly = false,
      this.suffix,
      this.prefix});
  final TextEditingController controller;
  final String label;
  final String? hint;
  final ValueChanged<String>? onChanged;
  final bool readOnly;
  final Widget? suffix;
  final IconData? prefix;

  @override
  Widget build(BuildContext context) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
        Text(label, style: TextStyle(color: Design.text.withAlpha(165), fontSize: Design.baseFontSize)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          onChanged: onChanged,
          readOnly: readOnly,
          style: TextStyle(color: Design.text, fontSize: Design.baseFontSize + 1),
          cursorColor: Design.accent,
          decoration: InputDecoration(
            hintText: hint,
            hintStyle: TextStyle(color: Design.text.withAlpha(70), fontSize: Design.baseFontSize + 1),
            isDense: true,
            filled: true,
            fillColor: Design.text.withAlpha(5),
            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            suffixIcon: suffix,
            prefixIcon: prefix == null ? null : Icon(prefix, size: 18, color: Design.text.withAlpha(110)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: Design.text.withAlpha(22))),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(7), borderSide: BorderSide(color: Design.accent.withAlpha(130))),
          ),
        ),
      ]);
}
