import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../../models/clipboard_history.dart';
import 'plugin_manifest.dart';
import 'plugin_protocol.dart';

/// Built-in clipboard browser using the same frames and actions as script plugins.
class ClipboardHistoryPlugin {
  ClipboardHistoryPlugin({required this.onFrame, required this.onCommand});

  static const PluginManifest manifest = PluginManifest(
    id: 'tabame.builtin.clipboard-history',
    name: 'Clipboard History',
    keyword: 'clb',
    description: 'Browse and copy saved clipboard history',
    icon: 'clipboard',
    runtime: '',
    entry: '',
    args: <String>[],
    directory: '',
  );

  final void Function(PluginRenderFrame) onFrame;
  final void Function(PluginCommand) onCommand;
  final List<PluginItem> _items = <PluginItem>[];
  final Map<String, ClipboardHistoryEntry> _entries = <String, ClipboardHistoryEntry>{};
  String _query = '';
  int _generation = 0;
  int _offset = 0;
  bool _hasMore = false;
  bool _loading = false;
  bool _disposed = false;

  void dispose() {
    _disposed = true;
    _generation++;
  }

  void handle(Map<String, Object?> event) {
    if (_disposed) return;
    switch (event['type']) {
      case 'query':
        _generation++;
        _query = event['text'] as String;
        _items.clear();
        _entries.clear();
        _offset = 0;
        _hasMore = false;
        unawaited(_load(_generation));
        break;
      case 'loadMore':
        if (_hasMore && !_loading) unawaited(_load(_generation));
        break;
      case 'action':
        final ClipboardHistoryEntry? entry = _entries[event['id']];
        if (entry != null) unawaited(_act(entry, event['action'] as String));
        break;
    }
  }

  Future<void> _load(int generation) async {
    _loading = true;
    _render();
    try {
      const int limit = 30;
      final String query = _query;
      final String normalized = query.trim().toLowerCase();
      final List<ClipboardHistoryEntry> pinned = (await ClipboardHistoryStore.loadPinned())
          .where((ClipboardHistoryEntry entry) =>
              normalized.isEmpty || '${entry.text}\n${entry.html}'.toLowerCase().contains(normalized))
          .toList(growable: false);
      if (_disposed || generation != _generation) return;
      final List<ClipboardHistoryEntry> page = pinned.skip(_offset).take(limit + 1).toList();
      if (page.length < limit + 1) {
        page.addAll(await ClipboardHistoryStore.loadPaged(
          offset: (_offset - pinned.length).clamp(0, 1000000),
          limit: limit + 1 - page.length,
          query: query,
        ));
      }
      if (_disposed || generation != _generation) return;
      _hasMore = page.length > limit;
      if (_hasMore) page.removeLast();
      _offset += page.length;
      for (final ClipboardHistoryEntry entry in page) {
        if (_entries.containsKey(entry.id)) continue;
        _entries[entry.id] = entry;
        _items.add(_item(entry));
      }
      _loading = false;
      _render();
    } catch (error) {
      if (_disposed || generation != _generation) return;
      _loading = false;
      onFrame(PluginRenderFrame.errorFrame('Could not load clipboard history: $error'));
    }
  }

  void _render() {
    onFrame(PluginRenderFrame(
      view: PluginViewType.list,
      items: List<PluginItem>.of(_items),
      gridColumns: 3,
      gridAspectRatio: 1,
      detailMarkdown: '',
      emptyText: 'No clipboard history',
      rev: 0,
      placeholder: 'clb [search clipboard history]',
      previewEnabled: true,
      loading: _loading,
      hasMore: _hasMore,
      empty: PluginEmptyState(
        icon: 'clipboard',
        title: _query.trim().isEmpty ? 'No clipboard history' : 'No matching clipboard items',
        hint: _query.trim().isEmpty
            ? 'Copy text or images while Clipboard History is enabled in Tabame.'
            : 'Try another search.',
      ),
    ));
  }

  PluginItem _item(ClipboardHistoryEntry entry) {
    final bool image = entry.type == ClipboardHistoryType.image;
    final String kind = image
        ? 'IMAGE'
        : entry.type == ClipboardHistoryType.richText
            ? 'RICH TEXT'
            : 'TEXT';
    final int length = entry.textLength ?? entry.text.length;
    final String compact = entry.text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final String title = compact.length > 52 ? '${compact.substring(0, 51)}…' : compact;
    final String preview = entry.text.length > 400 ? entry.text.substring(0, 400) : entry.text;
    // Indentation keeps clipboard content literal, including embedded backticks.
    final String markdown = image
        ? entry.imagePath.isEmpty
            ? '## Image clipboard item\n\nThe cached image is unavailable.'
            : '## Image clipboard item\n\n![Clipboard image](${File(entry.imagePath).absolute.uri})'
        : '## Clipboard preview\n\n${preview.split('\n').map((String line) => '    $line').join('\n')}'
            '${length > preview.length ? '\n\n> Preview is bounded; Copy restores the complete item.' : ''}';
    final List<Map<String, dynamic>> actions = <Map<String, dynamic>>[
      <String, dynamic>{'id': 'copy', 'title': 'Copy', 'icon': 'copy', 'shortcut': 'ctrl+shift+c'},
      if (image && entry.imagePath.isNotEmpty) ...<Map<String, dynamic>>[
        <String, dynamic>{'id': 'copy_file', 'title': 'Copy File', 'icon': 'file'},
        <String, dynamic>{'id': 'open_location', 'title': 'Open File Location', 'icon': 'folder'},
      ],
    ];
    return PluginItem.fromJson(<String, dynamic>{
      'id': entry.id,
      'title': image
          ? 'Image clipboard item'
          : title.isEmpty
              ? '(empty text)'
              : title,
      'subtitle': image ? kind : '$kind · $length chars',
      'icon': image ? 'image' : 'clipboard',
      'accessories': <Map<String, dynamic>>[
        if (entry.pinned) <String, dynamic>{'text': 'PINNED'}
      ],
      'actions': actions,
      'preview': <String, dynamic>{
        'markdown': markdown,
        'metadata': <Map<String, dynamic>>[
          <String, dynamic>{'label': 'Type', 'text': kind, 'icon': 'clipboard'},
          if (!image) <String, dynamic>{'label': 'Size', 'text': '$length characters', 'icon': 'file'},
          <String, dynamic>{
            'label': 'Saved',
            'text': entry.createdAt.toLocal().toString().split('.').first,
            'icon': 'calendar'
          },
          <String, dynamic>{'label': 'Action', 'text': 'Copy the full original', 'actions': actions},
        ],
      },
    }, _items.length);
  }

  Future<void> _act(ClipboardHistoryEntry entry, String action) async {
    try {
      if (action == 'default' || action == 'copy') {
        final bool copied = await ClipboardHistoryStore.copyById(entry.id);
        if (!_disposed) _toast(copied ? 'Copied to clipboard' : 'Could not copy clipboard item', error: !copied);
      } else if (action == 'copy_file' || action == 'open_location') {
        if (entry.imagePath.isEmpty || !await File(entry.imagePath).exists()) {
          if (!_disposed) _toast('The cached image file is unavailable', error: true);
          return;
        }
        if (_disposed) return;
        onCommand(action == 'copy_file'
            ? PluginCommand(name: 'copyfile', data: <String, dynamic>{'path': entry.imagePath})
            : PluginCommand(name: 'open', url: p.dirname(entry.imagePath)));
      }
    } catch (error) {
      if (!_disposed) _toast('Clipboard action failed: $error', error: true);
    }
  }

  void _toast(String text, {bool error = false}) {
    onCommand(PluginCommand(name: 'toast', text: text, data: <String, dynamic>{'style': error ? 'error' : 'success'}));
  }
}
