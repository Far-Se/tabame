import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
// ignore: implementation_imports
import 'package:flutter/src/gestures/events.dart';
import 'quickrun.dart';
import 'package:window_manager/window_manager.dart';
import '../models/settings.dart';
import '../models/win32/win32.dart';
import '../models/globals.dart';
import '../widgets/quickmenu/bottom_bar.dart';
import '../widgets/quickmenu/list_pinned_tray.dart';
import '../widgets/quickmenu/task_bar.dart';
import '../widgets/quickmenu/top_bar.dart';

class QuickMenu extends StatefulWidget {
  const QuickMenu({Key? key}) : super(key: key);
  @override
  State<QuickMenu> createState() => QuickMenuState();
}

Future<int> quickMenuWindowSetup() async {
  Globals.currentPage = Pages.quickmenu;

  if (Globals.lastPage != Pages.quickmenu) {
    await WindowManager.instance.setMinimumSize(const Size(300, 150));
    await WindowManager.instance.setSize(const Size(300, 350));
    await WindowManager.instance.setSkipTaskbar(true);
    await WindowManager.instance.setResizable(false);
    await WindowManager.instance.setAlwaysOnTop(true);
    await WindowManager.instance.setAspectRatio(0);
    await Win32.setMainWindowToMousePos();
  } else {
    await Win32.setMainWindowToMousePos();
  }
  return 1;
}

class QuickMenuState extends State<QuickMenu> {
  double lastHeight = 0;
  Timer? changeHeightTimer;
  @override
  void initState() {
    super.initState();
    Globals.changingPages = false;
    Globals.quickMenuFullyInitiated = false;
    //!RELEASE MODE
    if (!kDebugMode) {
      changeHeightTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) async {
        if (Globals.quickMenuFullyInitiated != true || Globals.isWindowActive || globalSettings.quickRunState != 0) return;
        final double newHeight = Globals.heights.allSummed + 80;
        if (lastHeight != newHeight) {
          if (!mounted) return;
          await windowManager.setSize(Size(300, newHeight));
          lastHeight = newHeight;
        }
      });
    }
    // WidgetsBinding.instance.addPostFrameCallback((Duration timeStamp) => FocusScope.of(context).requestFocus(focusNode));
  }

  final Future<int> quickMenuWindow = quickMenuWindowSetup();

  final FocusNode focusNode = FocusNode();
  @override
  void dispose() {
    PaintingBinding.instance.imageCache.clear();
    if (!kDebugMode) changeHeightTimer?.cancel();
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (Globals.changingPages) {
      return const SizedBox(width: 10);
    }
    if (kReleaseMode) {
      return FutureBuilder<int>(
        future: quickMenuWindow,
        builder: (BuildContext x, AsyncSnapshot<Object?> snapshot) {
          if (!snapshot.hasData) return const SizedBox(width: 10);
          return mainWidget(context);
        },
      );
    }
    return FutureBuilder<int>(
      future: quickMenuWindow,
      builder: (BuildContext x, AsyncSnapshot<Object?> snapshot) {
        if (!snapshot.hasData) return const SizedBox(width: 10);
        return FutureBuilder<int>(
          future: Future<int>.delayed(const Duration(seconds: 1), () => 1),
          builder: (BuildContext x, AsyncSnapshot<Object?> snapshot) {
            if (!snapshot.hasData) return const SizedBox(width: 10);
            return mainWidget(context);
          },
        );
      },
    );
  }

  RawKeyboardListener mainWidget(BuildContext context) {
    return RawKeyboardListener(
      focusNode: focusNode,
      autofocus: true,
      onKey: (RawKeyEvent keyEvent) async {
        if (globalSettings.noopKeyListener) return;
        PhysicalKeyboardKey currentKey = keyEvent.physicalKey;
        if (currentKey == PhysicalKeyboardKey.escape) {
          globalSettings.quickRunState = 0;
          globalSettings.quickRunText = "";
          setState(() {});
        } else if (globalSettings.quickRunState != 2 && keyEvent.logicalKey.keyId.isBetween(0, 200)) {
          if (lastHeight < 330) {
            await windowManager.setSize(const Size(300, 330));
          }
          globalSettings.quickRunState = 1;
          globalSettings.quickRunText += String.fromCharCode(keyEvent.logicalKey.keyId);
          setState(() {});
        }
      },
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: MouseRegion(
          onEnter: (PointerEnterEvent event) async {
            if (!await WindowManager.instance.isFocused()) {}
            await WindowManager.instance.focus();
            Globals.isWindowActive = true;
            Win32.activateWindow(Win32.hWnd);
            setState(() {});
          },
          onExit: (PointerExitEvent event) => Globals.isWindowActive = false,
          child: SingleChildScrollView(
            scrollDirection: Axis.vertical,
            physics: const NeverScrollableScrollPhysics(),
            child: Stack(
              children: <Widget>[
                if (globalSettings.customSpash != "") Positioned(child: Image.file(File(globalSettings.customSpash), height: 30), left: 10),
                Padding(
                  padding: const EdgeInsets.all(10) + const EdgeInsets.only(top: 20),
                  child: Container(
                    key: Globals.quickMenu,
                    color: globalSettings.themeTypeMode == ThemeType.dark ? Colors.white : Colors.black,
                    child: Container(
                      decoration: BoxDecoration(
                          color: Theme.of(context).backgroundColor,
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
                          ]),
                      child: globalSettings.quickRunState != 0
                          ? const QuickRun()
                          : Column(
                              mainAxisAlignment: MainAxisAlignment.start,
                              mainAxisSize: MainAxisSize.max,
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: <Widget>[
                                //3 Items
                                const TopBar(),
                                const TaskBar(),
                                const Divider(thickness: 1, height: 1),
                                if (globalSettings.quickMenuPinnedWithTrayAtBottom) const PinnedAndTrayList(),
                                const BottomBar(),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
