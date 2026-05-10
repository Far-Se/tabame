import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes/boxes_base.dart';
import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/quick_action_list.dart';
import '../itzy/quickmenu/button_changelog.dart';
import '../itzy/quickmenu/button_logo_drag.dart';
import '../itzy/quickmenu/button_open_settings.dart';
import '../itzy/quickmenu/button_persistent_reminders.dart';
import '../itzy/quickmenu/button_testing.dart';
import '../itzy/quickmenu/list_pinned_apps.dart';
import '../widgets/bar_with_buttons.dart';
import 'tray_bar.dart';

class PinnedAndTrayList extends StatelessWidget {
  const PinnedAndTrayList({super.key});

  @override
  Widget build(BuildContext context) {
    final double height = userSettings.expandedTaskbar ? 32 : 27;
    Globals.heights.pinnedAndTray = userSettings.taskManagerStats ? height * 2 : height;
    return Container(
      height: height,
      width: double.infinity,
      child: Padding(
        padding: !userSettings.expandedTaskbar
            ? const EdgeInsets.fromLTRB(7, 3, 3, 3)
            : const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: userSettings.bottomBarOnTop
              ? <Widget>[
                  Expanded(
                    flex: 6,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: <Widget>[
                        const LogoDragButton(),
                        const SizedBox(width: 3),
                        const Expanded(child: BarWithQuickActions()),
                        Theme(
                            data: Theme.of(context).copyWith(
                                iconTheme: IconThemeData(
                              size: 16,
                              color: Theme.of(context).iconTheme.color,
                            )),
                            child: const OpenSettingsButton()),
                      ],
                    ),
                  ),
                  if (Boxes.pinnedApps.isNotEmpty) const Flexible(flex: 4, child: PinnedApps()),
                  const Flexible(flex: 4, child: TrayBar()),
                ]
              : <Widget>[
                  if (userSettings.quickActionsAtBottom) const Expanded(flex: 5, child: BarWithQuickActions()),
                  if (Boxes.pinnedApps.isNotEmpty) const Flexible(flex: 4, child: PinnedApps()),
                  const Flexible(flex: 4, child: TrayBar()),
                ],
        ),
      ),
    );
  }
}

class BarWithQuickActions extends StatefulWidget {
  const BarWithQuickActions({super.key});

  @override
  State<BarWithQuickActions> createState() => _BarWithQuickActionsState();
}

class _BarWithQuickActionsState extends State<BarWithQuickActions> with QuickMenuTriggers {
  List<Widget> showWidgets = <Widget>[];
  Map<String, Widget> widgets = <String, Widget>{};
  OverlayEntry? _logoDragOverlayEntry;

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    Debug.add("QuickMenu: Topbar");
    widgets.addAll(
        quickActionsMap.map((String key, QuickAction value) => MapEntry<String, Widget>("$key", value.widget())));
    final List<String> showWidgetsNames = Boxes().topBarWidgets;
    for (String x in showWidgetsNames) {
      if (x == "Deactivated:") break;
      if (widgets.containsKey(x)) {
        showWidgets.add(widgets[x]!);
      }
    }
    Globals.heights.topbar = 25;
  }

  @override
  void dispose() {
    _removeLogoDragOverlay();
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  void refreshQuickMenu() {
    if (mounted) {
      setState(() {});
    } else {}
  }

  void _syncLogoDragOverlay() {
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
            iconTheme: IconThemeData(
              size: 16,
              color: Theme.of(context).iconTheme.color,
            ),
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
    _logoDragOverlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !userSettings.bottomBarOnTop) _syncLogoDragOverlay();
    });
    return Theme(
      data: Theme.of(context).copyWith(
        iconTheme: IconThemeData(
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
        hoverColor: Colors.grey.withAlpha(50),
      ),
      child: showWidgets.isNotEmpty
          ? BarWithButtons(
              height: 25.1,
              children: <Widget>[
                if (kDebugMode) const TestingButton(),
                if (userSettings.persistentReminders.isNotEmpty) const PersistentRemindersWidget(),
                ...List<Widget>.generate(showWidgets.length, (int i) => showWidgets[i]),
                if (userSettings.lastChangelog != Globals.version) const CheckChangelogButton(),
                if (!userSettings.bottomBarOnTop) const OpenSettingsButton(),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}
