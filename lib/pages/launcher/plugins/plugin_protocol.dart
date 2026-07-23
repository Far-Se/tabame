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
const int pluginProtocolVersion = 5;

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
    this.image,
    this.imageWidth,
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
    final Object? url = json['url'];
    final String? imageUrl = image is String && _isHttpUrl(image) ? image.trim() : null;
    return PluginMetadataEntry(
      label: label is String ? label : '',
      text: text is String ? text : '',
      color: parsePluginColor(json['color']),
      icon: icon is String ? icon : null,
      image: imageUrl,
      imageWidth: imageUrl != null && imageWidth is num ? imageWidth.toDouble().clamp(48.0, 280.0) : null,
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
    );
  }

  static List<PluginAction> listFromJson(Object? json) {
    if (json is! List) return const <PluginAction>[];
    return json.map(fromJson).whereType<PluginAction>().toList(growable: false);
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
    this.previewImageUrl,
    this.previewImageWidth,
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

  /// Optional remote raster image shown to the right of preview markdown.
  final String? previewImageUrl;

  /// Display width of [previewImageUrl], in logical pixels.
  final double? previewImageWidth;

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
    String? previewImageUrl;
    double? previewImageWidth;
    if (rawPreview is Map) {
      final Object? md = rawPreview['markdown'];
      if (md is String) previewMarkdown = md;
      previewMetadata = PluginMetadataEntry.listFromJson(rawPreview['metadata']);
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
      previewImageUrl: previewImageUrl,
      previewImageWidth: previewImageWidth,
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

/// One input in a `form` view: `text`, `password`, `textarea`, `dropdown`,
/// `checkbox`, `number`, `date`, `filepicker`, `folderpicker`, or `tags`.
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

  static const Set<String> knownTypes = <String>{
    'text', 'password', 'textarea', 'dropdown', 'checkbox', //
    'number', 'date', 'filepicker', 'folderpicker', 'tags',
  };

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
  });

  final String title;
  final String submitLabel;
  final List<PluginFormField> fields;

  /// Optional multi-button row replacing the single submit CTA. Each submits
  /// the form with its id in the `submit` message's `"button"` field.
  final List<PluginFormButton> buttons;

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
    'copy', 'paste', 'open', 'hide', 'toast', 'setquery', //
    'storage', 'clipboardread', 'clipboardhistory', 'notify', 'background',
  };

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
      data: json,
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
    this.loadingText,
    this.placeholder,
    this.empty,
    this.canGoBack = false,
    this.frameActions = const <PluginAction>[],
    this.selectId,
    this.hasMore = false,
    this.submitInput = false,
    this.detailAppend,
  });

  final PluginViewType view;
  final List<PluginItem> items;
  final int gridColumns;
  final double gridAspectRatio;

  /// Frame-level Ctrl+K actions, available regardless of the highlighted item
  /// (refresh, create, sign out). Shown after the item's own actions.
  final List<PluginAction> frameActions;

  /// When set, the launcher moves the highlight to the item with this id (only
  /// applied when the frame's item set actually changed).
  final String? selectId;

  /// List/grid: the plugin has more items — scrolling near the end sends a
  /// `{"type":"loadMore"}` event; the plugin answers with a longer list.
  final bool hasMore;

  /// `inputMode: "submit"` — keystrokes are not streamed to the plugin; Enter
  /// sends one `{"type":"submitQuery"}` with the full text (chat-style input).
  final bool submitInput;

  /// `detail.append`: a chunk to add to the *previous* frame's detail markdown
  /// instead of replacing the document — streaming LLM output. The host merges
  /// this before the frame reaches the view.
  final String? detailAppend;

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

  bool get hasPreview => previewEnabled && view != PluginViewType.detail && view != PluginViewType.form;

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
      previewEnabled: previewEnabled,
      previewWide: previewWide,
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
      selectId: selectId,
      hasMore: hasMore,
      submitInput: submitInput,
      detailAppend: null,
    );
  }

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
    final Object? loadingText = json['loadingText'];
    final Object? placeholder = json['placeholder'];
    final Object? selectId = json['selectId'];

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
      loadingText: loadingText is String && loadingText.trim().isNotEmpty ? loadingText : null,
      emptyText: emptyText is String ? emptyText : 'No results',
      rev: rev is num ? rev.toInt() : 0,
      form: PluginForm.fromJson(json['form']),
      placeholder: placeholder is String && placeholder.trim().isNotEmpty ? placeholder : null,
      empty: PluginEmptyState.fromJson(json['empty']),
      canGoBack: json['canGoBack'] == true,
      frameActions: PluginAction.listFromJson(json['actions']),
      selectId: selectId is String && selectId.isNotEmpty ? selectId : null,
      hasMore: json['hasMore'] == true,
      submitInput: json['inputMode'] == 'submit',
      detailAppend: detailAppend,
    );
  }
}
