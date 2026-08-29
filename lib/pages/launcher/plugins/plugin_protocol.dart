// ignore_for_file: always_specify_types

import 'dart:convert';
import 'dart:ui' show Color;

/// Version of the host↔plugin protocol, reported to plugins in `init`.
/// 2 = commands, forms, back-stack, tab, metadata, theme handshake.
/// 3 = frame-level actions + shortcuts + confirm/destructive, `selectId`,
///     `hasMore`/`loadMore` pagination, `inputMode: "submit"`, streaming
///     `detail.append`, form v2 (validation, number/date/file/tags fields,
///     buttons, change events), storage/clipboardRead/notify/background
///     commands, and toast styles.
/// 4 = metadata image URLs.
/// 5 = metadata action buttons, image widths, and preview-side images.
/// 6 = chat view for message-oriented plugins.
/// 7 = bulk selection, table/tree/timeline/chart views, cancellable operations,
///     action parameters, and host-mediated loopback OAuth.
/// 8 = composite dashboard frames with stacked or tabbed sub-views.
/// 9 = page identity/history, scoped events, richer conditional forms, and
///     kanban/diff/log views.
/// 10 = calendar/agenda and gallery/media-browser views.
/// 11 = bottom-right `floatingAction` buttons.
/// 12 = chat typing/status text and chat history affordances.
/// 13 = toolbars, configurable tables, resizable previews, file drops,
///      inline editing, banners, skeletons, media controls, async form
///      validation, richer form inputs, and production chart controls.
/// 14 = host-mediated image and file clipboard commands.
const int pluginProtocolVersion = 14;

/// The layout a plugin render frame requests.
enum PluginViewType {
  list,
  grid,
  detail,
  chat,
  form,
  table,
  tree,
  timeline,
  chart,
  operation,
  dashboard,
  kanban,
  diff,
  log,
  calendar,
  gallery,
}

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
    case 'chat':
      return PluginViewType.chat;
    case 'form':
      return PluginViewType.form;
    case 'table':
      return PluginViewType.table;
    case 'tree':
      return PluginViewType.tree;
    case 'timeline':
      return PluginViewType.timeline;
    case 'chart':
      return PluginViewType.chart;
    case 'operation':
      return PluginViewType.operation;
    case 'dashboard':
      return PluginViewType.dashboard;
    case 'kanban':
      return PluginViewType.kanban;
    case 'diff':
      return PluginViewType.diff;
    case 'log':
      return PluginViewType.log;
    case 'calendar':
      return PluginViewType.calendar;
    case 'gallery':
      return PluginViewType.gallery;
    case 'list':
    default:
      return PluginViewType.list;
  }
}

/// Stable page identity and lightweight host-side history hints. Plugins still
/// own navigation and render the destination frame; the host uses this data to
/// restore selection/scroll/form state and to render breadcrumbs.
class PluginPageInfo {
  const PluginPageInfo({
    required this.id,
    required this.title,
    required this.breadcrumbs,
    this.history = 'none',
    this.preserveState = true,
  });

  final String id;
  final String title;
  final List<PluginBreadcrumb> breadcrumbs;
  final String history;
  final bool preserveState;

  static PluginPageInfo? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || (json['id'] as String).trim().isEmpty) return null;
    final Object? rawHistory = json['history'];
    final String history = rawHistory == 'push' || rawHistory == 'replace' ? rawHistory as String : 'none';
    final Object? rawTitle = json['title'];
    return PluginPageInfo(
      id: (json['id'] as String).trim(),
      title: rawTitle is String ? rawTitle.trim() : '',
      breadcrumbs: PluginBreadcrumb.listFromJson(json['breadcrumbs'] ?? json['breadcrumb']),
      history: history,
      preserveState: json['preserveState'] != false,
    );
  }
}

/// One clickable ancestor in a page breadcrumb trail.
class PluginBreadcrumb {
  const PluginBreadcrumb({required this.id, required this.label});

  final String id;
  final String label;

  static PluginBreadcrumb? fromJson(Object? json) {
    if (json is String && json.trim().isNotEmpty) return PluginBreadcrumb(id: json.trim(), label: json.trim());
    if (json is! Map || json['id'] is! String) return null;
    final String id = (json['id'] as String).trim();
    if (id.isEmpty) return null;
    final Object? label = json['label'];
    return PluginBreadcrumb(id: id, label: label is String && label.trim().isNotEmpty ? label.trim() : id);
  }

  static List<PluginBreadcrumb> listFromJson(Object? json) => json is List
      ? json.map(PluginBreadcrumb.fromJson).whereType<PluginBreadcrumb>().toList(growable: false)
      : const <PluginBreadcrumb>[];
}

/// Common source address attached to plugin UI events. Old plugins can ignore
/// these additive fields; v9 plugins can distinguish nested dashboard panels
/// and multiple interactive elements without encoding scope into item ids.
class PluginEventScope {
  const PluginEventScope({this.pageId, this.panelId, this.elementId});

  final String? pageId;
  final String? panelId;
  final String? elementId;

  String get key => '${pageId ?? ''}|${panelId ?? ''}|${elementId ?? ''}';

  Map<String, Object?> get fields => <String, Object?>{
        if (pageId != null) 'pageId': pageId,
        if (panelId != null) 'panelId': panelId,
        if (elementId != null) 'elementId': elementId,
      };
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

/// A compact quoted-message preview rendered above a chat message.
class PluginReplyPreview {
  const PluginReplyPreview({required this.author, required this.text, this.icon});

  final String author;
  final String text;
  final String? icon;

  static PluginReplyPreview? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? author = json['author'];
    final Object? text = json['text'];
    if (author is! String || text is! String || author.trim().isEmpty || text.trim().isEmpty) return null;
    final Object? icon = json['icon'];
    return PluginReplyPreview(
      author: author.trim(),
      text: text.trim(),
      icon: icon is String && icon.trim().isNotEmpty ? icon.trim() : null,
    );
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
    this.image,
    this.imageWidth,
    this.height,
    this.url,
    this.separator = false,
    this.sparkline,
    this.actions = const <PluginAction>[],
  });

  final String label;
  final String text;

  /// Optional tint for the value text / dot / sparkline.
  final Color? color;

  /// Optional icon name shown before the value.
  final String? icon;

  /// Optional remote raster image shown above the value. Only HTTP(S) URLs
  /// are accepted so malformed or local values safely degrade to text.
  final String? image;

  /// Display width of [image], in logical pixels.
  final double? imageWidth;

  /// Display height of [image], in logical pixels.
  final double? height;

  /// When set, the value renders as a link and opens this on click.
  final String? url;

  /// A `{"separator": true}` entry renders as a thin divider instead of a row.
  final bool separator;

  /// Optional inline mini-chart values, drawn before the value text.
  final List<double>? sparkline;

  /// Clickable actions rendered as buttons below the metadata value.
  final List<PluginAction> actions;

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
    final Object? image = json['image'];
    final Object? imageWidth = json['width'];
    final Object? imageHeight = json['height'];
    final Object? url = json['url'];
    final String? imageUrl = image is String && _isHttpUrl(image) ? image.trim() : null;
    return PluginMetadataEntry(
      label: label is String ? label : '',
      text: text is String ? text : '',
      color: parsePluginColor(json['color']),
      icon: icon is String ? icon : null,
      image: imageUrl,
      imageWidth: imageUrl != null && imageWidth is num ? imageWidth.toDouble().clamp(48.0, 280.0) : null,
      height: imageUrl != null && imageHeight is num ? imageHeight.toDouble().clamp(48.0, 420.0) : null,
      url: url is String ? url : null,
      sparkline: sparkline,
      actions: PluginAction.listFromJson(json['actions']),
    );
  }

  static bool _isHttpUrl(String value) {
    final Uri? uri = Uri.tryParse(value.trim());
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  static List<PluginMetadataEntry> listFromJson(Object? json) {
    if (json is! List) return const <PluginMetadataEntry>[];
    return json.map(fromJson).whereType<PluginMetadataEntry>().toList(growable: false);
  }
}

/// An "are you sure?" gate on an action (`"confirm": true` or
/// `{"title","message","confirmLabel"}`). The host shows the dialog and only
/// forwards the action to the plugin when the user accepts.
class PluginConfirm {
  const PluginConfirm({required this.title, required this.message, required this.confirmLabel});

  final String title;
  final String message;
  final String confirmLabel;

  static PluginConfirm? fromJson(Object? json) {
    if (json == true) return const PluginConfirm(title: 'Are you sure?', message: '', confirmLabel: 'Confirm');
    if (json is! Map) return null;
    final Object? title = json['title'];
    final Object? message = json['message'];
    final Object? confirmLabel = json['confirmLabel'];
    return PluginConfirm(
      title: title is String && title.trim().isNotEmpty ? title : 'Are you sure?',
      message: message is String ? message : '',
      confirmLabel: confirmLabel is String && confirmLabel.trim().isNotEmpty ? confirmLabel : 'Confirm',
    );
  }
}

/// One entry in an item's (or the frame's) Ctrl+K action menu.
class PluginAction {
  const PluginAction({
    required this.id,
    required this.title,
    this.icon,
    this.shortcut,
    this.destructive = false,
    this.confirm,
    this.parameters = const <PluginFormField>[],
  });

  final String id;
  final String title;
  final String? icon;

  /// Optional keyboard shortcut (e.g. `"ctrl+shift+c"`) that fires the action
  /// directly, without opening the Ctrl+K palette.
  final String? shortcut;

  /// Renders the action in the palette's danger tint (deletes, sign-outs).
  final bool destructive;

  /// When set, the host asks for confirmation before forwarding the action.
  final PluginConfirm? confirm;

  /// Optional compact form collected before this action is dispatched. This is
  /// deliberately the same field grammar as a full plugin form, allowing an
  /// action such as "Deploy" to ask for a target or change note in context.
  final List<PluginFormField> parameters;

  static PluginAction? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? id = json['id'];
    final Object? title = json['title'];
    if (id is! String || title is! String) return null;
    final Object? icon = json['icon'];
    final Object? shortcut = json['shortcut'];
    return PluginAction(
      id: id,
      title: title,
      icon: icon is String ? icon : null,
      shortcut: shortcut is String && shortcut.trim().isNotEmpty ? shortcut.trim().toLowerCase() : null,
      destructive: json['destructive'] == true,
      confirm: PluginConfirm.fromJson(json['confirm']),
      parameters: json['parameters'] is List
          ? (json['parameters'] as List)
              .map<PluginFormField?>(PluginFormField.fromJson)
              .whereType<PluginFormField>()
              .toList(growable: false)
          : const <PluginFormField>[],
    );
  }

  static List<PluginAction> listFromJson(Object? json) {
    if (json is! List) return const <PluginAction>[];
    return json.map(fromJson).whereType<PluginAction>().toList(growable: false);
  }

  /// Parses either one action object or an array of actions. This is used by
  /// `floatingAction`, whose common one-button form stays pleasantly compact
  /// while still allowing several bottom-right buttons when needed.
  static List<PluginAction> listOrSingleFromJson(Object? json) {
    if (json is List) return listFromJson(json);
    final PluginAction? action = fromJson(json);
    return action == null ? const <PluginAction>[] : <PluginAction>[action];
  }
}

/// One column in a `table` frame. An item supplies its values via `cells`.
class PluginTableColumn {
  const PluginTableColumn({
    required this.id,
    required this.label,
    this.width,
    this.minWidth = 72,
    this.maxWidth = 420,
    this.align = 'start',
    this.sortable = false,
    this.editable = false,
    this.visible = true,
  });

  final String id;
  final String label;
  final double? width;
  final double minWidth;
  final double maxWidth;
  final String align;
  final bool sortable;
  final bool editable;
  final bool visible;

  static PluginTableColumn? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String) return null;
    final String id = json['id'] as String;
    if (id.trim().isEmpty) return null;
    final Object? align = json['align'];
    final double minWidth = json['minWidth'] is num ? (json['minWidth'] as num).toDouble().clamp(48, 360) : 72;
    final double maxWidth = json['maxWidth'] is num ? (json['maxWidth'] as num).toDouble().clamp(minWidth, 720) : 420;
    return PluginTableColumn(
      id: id,
      label: json['label'] is String ? json['label'] as String : id,
      width: json['width'] is num ? (json['width'] as num).toDouble().clamp(minWidth, maxWidth) : null,
      minWidth: minWidth,
      maxWidth: maxWidth,
      align: align == 'end' || align == 'center' ? align as String : 'start',
      sortable: json['sortable'] == true,
      editable: json['editable'] == true,
      visible: json['visible'] != false,
    );
  }

  static List<PluginTableColumn> listFromJson(Object? json) => json is List
      ? json.map(PluginTableColumn.fromJson).whereType<PluginTableColumn>().toList(growable: false)
      : const <PluginTableColumn>[];
}

/// A compact choice used by toolbar filters, scope, sorting, and view toggles.
class PluginToolbarOption {
  const PluginToolbarOption({required this.value, required this.label, this.icon});

  final String value;
  final String label;
  final String? icon;

  static PluginToolbarOption? fromJson(Object? json) {
    if (json is String) return PluginToolbarOption(value: json, label: json);
    if (json is! Map || json['value'] is! String) return null;
    final String value = json['value'] as String;
    return PluginToolbarOption(
      value: value,
      label: json['label'] is String ? json['label'] as String : value,
      icon: json['icon'] is String ? json['icon'] as String : null,
    );
  }

  static List<PluginToolbarOption> listFromJson(Object? json) => json is List
      ? json.map(fromJson).whereType<PluginToolbarOption>().toList(growable: false)
      : const <PluginToolbarOption>[];
}

/// One host-rendered toolbar control. The plugin remains the source of truth;
/// changing a control sends `toolbarChange` and the next frame supplies state.
class PluginToolbarControl {
  const PluginToolbarControl({
    required this.id,
    required this.type,
    required this.label,
    required this.options,
    this.value,
    this.values = const <String>[],
    this.multiple = false,
    this.direction = 'asc',
  });

  final String id;
  final String type;
  final String label;
  final List<PluginToolbarOption> options;
  final String? value;
  final List<String> values;
  final bool multiple;
  final String direction;

  static PluginToolbarControl? fromJson(Object? json, String type, {String? fallbackId}) {
    if (json is! Map) return null;
    final Object? rawId = json['id'];
    final String id = rawId is String && rawId.trim().isNotEmpty ? rawId.trim() : (fallbackId ?? type);
    final List<PluginToolbarOption> options = PluginToolbarOption.listFromJson(json['options']);
    if (options.isEmpty) return null;
    final Object? rawValues = json['values'];
    return PluginToolbarControl(
      id: id,
      type: type,
      label: json['label'] is String ? json['label'] as String : '',
      options: options,
      value: json['value'] is String ? json['value'] as String : null,
      values: rawValues is List ? rawValues.whereType<String>().toList(growable: false) : const <String>[],
      multiple: json['multiple'] == true,
      direction: json['direction'] == 'desc' ? 'desc' : 'asc',
    );
  }

  static List<PluginToolbarControl> fromToolbarJson(Object? json) {
    if (json is! Map) return const <PluginToolbarControl>[];
    final List<PluginToolbarControl> controls = <PluginToolbarControl>[];
    final Object? filters = json['filters'];
    if (filters is List) {
      for (final Object? filter in filters) {
        final PluginToolbarControl? parsed = fromJson(filter, 'filter');
        if (parsed != null) controls.add(parsed);
      }
    }
    for (final (String, String) entry in <(String, String)>[
      ('scope', 'scope'),
      ('sort', 'sort'),
      ('view', 'view'),
    ]) {
      final PluginToolbarControl? parsed = fromJson(json[entry.$1], entry.$2, fallbackId: entry.$1);
      if (parsed != null) controls.add(parsed);
    }
    return controls;
  }
}

/// An in-context notice rendered above a plugin page.
class PluginBanner {
  const PluginBanner({
    required this.id,
    required this.style,
    required this.title,
    required this.message,
    required this.actions,
    this.icon,
    this.dismissible = false,
  });

  final String id;
  final String style;
  final String title;
  final String message;
  final String? icon;
  final bool dismissible;
  final List<PluginAction> actions;

  static PluginBanner? fromJson(Object? json, int index) {
    if (json is! Map) return null;
    final String title = json['title'] is String ? json['title'] as String : '';
    final String message = json['message'] is String ? json['message'] as String : '';
    if (title.isEmpty && message.isEmpty) return null;
    final Object? rawStyle = json['style'];
    final String style =
        const <String>{'info', 'success', 'warning', 'error'}.contains(rawStyle) ? rawStyle as String : 'info';
    return PluginBanner(
      id: json['id'] is String && (json['id'] as String).trim().isNotEmpty
          ? (json['id'] as String).trim()
          : 'banner-$index',
      style: style,
      title: title,
      message: message,
      icon: json['icon'] is String ? json['icon'] as String : null,
      dismissible: json['dismissible'] == true,
      actions: PluginAction.listFromJson(json['actions']),
    );
  }

  static List<PluginBanner> listFromJson(Object? json) {
    if (json is Map) {
      final PluginBanner? banner = fromJson(json, 0);
      return banner == null ? const <PluginBanner>[] : <PluginBanner>[banner];
    }
    if (json is! List) return const <PluginBanner>[];
    return <PluginBanner>[
      for (int index = 0; index < json.length; index++)
        if (fromJson(json[index], index) case final PluginBanner banner) banner,
    ];
  }
}

/// A page-level operating-system file drop target.
class PluginDropZone {
  const PluginDropZone({
    required this.id,
    required this.label,
    required this.hint,
    required this.extensions,
    this.multiple = true,
    this.maxFiles = 20,
  });

  final String id;
  final String label;
  final String hint;
  final List<String> extensions;
  final bool multiple;
  final int maxFiles;

  static PluginDropZone? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? rawExtensions = json['extensions'];
    return PluginDropZone(
      id: json['id'] is String && (json['id'] as String).trim().isNotEmpty ? (json['id'] as String).trim() : 'drop',
      label: json['label'] is String ? json['label'] as String : 'Drop files here',
      hint: json['hint'] is String ? json['hint'] as String : '',
      extensions: rawExtensions is List
          ? rawExtensions.whereType<String>().map((String value) => value.toLowerCase()).toList(growable: false)
          : const <String>[],
      multiple: json['multiple'] != false,
      maxFiles: json['maxFiles'] is num ? (json['maxFiles'] as num).toInt().clamp(1, 200) : 20,
    );
  }
}

/// Visual and interaction options for a chart frame.
class PluginChartOptions {
  const PluginChartOptions({
    this.type = 'line',
    this.showAxes = true,
    this.showGrid = true,
    this.showLegend = true,
    this.tooltips = true,
    this.selectableRange = false,
    this.xLabels = const <String>[],
    this.xTitle,
    this.yTitle,
    this.minY,
    this.maxY,
  });

  final String type;
  final bool showAxes;
  final bool showGrid;
  final bool showLegend;
  final bool tooltips;
  final bool selectableRange;
  final List<String> xLabels;
  final String? xTitle;
  final String? yTitle;
  final double? minY;
  final double? maxY;

  static PluginChartOptions fromJson(Object? json) {
    if (json is! Map) return const PluginChartOptions();
    final Object? rawType = json['type'];
    final Object? rawLabels = json['xLabels'];
    return PluginChartOptions(
      type: const <String>{'line', 'area', 'bar'}.contains(rawType) ? rawType as String : 'line',
      showAxes: json['showAxes'] != false,
      showGrid: json['showGrid'] != false,
      showLegend: json['showLegend'] != false,
      tooltips: json['tooltips'] != false,
      selectableRange: json['selectableRange'] == true,
      xLabels: rawLabels is List
          ? rawLabels.map((Object? value) => value?.toString() ?? '').toList(growable: false)
          : const <String>[],
      xTitle: json['xTitle'] is String ? json['xTitle'] as String : null,
      yTitle: json['yTitle'] is String ? json['yTitle'] as String : null,
      minY: json['minY'] is num ? (json['minY'] as num).toDouble() : null,
      maxY: json['maxY'] is num ? (json['maxY'] as num).toDouble() : null,
    );
  }
}

/// A selectable point series for the `chart` view.
class PluginChartSeries {
  const PluginChartSeries({required this.id, required this.label, required this.values, this.color});
  final String id;
  final String label;
  final List<double> values;
  final Color? color;

  static PluginChartSeries? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || json['values'] is! List) return null;
    final List<double> values =
        (json['values'] as List).whereType<num>().map<double>((num value) => value.toDouble()).toList();
    if (values.length < 2) return null;
    final String id = json['id'] as String;
    return PluginChartSeries(
      id: id,
      label: json['label'] is String ? json['label'] as String : id,
      values: values,
      color: parsePluginColor(json['color']),
    );
  }
}

/// Long-running work surfaced above a plugin view. The cancel control only
/// appears when the plugin explicitly declares it cancellable.
class PluginOperation {
  const PluginOperation(
      {required this.id, required this.title, this.detail = '', this.progress, this.cancellable = false});
  final String id;
  final String title;
  final String detail;
  final double? progress;
  final bool cancellable;

  static PluginOperation? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || (json['id'] as String).trim().isEmpty) return null;
    final Object? progress = json['progress'];
    return PluginOperation(
      id: json['id'] as String,
      title: json['title'] is String ? json['title'] as String : 'Working…',
      detail: json['detail'] is String ? json['detail'] as String : '',
      progress: progress is num ? progress.toDouble().clamp(0, 1) : null,
      cancellable: json['cancellable'] == true,
    );
  }
}

/// One column in a `kanban` frame. Cards are ordinary [PluginItem]s whose
/// `column` field matches this id.
class PluginKanbanColumn {
  const PluginKanbanColumn({required this.id, required this.title, this.color, this.limit});

  final String id;
  final String title;
  final Color? color;
  final int? limit;

  static PluginKanbanColumn? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || (json['id'] as String).trim().isEmpty) return null;
    final String id = (json['id'] as String).trim();
    final Object? title = json['title'];
    final Object? limit = json['limit'];
    return PluginKanbanColumn(
      id: id,
      title: title is String && title.trim().isNotEmpty ? title.trim() : id,
      color: parsePluginColor(json['color']),
      limit: limit is num ? limit.toInt().clamp(1, 9999) : null,
    );
  }

  static List<PluginKanbanColumn> listFromJson(Object? json) => json is List
      ? json.map(PluginKanbanColumn.fromJson).whereType<PluginKanbanColumn>().toList(growable: false)
      : const <PluginKanbanColumn>[];
}

/// One semantic line in a `diff` frame.
class PluginDiffLine {
  const PluginDiffLine({required this.type, required this.text, this.oldLine, this.newLine});

  final String type;
  final String text;
  final int? oldLine;
  final int? newLine;

  static PluginDiffLine? fromJson(Object? json) {
    if (json is String) return _fromText(json);
    if (json is! Map || json['text'] is! String) return null;
    final Object? rawType = json['type'];
    final String type =
        const <String>{'add', 'remove', 'context', 'header'}.contains(rawType) ? rawType as String : 'context';
    return PluginDiffLine(
      type: type,
      text: json['text'] as String,
      oldLine: json['oldLine'] is num ? (json['oldLine'] as num).toInt() : null,
      newLine: json['newLine'] is num ? (json['newLine'] as num).toInt() : null,
    );
  }

  static PluginDiffLine _fromText(String line) {
    final String type = line.startsWith('+++') || line.startsWith('---') || line.startsWith('@@')
        ? 'header'
        : line.startsWith('+')
            ? 'add'
            : line.startsWith('-')
                ? 'remove'
                : 'context';
    return PluginDiffLine(type: type, text: line);
  }

  static List<PluginDiffLine> listFromJson(Object? json) {
    if (json is String) return json.split('\n').map(_fromText).toList(growable: false);
    if (json is! List) return const <PluginDiffLine>[];
    return json.map(fromJson).whereType<PluginDiffLine>().toList(growable: false);
  }
}

/// One structured entry in a `log` frame.
class PluginLogLine {
  const PluginLogLine({
    required this.id,
    required this.text,
    required this.level,
    this.timestamp = '',
    this.source = '',
  });

  final String id;
  final String text;
  final String level;
  final String timestamp;
  final String source;

  static PluginLogLine? fromJson(Object? json, int index) {
    if (json is String) return PluginLogLine(id: 'line-$index', text: json, level: 'info');
    if (json is! Map || json['text'] is! String) return null;
    final Object? rawLevel = json['level'];
    final String level = const <String>{'trace', 'debug', 'info', 'warn', 'error', 'success'}.contains(rawLevel)
        ? rawLevel as String
        : 'info';
    return PluginLogLine(
      id: json['id']?.toString() ?? 'line-$index',
      text: json['text'] as String,
      level: level,
      timestamp: json['timestamp'] is String ? json['timestamp'] as String : '',
      source: json['source'] is String ? json['source'] as String : '',
    );
  }

  static List<PluginLogLine> listFromJson(Object? json) {
    if (json is! List) return const <PluginLogLine>[];
    final List<PluginLogLine> lines = <PluginLogLine>[];
    for (int index = 0; index < json.length; index++) {
      final PluginLogLine? line = fromJson(json[index], index);
      if (line != null) lines.add(line);
    }
    return lines;
  }
}

/// Date/time metadata attached to an item in a `calendar` frame.
class PluginCalendarItem {
  const PluginCalendarItem({
    required this.start,
    this.end,
    this.allDay = false,
    this.color,
    this.location = '',
  });

  final DateTime start;
  final DateTime? end;
  final bool allDay;
  final Color? color;
  final String location;

  static PluginCalendarItem? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? rawStart = json['start'] ?? json['date'];
    final DateTime? start = rawStart is String ? DateTime.tryParse(rawStart.trim()) : null;
    if (start == null) return null;
    final Object? rawEnd = json['end'];
    final DateTime? end = rawEnd is String ? DateTime.tryParse(rawEnd.trim()) : null;
    return PluginCalendarItem(
      start: start,
      end: end != null && !end.isBefore(start) ? end : null,
      allDay: json['allDay'] == true || !rawStart.toString().contains('T'),
      color: parsePluginColor(json['color']),
      location: json['location'] is String ? (json['location'] as String).trim() : '',
    );
  }
}

/// Thumbnail/source metadata attached to an item in a `gallery` frame.
class PluginMediaInfo {
  const PluginMediaInfo({
    required this.url,
    required this.type,
    this.thumbnail,
    this.duration = '',
    this.size = '',
    this.width,
    this.height,
  });

  final String url;
  final String type;
  final String? thumbnail;
  final String duration;
  final String size;
  final int? width;
  final int? height;

  String get displaySource => thumbnail ?? url;

  static PluginMediaInfo? fromJson(Object? json) {
    if (json is String && _isPluginMediaSource(json)) {
      return PluginMediaInfo(url: json.trim(), type: 'image');
    }
    if (json is! Map || json['url'] is! String) return null;
    final String url = (json['url'] as String).trim();
    if (!_isPluginMediaSource(url)) return null;
    final Object? rawType = json['type'];
    final String type =
        const <String>{'image', 'video', 'audio', 'file'}.contains(rawType) ? rawType as String : 'image';
    final Object? rawThumbnail = json['thumbnail'];
    final String? thumbnail = rawThumbnail is String && _isPluginMediaSource(rawThumbnail) ? rawThumbnail.trim() : null;
    final Object? rawWidth = json['width'];
    final Object? rawHeight = json['height'];
    return PluginMediaInfo(
      url: url,
      type: type,
      thumbnail: thumbnail,
      duration: json['duration'] is String ? json['duration'] as String : '',
      size: _sizeLabel(json['size']),
      width: rawWidth is num && rawWidth > 0 ? rawWidth.toInt() : null,
      height: rawHeight is num && rawHeight > 0 ? rawHeight.toInt() : null,
    );
  }

  static bool _isPluginMediaSource(String value) {
    final String source = value.trim();
    if (source.startsWith('data:image/')) return source.length <= 2 * 1024 * 1024;
    if (source.startsWith('file://')) return Uri.tryParse(source) != null;
    final Uri? uri = Uri.tryParse(source);
    return uri != null && (uri.scheme == 'http' || uri.scheme == 'https') && uri.host.isNotEmpty;
  }

  static String _sizeLabel(Object? value) {
    if (value is String) return value.trim();
    if (value is! num || value < 0) return '';
    final double bytes = value.toDouble();
    const List<String> units = <String>['B', 'KB', 'MB', 'GB', 'TB'];
    double amount = bytes;
    int unit = 0;
    while (amount >= 1024 && unit < units.length - 1) {
      amount /= 1024;
      unit++;
    }
    final String formatted = unit == 0 || amount >= 10 ? amount.toStringAsFixed(0) : amount.toStringAsFixed(1);
    return '$formatted ${units[unit]}';
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
    required this.previewDiffLines,
    this.previewImageUrl,
    this.previewImageWidth,
    this.previewDiffMode = 'unified',
    this.previewDiffOldLabel = 'Before',
    this.previewDiffNewLabel = 'After',
    this.chatImageUrls = const <String>[],
    this.tileColor,
    this.section,
    this.progress,
    this.subtitleLines = 1,
    this.cells = const <String, String>{},
    this.depth = 0,
    this.expanded = false,
    this.timestamp,
    this.column,
    this.calendar,
    this.media,
    this.reply,
    this.editableFields = const <String>{},
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

  /// Semantic lines rendered with the built-in diff widget in the preview.
  final List<PluginDiffLine> previewDiffLines;

  final String previewDiffMode;
  final String previewDiffOldLabel;
  final String previewDiffNewLabel;

  /// Optional remote raster image shown to the right of preview markdown.
  final String? previewImageUrl;

  /// Display width of [previewImageUrl], in logical pixels.
  final double? previewImageWidth;

  /// Inline image attachments rendered by the `chat` view.
  final List<String> chatImageUrls;

  /// Grid view only: fills the tile with this color (color/theme pickers).
  final Color? tileColor;

  /// List view only: items are grouped under slim headers whenever this value
  /// changes from the previous item's.
  final String? section;

  /// 0..1 renders a thin progress bar under the row (downloads, timers).
  final double? progress;

  /// How many lines the subtitle may wrap to (1–3, from `"lines"`).
  final int subtitleLines;

  /// `table` view cell values, keyed by the frame's `columns[].id`.
  final Map<String, String> cells;

  /// `tree` view nesting level and visual expansion state. Plugins remain the
  /// source of truth and receive `toggle` when the disclosure is activated.
  final int depth;
  final bool expanded;

  /// `timeline` view's leading time/status label.
  final String? timestamp;

  /// `kanban` view column id. Falls back to [section] for concise frames.
  final String? column;

  /// Date/time data for `calendar` and `agenda` rendering.
  final PluginCalendarItem? calendar;

  /// Source/thumbnail data for `gallery` and media-browser rendering.
  final PluginMediaInfo? media;

  /// Optional quoted message preview shown above a chat message.
  final PluginReplyPreview? reply;

  /// Fields that may be edited in place. Supported today: `title`, `subtitle`,
  /// and table cell ids. A bare `true` enables title/subtitle and all cells.
  final Set<String> editableFields;

  static PluginItem fromJson(Map<String, dynamic> json, int index) {
    final Object? rawId = json['id'];
    final Object? rawAccessories = json['accessories'];
    final Object? rawActions = json['actions'];
    final Object? rawPreview = json['preview'];
    final Object? rawSection = json['section'];
    final Object? rawProgress = json['progress'];
    final Object? rawLines = json['lines'];
    final Object? rawImages = json['images'];
    final Object? rawCells = json['cells'];
    final Object? rawEditable = json['editable'];
    final PluginReplyPreview? reply = PluginReplyPreview.fromJson(json['reply']);

    String? previewMarkdown;
    List<PluginMetadataEntry> previewMetadata = const <PluginMetadataEntry>[];
    List<PluginDiffLine> previewDiffLines = const <PluginDiffLine>[];
    String previewDiffMode = 'unified';
    String previewDiffOldLabel = 'Before';
    String previewDiffNewLabel = 'After';
    String? previewImageUrl;
    double? previewImageWidth;
    if (rawPreview is Map) {
      final Object? md = rawPreview['markdown'];
      if (md is String) previewMarkdown = md;
      previewMetadata = PluginMetadataEntry.listFromJson(rawPreview['metadata']);
      final Object? rawDiff = rawPreview['diff'];
      previewDiffLines = PluginDiffLine.listFromJson(rawDiff is Map ? (rawDiff['lines'] ?? rawDiff['text']) : rawDiff);
      previewDiffMode = rawDiff is Map && rawDiff['mode'] == 'split' ? 'split' : 'unified';
      previewDiffOldLabel = rawDiff is Map && rawDiff['oldLabel'] is String ? rawDiff['oldLabel'] as String : 'Before';
      previewDiffNewLabel = rawDiff is Map && rawDiff['newLabel'] is String ? rawDiff['newLabel'] as String : 'After';
      final Object? rawImage = rawPreview['image'];
      if (rawImage is Map) {
        final Object? url = rawImage['url'];
        final Object? width = rawImage['width'];
        if (url is String && PluginMetadataEntry._isHttpUrl(url)) {
          previewImageUrl = url.trim();
          previewImageWidth = width is num ? width.toDouble().clamp(48.0, 280.0) : null;
        }
      }
    } else if (rawPreview is String) {
      previewMarkdown = rawPreview;
    }
    final List<String> chatImageUrls = rawImages is List
        ? rawImages
            .whereType<String>()
            .where(PluginMetadataEntry._isHttpUrl)
            .map((String url) => url.trim())
            .toList(growable: false)
        : const <String>[];

    return PluginItem(
      id: rawId is String ? rawId : (rawId?.toString() ?? 'item-$index'),
      title: json['title'] is String ? json['title'] as String : '',
      subtitle: json['subtitle'] is String ? json['subtitle'] as String : '',
      icon: json['icon'] is String ? json['icon'] as String : null,
      accessories: rawAccessories is List
          ? rawAccessories.map(PluginAccessory.fromJson).whereType<PluginAccessory>().toList(growable: false)
          : const <PluginAccessory>[],
      actions: rawActions is List
          ? rawActions.map(PluginAction.fromJson).whereType<PluginAction>().toList(growable: false)
          : const <PluginAction>[],
      previewMarkdown: previewMarkdown,
      previewMetadata: previewMetadata,
      previewDiffLines: previewDiffLines,
      previewImageUrl: previewImageUrl,
      previewImageWidth: previewImageWidth,
      previewDiffMode: previewDiffMode,
      previewDiffOldLabel: previewDiffOldLabel,
      previewDiffNewLabel: previewDiffNewLabel,
      chatImageUrls: chatImageUrls,
      tileColor: parsePluginColor(json['tileColor']),
      section: rawSection is String && rawSection.trim().isNotEmpty ? rawSection.trim() : null,
      progress: rawProgress is num ? rawProgress.toDouble().clamp(0.0, 1.0) : null,
      subtitleLines: rawLines is num ? rawLines.toInt().clamp(1, 3) : 1,
      cells: rawCells is Map
          ? rawCells.map<String, String>(
              (Object? key, Object? value) => MapEntry<String, String>(key.toString(), value?.toString() ?? ''))
          : const <String, String>{},
      depth: json['depth'] is num ? (json['depth'] as num).toInt().clamp(0, 12) : 0,
      expanded: json['expanded'] == true,
      timestamp: json['timestamp'] is String && (json['timestamp'] as String).trim().isNotEmpty
          ? (json['timestamp'] as String).trim()
          : null,
      column: json['column'] is String && (json['column'] as String).trim().isNotEmpty
          ? (json['column'] as String).trim()
          : (rawSection is String && rawSection.trim().isNotEmpty ? rawSection.trim() : null),
      calendar: PluginCalendarItem.fromJson(json['calendar'] is Map ? json['calendar'] : json),
      media: PluginMediaInfo.fromJson(json['media']),
      reply: reply,
      editableFields: rawEditable == true
          ? <String>{
              'title',
              'subtitle',
              if (rawCells is Map) ...rawCells.keys.map((Object? key) => key.toString()),
            }
          : rawEditable is List
              ? rawEditable.whereType<String>().toSet()
              : const <String>{},
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

/// Declarative dependency used by `visibleWhen` and `enabledWhen`.
class PluginFormCondition {
  const PluginFormCondition({required this.field, this.equals, this.notEquals, this.oneOf, this.truthy});

  final String field;
  final Object? equals;
  final Object? notEquals;
  final List<Object?>? oneOf;
  final bool? truthy;

  bool matches(Map<String, Object?> values) {
    final Object? value = values[field];
    if (truthy != null) {
      final bool isTruthy = value == true ||
          (value is String && value.trim().isNotEmpty) ||
          (value is num && value != 0) ||
          (value is Iterable && value.isNotEmpty);
      if (isTruthy != truthy) return false;
    }
    if (oneOf != null && !oneOf!.contains(value)) return false;
    if (equals != null && value != equals) return false;
    if (notEquals != null && value == notEquals) return false;
    return true;
  }

  static PluginFormCondition? fromJson(Object? json) {
    if (json is! Map || json['field'] is! String || (json['field'] as String).trim().isEmpty) return null;
    return PluginFormCondition(
      field: (json['field'] as String).trim(),
      equals: json['equals'],
      notEquals: json['notEquals'],
      oneOf: json['in'] is List ? List<Object?>.from(json['in'] as List) : null,
      truthy: json['truthy'] is bool ? json['truthy'] as bool : null,
    );
  }
}

/// Visual grouping for related form fields.
class PluginFormSection {
  const PluginFormSection({required this.id, required this.title, this.description = '', this.collapsible = false});

  final String id;
  final String title;
  final String description;
  final bool collapsible;

  static PluginFormSection? fromJson(Object? json) {
    if (json is! Map || json['id'] is! String || (json['id'] as String).trim().isEmpty) return null;
    final String id = (json['id'] as String).trim();
    return PluginFormSection(
      id: id,
      title: json['title'] is String ? json['title'] as String : id,
      description: json['description'] is String ? json['description'] as String : '',
      collapsible: json['collapsible'] == true,
    );
  }

  static List<PluginFormSection> listFromJson(Object? json) => json is List
      ? json.map(PluginFormSection.fromJson).whereType<PluginFormSection>().toList(growable: false)
      : const <PluginFormSection>[];
}

/// One input in a `form` view: `text`, `password`, `textarea`, `dropdown`,
/// `combobox`, `checkbox`, `number`, date/time pickers, file/folder/drop
/// pickers, choice controls, app/shortcut pickers, sliders, or code editors.
class PluginFormField {
  const PluginFormField({
    required this.id,
    required this.type,
    required this.label,
    required this.placeholder,
    required this.value,
    required this.options,
    this.required = false,
    this.description = '',
    this.error,
    this.watch = false,
    this.min,
    this.max,
    this.section,
    this.visibleWhen,
    this.enabledWhen,
    this.readOnly = false,
    this.minLength,
    this.maxLength,
    this.pattern,
    this.validationMessage,
    this.optionsLoading = false,
    this.allowCustom = false,
    this.multiple = false,
    this.extensions = const <String>[],
    this.step,
    this.rows = 6,
    this.language,
    this.validate = false,
    this.validationDebounceMs = 400,
    this.validating = false,
    this.valid,
  });

  final String id;
  final String type;
  final String label;
  final String placeholder;

  /// Initial value: a String for text-like fields, dropdowns and dates, a bool
  /// for checkboxes, a num for numbers, a `List<String>` for tags.
  final Object? value;

  /// Dropdown/tags choices; empty for other types.
  final List<PluginFormOption> options;

  /// Host-side validation: the field must be non-empty to submit.
  final bool required;

  /// Dimmed hint rendered under the field.
  final String description;

  /// Plugin-supplied validation error shown inline (server-side validation on
  /// a re-rendered form).
  final String? error;

  /// When true, every change to this field sends the plugin a
  /// `{"type":"change","id",...,"values":{...}}` event (dependent dropdowns).
  final bool watch;

  /// `number` fields: optional inclusive bounds.
  final num? min;
  final num? max;

  final String? section;
  final PluginFormCondition? visibleWhen;
  final PluginFormCondition? enabledWhen;
  final bool readOnly;
  final int? minLength;
  final int? maxLength;
  final String? pattern;
  final String? validationMessage;

  /// `combobox`: show an inline spinner while the plugin is resolving options.
  final bool optionsLoading;

  /// `combobox`: permit values that are not present in [options].
  final bool allowCustom;

  /// File/drop fields may accept several paths and restrict extensions.
  final bool multiple;
  final List<String> extensions;

  /// Slider increment, code editor height, and optional language hint.
  final num? step;
  final int rows;
  final String? language;

  /// Async validation contract. `validate:true` schedules a debounced
  /// `validate` event. Plugins re-render with `validating`, `valid`, or `error`.
  final bool validate;
  final int validationDebounceMs;
  final bool validating;
  final bool? valid;

  static const Set<String> knownTypes = <String>{
    'text', 'password', 'textarea', 'dropdown', 'combobox', 'checkbox', //
    'number', 'date', 'time', 'datetime', 'filepicker', 'folderpicker', 'dropzone',
    'tags', 'color', 'slider', 'radio', 'multiselect', 'apppicker',
    'shortcut', 'code', 'json',
  };

  bool get isTextLike => type == 'text' || type == 'password' || type == 'textarea' || type == 'code' || type == 'json';

  static PluginFormField? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? id = json['id'];
    if (id is! String || id.trim().isEmpty) return null;
    final Object? type = json['type'];
    final String resolvedType = type is String && knownTypes.contains(type) ? type : 'text';
    final Object? label = json['label'];
    final Object? placeholder = json['placeholder'];
    final Object? rawOptions = json['options'];
    final Object? description = json['description'];
    final Object? error = json['error'];
    final Object? min = json['min'];
    final Object? max = json['max'];
    Object? value = json['value'];
    if (value is List) {
      value = value.whereType<String>().toList(growable: false);
    } else if (value is! String && value is! bool && value is! num) {
      value = null;
    }
    return PluginFormField(
      id: id,
      type: resolvedType,
      label: label is String ? label : id,
      placeholder: placeholder is String ? placeholder : '',
      value: value,
      options: rawOptions is List
          ? rawOptions.map(PluginFormOption.fromJson).whereType<PluginFormOption>().toList(growable: false)
          : const <PluginFormOption>[],
      required: json['required'] == true,
      description: description is String ? description : '',
      error: error is String && error.trim().isNotEmpty ? error : null,
      watch: json['watch'] == true,
      min: min is num ? min : null,
      max: max is num ? max : null,
      section: json['section'] is String && (json['section'] as String).trim().isNotEmpty
          ? (json['section'] as String).trim()
          : null,
      visibleWhen: PluginFormCondition.fromJson(json['visibleWhen']),
      enabledWhen: PluginFormCondition.fromJson(json['enabledWhen']),
      readOnly: json['readOnly'] == true,
      minLength: json['minLength'] is num ? (json['minLength'] as num).toInt().clamp(0, 1000000) : null,
      maxLength: json['maxLength'] is num ? (json['maxLength'] as num).toInt().clamp(0, 1000000) : null,
      pattern: json['pattern'] is String && (json['pattern'] as String).isNotEmpty ? json['pattern'] as String : null,
      validationMessage: json['validationMessage'] is String ? json['validationMessage'] as String : null,
      optionsLoading: json['optionsLoading'] == true,
      allowCustom: json['allowCustom'] == true,
      multiple: json['multiple'] == true,
      extensions: json['extensions'] is List
          ? (json['extensions'] as List)
              .whereType<String>()
              .map((String value) => value.toLowerCase())
              .toList(growable: false)
          : const <String>[],
      step: json['step'] is num ? json['step'] as num : null,
      rows: json['rows'] is num ? (json['rows'] as num).toInt().clamp(3, 24) : 6,
      language: json['language'] is String ? json['language'] as String : null,
      validate: json['validate'] == true,
      validationDebounceMs: json['validationDebounceMs'] is num
          ? (json['validationDebounceMs'] as num).toInt().clamp(100, 3000)
          : json['validationDebounce'] is num
              ? (json['validationDebounce'] as num).toInt().clamp(100, 3000)
              : 400,
      validating: json['validating'] == true,
      valid: json['valid'] is bool ? json['valid'] as bool : null,
    );
  }
}

/// One button under a form (`form.buttons`). Submitting with a button includes
/// its id in the `submit` message as `"button"`.
class PluginFormButton {
  const PluginFormButton({required this.id, required this.label, this.destructive = false});

  final String id;
  final String label;
  final bool destructive;

  static PluginFormButton? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? id = json['id'];
    final Object? label = json['label'];
    if (id is! String || label is! String) return null;
    return PluginFormButton(id: id, label: label, destructive: json['destructive'] == true);
  }
}

/// The `form` view payload: a titled set of input fields plus a submit button.
/// Submitting sends `{"type":"submit","values":{...}}` back to the plugin.
class PluginForm {
  const PluginForm({
    required this.title,
    required this.submitLabel,
    required this.fields,
    this.buttons = const <PluginFormButton>[],
    this.sections = const <PluginFormSection>[],
    this.error,
  });

  final String title;
  final String submitLabel;
  final List<PluginFormField> fields;

  /// Optional multi-button row replacing the single submit CTA. Each submits
  /// the form with its id in the `submit` message's `"button"` field.
  final List<PluginFormButton> buttons;
  final List<PluginFormSection> sections;
  final String? error;

  static PluginForm? fromJson(Object? json) {
    if (json is! Map) return null;
    final Object? title = json['title'];
    final Object? submitLabel = json['submitLabel'];
    final Object? rawFields = json['fields'];
    final Object? rawButtons = json['buttons'];
    final List<PluginFormField> fields = rawFields is List
        ? rawFields.map(PluginFormField.fromJson).whereType<PluginFormField>().toList(growable: false)
        : const <PluginFormField>[];
    if (fields.isEmpty) return null;
    return PluginForm(
      title: title is String ? title : '',
      submitLabel: submitLabel is String && submitLabel.trim().isNotEmpty ? submitLabel : 'Submit',
      fields: fields,
      sections: PluginFormSection.listFromJson(json['sections']),
      error: json['error'] is String && (json['error'] as String).trim().isNotEmpty
          ? (json['error'] as String).trim()
          : null,
      buttons: rawButtons is List
          ? rawButtons.map(PluginFormButton.fromJson).whereType<PluginFormButton>().toList(growable: false)
          : const <PluginFormButton>[],
    );
  }
}

/// Custom empty state (`"empty": {"icon","title","hint"}`), richer than the
/// plain `emptyText` string it supersedes.
class PluginEmptyState {
  const PluginEmptyState({required this.icon, required this.title, required this.hint, this.action});

  final String? icon;
  final String title;
  final String hint;

  /// Optional call-to-action button ("No config → Set up"). Clicking it sends
  /// the plugin an `action` message with an empty item id.
  final PluginAction? action;

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
      action: PluginAction.fromJson(json['action']),
    );
  }
}

/// A side-effect request from the plugin (`{"type":"command", ...}`): instead
/// of shelling out to `clip`/`start` itself, a plugin asks the host to copy,
/// paste, open a URL, hide the launcher, show a toast/notification, read the
/// clipboard, or persist values in per-plugin storage.
/// Image pixels and native file-drop payloads use the `copyimage` and
/// `copyfile` commands respectively.
class PluginCommand {
  const PluginCommand({required this.name, this.text, this.url, this.data = const <String, dynamic>{}});

  /// One of [knownCommands].
  final String name;

  /// Payload for `copy` / `paste` / `toast` / `notify` / `setquery`.
  final String? text;

  /// Target for `open` — a URL or a file/folder path.
  final String? url;

  /// The full decoded command message, for commands with richer payloads
  /// (storage ops, toast styles, notify titles, background timeouts).
  final Map<String, dynamic> data;

  static const Set<String> knownCommands = <String>{
    'copy', 'copyimage', 'copyfile', 'paste', 'open', 'hide', 'toast', 'setquery', //
    'storage', 'clipboardread', 'clipboardhistory', 'notify', 'background', 'oauth', 'browserbridge',
  };

  /// Parses a decoded `{"type":"command"}` message. Returns null when the
  /// `command` field is missing or not a string (unknown-but-well-formed names
  /// are kept so the host can report them to the debug console).
  static PluginCommand? fromJson(Map<String, dynamic> json) {
    final Object? name = json['command'];
    if (name is! String || name.trim().isEmpty) return null;
    final Object? text = json['text'];
    Object? url;
    for (final String key in <String>['url', 'path', 'file']) {
      final Object? candidate = json[key];
      if (candidate is String && candidate.trim().isNotEmpty) {
        url = candidate;
        break;
      }
    }
    return PluginCommand(
      name: name.trim().toLowerCase(),
      text: text is String ? text : null,
      url: url is String ? url : null,
      data: json,
    );
  }
}

/// One independent surface in a `dashboard` frame. Its visual fields use the
/// same grammar as a normal render frame; `id`, `title`, and `height` belong to
/// the panel wrapper rather than its child view.
class PluginDashboardPanel {
  const PluginDashboardPanel({required this.id, required this.title, required this.frame, this.height});

  final String id;
  final String title;
  final PluginRenderFrame frame;
  final double? height;

  static PluginDashboardPanel? fromJson(Object? json, int index) {
    if (json is! Map) return null;
    final Map<String, dynamic> raw = json.cast<String, dynamic>();
    final String id =
        raw['id'] is String && (raw['id'] as String).trim().isNotEmpty ? raw['id'] as String : 'panel-$index';
    final String title =
        raw['title'] is String && (raw['title'] as String).trim().isNotEmpty ? raw['title'] as String : id;
    final Object? rawHeight = raw['height'];
    return PluginDashboardPanel(
      id: id,
      title: title,
      frame: PluginRenderFrame.fromJson(raw),
      height: rawHeight is num ? rawHeight.toDouble().clamp(96, 640) : null,
    );
  }

  static List<PluginDashboardPanel> listFromJson(Object? json) {
    if (json is! List) return const <PluginDashboardPanel>[];
    final List<PluginDashboardPanel> panels = <PluginDashboardPanel>[];
    for (int index = 0; index < json.length; index++) {
      final PluginDashboardPanel? panel = fromJson(json[index], index);
      if (panel != null) panels.add(panel);
    }
    return panels;
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
    this.wide = false,
    required this.previewEnabled,
    this.previewWide = true,
    this.previewResizable = false,
    this.previewInitialWidth,
    this.previewMinWidth = 240,
    this.previewMaxWidth = 720,
    required this.loading,
    required this.emptyText,
    required this.rev,
    this.error,
    this.form,
    this.loadingProgress,
    this.loadingText,
    this.placeholder,
    this.empty,
    this.canGoBack = false,
    this.frameActions = const <PluginAction>[],
    this.floatingActions = const <PluginAction>[],
    this.selectId,
    this.hasMore = false,
    this.submitInput = false,
    this.typing,
    this.detailAppend,
    this.multiSelect = false,
    this.multiSelectMax,
    this.columns = const <PluginTableColumn>[],
    this.chartSeries = const <PluginChartSeries>[],
    this.chartTitle,
    this.chartOptions = const PluginChartOptions(),
    this.toolbarControls = const <PluginToolbarControl>[],
    this.banners = const <PluginBanner>[],
    this.dropZone,
    this.loadingStyle = 'spinner',
    this.skeletonCount = 6,
    this.tableResizable = false,
    this.tableStickyHeader = true,
    this.tableColumnVisibility = false,
    this.tableSortColumn,
    this.tableSortDirection = 'asc',
    this.operation,
    this.dashboardLayout = 'stack',
    this.dashboardPanels = const <PluginDashboardPanel>[],
    this.page,
    this.elementId,
    this.kanbanColumns = const <PluginKanbanColumn>[],
    this.diffLines = const <PluginDiffLine>[],
    this.diffMode = 'unified',
    this.diffOldLabel = 'Before',
    this.diffNewLabel = 'After',
    this.logLines = const <PluginLogLine>[],
    this.logFollow = true,
    this.logWrap = false,
    this.calendarMode = 'month',
    this.calendarDate,
    this.calendarWeekStart = DateTime.monday,
    this.calendarDays = 30,
    this.galleryColumns = 4,
    this.galleryAspectRatio = 1.15,
    this.galleryFit = 'cover',
    this.galleryShowLabels = true,
  });

  final PluginViewType view;
  final List<PluginItem> items;
  final int gridColumns;
  final double gridAspectRatio;

  /// Frame-level Ctrl+K actions, available regardless of the highlighted item
  /// (refresh, create, sign out). Shown after the item's own actions.
  final List<PluginAction> frameActions;

  /// Prominent action buttons overlaid at the bottom-right of this frame.
  /// They dispatch frame-level action events (empty item id), including any
  /// launcher-owned bulk-selection ids.
  final List<PluginAction> floatingActions;

  /// When set, the launcher moves the highlight to the item with this id (only
  /// applied when the frame's item set actually changed).
  final String? selectId;

  /// List/grid: the plugin has more items — scrolling near the end sends a
  /// `{"type":"loadMore"}` event; the plugin answers with a longer list.
  final bool hasMore;

  /// `inputMode: "submit"` — keystrokes are not streamed to the plugin; Enter
  /// sends one `{"type":"submitQuery"}` with the full text (chat-style input).
  final bool submitInput;

  /// Optional transient status shown at the bottom of a chat, such as
  /// "Ava is typing...". Plugins can keep ephemeral presence out of message
  /// rows by using this field.
  final String? typing;

  /// `detail.append`: a chunk to add to the *previous* frame's detail markdown
  /// instead of replacing the document — streaming LLM output. The host merges
  /// this before the frame reaches the view.
  final String? detailAppend;

  /// Lets the user select several item views, including gallery, for batch actions.
  final bool multiSelect;
  final int? multiSelectMax;
  final List<PluginTableColumn> columns;
  final List<PluginChartSeries> chartSeries;
  final String? chartTitle;
  final PluginChartOptions chartOptions;
  final List<PluginToolbarControl> toolbarControls;
  final List<PluginBanner> banners;
  final PluginDropZone? dropZone;
  final String loadingStyle;
  final int skeletonCount;
  final bool tableResizable;
  final bool tableStickyHeader;
  final bool tableColumnVisibility;
  final String? tableSortColumn;
  final String tableSortDirection;
  final PluginOperation? operation;

  /// `dashboard` composition: either vertically stacked panels or tabs.
  final String dashboardLayout;
  final List<PluginDashboardPanel> dashboardPanels;

  /// Optional stable page identity used for navigation chrome and state
  /// restoration. [elementId] addresses this frame within its page.
  final PluginPageInfo? page;
  final String? elementId;

  final List<PluginKanbanColumn> kanbanColumns;
  final List<PluginDiffLine> diffLines;
  final String diffMode;
  final String diffOldLabel;
  final String diffNewLabel;
  final List<PluginLogLine> logLines;
  final bool logFollow;
  final bool logWrap;
  final String calendarMode;
  final DateTime? calendarDate;
  final int calendarWeekStart;
  final int calendarDays;
  final int galleryColumns;
  final double galleryAspectRatio;
  final String galleryFit;
  final bool galleryShowLabels;

  /// Full-width markdown, used when [view] is [PluginView.detail].
  final String? detailMarkdown;

  /// Structured key-value rows shown under [detailMarkdown] in detail view.
  final List<PluginMetadataEntry> detailMetadata;

  /// Detail view: widen the launcher window (like the split preview does) so
  /// long-form markdown gets room to breathe. From `detail.wide`.
  final bool detailWide;

  /// Widen the launcher window for this frame. From the root-level `wide`
  /// property, independent of the selected view.
  final bool wide;

  /// Whether the split preview pane is shown (list/grid views only).
  final bool previewEnabled;

  /// Whether an enabled preview should widen the launcher window. From
  /// `preview.wide` (default true). When false, the preview pane still renders
  /// but the window keeps its normal size. Ignored unless [previewEnabled].
  final bool previewWide;
  final bool previewResizable;
  final double? previewInitialWidth;
  final double previewMinWidth;
  final double previewMaxWidth;

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

  /// Optional caption shown under the spinner while [loading] (e.g. "Searching…",
  /// "Installing dependencies…"). Distinct from [emptyText], which is only shown
  /// when there are no items and the frame is *not* loading.
  final String? loadingText;

  /// Replaces the launcher's search-field hint text while this frame is shown.
  final String? placeholder;

  /// Richer empty state; falls back to [emptyText] when absent.
  final PluginEmptyState? empty;

  /// When true, Escape sends `{"type":"back"}` to the plugin (which should
  /// render its previous screen) instead of exiting the plugin. Frames at the
  /// plugin's root should leave this false so Escape exits as usual.
  final bool canGoBack;

  PluginEventScope scope({String? panelId}) =>
      PluginEventScope(pageId: page?.id, panelId: panelId, elementId: elementId);

  bool get hasPreview =>
      previewEnabled && view != PluginViewType.detail && view != PluginViewType.chat && view != PluginViewType.form;

  /// Resolves a streaming `detail.append` frame against the markdown that is
  /// currently on screen, producing a full frame the view can render.
  PluginRenderFrame resolveAppend(String? previousMarkdown) {
    if (detailAppend == null) return this;
    return PluginRenderFrame(
      view: view,
      items: items,
      gridColumns: gridColumns,
      gridAspectRatio: gridAspectRatio,
      detailMarkdown: '${previousMarkdown ?? detailMarkdown ?? ''}$detailAppend',
      detailMetadata: detailMetadata,
      detailWide: detailWide,
      wide: wide,
      previewEnabled: previewEnabled,
      previewWide: previewWide,
      previewResizable: previewResizable,
      previewInitialWidth: previewInitialWidth,
      previewMinWidth: previewMinWidth,
      previewMaxWidth: previewMaxWidth,
      loading: loading,
      emptyText: emptyText,
      rev: rev,
      error: error,
      form: form,
      loadingProgress: loadingProgress,
      loadingText: loadingText,
      placeholder: placeholder,
      empty: empty,
      canGoBack: canGoBack,
      frameActions: frameActions,
      floatingActions: floatingActions,
      selectId: selectId,
      hasMore: hasMore,
      submitInput: submitInput,
      typing: typing,
      detailAppend: null,
      multiSelect: multiSelect,
      multiSelectMax: multiSelectMax,
      columns: columns,
      chartSeries: chartSeries,
      chartTitle: chartTitle,
      chartOptions: chartOptions,
      toolbarControls: toolbarControls,
      banners: banners,
      dropZone: dropZone,
      loadingStyle: loadingStyle,
      skeletonCount: skeletonCount,
      tableResizable: tableResizable,
      tableStickyHeader: tableStickyHeader,
      tableColumnVisibility: tableColumnVisibility,
      tableSortColumn: tableSortColumn,
      tableSortDirection: tableSortDirection,
      operation: operation,
      dashboardLayout: dashboardLayout,
      dashboardPanels: dashboardPanels,
      page: page,
      elementId: elementId,
      kanbanColumns: kanbanColumns,
      diffLines: diffLines,
      diffMode: diffMode,
      diffOldLabel: diffOldLabel,
      diffNewLabel: diffNewLabel,
      logLines: logLines,
      logFollow: logFollow,
      logWrap: logWrap,
      calendarMode: calendarMode,
      calendarDate: calendarDate,
      calendarWeekStart: calendarWeekStart,
      calendarDays: calendarDays,
      galleryColumns: galleryColumns,
      galleryAspectRatio: galleryAspectRatio,
      galleryFit: galleryFit,
      galleryShowLabels: galleryShowLabels,
    );
  }

  /// Whether this frame asks for the widened launcher window: a split preview
  /// pane that opted into widening, a detail/chat view marked `wide`, or a
  /// root-level `wide: true`.
  bool get wantsWideWindow =>
      wide ||
      (hasPreview && previewWide) ||
      ((view == PluginViewType.detail || view == PluginViewType.chat) && detailWide);

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

  /// A transient host-side status frame (e.g. "Installing dependencies…") shown
  /// as a spinner with a caption before the plugin process produces its first
  /// real frame. Uses `rev: 0` so it is never dropped by the staleness guard.
  static PluginRenderFrame statusFrame(String message) => PluginRenderFrame(
        view: PluginViewType.list,
        items: const <PluginItem>[],
        gridColumns: 4,
        gridAspectRatio: 1.0,
        detailMarkdown: null,
        previewEnabled: false,
        loading: true,
        emptyText: '',
        loadingText: message,
        rev: 0,
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
    final Object? selection = json['selection'];
    final Object? chart = json['chart'];
    final Object? toolbar = json['toolbar'];
    final Object? table = json['table'];
    final Object? dashboard = json['dashboard'];
    final Object? kanban = json['kanban'];
    final Object? diff = json['diff'];
    final Object? log = json['log'];
    final Object? calendar = json['calendar'];
    final Object? gallery = json['gallery'];

    int gridColumns = 4;
    double gridAspectRatio = 1.0;
    if (grid is Map) {
      final Object? cols = grid['columns'];
      if (cols is num) gridColumns = cols.toInt().clamp(1, 12);
      final Object? ratio = grid['aspectRatio'];
      if (ratio is num && ratio > 0) gridAspectRatio = ratio.toDouble();
    }

    String? detailMarkdown;
    String? detailAppend;
    List<PluginMetadataEntry> detailMetadata = const <PluginMetadataEntry>[];
    bool detailWide = false;
    if (detail is Map) {
      final Object? md = detail['markdown'];
      if (md is String) detailMarkdown = md;
      final Object? append = detail['append'];
      if (append is String) detailAppend = append;
      detailMetadata = PluginMetadataEntry.listFromJson(detail['metadata']);
      detailWide = detail['wide'] == true;
    } else if (detail is String) {
      detailMarkdown = detail;
    }

    bool previewEnabled = false;
    bool previewWide = true;
    bool previewResizable = false;
    double? previewInitialWidth;
    double previewMinWidth = 240;
    double previewMaxWidth = 720;
    if (preview is Map) {
      previewEnabled = preview['enabled'] == true;
      // Opt out of the widened window with `"wide": false`; anything else
      // (absent, true) keeps the historical widen-on-preview behavior.
      previewWide = preview['wide'] != false;
      previewResizable = preview['resizable'] == true;
      previewMinWidth = preview['minWidth'] is num ? (preview['minWidth'] as num).toDouble().clamp(160, 560) : 240;
      previewMaxWidth =
          preview['maxWidth'] is num ? (preview['maxWidth'] as num).toDouble().clamp(previewMinWidth, 960) : 720;
      previewInitialWidth = preview['initialWidth'] is num
          ? (preview['initialWidth'] as num).toDouble().clamp(previewMinWidth, previewMaxWidth)
          : null;
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
    final Object? loadingText = json['loadingText'];
    final Object? placeholder = json['placeholder'];
    final Object? selectId = json['selectId'];
    final int? multiSelectMax =
        selection is Map && selection['max'] is num ? (selection['max'] as num).toInt().clamp(1, 999) : null;
    final List<PluginChartSeries> chartSeries = chart is Map && chart['series'] is List
        ? (chart['series'] as List)
            .map<PluginChartSeries?>(PluginChartSeries.fromJson)
            .whereType<PluginChartSeries>()
            .toList(growable: false)
        : const <PluginChartSeries>[];

    // `loading` is either a bool or `{"progress": 0..1}` for a determinate bar.
    final Object? rawLoading = json['loading'];
    bool loading = rawLoading == true;
    double? loadingProgress;
    String loadingStyle = 'spinner';
    int skeletonCount = 6;
    if (rawLoading is Map) {
      loading = true;
      final Object? progress = rawLoading['progress'];
      if (progress is num) loadingProgress = progress.toDouble().clamp(0.0, 1.0);
      loadingStyle = rawLoading['style'] == 'skeleton' ? 'skeleton' : 'spinner';
      skeletonCount = rawLoading['count'] is num ? (rawLoading['count'] as num).toInt().clamp(1, 24) : 6;
    }

    return PluginRenderFrame(
      view: _viewFromString(json['view'] as String?),
      items: items,
      gridColumns: gridColumns,
      gridAspectRatio: gridAspectRatio,
      detailMarkdown: detailMarkdown,
      detailMetadata: detailMetadata,
      detailWide: detailWide,
      wide: json['wide'] == true,
      previewEnabled: previewEnabled,
      previewWide: previewWide,
      previewResizable: previewResizable,
      previewInitialWidth: previewInitialWidth,
      previewMinWidth: previewMinWidth,
      previewMaxWidth: previewMaxWidth,
      loading: loading,
      loadingProgress: loadingProgress,
      loadingStyle: loadingStyle,
      skeletonCount: skeletonCount,
      loadingText: loadingText is String && loadingText.trim().isNotEmpty ? loadingText : null,
      emptyText: emptyText is String ? emptyText : 'No results',
      rev: rev is num ? rev.toInt() : 0,
      form: PluginForm.fromJson(json['form']),
      placeholder: placeholder is String && placeholder.trim().isNotEmpty ? placeholder : null,
      empty: PluginEmptyState.fromJson(json['empty']),
      canGoBack: json['canGoBack'] == true,
      frameActions: PluginAction.listFromJson(json['actions']),
      floatingActions: PluginAction.listOrSingleFromJson(json['floatingAction']),
      selectId: selectId is String && selectId.isNotEmpty ? selectId : null,
      hasMore: json['hasMore'] == true,
      submitInput: json['inputMode'] == 'submit',
      typing: json['typing'] is String && (json['typing'] as String).trim().isNotEmpty
          ? (json['typing'] as String).trim()
          : null,
      detailAppend: detailAppend,
      multiSelect: selection == true || (selection is Map && selection['enabled'] != false),
      multiSelectMax: multiSelectMax,
      columns: PluginTableColumn.listFromJson(json['columns']),
      chartSeries: chartSeries,
      chartTitle: chart is Map && chart['title'] is String ? chart['title'] as String : null,
      chartOptions: PluginChartOptions.fromJson(chart),
      toolbarControls: PluginToolbarControl.fromToolbarJson(toolbar),
      banners: PluginBanner.listFromJson(json['banners'] ?? json['banner']),
      dropZone: PluginDropZone.fromJson(json['dropZone']),
      tableResizable: table is Map && table['resizable'] == true,
      tableStickyHeader: table is! Map || table['stickyHeader'] != false,
      tableColumnVisibility: table is Map && table['columnVisibility'] == true,
      tableSortColumn: table is Map && table['sortColumn'] is String ? table['sortColumn'] as String : null,
      tableSortDirection: table is Map && table['sortDirection'] == 'desc' ? 'desc' : 'asc',
      operation: PluginOperation.fromJson(json['operation']),
      dashboardLayout: dashboard is Map && dashboard['layout'] == 'tabs' ? 'tabs' : 'stack',
      dashboardPanels: PluginDashboardPanel.listFromJson(dashboard is Map ? dashboard['panels'] : json['panels']),
      page: PluginPageInfo.fromJson(json['page']),
      elementId: json['elementId'] is String && (json['elementId'] as String).trim().isNotEmpty
          ? (json['elementId'] as String).trim()
          : null,
      kanbanColumns: PluginKanbanColumn.listFromJson(kanban is Map ? kanban['columns'] : json['kanbanColumns']),
      diffLines: PluginDiffLine.listFromJson(diff is Map ? (diff['lines'] ?? diff['text']) : diff),
      diffMode: diff is Map && diff['mode'] == 'split' ? 'split' : 'unified',
      diffOldLabel: diff is Map && diff['oldLabel'] is String ? diff['oldLabel'] as String : 'Before',
      diffNewLabel: diff is Map && diff['newLabel'] is String ? diff['newLabel'] as String : 'After',
      logLines: PluginLogLine.listFromJson(log is Map ? log['lines'] : log),
      logFollow: log is Map ? log['follow'] != false : true,
      logWrap: log is Map && log['wrap'] == true,
      calendarMode: calendar is Map && calendar['mode'] == 'agenda' ? 'agenda' : 'month',
      calendarDate:
          calendar is Map && calendar['date'] is String ? DateTime.tryParse((calendar['date'] as String).trim()) : null,
      calendarWeekStart: calendar is Map && calendar['weekStart'] == 'sunday' ? DateTime.sunday : DateTime.monday,
      calendarDays: calendar is Map && calendar['days'] is num ? (calendar['days'] as num).toInt().clamp(1, 90) : 30,
      galleryColumns: gallery is Map && gallery['columns'] is num ? (gallery['columns'] as num).toInt().clamp(2, 8) : 4,
      galleryAspectRatio: gallery is Map && gallery['aspectRatio'] is num && (gallery['aspectRatio'] as num) > 0
          ? (gallery['aspectRatio'] as num).toDouble().clamp(0.5, 2.5)
          : 1.15,
      galleryFit: gallery is Map && gallery['fit'] == 'contain' ? 'contain' : 'cover',
      galleryShowLabels: gallery is! Map || gallery['showLabels'] != false,
    );
  }
}
