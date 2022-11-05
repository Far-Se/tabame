import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../models/settings.dart';
import '../../../pages/quickactions.dart';
import '../../widgets/quick_actions_item.dart';

class QuickActionsMenuButton extends StatefulWidget {
  const QuickActionsMenuButton({Key? key}) : super(key: key);
  @override
  QuickActionsMenuButtonState createState() => QuickActionsMenuButtonState();
}

class QuickActionsMenuButtonState extends State<QuickActionsMenuButton> {
  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return QuickActionItem(
      message: "QuickActions Menu",
      icon: const Icon(Icons.grid_view),
      onTap: () async {
        showModalBottomSheet<void>(
          context: context,
          anchorPoint: const Offset(100, 200),
          elevation: 0,
          backgroundColor: Colors.transparent,
          barrierColor: Colors.transparent,
          constraints: const BoxConstraints(maxWidth: 280),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          enableDrag: true,
          isScrollControlled: true,
          builder: (BuildContext context) {
            return BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 5, sigmaY: 5),
              child: FractionallySizedBox(
                heightFactor: 0.85,
                child: Listener(
                  onPointerDown: (PointerDownEvent event) {
                    if (event.kind == PointerDeviceKind.mouse) {
                      if (event.buttons == kSecondaryMouseButton) {
                        Navigator.pop(context);
                      }
                    }
                  },
                  child: Padding(
                    padding: const EdgeInsets.all(2.0),
                    child: Material(
                      type: MaterialType.transparency,
                      child: Align(
                        alignment: Alignment.topCenter,
                        child: Container(
                          height: double.infinity,
                          width: 280,
                          constraints: const BoxConstraints(maxWidth: 280, maxHeight: 300),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(5),
                            gradient: LinearGradient(
                              colors: <Color>[
                                Theme.of(context).backgroundColor,
                                Theme.of(context).backgroundColor.withAlpha(globalSettings.themeColors.gradientAlpha),
                                Theme.of(context).backgroundColor,
                              ],
                              stops: <double>[0, 0.4, 1],
                              end: Alignment.bottomRight,
                            ),
                            boxShadow: <BoxShadow>[
                              const BoxShadow(color: Colors.black26, offset: Offset(3, 5), blurStyle: BlurStyle.inner),
                            ],
                            color: Theme.of(context).backgroundColor,
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                            child: SingleChildScrollView(
                              controller: ScrollController(),
                              child: const QuickActionWidget(popup: true),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        );
        return;
      },
    );
  }
}
