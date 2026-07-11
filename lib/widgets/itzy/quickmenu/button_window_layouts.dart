import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/classes/saved_maps.dart';
import '../../../models/settings.dart';
import '../../../models/util/window_layout_snapshots.dart';
import '../../widgets/modal_button.dart';
import '../../widgets/panel_header.dart';
import '../../widgets/windows_scroll.dart';

class WindowLayoutsButton extends StatelessWidget {
  const WindowLayoutsButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ModalButton(
      actionName: 'Window Layouts',
      icon: const Icon(Icons.view_quilt_outlined),
      child: () => const WindowLayoutsPanel(),
    );
  }
}

class WindowLayoutsPanel extends StatefulWidget {
  const WindowLayoutsPanel({super.key});

  @override
  State<WindowLayoutsPanel> createState() => _WindowLayoutsPanelState();
}

class _WindowLayoutsPanelState extends State<WindowLayoutsPanel> {
  final TextEditingController _nameController = TextEditingController();
  String _currentSignature = '';
  String _status = '';
  bool _busy = false;
  String _confirmDeleteId = '';
  Timer? _confirmDeleteTimer;
  String _editingId = '';

  List<WindowLayoutSnapshot> get _layouts => Boxes.windowLayouts;

  @override
  void initState() {
    super.initState();
    _currentSignature = WindowLayoutSnapshots.monitorSignature();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _confirmDeleteTimer?.cancel();
    super.dispose();
  }

  Future<void> _captureNew() async {
    if (_busy) return;
    setState(() => _busy = true);

    String name = _nameController.text.trim();
    if (name.isEmpty) name = 'Layout ${_layouts.length + 1}';
    final WindowLayoutSnapshot snapshot = await WindowLayoutSnapshots.capture(name);

    Boxes.windowLayouts = <WindowLayoutSnapshot>[..._layouts, snapshot];
    _nameController.clear();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = 'Captured ${snapshot.entries.length} windows as "$name"';
    });
  }

  Future<void> _restore(WindowLayoutSnapshot snapshot) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _status = 'Restoring "${snapshot.name}"...';
    });

    final ({int missing, int restored}) result = await WindowLayoutSnapshots.restore(snapshot);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = result.missing == 0
          ? 'Restored all ${result.restored} windows'
          : 'Restored ${result.restored} windows · ${result.missing} not running';
    });
    await Future<void>.delayed(const Duration(milliseconds: 700));
    QuickMenuFunctions.hideQuickMenu();
  }

  Future<void> _updateSnapshot(WindowLayoutSnapshot snapshot) async {
    if (_busy) return;
    setState(() => _busy = true);

    final WindowLayoutSnapshot fresh = await WindowLayoutSnapshots.capture(snapshot.name);
    final List<WindowLayoutSnapshot> updated = _layouts.map((WindowLayoutSnapshot s) {
      if (s.id != snapshot.id) return s;
      return s.copyWith(
        createdAt: fresh.createdAt,
        monitorSignature: fresh.monitorSignature,
        entries: fresh.entries,
      );
    }).toList();
    Boxes.windowLayouts = updated;
    if (!mounted) return;
    setState(() {
      _busy = false;
      _status = 'Updated "${snapshot.name}" · ${fresh.entries.length} windows';
    });
  }

  void _toggleAutoRestore(WindowLayoutSnapshot snapshot) {
    Boxes.windowLayouts = _layouts.map((WindowLayoutSnapshot s) {
      if (s.id != snapshot.id) return s;
      return s.copyWith(autoRestore: !s.autoRestore);
    }).toList();
    setState(() {});
  }

  void _delete(WindowLayoutSnapshot snapshot) {
    if (_confirmDeleteId != snapshot.id) {
      setState(() => _confirmDeleteId = snapshot.id);
      _confirmDeleteTimer?.cancel();
      _confirmDeleteTimer = Timer(const Duration(seconds: 3), () {
        if (mounted) setState(() => _confirmDeleteId = '');
      });
      return;
    }
    _confirmDeleteTimer?.cancel();
    Boxes.windowLayouts = _layouts.where((WindowLayoutSnapshot s) => s.id != snapshot.id).toList();
    setState(() {
      _confirmDeleteId = '';
      if (_editingId == snapshot.id) _editingId = '';
      _status = 'Deleted "${snapshot.name}"';
    });
  }

  void _toggleEdit(WindowLayoutSnapshot snapshot) {
    setState(() => _editingId = _editingId == snapshot.id ? '' : snapshot.id);
  }

  void _removeEntry(WindowLayoutSnapshot snapshot, int index) {
    Boxes.windowLayouts = _layouts.map((WindowLayoutSnapshot s) {
      if (s.id != snapshot.id) return s;
      final List<WindowLayoutEntry> entries = List<WindowLayoutEntry>.from(s.entries);
      if (index >= 0 && index < entries.length) entries.removeAt(index);
      return s.copyWith(entries: entries);
    }).toList();
    setState(() {
      _status = 'Removed app from "${snapshot.name}"';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        const PanelHeader(
          title: 'Window Layouts',
          icon: Icons.view_quilt_rounded,
        ),
        Flexible(
          child: Material(
            type: MaterialType.transparency,
            child: WindowsScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 10),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _buildCaptureCard(),
                    if (_status.isNotEmpty) ...<Widget>[
                      const SizedBox(height: 6),
                      _buildStatusStrip(),
                    ],
                    const SizedBox(height: 10),
                    _buildSectionLabel(label: 'Saved Layouts', count: _layouts.length, icon: Icons.grid_view_rounded),
                    const SizedBox(height: 8),
                    if (_layouts.isEmpty)
                      _buildEmptyState()
                    else
                      for (final WindowLayoutSnapshot snapshot in _layouts) ...<Widget>[
                        _buildLayoutRow(snapshot),
                        const SizedBox(height: 6),
                      ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCaptureCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: Row(
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _nameController,
              enabled: !_busy,
              onSubmitted: (String _) => _captureNew(),
              style: TextStyle(fontSize: Design.baseFontSize + 1.5),
              decoration: InputDecoration(
                isDense: true,
                hintText: 'Layout name (optional)',
                hintStyle: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(90)),
                contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Design.text.withAlpha(30)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: BorderSide(color: Design.text.withAlpha(30)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          InkWell(
            onTap: _busy ? null : _captureNew,
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 14),
              decoration: BoxDecoration(
                color: Design.accent.withAlpha(28),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Design.accent.withAlpha(80)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: <Widget>[
                  if (_busy)
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Design.accent),
                    )
                  else
                    Icon(Icons.center_focus_strong_rounded, size: 14, color: Design.accent),
                  const SizedBox(width: 6),
                  Text(
                    'CAPTURE',
                    style: TextStyle(
                      fontSize: Design.baseFontSize + 0.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                      color: Design.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusStrip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: Design.accent.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Design.accent.withAlpha(30)),
      ),
      child: Text(
        _status,
        style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: Design.accent, fontWeight: FontWeight.w600),
      ),
    );
  }

  Widget _buildSectionLabel({required String label, required int count, required IconData icon}) {
    return Row(
      children: <Widget>[
        Icon(icon, size: 14, color: Design.accent),
        const SizedBox(width: 6),
        Text(
          label.toUpperCase(),
          style: TextStyle(
            fontSize: Design.baseFontSize + 1,
            fontWeight: FontWeight.w700,
            letterSpacing: 0.5,
            color: Design.text,
          ),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          decoration: BoxDecoration(color: Design.accent.withAlpha(28), borderRadius: BorderRadius.circular(99)),
          child: Text('$count', style: TextStyle(fontSize: Design.baseFontSize, color: Design.accent)),
        ),
        const SizedBox(width: 8),
        Expanded(child: Divider(height: 1, color: Design.text.withAlpha(20))),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28),
      child: Column(
        children: <Widget>[
          Icon(Icons.view_quilt_rounded, size: 42, color: Design.text.withAlpha(38)),
          const SizedBox(height: 12),
          Text(
            'No layouts captured',
            style: TextStyle(fontSize: 13, color: Design.text.withAlpha(150)),
          ),
          const SizedBox(height: 4),
          Text(
            'Capture the current window arrangement, restore it anytime',
            style: TextStyle(fontSize: Design.baseFontSize + 1, color: Design.text.withAlpha(110)),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutRow(WindowLayoutSnapshot snapshot) {
    final bool monitorsMatch = snapshot.monitorSignature == _currentSignature;
    final bool confirmingDelete = _confirmDeleteId == snapshot.id;
    final bool editing = _editingId == snapshot.id;
    final int monitorCount = snapshot.monitorSignature.isEmpty ? 1 : snapshot.monitorSignature.split('|').length;

    return Container(
      decoration: BoxDecoration(
        color: Design.text.withAlpha(7),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: editing ? Design.accent.withAlpha(70) : Design.text.withAlpha(16)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          InkWell(
        onTap: () => _restore(snapshot),
        borderRadius: BorderRadius.circular(10),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          child: Row(
            children: <Widget>[
              Icon(
                Icons.view_quilt_rounded,
                size: 18,
                color: monitorsMatch ? Design.accent : Design.text.withAlpha(90),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Row(
                      children: <Widget>[
                        Flexible(
                          child: Text(
                            snapshot.name,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                        ),
                        if (!monitorsMatch) ...<Widget>[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withAlpha(24),
                              borderRadius: BorderRadius.circular(99),
                            ),
                            child: Text(
                              '≠ MONITORS',
                              style: TextStyle(
                                fontSize: Design.baseFontSize - 1,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.4,
                                color: Colors.orange.shade400,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${snapshot.entries.length} windows · $monitorCount monitor${monitorCount == 1 ? '' : 's'} · ${_formatDate(snapshot.createdAt)}',
                      style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: Design.text.withAlpha(140)),
                    ),
                  ],
                ),
              ),
              _rowIconButton(
                icon: Icons.bolt_rounded,
                tooltip: snapshot.autoRestore
                    ? 'Auto-restore on this monitor setup: ON'
                    : 'Auto-restore when this monitor setup is detected',
                color: snapshot.autoRestore ? Design.accent : Design.text.withAlpha(80),
                onTap: () => _toggleAutoRestore(snapshot),
              ),
              _rowIconButton(
                icon: editing ? Icons.edit_rounded : Icons.edit_outlined,
                tooltip: editing ? 'Done editing' : 'Edit apps in this layout',
                color: editing ? Design.accent : Design.text.withAlpha(120),
                onTap: () => _toggleEdit(snapshot),
              ),
              _rowIconButton(
                icon: Icons.refresh_rounded,
                tooltip: 'Re-capture current windows into this layout',
                color: Design.text.withAlpha(120),
                onTap: () => _updateSnapshot(snapshot),
              ),
              _rowIconButton(
                icon: confirmingDelete ? Icons.delete_forever_rounded : Icons.delete_outline_rounded,
                tooltip: confirmingDelete ? 'Tap again to delete' : 'Delete layout',
                color: confirmingDelete ? Colors.red.shade400 : Design.text.withAlpha(120),
                onTap: () => _delete(snapshot),
              ),
            ],
          ),
        ),
          ),
          if (editing) _buildEditPanel(snapshot),
        ],
      ),
    );
  }

  Widget _buildEditPanel(WindowLayoutSnapshot snapshot) {
    return Container(
      margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      decoration: BoxDecoration(
        color: Design.text.withAlpha(10),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Design.text.withAlpha(16)),
      ),
      child: snapshot.entries.isEmpty
          ? Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: Text(
                  'No apps in this layout',
                  style: TextStyle(fontSize: Design.baseFontSize + 0.5, color: Design.text.withAlpha(120)),
                ),
              ),
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                for (int i = 0; i < snapshot.entries.length; i++) _buildEntryRow(snapshot, i),
              ],
            ),
    );
  }

  Widget _buildEntryRow(WindowLayoutSnapshot snapshot, int index) {
    final WindowLayoutEntry entry = snapshot.entries[index];
    final String primary = entry.title.isNotEmpty ? entry.title : entry.exe;
    final bool showExe = entry.title.isNotEmpty && entry.exe.isNotEmpty;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
      child: Row(
        children: <Widget>[
          Icon(Icons.crop_square_rounded, size: 13, color: Design.text.withAlpha(90)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  primary,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600, color: Design.text),
                ),
                if (showExe)
                  Text(
                    entry.exe,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: Design.baseFontSize - 0.5, color: Design.text.withAlpha(110)),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          _rowIconButton(
            icon: Icons.close_rounded,
            tooltip: 'Remove this app from the layout',
            color: Colors.red.shade400.withAlpha(200),
            onTap: () => _removeEntry(snapshot, index),
          ),
        ],
      ),
    );
  }

  Widget _rowIconButton({
    required IconData icon,
    required String tooltip,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: Padding(
          padding: const EdgeInsets.all(5),
          child: Icon(icon, size: 16, color: color),
        ),
      ),
    );
  }

  static const List<String> _months = <String>[
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec' //
  ];

  String _formatDate(int millisecondsSinceEpoch) {
    if (millisecondsSinceEpoch <= 0) return '';
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch);
    final DateTime now = DateTime.now();
    if (date.year == now.year && date.month == now.month && date.day == now.day) {
      return 'today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    }
    return '${date.day} ${_months[date.month - 1]}';
  }
}
