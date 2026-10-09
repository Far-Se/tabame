import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../widgets/design_preview.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/quick_action_list.dart';
import '../itzy/quickmenu/button_bmac.dart';
import '../itzy/quickmenu/button_changelog.dart';
import '../itzy/quickmenu/button_logo_drag.dart';
import '../itzy/quickmenu/button_open_settings.dart';
import '../itzy/quickmenu/button_persistent_reminders.dart';
import '../itzy/quickmenu/button_testing.dart';
import '../widgets/bar_with_buttons.dart';

class QuickActionsBar extends StatefulWidget {
  const QuickActionsBar({super.key, required this.isTop, this.allMerged = false, this.shrinkWrap = false});

  final bool isTop;
  final bool allMerged;
  final bool shrinkWrap;

  @override
  State<QuickActionsBar> createState() => _QuickActionsBarState();
}

class _QuickActionsBarState extends State<QuickActionsBar> with QuickMenuTriggers {
  List<Widget> showWidgets = <Widget>[];
  OverlayEntry? _logoDragOverlayEntry;

  List<Widget> _buildShowWidgets() {
    return <Widget>[
      for (final String name in Boxes().topBarWidgets.takeWhile((String name) => name != 'Deactivated:'))
        if (name != buyMeACoffeeButtonName && (quickActionsMap[name]?.isVisible ?? false))
          quickActionsMap[name]!.widget(),
    ];
  }

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    showWidgets = _buildShowWidgets();
  }

  @override
  void dispose() {
    _removeLogoDragOverlay();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> refreshQuickMenu() async {
    if (mounted) setState(() => showWidgets = _buildShowWidgets());
  }

  void _syncLogoDragOverlay() {
    if (DesignPreview.isActive(context)) return;
    if (_logoDragOverlayEntry != null) {
      _logoDragOverlayEntry!.markNeedsBuild();
      return;
    }
    final OverlayState overlay = Overlay.of(context, rootOverlay: true);
    _logoDragOverlayEntry = OverlayEntry(
      builder: (BuildContext context) => Positioned(
        left: 10,
        top: 20,
        width: 28,
        height: 25.1,
        child: Theme(
          data: Theme.of(context).copyWith(
            iconTheme: IconThemeData(size: 16, color: Theme.of(context).iconTheme.color),
            hoverColor: Colors.grey.withAlpha(50),
          ),
          child: const Material(
            color: Colors.transparent,
            child: LogoDragButton(),
          ),
        ),
      ),
    );
    overlay.insert(_logoDragOverlayEntry!);
  }

  void _removeLogoDragOverlay() {
    _logoDragOverlayEntry?.remove();
    _logoDragOverlayEntry?.dispose();
    _logoDragOverlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isTop) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _syncLogoDragOverlay();
      });
    }
    final bool showBuyMeACoffee = shouldShowBuyMeACoffeeButton();
    final bool hasActions = showBuyMeACoffee || showWidgets.isNotEmpty || user.persistentReminders.isNotEmpty;
    return Theme(
      data: Theme.of(context).copyWith(
        iconTheme: IconThemeData(size: 16, color: Theme.of(context).iconTheme.color),
        hoverColor: Colors.grey.withAlpha(50),
        tooltipTheme: Theme.of(context)
            .tooltipTheme
            .copyWith(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface), preferBelow: false),
      ),
      child: Row(
        mainAxisSize: widget.allMerged || widget.shrinkWrap ? MainAxisSize.min : MainAxisSize.max,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.allMerged
            ? <Widget>[
                if (hasActions && showBuyMeACoffee) const BuyMeACoffeeButton(),
                if (hasActions && kDebugMode) const TestingButton(),
                if (hasActions && user.persistentReminders.isNotEmpty) const PersistentRemindersWidget(),
                if (hasActions) ...List<Widget>.generate(showWidgets.length, (int i) => showWidgets[i]),
              ]
            : <Widget>[
                if (widget.isTop) const LogoDragButton(),
                if (widget.isTop) const SizedBox(width: 4),
                Flexible(
                  fit: widget.shrinkWrap ? FlexFit.loose : FlexFit.tight,
                  child: hasActions
                      ? BarWithButtons(
                          shrinkWrap: widget.shrinkWrap,
                          height: widget.isTop ? 25 : 25.1,
                          children: <Widget>[
                            if (showBuyMeACoffee) const BuyMeACoffeeButton(),
                            if (kDebugMode) const TestingButton(),
                            if (user.persistentReminders.isNotEmpty) const PersistentRemindersWidget(),
                            ...List<Widget>.generate(showWidgets.length, (int i) => showWidgets[i]),
                          ],
                        )
                      : const SizedBox.shrink(),
                ),
                if (user.lastChangelog != Globals.version) const CheckChangelogButton(),
                const OpenSettingsButton(),
                const SizedBox(width: 2),
              ],
      ),
    );
  }
}
