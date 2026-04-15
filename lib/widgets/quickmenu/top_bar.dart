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
import '../widgets/bar_with_buttons.dart';
import '../itzy/quickmenu/button_testing.dart';

class TopBar extends StatefulWidget {
  const TopBar({super.key});

  @override
  State<TopBar> createState() => _TopBarState();
}

class _TopBarState extends State<TopBar> with QuickMenuTriggers {
  List<Widget> showWidgets = <Widget>[];
  Map<String, Widget> widgets = <String, Widget>{};

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
    Debug.add("QuickMenu: Topbar");
    widgets
        .addAll(quickActionsMap.map((String key, QuickAction value) => MapEntry<String, Widget>("$key", value.widget)));
    final List<String> showWidgetsNames = Boxes().topBarWidgets;
    for (String x in showWidgetsNames) {
      if (x == "Deactivated:") break;
      if (widgets.containsKey(x)) {
        showWidgets.add(widgets[x]!);
      }
    }
    Globals.heights.topbar = 20;
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  void refreshQuickMenu() {
    if (mounted) {
      setState(() {});
    } else {}
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(
          iconTheme: const IconThemeData(size: 16),
          hoverColor: Colors.grey.withAlpha(50),
          tooltipTheme: Theme.of(context)
              .tooltipTheme
              .copyWith(decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface), preferBelow: false)),
      child: IconTheme(
        data: IconThemeData(
          size: 16,
          color: Theme.of(context).iconTheme.color,
        ),
        child: Container(
          height: 25,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.max,
            children: <Widget>[
              Expanded(
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.start,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: <Widget>[
                    const SizedBox(width: 4),
                    const LogoDragButton(),
                    const SizedBox(width: 4),
                    if (showWidgets.isNotEmpty)
                      Expanded(
                        // topBar QuickActions Buttons
                        child: BarWithButtons(
                          children: <Widget>[
                            if (globalSettings.persistentReminders.isNotEmpty) const PersistentRemindersWidget(),
                            ...List<Widget>.generate(showWidgets.length, (int i) => showWidgets[i])
                          ],
                        ),
                      ),
                  ],
                ),
              ),
              if (kDebugMode) const TestingButton(),
              if (globalSettings.lastChangelog != Globals.version) const CheckChangelogButton(),
              const OpenSettingsButton(),
              const SizedBox(width: 2),
            ],
          ),
        ),
      ),
    );
  }
}
