import 'dart:convert';
import 'dart:ui' show Color;

/// Version of the host↔plugin protocol, reported to plugins in `init`.
/// 2 = commands, forms, back-stack, tab, metadata, theme handshake.
const int pluginProtocolVersion = 2;

/// The layout a plugin render frame requests.
enum PluginViewType { list, grid, detail, form }

/// Parses a `#RGB` / `#RRGGBB` / `#AARRGGBB` string from plugin JSON into a
/// [Color]. Returns null for anything else, so a bad value degrades to the
/// theme default instead of erroring.
Color? parsePluginColor(Object? value) {
  if (value is! String) return null;
  String hex = value.trim();
  if (!hex.startsWith('#')) return null;
  hex = hex.substring(1);
  if (hex.length == 3) hex = hex.split('').map((String c) => '$c$c').join();
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) return null;
  final int? argb = int.tryParse(hex, radix: 16);
  return argb == null ? null : Color(argb);
}

/// Formats a [Color] as the `#RRGGBB` string plugins receive in the `init`
/// theme handshake (alpha is dropped — theme colors are opaque).
String pluginColorToHex(Color color) {
  final int argb = color.toARGB32();
  return '#${(argb & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';
}

PluginViewType _viewFromString(String? value) {
  switch (value) {
    case 'grid':
      return PluginViewType.grid;
    case 'detail':
      return PluginViewType.detail;
    case 'form':
      return PluginViewType.form;
    case 'list':
    default:
      return PluginViewType.list;
  }
}

/// A trailing chip shown on a list/grid item (e.g. a country code, a shortcut).
class PluginAccessory {
  const PluginAccessory({required this.text, this.color, this.icon});

  final String text;

  /// Optional tint (`#RRGGBB`) — status badges, tag colors. Falls back to the
  /// theme accent when absent.
  final Color? color;

  /// Optional icon name (see `plugin_icons.dart`).
  final String? icon;

  static PluginAccessory? fromJson(Object? json) {
    if (json is String) return PluginAccessory(text: json);
    if (json is Map) {
      final Object? text = json['text'];
      final Object? icon = json['icon'];
      if (text is String) {
        return PluginAccessory(
          text: text,
          color: parsePluginColor(json['color']),
          icon: icon is String ? icon : null,
        );
      }
    }
    return null;
  }
}

/// One row of the structured key-value pane shown next to (or instead of)
/// preview/detail markdown — status, assignee, dates, links.
class PluginMetadataEntry {
  const PluginMetadataEntry({
    required this.label,
    required this.text,
    this.color,
    this.icon,
    this.url,
    this.separator = false,
    this.sparkline,
  });

  final String label;
  final String text;

  /// Optional tint for the value text / dot / sparkline.
  final Color? color;

  /// Optional icon name shown before the value.
  final String? icon;

  /// When set, the value renders as a link and opens this on click.
  final String? url;

  /// A `{"separator": true}` entry renders as a thin divider instead of a row.
  final bool separator;

  /// Optional inline mini-chart values, drawn before the value text.
  final List<double>? sparkline;

  static PluginMetadataEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    if (json['separator'] == true) return const PluginMetadataEntry(label: '', text: '', separator: true);
    final Object? label = json['label'];
    final Object? text = json['text'];
    final Object? rawSparkline = json['sparkline'];
    List<double>? sparkline;
    if (rawSparkline is List) {
      sparkline = rawSparkline.whereType<num>().map((num n) => n.toDouble()).toList(growable: false);
      if (sparkline.length < 2) sparkline = null;
    }
    if (text is! String && sparkline == null) return null;
    final Object? icon = json['icon'];
    final Object? url = json['url'];
    return PluginMetadataEntry(
      label: label is String ? label : '',
      text: text is String ? text : '',
      color: parsePluginColor(json['color']),
      icon: icon is String ? icon : null,
      url: url is String ? url : null,
      sparkline: sparkline,
    );
  }

  static List<PluginMetadataEntry> listFromJson(Object? json) {
    if (json is! List) return const <PluginMetadataEntry>[];
    return json.map(fromJson).whereType<PluginMetadataEntry>().toList(growable: false);
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
    required this.previewMetadata,
    this.tileColor,
    this.section,
    this.progress,
    this.subtitleLines = 1,
  });

  final String id;
  final String title;
  final String subtitle;
  final String? icon;
  final List<PluginAccessory> accessories;
  final List<PluginAction> actions;

  /// Markdown shown in the preview pane while this item is selected.
  final String? previewMarkdown;

  /// Structured key-value rows shown under the preview markdown.
  final List<PluginMetadataEntry> previewMetadata;

  /// Grid view only: fills the tile with this color (color/theme pickers).
  final Color? tileColor;

  /// List view only: items are grouped under slim headers whenever this value
  /// changes from the previous item's.
  final String? section;

  /// 0..1 renders a thin progress bar under the row (downloads, timers).
  final double? progress;

  /// How many lines the subtitle may wrap to (1–3, from `"lines"`).
  final int subtitleLines;

  static PluginItem fromJson(Map<String, dynamic> json, int index) {
    final Object? rawId = json['id'];
    final Object? rawAccessories = json['accessories'];
    final Object? rawActions = json['actions'];
    final Object? rawPreview = json['preview'];
    final Object? rawSection = json['section'];
    final Object? rawProgress = json['progress'];
    final Object? rawLines = json['lines'];

    String? previewMarkdown;
    List<PluginMetadataEntry> previewMetadata = const <PluginMetadataEntry>[];
    if (rawPreview is Map) {
      final Object? md = rawPreview['markdown'];
      if (md is String) previewMarkdown = md;
      previewMetadata = PluginMetadataEntry.listFromJson(rawPreview['metadata']);
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
      previewMetadata: previewMetadata,
      tileColor: parsePluginColor(json['tileColor']),
      section: rawSection is String && rawSection.trim().isNotEmpty ? rawSection.trim() : null,
      progress: rawProgress is num ? rawProgress.toDouble().clamp(0.0, 1.0) : null,
      subtitleLines: rawLines is num ? rawLines.toInt().clamp(1, 3) : 1,
    );
  }
}

/// One choice in a dropdown form field.
class PluginFormOption {
  const PluginFormOption({required this.value, required this.label});
  final String value;
  final String label;

  static PluginFormOption? fromJson(Object? json) {
    if (json is String) return PluginFormOption(value: json, label: json);
    if (json is Map) {
      final Object? value = json['value'];
      if (value is! String) return null;
      final Object? label = json['label'];
      return PluginFormOption(value: value, label: label is String ? label : value);
    }
    return null;
  }
}

/// One input in a `form` view: `text`, `password`, `textarea`, `dropdown`, or
/// `checkbox`.
class PluginFormField {
  const PluginFormField({
    required this.id,
    required this.type,
    required this.label,
    required this.placeholder,
    required this.value,
    required this.options,
  });

  final String id;
  final String type;
  final String label;
  final String placeholder;

  /// Initial value: a String for text-like fields and dropdowns, a bool for
  /// checkboxes.
  final Object? value;

  /// Dropdown choices; empty for other types.
  final List<PluginFormOption> options;

  static const Set<String> knownTypes = <String>{'text', 'password', 'textarea', 'dropdown', 'checkbox'};

  bool get isTextLike => type == 'text' || type == 'password' || type == 'textarea';

  static PluginFormField? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? id = json['id'];
    if (id is! String || id.trim().isEmpty) return null;
    final Object? type = json['type'];
    final String resolvedType = type is String && knownTypes.contains(type) ? type : 'text';
    final Object? label = json['label'];
    final Object? placeholder = json['placeholder'];
    final Object? rawOptions = json['options'];
    final Object? value = json['value'];
    return PluginFormField(
      id: id,
      type: resolvedType,
      label: label is String ? label : id,
      placeholder: placeholder is String ? placeholder : '',
      value: value is String || value is bool ? value : null,
      options: rawOptions is List
          ? rawOptions.map(PluginFormOption.fromJson).whereType<PluginFormOption>().toList(growable: false)
          : const <PluginFormOption>[],
    );
  }
}

/// The `form` view payload: a titled set of input fields plus a submit button.
/// Submitting sends `{"type":"submit","values":{...}}` back to the plugin.
class PluginForm {
  const PluginForm({required this.title, required this.submitLabel, required this.fields});

  final String title;
  final String submitLabel;
  final List<PluginFormField> fields;

  static PluginForm? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? title = json['title'];
    final Object? submitLabel = json['submitLabel'];
    final Object? rawFields = json['fields'];
    final List<PluginFormField> fields = rawFields is List
        ? rawFields.map(PluginFormField.fromJson).whereType<PluginFormField>().toList(growable: false)
        : const <PluginFormField>[];
    if (fields.isEmpty) return null;
    return PluginForm(
      title: title is String ? title : '',
      submitLabel: submitLabel is String && submitLabel.trim().isNotEmpty ? submitLabel : 'Submit',
      fields: fields,
    );
  }
}

/// Custom empty state (`"empty": {"icon","title","hint"}`), richer than the
/// plain `emptyText` string it supersedes.
class PluginEmptyState {
  const PluginEmptyState({required this.icon, required this.title, required this.hint});

  final String? icon;
  final String title;
  final String hint;

  static PluginEmptyState? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? icon = json['icon'];
    final Object? title = json['title'];
    final Object? hint = json['hint'];
    if (title is! String && hint is! String) return null;
    return PluginEmptyState(
      icon: icon is String ? icon : null,
      title: title is String ? title : '',
      hint: hint is String ? hint : '',
    );
  }
}

/// A side-effect request from the plugin (`{"type":"command", ...}`): instead
/// of shelling out to `clip`/`start` itself, a plugin asks the host to copy,
/// paste, open a URL, hide the launcher, or show a toast.
class PluginCommand {
  const PluginCommand({required this.name, this.text, this.url});

  /// `copy` | `paste` | `open` | `hide` | `toast`.
  final String name;

  /// Payload for `copy` / `paste` / `toast`.
  final String? text;

  /// Target for `open` — a URL or a file/folder path.
  final String? url;

  static const Set<String> knownCommands = <String>{'copy', 'paste', 'open', 'hide', 'toast', 'setquery'};

  /// Parses a decoded `{"type":"command"}` message. Returns null when the
  /// `command` field is missing or not a string (unknown-but-well-formed names
  /// are kept so the host can report them to the debug console).
  static PluginCommand? fromJson(Map<String, dynamic> json) {
    final Object? name = json['command'];
    if (name is! String || name.trim().isEmpty) return null;
    final Object? text = json['text'];
    final Object? url = json['url'] ?? json['path'];
    return PluginCommand(
      name: name.trim().toLowerCase(),
      text: text is String ? text : null,
      url: url is String ? url : null,
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
    this.detailMetadata = const <PluginMetadataEntry>[],
    this.detailWide = false,
    required this.previewEnabled,
    this.previewWide = true,
    required this.loading,
    required this.emptyText,
    required this.rev,
    this.error,
    this.form,
    this.loadingProgress,
    this.placeholder,
    this.empty,
    this.canGoBack = false,
  });

  final PluginViewType view;
  final List<PluginItem> items;
  final int gridColumns;
  final double gridAspectRatio;

  /// Full-width markdown, used when [view] is [PluginView.detail].
  final String? detailMarkdown;

  /// Structured key-value rows shown under [detailMarkdown] in detail view.
  final List<PluginMetadataEntry> detailMetadata;

  /// Detail view: widen the launcher window (like the split preview does) so
  /// long-form markdown gets room to breathe. From `detail.wide`.
  final bool detailWide;

  /// Whether the split preview pane is shown (list/grid views only).
  final bool previewEnabled;

  /// Whether an enabled preview should widen the launcher window. From
  /// `preview.wide` (default true). When false, the preview pane still renders
  /// but the window keeps its normal size. Ignored unless [previewEnabled].
  final bool previewWide;

  final bool loading;
  final String emptyText;

  /// Echoed generation counter; older frames are dropped by the host.
  final int rev;

  /// Non-null when this frame reports a plugin-side failure.
  final String? error;

  /// The form definition when [view] is [PluginViewType.form].
  final PluginForm? form;

  /// 0..1 makes the loading spinner determinate.
  final double? loadingProgress;

  /// Replaces the launcher's search-field hint text while this frame is shown.
  final String? placeholder;

  /// Richer empty state; falls back to [emptyText] when absent.
  final PluginEmptyState? empty;

  /// When true, Escape sends `{"type":"back"}` to the plugin (which should
  /// render its previous screen) instead of exiting the plugin. Frames at the
  /// plugin's root should leave this false so Escape exits as usual.
  final bool canGoBack;

  bool get hasPreview => previewEnabled && view != PluginViewType.detail && view != PluginViewType.form;

  /// Whether this frame asks for the widened launcher window: a split preview
  /// pane that opted into widening, or a detail view marked `wide`.
  bool get wantsWideWindow => (hasPreview && previewWide) || (view == PluginViewType.detail && detailWide);

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
    List<PluginMetadataEntry> detailMetadata = const <PluginMetadataEntry>[];
    bool detailWide = false;
    if (detail is Map) {
      final Object? md = detail['markdown'];
      if (md is String) detailMarkdown = md;
      detailMetadata = PluginMetadataEntry.listFromJson(detail['metadata']);
      detailWide = detail['wide'] == true;
    } else if (detail is String) {
      detailMarkdown = detail;
    }

    bool previewEnabled = false;
    bool previewWide = true;
    if (preview is Map) {
      previewEnabled = preview['enabled'] == true;
      // Opt out of the widened window with `"wide": false`; anything else
      // (absent, true) keeps the historical widen-on-preview behavior.
      previewWide = preview['wide'] != false;
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
    final Object? placeholder = json['placeholder'];

    // `loading` is either a bool or `{"progress": 0..1}` for a determinate bar.
    final Object? rawLoading = json['loading'];
    bool loading = rawLoading == true;
    double? loadingProgress;
    if (rawLoading is Map) {
      loading = true;
      final Object? progress = rawLoading['progress'];
      if (progress is num) loadingProgress = progress.toDouble().clamp(0.0, 1.0);
    }

    return PluginRenderFrame(
      view: _viewFromString(json['view'] as String?),
      items: items,
      gridColumns: gridColumns,
      gridAspectRatio: gridAspectRatio,
      detailMarkdown: detailMarkdown,
      detailMetadata: detailMetadata,
      detailWide: detailWide,
      previewEnabled: previewEnabled,
      previewWide: previewWide,
      loading: loading,
      loadingProgress: loadingProgress,
      emptyText: emptyText is String ? emptyText : 'No results',
      rev: rev is num ? rev.toInt() : 0,
      form: PluginForm.fromJson(json['form']),
      placeholder: placeholder is String && placeholder.trim().isNotEmpty ? placeholder : null,
      empty: PluginEmptyState.fromJson(json['empty']),
      canGoBack: json['canGoBack'] == true,
    );
  }
}
