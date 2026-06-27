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
import '../widgets/windows_scroll.dart';
import 'tray_bar.dart';

class _MergedPinnedTray extends StatelessWidget {
  const _MergedPinnedTray();

  @override
  Widget build(BuildContext context) {
    // RepaintBoundary: this bar is right-aligned, so its content sits at a
    // fractional x offset. Without isolation, every unrelated repaint in the
    // QuickMenu (hover highlights, focus churn) re-samples the ShaderMask
    // saveLayer over that fractional offset, which wobbles ~1px — the "jitter".
    return RepaintBoundary(
      child: ShaderMask(
        shaderCallback: (Rect rect) {
          return const LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: <Color>[Colors.transparent, Colors.transparent, Color.fromARGB(255, 0, 0, 0)],
            stops: <double>[0.0, 0.93, 1.0],
          ).createShader(rect);
        },
        blendMode: BlendMode.dstOut,
        child: WindowsScrollView(
          scrollDirection: Axis.horizontal,
          showScrollbar: false,
          draggable: true,
          // hardEdge: integer-pixel clip, no extra anti-aliased saveLayer to wobble.
          clipBehavior: Clip.hardEdge,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const PinnedApps(wrapScroll: false),
              if (user.showTrayBar) const TrayBar(wrapScroll: false),
            ],
          ),
        ),
      ),
    );
  }
}

class PinnedAndTrayList extends StatelessWidget {
  const PinnedAndTrayList({super.key});

  @override
  Widget build(BuildContext context) {
    final double height = user.expandedTaskbar ? 32 : 27;
    Globals.heights.pinnedAndTray = (user.taskManagerStats || user.libreStats) ? height * 2 : height;
    return Container(
      height: height,
      width: double.infinity,
      child: Padding(
        padding:
            !user.expandedTaskbar ? const EdgeInsets.fromLTRB(7, 3, 3, 3) : const EdgeInsets.symmetric(horizontal: 10),
        child: LayoutBuilder(builder: (BuildContext context, BoxConstraints constraints) {
          // The horizontal scroll view already shrink-wraps to min(content,
          // maxWidth), so IntrinsicWidth was redundant — it only added an extra
          // unbounded layout pass of the row on every (frequent) rebuild.
          final Widget mergedTray = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.5),
            child: const ClipRRect(child: _MergedPinnedTray()),
          );
          return Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: user.bottomBarOnTop
                ? <Widget>[
                    //BarWithQuickActions Section
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
                                  iconTheme: IconThemeData(size: 16, color: Theme.of(context).iconTheme.color)),
                              child: const OpenSettingsButton()),
                        ],
                      ),
                    ),
                    if (user.mergePinnedTray)
                      mergedTray
                    else ...<Widget>[
                      if (Boxes.pinnedApps.isNotEmpty)
                        const Flexible(flex: 4, child: RepaintBoundary(child: PinnedApps())),
                      if (user.showTrayBar) const Flexible(flex: 4, child: RepaintBoundary(child: TrayBar())),
                    ],
                  ]
                : <Widget>[
                    if (user.quickActionsAtBottom) const Expanded(flex: 5, child: BarWithQuickActions()),
                    if (user.mergePinnedTray)
                      mergedTray
                    else ...<Widget>[
                      if (Boxes.pinnedApps.isNotEmpty)
                        const Flexible(flex: 4, child: RepaintBoundary(child: PinnedApps())),
                      if (user.showTrayBar) const Flexible(flex: 4, child: RepaintBoundary(child: TrayBar())),
                    ],
                  ],
          );
        }),
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
    for (final String name in Boxes().topBarWidgets) {
      if (name == "Deactivated:") break;
      final QuickAction? action = quickActionsMap[name];
      if (action != null) showWidgets.add(action.widget());
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
    _logoDragOverlayEntry?.dispose();
    _logoDragOverlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !user.bottomBarOnTop) _syncLogoDragOverlay();
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
                if (user.persistentReminders.isNotEmpty) const PersistentRemindersWidget(),
                ...List<Widget>.generate(showWidgets.length, (int i) => showWidgets[i]),
                if (user.lastChangelog != Globals.version) const CheckChangelogButton(),
                if (!user.bottomBarOnTop) const OpenSettingsButton(),
              ],
            )
          : const SizedBox.shrink(),
    );
  }
}
