import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../models/settings.dart';

void showCustomModal(BuildContext context, {required Widget child}) {
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
                    // height: MediaQuery.of(context).size.height,
                    height: double.infinity,
                    width: 280,
                    constraints: const BoxConstraints(maxWidth: 280, maxHeight: 350),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(5),
                      // border: Border.all(color: Theme.of(context).backgroundColor.withOpacity(0.5), width: 1),
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
                    child: Padding(padding: const EdgeInsets.all(8.0), child: child),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}
