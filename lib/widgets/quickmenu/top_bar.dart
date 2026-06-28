// ignore: unused_import
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../models/classes/boxes.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import '../../models/util/quick_action_list.dart';
import '../itzy/quickmenu/button_changelog.dart';
import '../itzy/quickmenu/button_logo_drag.dart';
import '../itzy/quickmenu/button_open_settings.dart';
import '../itzy/quickmenu/button_persistent_reminders.dart';
import '../itzy/quickmenu/button_testing.dart';
import '../widgets/bar_with_buttons.dart';

class TopBar extends StatefulWidget {
  const TopBar({super.key});

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> with QuickMenuTriggers {
  List<Widget> showWidgets = <Widget>[];

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    Debug.add("QuickMenu: Topbar");
    // Only instantiate the widgets that are actually active in the top bar
    // (everything before the "Deactivated:" marker). Building the full
    // quickActionsMap up front allocated a widget for every action, including
    // the deactivated ones that never get mounted.
    for (final String name in Boxes().topBarWidgets) {
      if (name == "Deactivated:") break;
      final QuickAction? action = quickActionsMap[name];
      if (action != null) showWidgets.add(action.widget());
    }
    Globals.heights.topbar = 25;
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> refreshQuickMenu() async {
    if (mounted) {
      setState(() {});
    } else {}
  }

  @override
  Widget build(BuildContext context) {
    if (user.quickActionsAtBottom) return const SizedBox.shrink();
    return Theme(
      data: Theme.of(context).copyWith(
          iconTheme: IconThemeData(
            size: 16,
            color: Theme.of(context).iconTheme.color,
          ),
          hoverColor: Colors.grey.withAlpha(50),
          tooltipTheme: Theme.of(context)
              .tooltipTheme
              .copyWith(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface), preferBelow: false)),
      child: Container(
        height: 25,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.max,
          children: <Widget>[
            if (kDebugMode) const TestingButton(),
            Expanded(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.start,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: <Widget>[
                  if (!user.quickActionsAtBottom) ...<Widget>[
                    const SizedBox(width: 4),
                    const LogoDragButton(),
                    const SizedBox(width: 4)
                  ],
                  if (showWidgets.isNotEmpty)
                    Expanded(
                      // topBar QuickActions Buttons
                      child: BarWithButtons(
                        height: 25,
                        children: <Widget>[
                          if (user.persistentReminders.isNotEmpty) const PersistentRemindersWidget(),
                          ...List<Widget>.generate(showWidgets.length, (int i) => showWidgets[i])
                        ],
                      ),
                    ),
                ],
              ),
            ),
            if (user.lastChangelog != Globals.version) const CheckChangelogButton(),
            const OpenSettingsButton(),
            const SizedBox(width: 2),
          ],
        ),
      ),
    );
  }
}
