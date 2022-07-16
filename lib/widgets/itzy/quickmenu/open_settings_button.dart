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
            final QuickMenuState? x = context.findAncestorStateOfType<QuickMenuState>();
            //ignore: invalid_use_of_protected_member
            x?.setState(() {
              Globals.changingPages = true;
            });
            Globals.changingPages = true;
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
            // return;
            mainPageViewController.jumpToPage(1);
            return;
          },
        ),
      ),
    );
  }
}
