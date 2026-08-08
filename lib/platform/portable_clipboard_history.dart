import 'package:flutter/material.dart';

import '../models/clipboard_history.dart';
import 'clipboard_service.dart';
import 'platform_capabilities.dart';

/// Small text-first history surface for the portable launcher shell.
///
/// Rich/image entries remain visible as unavailable metadata rather than being
/// silently interpreted as text. The feature is only exposed when the active
/// adapter reports clipboard monitoring capability.
class PortableClipboardHistoryPanel extends StatefulWidget {
  const PortableClipboardHistoryPanel({super.key});

  @override
  State<PortableClipboardHistoryPanel> createState() => _PortableClipboardHistoryPanelState();
}

class _PortableClipboardHistoryPanelState extends State<PortableClipboardHistoryPanel> {
  final TextEditingController _searchController = TextEditingController();
  List<ClipboardHistoryEntry> _entries = const <ClipboardHistoryEntry>[];
  bool _loading = true;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_reload);
    _reload();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_reload)
      ..dispose();
    super.dispose();
  }

  Future<void> _reload() async {
    if (mounted) setState(() => _loading = true);
    try {
      final List<ClipboardHistoryEntry> entries = await ClipboardHistoryStore.loadPaged(
        limit: 60,
        query: _searchController.text,
      );
      if (!mounted) return;
      setState(() {
        _entries = entries;
        _loading = false;
        _error = '';
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '$error';
      });
    }
  }

  Future<void> _copy(ClipboardHistoryEntry entry) async {
    await ClipboardHistoryStore.copyEntry(entry);
    if (mounted) setState(() {});
  }

  Future<void> _clear() async {
    await ClipboardHistoryStore.clear();
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final PlatformCapabilities capabilities = PlatformCapabilities.current;
    if (!capabilities.clipboardMonitoring) {
      return Center(
        child: Text(
          ClipboardService.instance.unavailableReason,
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search_rounded),
                  hintText: 'Search text history',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton(tooltip: 'Refresh', onPressed: _reload, icon: const Icon(Icons.refresh_rounded)),
            IconButton(
                tooltip: 'Clear', onPressed: _entries.isEmpty ? null : _clear, icon: const Icon(Icons.delete_outline)),
          ],
        ),
        const SizedBox(height: 10),
        Expanded(child: _buildEntries()),
      ],
    );
  }

  Widget _buildEntries() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error.isNotEmpty) return Center(child: Text(_error));
    if (_entries.isEmpty) {
      return const Center(child: Text('No text clipboard changes have been saved yet.'));
    }

    return ListView.separated(
      itemCount: _entries.length,
      separatorBuilder: (_, __) => const Divider(height: 1),
      itemBuilder: (BuildContext context, int index) {
        final ClipboardHistoryEntry entry = _entries[index];
        final bool usable = entry.text.isNotEmpty;
        return ListTile(
          dense: true,
          leading: Icon(usable ? Icons.content_copy_rounded : Icons.image_not_supported_outlined),
          title: Text(
            usable ? entry.text : 'Non-text clipboard entry (unsupported here)',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          subtitle: Text(entry.createdAt.toLocal().toString()),
          onTap: usable ? () => _copy(entry) : null,
        );
      },
    );
  }
}
