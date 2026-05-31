import 'dart:async';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/util/quick_action_list.dart';
import '../../widgets/windows_scroll.dart';

class QuickmenuTopbar extends StatefulWidget {
  const QuickmenuTopbar({super.key});

  @override
  QuickmenuTopbarState createState() => QuickmenuTopbarState();
}

class QuickmenuTopbarState extends State<QuickmenuTopbar> {
  List<String> activeItems = <String>[];
  List<String> disabledItems = <String>[];
  final Map<String, IconData> icons = <String, IconData>{};
  String? _hoveredItem;

  final ScrollController _activeScrollController = ScrollController();
  final ScrollController _disabledScrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _disabledSearchQuery = '';
  final GlobalKey _activeColumnKey = GlobalKey();
  final GlobalKey _disabledColumnKey = GlobalKey();

  bool _isDragging = false;
  Timer? _scrollTimer;

  @override
  void initState() {
    super.initState();
    icons.addAll(quickActionsMap.map((String key, QuickAction value) => MapEntry<String, IconData>(key, value.icon)));

    final List<String> topBarItems = Boxes().topBarWidgets;
    bool foundDeactivated = false;

    for (final String item in topBarItems) {
      if (item == "Deactivated:") {
        foundDeactivated = true;
        continue;
      }
      if (icons.containsKey(item)) {
        if (foundDeactivated) {
          disabledItems.add(item);
        } else {
          activeItems.add(item);
        }
      }
    }
    _saveDefaults();
  }

  void _saveDefaults() {
    Boxes.updateSettings("topBarWidgets", <String>[...activeItems, "Deactivated:", ...disabledItems]);
  }

  @override
  void dispose() {
    _activeScrollController.dispose();
    _disabledScrollController.dispose();
    _searchController.dispose();
    _scrollTimer?.cancel();
    super.dispose();
  }

  void _onItemDropped(String draggedItem, String? targetItem, bool targetIsActive) {
    setState(() {
      activeItems.remove(draggedItem);
      disabledItems.remove(draggedItem);

      final List<String> targetList = targetIsActive ? activeItems : disabledItems;
      if (targetItem == null) {
        targetList.add(draggedItem);
      } else {
        final int targetIndex = targetList.indexOf(targetItem);
        if (targetIndex != -1) {
          targetList.insert(targetIndex, draggedItem);
        } else {
          targetList.add(draggedItem);
        }
      }
      _hoveredItem = null;
    });
    _saveDefaults();
  }

  void _onItemHovered(String? item) {
    if (_hoveredItem != item) {
      setState(() => _hoveredItem = item);
    }
  }

  void _handlePointerMove(PointerMoveEvent event, bool isActive) {
    if (!_isDragging) return;

    final GlobalKey key = isActive ? _activeColumnKey : _disabledColumnKey;
    final ScrollController controller = isActive ? _activeScrollController : _disabledScrollController;

    final RenderBox? renderBox = key.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) return;

    final Offset localOffset = renderBox.globalToLocal(event.position);
    final double height = renderBox.size.height;
    const double scrollZone = 40.0;

    if (localOffset.dy < scrollZone) {
      // Near top
      final double speed = ((scrollZone - localOffset.dy) / scrollZone).clamp(0.1, 1.0) * 20;
      _startAutoScroll(controller, -speed);
    } else if (localOffset.dy > height - scrollZone) {
      // Near bottom
      final double speed = ((localOffset.dy - (height - scrollZone)) / scrollZone).clamp(0.1, 1.0) * 20;
      _startAutoScroll(controller, speed);
    } else {
      _stopAutoScroll();
    }
  }

  void _startAutoScroll(ScrollController controller, double delta) {
    if (_scrollTimer?.isActive ?? false) return;

    _scrollTimer = Timer.periodic(const Duration(milliseconds: 16), (Timer timer) {
      if (!controller.hasClients) {
        timer.cancel();
        return;
      }

      final double newOffset = (controller.offset + delta).clamp(
        0.0,
        controller.position.maxScrollExtent,
      );

      if (newOffset != controller.offset) {
        controller.jumpTo(newOffset);
      } else {
        timer.cancel();
      }
    });
  }

  void _stopAutoScroll() {
    _scrollTimer?.cancel();
    _scrollTimer = null;
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: <Widget>[
        _buildHeader(context),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                Expanded(
                  child: Listener(
                    onPointerMove: (PointerMoveEvent e) => _handlePointerMove(e, true),
                    onPointerUp: (_) => _stopAutoScroll(),
                    child: _buildColumn(context, true, activeItems),
                  ),
                ),
                const SizedBox(height: 16),
                Expanded(
                  child: Listener(
                    onPointerMove: (PointerMoveEvent e) => _handlePointerMove(e, false),
                    onPointerUp: (_) => _stopAutoScroll(),
                    child: _buildColumn(
                        context,
                        false,
                        _disabledSearchQuery.isEmpty
                            ? disabledItems
                            : disabledItems
                                .where((String item) => item.toLowerCase().contains(_disabledSearchQuery))
                                .toList()),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          // Title + subheader
          Column(
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
        ],
      ),
    );
  }

  Widget _buildColumn(BuildContext context, bool isActive, List<String> items) {
    final ThemeData theme = Theme.of(context);
    final Color primary = theme.colorScheme.primary;
    final Color onSurface = theme.colorScheme.onSurface;

    return DragTarget<String>(
      onWillAcceptWithDetails: (DragTargetDetails<String> details) {
        _onItemHovered(isActive ? "_area_active_" : "_area_disabled_");
        return true;
      },
      onLeave: (_) => _onItemHovered(null),
      onAcceptWithDetails: (DragTargetDetails<String> details) {
        _onItemDropped(details.data, null, isActive);
      },
      builder: (BuildContext context, List<String?> candidateData, List<dynamic> rejectedData) {
        final bool isAreaHovered = _hoveredItem == (isActive ? "_area_active_" : "_area_disabled_");

        return AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isAreaHovered
                ? (isActive ? primary.withValues(alpha: 0.05) : onSurface.withValues(alpha: 0.03))
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: isActive ? primary.withValues(alpha: 0.2) : onSurface.withValues(alpha: 0.1),
              width: 1.5,
            ),
          ),
          key: isActive ? _activeColumnKey : _disabledColumnKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              // Column Header
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: <Widget>[
                  Icon(
                    isActive ? Icons.generating_tokens_rounded : Icons.do_not_disturb_on_rounded,
                    size: 16,
                    color: isActive ? primary : onSurface.withValues(alpha: 0.5),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: <Widget>[
                        Text(
                          isActive ? "ACTIVE" : "DISABLED",
                          style: TextStyle(
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1.2,
                            fontSize: 12,
                            color: isActive ? primary : onSurface.withValues(alpha: 0.6),
                          ),
                        ),
                        if (!isActive)
                          InkWell(
                            onTap: () {
                              disabledItems.sort((String a, String b) => a.compareTo(b));
                              setState(() {});
                            },
                            child: const Text("Sort"),
                          ),
                        if (isActive)
                          Text(
                            "Order implies priority. Drag on top of other QuickAction to reorder",
                            softWrap: true,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w500,
                              color: primary.withValues(alpha: 0.6),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // Search field — explicitly attached to the right of the Disabled header
                  if (!isActive) ...<Widget>[
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 220,
                      height: 36,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (String value) => setState(() => _disabledSearchQuery = value.toLowerCase()),
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: onSurface),
                        decoration: InputDecoration(
                          hintText: 'Search disabled…',
                          hintStyle: TextStyle(fontSize: 12, color: onSurface.withValues(alpha: 0.4)),
                          prefixIcon: Icon(Icons.search_rounded, size: 16, color: onSurface.withValues(alpha: 0.4)),
                          suffixIcon: _disabledSearchQuery.isNotEmpty
                              ? GestureDetector(
                                  onTap: () {
                                    _searchController.clear();
                                    setState(() => _disabledSearchQuery = '');
                                  },
                                  child: Icon(Icons.close_rounded, size: 14, color: onSurface.withValues(alpha: 0.5)),
                                )
                              : null,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(vertical: 8),
                          filled: true,
                          fillColor: onSurface.withValues(alpha: 0.05),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: onSurface.withValues(alpha: 0.12), width: 1),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: onSurface.withValues(alpha: 0.12), width: 1),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.5), width: 1.5),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: 16),
              // Items Grid
              Expanded(
                child: WindowsScrollView(
                  controller: isActive ? _activeScrollController : _disabledScrollController,
                  padding: const EdgeInsets.all(8.0),
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: items.map((String item) {
                      return _DraggableGridItem(
                        key: ValueKey<String>(item),
                        item: item,
                        isActive: isActive,
                        icon: icons[item] ?? Icons.circle_outlined,
                        onDropped: (String draggedItem) => _onItemDropped(draggedItem, item, isActive),
                        onHover: (String? h) => _onItemHovered(h),
                        onDragStateChanged: (bool dragging) {
                          setState(() => _isDragging = dragging);
                          if (!dragging) _stopAutoScroll();
                        },
                        isHoveredByDrag: _hoveredItem == item,
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _DraggableGridItem extends StatefulWidget {
  final String item;
  final bool isActive;
  final IconData icon;
  final Function(String) onDropped;
  final Function(String?) onHover;
  final Function(bool) onDragStateChanged;
  final bool isHoveredByDrag;

  const _DraggableGridItem({
    required super.key,
    required this.item,
    required this.isActive,
    required this.icon,
    required this.onDropped,
    required this.onHover,
    required this.onDragStateChanged,
    required this.isHoveredByDrag,
  });

  @override
  State<_DraggableGridItem> createState() => _DraggableGridItemState();
}

class _DraggableGridItemState extends State<_DraggableGridItem> {
  bool _isMouseHovered = false;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final Color onSurface = theme.colorScheme.onSurface;
    final Color primary = theme.colorScheme.primary;

    return DragTarget<String>(
      onWillAcceptWithDetails: (DragTargetDetails<String> details) {
        if (details.data != widget.item) {
          widget.onHover(widget.item);
          return true;
        }
        return false;
      },
      onLeave: (_) => widget.onHover(null),
      onAcceptWithDetails: (DragTargetDetails<String> details) {
        widget.onDropped(details.data);
      },
      builder: (BuildContext context, List<String?> candidateData, List<dynamic> rejectedData) {
        final Widget content = AnimatedContainer(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOutQuint,
          margin: EdgeInsets.only(left: widget.isHoveredByDrag ? 90.0 : 0.0),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: widget.isActive
                ? (_isMouseHovered ? primary.withValues(alpha: 0.15) : primary.withValues(alpha: 0.08))
                : (_isMouseHovered ? onSurface.withValues(alpha: 0.12) : onSurface.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: widget.isHoveredByDrag
                  ? primary.withValues(alpha: 0.5)
                  : (_isMouseHovered
                      ? (widget.isActive ? primary.withValues(alpha: 0.3) : onSurface.withValues(alpha: 0.2))
                      : Colors.transparent),
              width: 1.5,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(
                widget.icon,
                size: 16,
                color: widget.isActive ? primary : onSurface.withValues(alpha: 0.6),
              ),
              const SizedBox(width: 8),
              Text(
                _formatItemLabel(widget.item),
                style: TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                  color: widget.isActive ? onSurface : onSurface.withValues(alpha: 0.6),
                ),
              ),
            ],
          ),
        );

        return MouseRegion(
          onEnter: (_) => setState(() => _isMouseHovered = true),
          onExit: (_) => setState(() => _isMouseHovered = false),
          cursor: SystemMouseCursors.grab,
          child: AnimatedScale(
            scale: _isMouseHovered ? 1.02 : 1.0,
            duration: const Duration(milliseconds: 200),
            child: Draggable<String>(
              data: widget.item,
              onDragStarted: () => widget.onDragStateChanged(true),
              onDragEnd: (_) => widget.onDragStateChanged(false),
              onDraggableCanceled: (_, __) => widget.onDragStateChanged(false),
              feedback: Material(
                color: Colors.transparent,
                child: Opacity(
                  opacity: 0.8,
                  child: Transform.scale(scale: 1.05, child: content),
                ),
              ),
              childWhenDragging: Opacity(opacity: 0.3, child: content),
              child: content,
            ),
          ),
        );
      },
    );
  }

  String _formatItemLabel(String item) {
    return item
        .replaceAllMapped(RegExp(r'([A-Z])', caseSensitive: true), (Match match) => ' ${match[0]}')
        .replaceAll("Button", "")
        .trim();
  }
}
