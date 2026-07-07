import 'dart:convert';

/// The layout a plugin render frame requests.
enum PluginViewType { list, grid, detail }

PluginViewType _viewFromString(String? value) {
  switch (value) {
    case 'grid':
      return PluginViewType.grid;
    case 'detail':
      return PluginViewType.detail;
    case 'list':
    default:
      return PluginViewType.list;
  }
}

/// A trailing chip shown on a list/grid item (e.g. a country code, a shortcut).
class PluginAccessory {
  const PluginAccessory({required this.text});
  final String text;

  static PluginAccessory? fromJson(Object? json) {
    if (json is String) return PluginAccessory(text: json);
    if (json is Map) {
      final Object? text = json['text'];
      if (text is String) return PluginAccessory(text: text);
    }
    return null;
  }
}

/// One entry in an item's Ctrl+K action menu.
class PluginAction {
  const PluginAction({required this.id, required this.title, this.icon});
  final String id;
  final String title;
  final String? icon;

  static PluginAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? id = json['id'];
    final Object? title = json['title'];
    if (id is! String || title is! String) return null;
    final Object? icon = json['icon'];
    return PluginAction(id: id, title: title, icon: icon is String ? icon : null);
  }
}

/// A single row/tile emitted by the plugin.
class PluginItem {
  const PluginItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.accessories,
    required this.actions,
    required this.previewMarkdown,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? icon;
  final List<PluginAccessory> accessories;
  final List<PluginAction> actions;

  /// Markdown shown in the preview pane while this item is selected.
  final String? previewMarkdown;

  static PluginItem fromJson(Map<String, dynamic> json, int index) {
    final Object? rawId = json['id'];
    final Object? rawAccessories = json['accessories'];
    final Object? rawActions = json['actions'];
    final Object? rawPreview = json['preview'];

    String? previewMarkdown;
    if (rawPreview is Map) {
      final Object? md = rawPreview['markdown'];
      if (md is String) previewMarkdown = md;
    } else if (rawPreview is String) {
      previewMarkdown = rawPreview;
    }

    return PluginItem(
      id: rawId is String ? rawId : (rawId?.toString() ?? 'item-$index'),
      title: json['title'] is String ? json['title'] as String : '',
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : '',
      icon: json['icon'] is String ? json['icon'] as String : null,
      accessories: rawAccessories is List
          ? rawAccessories
              .map(PluginAccessory.fromJson)
              .whereType<PluginAccessory>()
              .toList(growable: false)
          : const <PluginAccessory>[],
      actions: rawActions is List
          ? rawActions.map(PluginAction.fromJson).whereType<PluginAction>().toList(growable: false)
          : const <PluginAction>[],
      previewMarkdown: previewMarkdown,
    );
  }
}

/// A full description of the launcher UI at one point in time. The plugin sends
/// a new frame whenever it wants to change what is shown.
class PluginRenderFrame {
  const PluginRenderFrame({
    required this.view,
    required this.items,
    required this.gridColumns,
    required this.gridAspectRatio,
    required this.detailMarkdown,
    required this.previewEnabled,
    required this.loading,
    required this.emptyText,
    required this.rev,
    this.error,
  });

  final PluginViewType view;
  final List<PluginItem> items;
  final int gridColumns;
  final double gridAspectRatio;

  /// Full-width markdown, used when [view] is [PluginView.detail].
  final String? detailMarkdown;

  /// Whether the split preview pane is shown (list/grid views only).
  final bool previewEnabled;

  final bool loading;
  final String emptyText;

  /// Echoed generation counter; older frames are dropped by the host.
  final int rev;

  /// Non-null when this frame reports a plugin-side failure.
  final String? error;

  bool get hasPreview => previewEnabled && view != PluginViewType.detail;

  static PluginRenderFrame errorFrame(String message) => PluginRenderFrame(
        view: PluginViewType.detail,
        items: const <PluginItem>[],
        gridColumns: 4,
        gridAspectRatio: 1.0,
        detailMarkdown: '## Plugin error\n\n```\n$message\n```',
        previewEnabled: false,
        loading: false,
        emptyText: '',
        rev: 0,
        error: message,
      );

  /// Parses one line of stdout. Returns null when the line is not a render
  /// frame (blank lines, plugin log output, or malformed JSON).
  static PluginRenderFrame? tryParseLine(String line) {
    final String trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
    final Object? decoded;
    try {
      decoded = jsonDecode(trimmed);
    } catch (_) {
      return null;
    }
    if (decoded is! Map<String, dynamic>) return null;
    if (decoded['type'] != 'render') return null;
    return fromJson(decoded);
  }

  static PluginRenderFrame fromJson(Map<String, dynamic> json) {
    final Object? rawItems = json['items'];
    final Object? grid = json['grid'];
    final Object? detail = json['detail'];
    final Object? preview = json['preview'];

    int gridColumns = 4;
    double gridAspectRatio = 1.0;
    if (grid is Map) {
      final Object? cols = grid['columns'];
      if (cols is num) gridColumns = cols.toInt().clamp(1, 12);
      final Object? ratio = grid['aspectRatio'];
      if (ratio is num && ratio > 0) gridAspectRatio = ratio.toDouble();
    }

    String? detailMarkdown;
    if (detail is Map) {
      final Object? md = detail['markdown'];
      if (md is String) detailMarkdown = md;
    } else if (detail is String) {
      detailMarkdown = detail;
    }

    bool previewEnabled = false;
    if (preview is Map) {
      previewEnabled = preview['enabled'] == true;
    } else if (preview is bool) {
      previewEnabled = preview;
    }

    final List<PluginItem> items = <PluginItem>[];
    if (rawItems is List) {
      for (int i = 0; i < rawItems.length; i++) {
        final Object? raw = rawItems[i];
        if (raw is Map<String, dynamic>) {
          items.add(PluginItem.fromJson(raw, i));
        } else if (raw is Map) {
          items.add(PluginItem.fromJson(raw.cast<String, dynamic>(), i));
        }
      }
    }

    final Object? rev = json['rev'];
    final Object? emptyText = json['emptyText'];

    return PluginRenderFrame(
      view: _viewFromString(json['view'] as String?),
      items: items,
      gridColumns: gridColumns,
      gridAspectRatio: gridAspectRatio,
      detailMarkdown: detailMarkdown,
      previewEnabled: previewEnabled,
      loading: json['loading'] == true,
      emptyText: emptyText is String ? emptyText : 'No results',
      rev: rev is num ? rev.toInt() : 0,
    );
  }
}
