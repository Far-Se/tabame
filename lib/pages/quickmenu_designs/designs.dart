import 'package:flutter/cupertino.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import 'design_aurora.dart';
import 'design_cassette.dart';
import 'design_classic.dart';
import 'design_fluent.dart';
import 'design_gazette.dart';
import 'design_interface.dart';
import 'design_matrix.dart';
import 'design_modern.dart';
import 'design_player.dart';
import 'design_serene.dart';
import 'design_steam.dart';
import 'design_terminal.dart';

class LoadQuickMenuDesign extends StatefulWidget {
  const LoadQuickMenuDesign({super.key});

  @override
  State<LoadQuickMenuDesign> createState() => _LoadQuickMenuDesignState();
}

class _LoadQuickMenuDesignState extends State<LoadQuickMenuDesign> with QuickMenuTriggers {
  int _refreshCounter = 0;

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "RefreshQuickMenu") {
      refreshQuickMenu();
    }
  }

  @override
  Future<void> refreshQuickMenu() async {
    // PaintingBinding.instance.imageCache.clear();
    // PaintingBinding.instance.imageCache.clearLiveImages();
    _handleWindowSize();
    if (mounted) {
      setState(() {
        _refreshCounter++;
      });
    }
  }

  Future<void> _handleWindowSize() async {
    final bool isMatrix = QuickMenuDesigns.values[user.quickMenuDesign] == QuickMenuDesigns.matrix;
    if (isMatrix) {
      final Size size = await windowManager.getSize();
      if (size.width < 340) {
        await windowManager.setMinimumSize(Size(Globals.quickMenuSize.width, Globals.quickMenuSize.height));
        await windowManager.setSize(Size(Globals.quickMenuSize.width, size.height));
      } else {
        await windowManager.setMinimumSize(Size(Globals.quickMenuSize.width, Globals.quickMenuSize.height));
      }
    } else {
      await windowManager.setMinimumSize(Size(Globals.quickMenuSize.width, Globals.quickMenuSize.height));
    }
  }

  @override
  void initState() {
    QuickMenuFunctions.addListener(this);
    _handleWindowSize();
    super.initState();
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (QuickMenuDesigns.values[user.quickMenuDesign]) {
      QuickMenuDesigns.classic => MainMenuClassicWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.interface => MainMenuInterfaceWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.modern => MainMenuModernWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.matrix => MainMenuMatrixWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.serene => MainMenuSereneWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.aurora => MainMenuAuroraWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.terminal => MainMenuTerminalWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.cassette => MainMenuCassetteWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.fluent => MainMenuFluentWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.gazette => MainMenuGazetteWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.player => MainMenuPlayerWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.steam => MainMenuSteamWidget(key: ValueKey<int>(_refreshCounter)),
    };
  }
}
