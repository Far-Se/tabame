import 'package:flutter/material.dart';

import '../../../main.dart';
import '../../../models/globals.dart';
import '../../../pages/quickmenu.dart';

class OpenSettingsButton extends StatelessWidget {
  const OpenSettingsButton({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: SizedBox(
        width: 25,
        child: IconButton(
          padding: const EdgeInsets.all(0),
          splashRadius: 25,
          icon: const Icon(
            Icons.settings,
          ),
          onPressed: () {
            // final NavigatorState navOfContext = Navigator.of(context);
            final QuickMenuState? x = context.findAncestorStateOfType<QuickMenuState>();
            Globals.changingPages = true;
            //ignore: invalid_use_of_protected_member
            x?.setState(() {
              // navOfContext.pushAndRemoveUntil(
              //   PageRouteBuilder<Interface>(
              //     maintainState: false,
              //     pageBuilder: (BuildContext context, Animation<double> a1, Animation<double> a2) => const Interface(),
              //     transitionDuration: Duration.zero,
              //     reverseTransitionDuration: Duration.zero,
              //   ),
              //   (Route<dynamic> route) => false,
              // );
            });
            mainPageViewController.jumpToPage(Pages.interface.index);
            Globals.changingPages = true;
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
            return;
          },
        ),
      ),
    );
  }
}
