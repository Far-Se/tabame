import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/util/quick_action_list.dart';

class QuickmenuTopbar extends StatefulWidget {
  const QuickmenuTopbar({super.key});

  @override
  QuickmenuTopbarState createState() => QuickmenuTopbarState();
}

class QuickmenuTopbarState extends State<QuickmenuTopbar> {
  List<String> topBarItems = Boxes().topBarWidgets;
  final Map<String, IconData> icons = <String, IconData>{};
  final ScrollController _previewController = ScrollController();

  @override
  void initState() {
    super.initState();
    icons.addAll(quickActionsMap.map((String key, QuickAction value) => MapEntry<String, IconData>(key, value.icon)));
    icons["Deactivated:"] = Icons.do_not_disturb_on_rounded;

    // cleanup
    bool foundDeactivated = false;
    for (int i = 0; i < topBarItems.length; i++) {
      if (topBarItems[i] == "Deactivated:") {
        foundDeactivated = true;
        continue;
      }
      if (!icons.containsKey(topBarItems[i])) {
        topBarItems.removeAt(i);
        i--;
      }
    }
    if (!foundDeactivated) {
      topBarItems.add("Deactivated:");
    }

    Boxes.updateSettings("topBarWidgets", topBarItems);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _previewController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(context),
        Expanded(
          child: ReorderableListView.builder(
            buildDefaultDragHandles: false,
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 80),
            itemCount: topBarItems.length,
            onReorder: _reorderQuickActions,
            proxyDecorator: (Widget child, int index, Animation<double> animation) {
              return Material(
                color: Colors.transparent,
                child: Opacity(opacity: 0.8, child: child),
              );
            },
            itemBuilder: (BuildContext context, int index) {
              final String item = topBarItems[index];
              final int thresholdIndex = topBarItems.indexOf("Deactivated:");
              final bool isActive = index < thresholdIndex;
              final bool isThreshold = item == "Deactivated:";

              return _QuickActionRow(
                key: ValueKey<String>("qa_$item"),
                item: item,
                index: index,
                isActive: isActive,
                isThreshold: isThreshold,
                icon: icons[item] ?? Icons.circle_outlined,
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            "TOOLBAR ORCHESTRATOR",
            style: theme.textTheme.displaySmall?.copyWith(
              fontSize: 24,
              fontWeight: FontWeight.w700,
              letterSpacing: -1,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            "Curate your top-bar priority and active states",
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: theme.hintColor.withValues(alpha: 0.8),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _reorderQuickActions(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    setState(() {
      final String item = topBarItems.removeAt(oldIndex);
      topBarItems.insert(newIndex, item);
    });
    await Boxes.updateSettings("topBarWidgets", topBarItems);
  }
}

class _QuickActionRow extends StatefulWidget {
  final String item;
  final int index;
  final bool isActive;
  final bool isThreshold;
  final IconData icon;

  const _QuickActionRow({
    required super.key,
    required this.item,
    required this.index,
    required this.isActive,
    required this.isThreshold,
    required this.icon,
  });

  @override
  State<_QuickActionRow> createState() => _QuickActionRowState();
}

class _QuickActionRowState extends State<_QuickActionRow> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    final Color primary = theme.colorScheme.primary;

    if (widget.isThreshold) return _buildThresholdMarker(theme);

    return Opacity(
      opacity: widget.isActive ? 1.0 : 0.5,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: MouseRegion(
          onEnter: (_) => setState(() => _isHovered = true),
          onExit: (_) => setState(() => _isHovered = false),
          child: ReorderableDragStartListener(
            index: widget.index,
            child: AnimatedScale(
              scale: _isHovered ? 1.01 : 1.0,
              duration: const Duration(milliseconds: 200),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: widget.isActive
                        ? (_isHovered
                            ? <Color>[
                                primary.withValues(alpha: 0.08),
                                primary.withValues(alpha: 0.15),
                                primary.withValues(alpha: 0.20),
                                primary.withValues(alpha: 0.20)
                              ]
                            : <Color>[primary.withValues(alpha: 0.08), primary.withValues(alpha: 0.04)])
                        : (_isHovered
                            ? <Color>[
                                onSurface.withValues(alpha: 0.05),
                                onSurface.withValues(alpha: 0.15),
                                onSurface.withValues(alpha: 0.15),
                                onSurface.withValues(alpha: 0.15)
                              ]
                            : <Color>[onSurface.withValues(alpha: 0.03), onSurface.withValues(alpha: 0.08)]),
                  ),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _isHovered ? primary.withValues(alpha: 0.3) : onSurface.withValues(alpha: 0.08),
                    width: 1.5,
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    MouseRegion(
                      cursor: SystemMouseCursors.resizeUpDown,
                      child: Icon(Icons.drag_indicator_rounded, size: 20, color: onSurface.withValues(alpha: 0.2)),
                    ),
                    const SizedBox(width: 16),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: widget.isActive ? primary.withValues(alpha: 0.1) : onSurface.withValues(alpha: 0.05),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Icon(widget.icon,
                          size: 18, color: widget.isActive ? primary : onSurface.withValues(alpha: 0.4)),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Text(
                        _formatItemLabel(widget.item),
                        style: TextStyle(
                          fontWeight: FontWeight.w600,
                          fontSize: 14,
                          color: widget.isActive ? onSurface : onSurface.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (widget.isActive)
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          "ACTIVE",
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: primary),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildThresholdMarker(ThemeData theme) {
    return ReorderableDragStartListener(
      index: widget.index,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeUpDown,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 20),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                theme.colorScheme.error.withValues(alpha: 0.15),
                theme.colorScheme.error.withValues(alpha: 0.05),
              ],
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: theme.colorScheme.error.withValues(alpha: 0.3), width: 1.5),
          ),
          child: Row(
            children: <Widget>[
              Icon(Icons.do_not_disturb_on_rounded, color: theme.colorScheme.error, size: 20),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      "SYSTEM THRESHOLD",
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        color: theme.colorScheme.error,
                        letterSpacing: 1,
                      ),
                    ),
                    Text(
                      "Actions below this line are hidden from the top bar",
                      style: TextStyle(fontSize: 11, color: theme.colorScheme.error.withValues(alpha: 0.7)),
                    ),
                  ],
                ),
              ),
              Icon(Icons.drag_indicator_rounded, color: theme.colorScheme.error.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }

  String _formatItemLabel(String item) {
    return item
        .replaceAllMapped(RegExp(r'([A-Z])', caseSensitive: true), (Match match) => ' ${match[0]}')
        .replaceAll("Button", "")
        .trim();
  }
}
