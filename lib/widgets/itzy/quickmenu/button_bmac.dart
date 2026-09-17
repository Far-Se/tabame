import 'package:flutter/material.dart';

import '../../../models/classes/boxes.dart';
import '../../../models/settings.dart';
import '../../widgets/bmac_dialog.dart';
import '../../widgets/quick_actions_item.dart';

const String buyMeACoffeeButtonName = 'BuyMeACoffeeButton';

bool shouldShowBuyMeACoffeeButton() {
  if (Boxes.pref.containsKey('bmacPopup')) return false;

  final int? installDate = Boxes.pref.getInt('installDate');
  if (installDate == null) {
    Boxes.pref.setInt('installDate', DateTime.now().millisecondsSinceEpoch);
    return false;
  }

  final Duration timeSinceInstall = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(installDate));
  return timeSinceInstall.inDays >= 5;
}

class BuyMeACoffeeButton extends StatelessWidget {
  const BuyMeACoffeeButton({super.key});

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: 'Support Tabame',
      icon: const Icon(Icons.coffee_rounded),
      hoverColor: Design.accent,
      onTap: () {
        showModalBottomSheet<void>(
          context: context,
          anchorPoint: const Offset(100, 2),
          elevation: 0,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          constraints: const BoxConstraints(maxWidth: 400),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          enableDrag: true,
          isScrollControlled: true,
          sheetAnimationStyle:
              const AnimationStyle(duration: Duration(milliseconds: 140), reverseDuration: Duration(milliseconds: 100)),
          builder: (BuildContext context) => const BMACDialog(center: false),
        ).whenComplete(() {
          QuickMenuFunctions.refreshQuickMenu();
        });
        // showQuickMenuModal(
        //   context: context,
        //   maxWidth: 360,
        //   child: const BMACDialog(),
        //   whenComplete: () {
        //     QuickMenuFunctions.refreshQuickMenu();
        //   },
        // );
      },
    );
  }
}
