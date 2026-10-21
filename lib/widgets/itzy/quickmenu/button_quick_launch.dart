import 'dart:io';

import 'package:flutter/material.dart';

import '../../../models/classes/boxes/quick_menu_box.dart';
import '../../../models/globals.dart';
import '../../../models/quick_launch.dart';
import '../../../models/settings.dart';
import '../../../models/win32/win_utils.dart';
import '../../../services/quick_launch_icon_service.dart';
import '../../widgets/custom_tooltip.dart';
import '../../widgets/quick_actions_item.dart';
import 'button_window_app.dart';

class QuickLaunchButton extends StatefulWidget {
  const QuickLaunchButton({super.key, required this.index});
  final int index;

  @override
  State<QuickLaunchButton> createState() => _QuickLaunchButtonState();
}

class _QuickLaunchButtonState extends State<QuickLaunchButton> with QuickMenuTriggers {
  GlobalKey<TooltipState> _tooltipKey = GlobalKey<TooltipState>();

  @override
  void initState() {
    super.initState();
    QuickMenuFunctions.addListener(this);
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Future<void> onQuickMenuToggled(bool visible, QuickMenuPage type) async {
    if (mounted) setState(() => _tooltipKey = GlobalKey<TooltipState>());
  }

  Future<void> _launch(QuickLaunchEntry entry) async {
    try {
      if (!Platform.isWindows) {
        //TODO: Implement multiplatform
        throw UnsupportedError('QuickLaunch execution is currently available on Windows.');
      }
      if (entry.kind == QuickLaunchKind.command) {
        WinUtils.open('cmd.exe', arguments: '/d /s /k "${entry.target}"', parseParamaters: false);
      } else {
        WinUtils.open(entry.target, parseParamaters: false);
      }
      if (mounted) setState(() => _tooltipKey = GlobalKey<TooltipState>());
      await QuickMenuFunctions.hideQuickMenu();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)
          ?.showSnackBar(SnackBar(content: Text('Could not launch ${entry.name}: $error')));
    }
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<int>(
        valueListenable: QuickLaunchStore.revision,
        builder: (BuildContext context, int revision, Widget? child) {
          final QuickLaunchGroup group = QuickLaunchStore.read()[widget.index];
          return Tooltip(
            key: _tooltipKey,
            ignorePointer: false,
            enableTapToDismiss: false,
            preferBelow: !user.quickMenuBarLayout.quickActionsAtBottom,
            verticalOffset: 14,
            waitDuration: const Duration(milliseconds: 110),
            exitDuration: const Duration(milliseconds: 500),
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Design.text.withAlpha(24)),
            ),
            richMessage: WidgetSpan(
              child: Material(
                type: MaterialType.transparency,
                child: SizedBox(
                  width: 264,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(group.name,
                          style: TextStyle(
                              color: Design.text, fontSize: Design.baseFontSize + 1, fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      if (group.items.isEmpty)
                        Text('Add items in Interface Settings → QuickLaunch.',
                            style: TextStyle(color: Design.text.withAlpha(170), fontSize: Design.baseFontSize))
                      else
                        ConstrainedBox(
                          constraints:
                              BoxConstraints(maxHeight: (MediaQuery.sizeOf(context).height * .45).clamp(60, 280)),
                          child: GridView.builder(
                            shrinkWrap: true,
                            padding: EdgeInsets.zero,
                            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: 6,
                              mainAxisSpacing: 4,
                              crossAxisSpacing: 4,
                            ),
                            itemCount: group.items.length,
                            itemBuilder: (BuildContext context, int index) {
                              final QuickLaunchEntry entry = group.items[index];
                              return CustomTooltip(
                                message: entry.name,
                                child: Semantics(
                                  label: entry.name,
                                  button: true,
                                  child: InkWell(
                                    onTap: () => _launch(entry),
                                    borderRadius: BorderRadius.circular(8),
                                    hoverColor: Design.accent.withAlpha(35),
                                    child: Padding(
                                      padding: const EdgeInsets.all(6),
                                      child: QuickLaunchItemIcon(entry: entry),
                                    ),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            child: Semantics(
              label: 'QuickLaunch ${widget.index + 1}: ${group.name}',
              button: true,
              child: QuickActionItem(
                  message: '',
                  icon: Icon(group.iconData),
                  onTap: () => _tooltipKey.currentState?.ensureTooltipVisible()),
            ),
          );
        },
      );
}

class QuickLaunchItemIcon extends StatefulWidget {
  const QuickLaunchItemIcon({super.key, required this.entry});
  final QuickLaunchEntry entry;

  @override
  State<QuickLaunchItemIcon> createState() => _QuickLaunchItemIconState();
}

class _QuickLaunchItemIconState extends State<QuickLaunchItemIcon> {
  late Future<String> _path = QuickLaunchIconService.resolve(widget.entry);

  @override
  void didUpdateWidget(covariant QuickLaunchItemIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.target != widget.entry.target ||
        oldWidget.entry.iconPath != widget.entry.iconPath ||
        oldWidget.entry.kind != widget.entry.kind) {
      _path = QuickLaunchIconService.resolve(widget.entry);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget fallback = Icon(widget.entry.icon, color: Design.accent, size: 24);
    if (!Platform.isWindows) return fallback;
    return FutureBuilder<String>(
      future: _path,
      builder: (BuildContext context, AsyncSnapshot<String> snapshot) {
        final String path = snapshot.data ?? '';
        if (path.isEmpty) return fallback;
        if (path.toLowerCase().endsWith('.png')) {
          return Image.file(
            File(path),
            width: 32,
            height: 32,
            fit: BoxFit.contain,
            errorBuilder: (BuildContext context, Object error, StackTrace? stackTrace) => fallback,
          );
        }
        return IgnorePointer(child: WindowsAppButton(path: path, placeholder: fallback));
      },
    );
  }
}
