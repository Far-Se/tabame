import 'package:flutter/material.dart';

import '../../../models/globals.dart';
import '../../../pages/interface.dart';

class OpenSettingsButton extends StatelessWidget {
  const OpenSettingsButton({
    Key? key,
  }) : super(key: key);

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
            Globals.opacity = false;
            PaintingBinding.instance.imageCache.clear();
            PaintingBinding.instance.imageCache.clearLiveImages();
            Navigator.of(context).pushAndRemoveUntil(
              PageRouteBuilder<Interface>(
                pageBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation) =>
                    Theme(data: Theme.of(context), child: const Interface()),
                transitionsBuilder: (BuildContext context, Animation<double> animation, Animation<double> secondaryAnimation, Widget child) {
                  const Cubic curve = Curves.fastOutSlowIn;
                  final Tween<double> tween = Tween<double>(begin: 0, end: 1);
                  final CurvedAnimation curvedAnimation = CurvedAnimation(parent: animation, curve: curve);
                  return FadeTransition(opacity: tween.animate(curvedAnimation), child: const Interface());
                },
                transitionDuration: const Duration(milliseconds: 500),
              ),
              (Route<dynamic> route) => false,
            );
          },
        ),
      ),
    );
  }
}
