import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../../models/util/quick_action_list.dart';

class QuickmenuTopbar extends StatefulWidget {
  const QuickmenuTopbar({super.key});

  @override
  QuickmenuTopbarState createState() => QuickmenuTopbarState();
}

class QuickmenuTopbarState extends State<QuickmenuTopbar> {
  List<String> topBarItems = Boxes().topBarWidgets;
  final Map<String, IconData> icons = <String, IconData>{};
  @override
  void initState() {
    icons.addAll(quickActionsMap.map((String key, QuickAction value) => MapEntry<String, IconData>("$key", value.icon)));
    icons["Deactivated:"] = Icons.do_disturb;
    // check which topBarItems do not have icons and remove them from topbarWidgets then save it
    for (int i = 0; i < topBarItems.length; i++) {
      if (!icons.containsKey(topBarItems[i])) {
        topBarItems.removeAt(i);
        i--;
      }
    }
    Boxes.updateSettings("topBarWidgets", topBarItems);
    if (mounted) setState(() {});
    super.initState();
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: ScrollController(),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            _buildQuickActionsCard(),
            const SizedBox(height: 100),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActionsCard() {
    return Card(
      elevation: 0,
      color: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: Theme.of(context).dividerColor.withValues(alpha: 0.1)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          children: <Widget>[
            _buildSectionHeader(),
            const Divider(),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
              child: Row(
                children: <Widget>[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      "Layout Tool",
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      "Drag actions into place to shape the top bar from most important to least.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                    ),
                  ),
                ],
              ),
            ),
            ReorderableListView.builder(
              shrinkWrap: true,
              buildDefaultDragHandles: false,
              dragStartBehavior: DragStartBehavior.down,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
              proxyDecorator: (Widget child, int index, Animation<double> animation) {
                return Material(
                  color: Colors.transparent,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: child,
                  ),
                );
              },
              itemBuilder: (BuildContext context, int index) => _buildQuickActionRow(index),
              itemCount: topBarItems.length,
              onReorder: _reorderQuickActions,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(Icons.flash_on_outlined, size: 20, color: Theme.of(context).colorScheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  "QuickActions Order",
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 3),
                Text(
                  "Keep the top bar tidy while still putting your fastest actions within reach.",
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor, height: 1.25),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionRow(int index) {
    final String item = topBarItems[index];
    final bool isDeactivatedLabel = item == "Deactivated:";
    final Color borderColor = isDeactivatedLabel ? Colors.redAccent.withValues(alpha: 0.18) : Theme.of(context).dividerColor.withValues(alpha: 0.18);
    final Color backgroundColor =
        isDeactivatedLabel ? Colors.redAccent.withValues(alpha: 0.06) : Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.08);
    final IconData itemIcon = icons[item] ?? Icons.circle_outlined;

    return ReorderableDragStartListener(
      key: ValueKey<String>("quickaction-$index-$item"),
      index: index,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: backgroundColor,
          border: Border.all(color: borderColor),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: <Widget>[
            Container(
              width: 34,
              height: 34,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Theme.of(context).dividerColor.withValues(alpha: 0.2)),
              ),
              child: Icon(
                Icons.drag_indicator_rounded,
                size: 18,
                color: Theme.of(context).hintColor,
              ),
            ),
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                color: isDeactivatedLabel ? Colors.redAccent.withValues(alpha: 0.1) : Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                itemIcon,
                size: 18,
                color: isDeactivatedLabel ? Colors.redAccent : Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    _formatItemLabel(item),
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDeactivatedLabel ? Colors.redAccent : null,
                        ),
                  ),
                  const SizedBox(height: 2),
                  if (isDeactivatedLabel)
                    Text(
                      "Actions below this line are currently hidden from the top bar.",
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Theme.of(context).hintColor),
                    ),
                ],
              ),
            ),
            if (isDeactivatedLabel)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.redAccent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text(
                  "Hidden",
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  String _formatItemLabel(String item) {
    if (item == "Deactivated:") {
      return item.toUperCaseAll().replaceAll("Button", "");
    }
    return item.replaceAllMapped(RegExp(r'([A-Z])', caseSensitive: true), (Match match) => ' ${match[0]}').replaceAll("Button", "").trim();
  }

  Future<void> _reorderQuickActions(int oldIndex, int newIndex) async {
    if (oldIndex < newIndex) newIndex -= 1;
    final String item = topBarItems.removeAt(oldIndex);
    topBarItems.insert(newIndex, item);
    await Boxes.updateSettings("topBarWidgets", topBarItems);
    if (!mounted) return;
    setState(() {});
  }
}
