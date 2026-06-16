import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/clipboard_history.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/mini_switch.dart';
import '../../widgets/mix_widgets.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/quick_menu_panel.dart';
import '../../widgets/text_input.dart';
import '../../widgets/windows_scroll.dart';

class ClipboardHistoryButton extends StatelessWidget {
  const ClipboardHistoryButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: "Clipboard History",
      icon: const Icon(Icons.content_paste_search_rounded),
      child: () => const ClipboardHistoryPanel(),
    );
  }
}

class ClipboardHistoryPanel extends StatefulWidget {
  const ClipboardHistoryPanel({super.key});

  @override
  State<ClipboardHistoryPanel> createState() => _ClipboardHistoryPanelState();
}

class _ClipboardHistoryPanelState extends State<ClipboardHistoryPanel> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final FocusNode _focusNode = FocusNode();
  List<ClipboardHistoryEntry> _pinnedEntries = <ClipboardHistoryEntry>[];
  List<ClipboardHistoryEntry> _historyEntries = <ClipboardHistoryEntry>[];
  bool _settingsMode = false;
  bool _enabled = true;
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = true;
  int _pageOffset = 0;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _enabled = ClipboardHistoryStore.enabled;
    _scrollController.addListener(_onScroll);
    _searchController.addListener(_onSearch);
    _load();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _focusNode.requestFocus();
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >= _scrollController.position.maxScrollExtent - 200) {
      if (!_loadingMore && _hasMore && _searchController.text.isEmpty) {
        _loadMore();
      }
    }
  }

  void _onSearch() {
    if (_debounceTimer?.isActive ?? false) _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 300), () {
      if (mounted) _load();
    });
  }

  Timer? _debounceTimer;

  Future<void> _load() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
      _pageOffset = 0;
      _hasMore = true;
    });

    try {
      final List<ClipboardHistoryEntry> pinned = await ClipboardHistoryStore.loadPinned();
      final List<ClipboardHistoryEntry> history =
          await ClipboardHistoryStore.loadPaged(offset: 0, query: _searchController.text);
      if (!mounted) return;
      setState(() {
        _pinnedEntries = pinned;
        _historyEntries = history;
        _loading = false;
        if (history.length < 30) _hasMore = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.toString();
        _loading = false;
      });
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);

    try {
      final int newOffset = _pageOffset + 30;
      final List<ClipboardHistoryEntry> more =
          await ClipboardHistoryStore.loadPaged(offset: newOffset, query: _searchController.text);
      if (!mounted) return;
      setState(() {
        _historyEntries.addAll(more);
        _pageOffset += more.length;
        if (more.length < 30) _hasMore = false;
        _loadingMore = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  Future<void> _toggleEnabled(bool value) async {
    await ClipboardHistoryStore.setEnabled(value);
    if (mounted) {
      setState(() {
        _enabled = value;
      });
    }
  }

  Future<void> _saveDays(String value) async {
    final int days = int.tryParse(value) ?? ClipboardHistoryStore.defaultCacheDays;
    await ClipboardHistoryStore.setCacheDays(days);
    await _load();
  }

  Future<void> _copy(ClipboardHistoryEntry entry) async {
    await ClipboardHistoryStore.copyEntry(entry);
    if (!mounted) return;
    QuickMenuFunctions.hideQuickMenu();
  }

  Future<void> _delete(ClipboardHistoryEntry entry) async {
    await ClipboardHistoryStore.remove(entry);
    await _load();
  }

  Future<void> _clear() async {
    await ClipboardHistoryStore.clear();
    await _load();
  }

  Future<void> _pruneHistory() async {
    await ClipboardHistoryStore.clearCache();
    await _load();
  }

  Future<void> _togglePin(ClipboardHistoryEntry entry) async {
    await ClipboardHistoryStore.setPinned(entry, !entry.pinned);
    await _load();
  }

  void _openImageFile(ClipboardHistoryEntry entry) {
    if (entry.imagePath.isEmpty || !File(entry.imagePath).existsSync()) return;
    WinUtils.open('explorer.exe', arguments: '/select,"${entry.imagePath}"', parseParamaters: false);
    QuickMenuFunctions.hideQuickMenu();
  }

  @override
  Widget build(BuildContext context) {
    final Color accent = Design.accent;
    final Color onSurface = Theme.of(context).colorScheme.onSurface;

    return QuickMenuPanel(
      title: _settingsMode ? "Clipboard Settings" : "Clipboard History",
      accent: accent,
      icon: _settingsMode ? Icons.settings_rounded : Icons.content_paste_search_rounded,
      buttonIcon: _settingsMode ? Icons.history_rounded : Icons.settings_rounded,
      buttonTooltip: _settingsMode ? "History" : "Settings",
      buttonPressed: () {
        setState(() {
          _settingsMode = !_settingsMode;
        });
      },
      extraActions: <Widget>[
        CustomTooltip(
          message: "Clear history",
          child: IconButton(
            onPressed: () async {
              if ((_historyEntries.isEmpty && _pinnedEntries.isEmpty) || _loading) return;
              await _clear();
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            iconSize: 14,
            icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
          ),
        ),
        CustomTooltip(
          message: "Refresh",
          child: IconButton(
            onPressed: _load,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
            iconSize: 14,
            icon: Icon(Icons.refresh_rounded, color: accent),
          ),
        ),
      ],
      body: _settingsMode ? _buildSettings(accent, onSurface) : _buildHistory(accent, onSurface),
    );
  }

  Widget _buildSettings(Color accent, Color onSurface) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
      children: <Widget>[
        _settingsRow(
          accent: accent,
          onSurface: onSurface,
          icon: Icons.history_toggle_off_rounded,
          title: "Clipboard history",
          subtitle: _enabled ? "New clipboard changes are saved." : "Clipboard changes are ignored.",
          trailing: MiniToggleSwitch(
            value: _enabled,
            activeThumbColor: accent,
            onChanged: _toggleEnabled,
          ),
        ),
        const SizedBox(height: 8),
        _settingsRow(
          accent: accent,
          onSurface: onSurface,
          icon: Icons.event_repeat_rounded,
          title: "Cache window",
          subtitle: "Entries older than this are removed.",
          trailing: SizedBox(
            width: 86,
            child: CustomTextInput(
              value: ClipboardHistoryStore.cacheDays.toString(),
              labelText: "Days",
              onChanged: (String val) {},
              onSubmitted: (String val) {
                _saveDays(val);
              },
              onUpdated: (String val) {
                _saveDays(val);
              },
            ),
          ),
        ),
        const SizedBox(height: 8),
        _settingsRow(
          accent: accent,
          onSurface: onSurface,
          icon: Icons.cleaning_services_rounded,
          title: "Prune history",
          subtitle: "Remove entries older than ${ClipboardHistoryStore.cacheDays}d and orphaned images.",
          trailing: TextButton(
            onPressed: _pruneHistory,
            child: const Text("Prune"),
          ),
        ),
        const SizedBox(height: 8),
        _settingsRow(
          accent: Colors.redAccent,
          onSurface: onSurface,
          icon: Icons.delete_sweep_rounded,
          title: "Clear saved history",
          subtitle:
              "${_historyEntries.length + _pinnedEntries.length} saved item${(_historyEntries.length + _pinnedEntries.length) == 1 ? '' : 's'}",
          trailing: TextButton(
            onPressed: (_historyEntries.isEmpty && _pinnedEntries.isEmpty) ? null : _clear,
            child: const Text("Clear"),
          ),
        ),
      ],
    );
  }

  Widget _buildHistory(Color accent, Color onSurface) {
    if (_loading) {
      return Center(
          child: SizedBox.square(dimension: 22, child: CircularProgressIndicator(strokeWidth: 2, color: accent)));
    }

    if (_error.isNotEmpty) {
      return _messageState(
        accent: Colors.redAccent,
        onSurface: onSurface,
        icon: Icons.error_outline_rounded,
        title: "Could not load clipboard history",
        subtitle: _error,
      );
    }

    if (_historyEntries.isEmpty && _pinnedEntries.isEmpty) {
      return _messageState(
        accent: accent,
        onSurface: onSurface,
        icon: Icons.content_paste_off_rounded,
        title: "No clipboard history yet",
        subtitle: _enabled ? "Copy text or images and they will appear here." : "Enable clipboard history in settings.",
      );
    }

    return Column(
      children: <Widget>[
        _buildCommandRail(accent, onSurface),
        Expanded(
          child: Material(
            type: MaterialType.transparency,
            child: WindowsScrollView(
              controller: _scrollController,
              child: ListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 10),
                itemCount: (_pinnedEntries.isNotEmpty ? _pinnedEntries.length + 1 : 0) +
                    (_historyEntries.isNotEmpty ? _historyEntries.length + 1 : 0) +
                    (_loadingMore ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  int current = index;

                  // 1. Pinned Section
                  if (_pinnedEntries.isNotEmpty) {
                    if (current == 0) {
                      return _sectionLabel(
                        label: "Pinned",
                        accent: accent,
                        onSurface: onSurface,
                        icon: Icons.push_pin_rounded,
                        count: _pinnedEntries.length,
                      );
                    }
                    current--;
                    if (current < _pinnedEntries.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: _ClipboardHistoryTile(
                          entry: _pinnedEntries[current],
                          accent: accent,
                          onSurface: onSurface,
                          onCopy: () => _copy(_pinnedEntries[current]),
                          onDelete: () => _delete(_pinnedEntries[current]),
                          onPin: () => _togglePin(_pinnedEntries[current]),
                          onOpenImageFile: () => _openImageFile(_pinnedEntries[current]),
                        ),
                      );
                    }
                    current -= _pinnedEntries.length;
                  }

                  // 2. History Section
                  if (_historyEntries.isNotEmpty) {
                    if (current == 0) {
                      return _sectionLabel(
                        label: _pinnedEntries.isEmpty ? "Recent" : "History",
                        accent: accent,
                        onSurface: onSurface,
                        icon: Icons.history_rounded,
                        count: _historyEntries.length,
                      );
                    }
                    current--;
                    if (current < _historyEntries.length) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 7),
                        child: _ClipboardHistoryTile(
                          entry: _historyEntries[current],
                          accent: accent,
                          onSurface: onSurface,
                          onCopy: () => _copy(_historyEntries[current]),
                          onDelete: () => _delete(_historyEntries[current]),
                          onPin: () => _togglePin(_historyEntries[current]),
                          onOpenImageFile: () => _openImageFile(_historyEntries[current]),
                        ),
                      );
                    }
                    current -= _historyEntries.length;
                  }

                  // 3. Loading More
                  if (_loadingMore && current == 0) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        child: SizedBox.square(
                          dimension: 16,
                          child: CircularProgressIndicator(strokeWidth: 2, color: accent.withAlpha(150)),
                        ),
                      ),
                    );
                  }

                  return const SizedBox();
                },
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSearch(Color accent, Color onSurface) {
    return TextField(
      controller: _searchController,
      focusNode: _focusNode,
      style: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface),
      decoration: InputDecoration(
        isDense: true,
        hintText: "Search clipboard",
        hintStyle: TextStyle(fontSize: Design.baseFontSize + 2, color: onSurface.withAlpha(110)),
        prefixIcon: Icon(Icons.search_rounded, size: 15, color: accent),
        suffixIcon: _searchController.text.isEmpty
            ? null
            : IconButton(
                onPressed: _searchController.clear,
                padding: EdgeInsets.zero,
                iconSize: 14,
                icon: Icon(Icons.close_rounded, color: onSurface.withAlpha(130)),
              ),
        filled: true,
        fillColor: onSurface.withAlpha(7),
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: onSurface.withAlpha(24)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: onSurface.withAlpha(24)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: BorderSide(color: accent.withAlpha(100)),
        ),
      ),
    );
  }

  Widget _buildCommandRail(Color accent, Color onSurface) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 9),
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 7),
        decoration: BoxDecoration(
          color: onSurface.withAlpha(6),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: onSurface.withAlpha(15)),
        ),
        child: LayoutBuilder(
          builder: (BuildContext context, BoxConstraints constraints) {
            final bool isNarrow = constraints.maxWidth < 240;
            return Column(
              children: <Widget>[
                _buildSearch(accent, onSurface),
                const SizedBox(height: 7),
                if (isNarrow)
                  Wrap(
                    spacing: 12,
                    runSpacing: 6,
                    alignment: WrapAlignment.center,
                    children: <Widget>[
                      _statSegment(
                          "TOTAL", (_historyEntries.length + _pinnedEntries.length).toString(), accent, onSurface,
                          expanded: false),
                      _statSegment("PINNED", _pinnedEntries.length.toString(), accent, onSurface, expanded: false),
                      _statSegment(_enabled ? "LIVE" : "OFF", "${ClipboardHistoryStore.cacheDays}d", accent, onSurface,
                          expanded: false),
                    ],
                  )
                else
                  Row(
                    children: <Widget>[
                      _statSegment(
                          "TOTAL", (_pinnedEntries.length + _historyEntries.length).toString(), accent, onSurface),
                      _statDivider(onSurface),
                      _statSegment("PINNED", _pinnedEntries.length.toString(), accent, onSurface),
                      _statDivider(onSurface),
                      _statSegment(_enabled ? "LIVE" : "OFF", "${ClipboardHistoryStore.cacheDays}d", accent, onSurface),
                    ],
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _statSegment(String label, String value, Color accent, Color onSurface, {bool expanded = true}) {
    final Widget child = Row(
      mainAxisAlignment: MainAxisAlignment.center,
      mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
      children: <Widget>[
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.5,
              color: onSurface.withAlpha(105),
            ),
          ),
        ),
        const SizedBox(width: 5),
        Text(
          value,
          style: TextStyle(fontSize: Design.baseFontSize + 0.5, fontWeight: FontWeight.w700, color: accent),
        ),
      ],
    );
    return expanded ? Expanded(child: child) : child;
  }

  Widget _statDivider(Color onSurface) {
    return Container(width: 1, height: 13, color: onSurface.withAlpha(22));
  }

  Widget _sectionLabel({
    required String label,
    required Color accent,
    required Color onSurface,
    required IconData icon,
    required int count,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 7, 2, 8),
      child: Row(
        children: <Widget>[
          Icon(icon, size: 13, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              label.toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: Design.baseFontSize + 1,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.5,
                color: onSurface.withAlpha(185),
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            count.toString().padLeft(2, '0'),
            style: TextStyle(fontSize: Design.baseFontSize + 0.5, fontWeight: FontWeight.w700, color: accent),
          ),
          const SizedBox(width: 8),
          Expanded(child: Divider(height: 1, color: onSurface.withAlpha(20))),
        ],
      ),
    );
  }

  Widget _settingsRow({
    required Color accent,
    required Color onSurface,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget trailing,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 8),
      decoration: BoxDecoration(
        color: onSurface.withAlpha(7),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: onSurface.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: accent.withAlpha(24), borderRadius: BorderRadius.circular(8)),
            child: Icon(icon, size: 15, color: accent),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(title,
                    style:
                        TextStyle(fontSize: Design.baseFontSize + 2.5, fontWeight: FontWeight.w700, color: onSurface)),
                const SizedBox(height: 2),
                Text(subtitle,
                    style:
                        TextStyle(fontSize: Design.baseFontSize + 0.5, color: onSurface.withAlpha(150), height: 1.25)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          trailing,
        ],
      ),
    );
  }

  Widget _messageState({
    required Color accent,
    required Color onSurface,
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            Icon(icon, size: 32, color: accent),
            const SizedBox(height: 10),
            Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: onSurface)),
            const SizedBox(height: 5),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: Design.baseFontSize + 1, color: onSurface.withAlpha(150), height: 1.25),
            ),
          ],
        ),
      ),
    );
  }
}

class _ClipboardHistoryTile extends StatefulWidget {
  const _ClipboardHistoryTile({
    required this.entry,
    required this.accent,
    required this.onSurface,
    required this.onCopy,
    required this.onDelete,
    required this.onPin,
    required this.onOpenImageFile,
  });

  final ClipboardHistoryEntry entry;
  final Color accent;
  final Color onSurface;
  final VoidCallback onCopy;
  final VoidCallback onDelete;
  final VoidCallback onPin;
  final VoidCallback onOpenImageFile;

  @override
  State<_ClipboardHistoryTile> createState() => _ClipboardHistoryTileState();
}

class _ClipboardHistoryTileState extends State<_ClipboardHistoryTile> {
  bool _hovered = false;
  OverlayEntry? _previewEntry;

  @override
  void dispose() {
    _hidePreview();
    super.dispose();
  }

  void _showImagePreview(BuildContext context) {
    if (_previewEntry != null) return;
    final ClipboardHistoryEntry entry = widget.entry;
    if (entry.type != ClipboardHistoryType.image || !File(entry.imagePath).existsSync()) return;

    final RenderBox? renderBox = context.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset offset = renderBox.localToGlobal(Offset.zero);
    final Size size = renderBox.size;
    const double thumbnailWidth = 54;
    final double left = offset.dx + thumbnailWidth + 12;
    final double width = (size.width - thumbnailWidth - 42).clamp(120.0, 280.0);
    final double height = (width * 0.66).clamp(110.0, 210.0);

    _previewEntry = OverlayEntry(
      builder: (BuildContext context) => Positioned(
        left: left,
        top: offset.dy - 24,
        child: Material(
          elevation: 10,
          color: Colors.black,
          borderRadius: BorderRadius.circular(10),
          clipBehavior: Clip.antiAlias,
          child: Container(
            width: width,
            height: height,
            decoration: BoxDecoration(
              border: Border.all(color: Colors.white.withAlpha(30)),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Stack(
              fit: StackFit.expand,
              children: <Widget>[
                Image.file(
                  File(entry.imagePath),
                  fit: BoxFit.contain,
                  gaplessPlayback: true,
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: Colors.black.withAlpha(165),
                    child: Text(
                      '${(entry.byteLength / 1024).toStringAsFixed(1)} KB',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: Colors.white, fontSize: Design.baseFontSize, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_previewEntry!);
  }

  void _hidePreview() {
    _previewEntry?.remove();
    _previewEntry?.dispose();
    _previewEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final ClipboardHistoryEntry entry = widget.entry;
    final String time = DateFormat('MMM d, HH:mm').format(entry.createdAt);
    final bool highlighted = entry.pinned || _hovered;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: InkWell(
        onTap: widget.onCopy,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.fromLTRB(9, 4, 8, 4),
          decoration: BoxDecoration(
            color: highlighted ? widget.accent.withAlpha(entry.pinned ? 10 : 8) : widget.onSurface.withAlpha(7),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: highlighted ? widget.accent.withAlpha(entry.pinned ? 30 : 24) : widget.onSurface.withAlpha(16),
            ),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: <Widget>[
              if (entry.type == ClipboardHistoryType.image) _preview(entry),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Icon(
                          entry.pinned ? Icons.push_pin_rounded : _typeIcon(entry),
                          size: 12,
                          color: entry.pinned ? widget.accent : widget.onSurface.withAlpha(135),
                        ),
                        const SizedBox(width: 5),
                        Flexible(
                          child: Text(
                            "${entry.type == ClipboardHistoryType.image ? "IMAGE" : "${(entry.textLength ?? entry.text.length).formatNum()} chars"}",
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: Design.baseFontSize + 0.5,
                              fontWeight: FontWeight.w700,
                              color: entry.pinned ? widget.accent : widget.onSurface.withAlpha(155),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            time,
                            overflow: TextOverflow.ellipsis,
                            style:
                                TextStyle(fontSize: Design.baseFontSize + 0.5, color: widget.onSurface.withAlpha(120)),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 5),
                    Text(
                      _summary(entry),
                      maxLines: entry.type == ClipboardHistoryType.image ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: Design.baseFontSize + 2, height: 1.25, color: widget.onSurface.withAlpha(210)),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _actionRail(entry),
            ],
          ),
        ),
      ),
    );
  }

  Widget _actionButton({
    required String message,
    required IconData icon,
    required VoidCallback? onPressed,
    bool active = false,
  }) {
    return CustomTooltip(
      message: message,
      child: IconButton(
        onPressed: onPressed,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
        iconSize: 16,
        icon: Icon(
          icon,
          color: active ? widget.accent : widget.onSurface.withAlpha(onPressed == null ? 55 : 120),
        ),
      ),
    );
  }

  Widget _actionRail(ClipboardHistoryEntry entry) {
    return Container(
      width: 36,
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: CancelTraversal(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            _actionButton(
              message: entry.pinned ? "Unpin" : "Pin",
              icon: entry.pinned ? Icons.push_pin_rounded : Icons.push_pin_outlined,
              active: entry.pinned,
              onPressed: widget.onPin,
            ),
            Container(width: 14, height: 1, color: widget.onSurface.withAlpha(14)),
            _actionButton(
              message: "Delete",
              icon: Icons.close_rounded,
              onPressed: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _preview(ClipboardHistoryEntry entry) {
    if (entry.type == ClipboardHistoryType.image && File(entry.imagePath).existsSync()) {
      return MouseRegion(
        onEnter: (_) => _showImagePreview(context),
        onExit: (_) => _hidePreview(),
        child: SizedBox(
          width: 54,
          height: 54,
          child: Stack(
            clipBehavior: Clip.none,
            children: <Widget>[
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(9),
                  child: Image.file(
                    File(entry.imagePath),
                    fit: BoxFit.cover,
                    cacheWidth: 108,
                    cacheHeight: 108,
                    gaplessPlayback: true,
                  ),
                ),
              ),
              Positioned(
                top: 3,
                right: 3,
                child: _thumbnailOpenButton(),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox();

    // return Container(
    //   width: 54,
    //   height: 54,
    //   alignment: Alignment.center,
    //   decoration: BoxDecoration(
    //     color: widget.onSurface.withAlpha(7),
    //     borderRadius: BorderRadius.circular(8),
    //     border: Border.all(color: widget.onSurface.withAlpha(16)),
    //   ),
    //   child: Icon(
    //     entry.type == ClipboardHistoryType.richText ? Icons.code_rounded : Icons.text_snippet_rounded,
    //     size: 18,
    //     color: widget.accent,
    //   ),
    // );
  }

  Widget _thumbnailOpenButton() {
    return CustomTooltip(
      message: "Open image file",
      child: InkWell(
        onTap: widget.onOpenImageFile,
        borderRadius: BorderRadius.circular(6),
        child: Container(
          width: 19,
          height: 19,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: Colors.black.withAlpha(150),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: Colors.white.withAlpha(35)),
          ),
          child: const Icon(Icons.open_in_new_rounded, size: 11, color: Colors.white),
        ),
      ),
    );
  }

  String _summary(ClipboardHistoryEntry entry) {
    if (entry.type == ClipboardHistoryType.image) {
      return '${(entry.byteLength / 1024).toStringAsFixed(1)} KB image';
    }
    final String source = entry.text.isNotEmpty ? entry.text : entry.html;
    return source.replaceAll(RegExp(r'\s+'), ' ').trim() + ((entry.textLength ?? 0) > source.length ? '...' : '');
  }

  IconData _typeIcon(ClipboardHistoryEntry entry) {
    switch (entry.type) {
      case ClipboardHistoryType.text:
        return Icons.text_snippet_rounded;
      case ClipboardHistoryType.richText:
        return Icons.code_rounded;
      case ClipboardHistoryType.image:
        return Icons.image_rounded;
    }
  }
}
