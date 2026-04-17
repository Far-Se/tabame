import 'package:flutter/material.dart';
import '../../models/settings.dart';
import '../../widgets/quickmenu/bottom_bar.dart';
import '../../widgets/quickmenu/list_pinned_tray.dart';
import '../../widgets/quickmenu/task_bar.dart';
import '../../widgets/quickmenu/top_bar.dart';

class MainMenuClassicWidget extends StatelessWidget {
  const MainMenuClassicWidget({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 203, maxHeight: 540),
        child: Container(
            decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                gradient: LinearGradient(
                  colors: <Color>[
                    Theme.of(context).colorScheme.surface,
                    Theme.of(context).colorScheme.surface.withAlpha(globalSettings.themeColors.gradientAlpha),
                    Theme.of(context).colorScheme.surface,
                  ],
                  stops: <double>[0, 0.4, 1],
                  end: Alignment.bottomRight,
                ),
                boxShadow: <BoxShadow>[
                  const BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
                ]),
            child: const Column(
              mainAxisAlignment: MainAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TopBar(),
                TaskBar(),
                Divider(thickness: 1, height: 1),
                Flexible(child: PinnedAndTrayList()),
                BottomBar(),
              ],
            )));
  }
}
