import 'package:flutter/cupertino.dart';
import 'package:window_manager/window_manager.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/globals.dart';
import '../../models/settings.dart';
import 'design_anime.dart';
import 'design_anime2.dart';
import 'design_cyber.dart';
import 'design_aurora.dart';
import 'design_cassette.dart';
import 'design_classic.dart';
import 'design_console.dart';
// import 'design_family_guy.dart';
import 'design_fluent.dart';
import 'design_foundry.dart';
import 'design_gazette.dart';
// import 'design_impact.dart';
import 'design_interface.dart';
import 'design_ledger.dart';
import 'design_manga.dart';
import 'design_matrix.dart';
import 'design_manifesto.dart';
import 'design_modern.dart';
import 'design_notion.dart';
import 'design_outrun.dart';
import 'design_outrun2.dart';
import 'design_player.dart';
import 'design_rundown.dart';
import 'design_serene.dart';
import 'design_steam.dart';
import 'design_tech.dart';
import 'design_terminal.dart';
import 'design_vector.dart';
import 'design_winamp.dart';
import 'design_windows_98.dart';
import 'design_windows_xp.dart';

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
      QuickMenuDesigns.manifesto => MainMenuManifestoWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.vector => MainMenuVectorWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.ledger => MainMenuLedgerWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.console => MainMenuConsoleWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.foundry => MainMenuFoundryWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.anime => MainMenuAnimeWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.anime2 => MainMenuAnime2Widget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.cyber => MainMenuCyberWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.tech => MainMenuTechWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.manga => MainMenuMangaWidget(key: ValueKey<int>(_refreshCounter)),
      // QuickMenuDesigns.impact => MainMenuImpactWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.outrun => MainMenuOutrunWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.outrun2 => MainMenuOutrun2Widget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.winamp => MainMenuWinampWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.windowsXp => MainMenuWindowsXpWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.windows98 => MainMenuWindows98Widget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.notion => MainMenuNotionWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.rundown => MainMenuRundownWidget(key: ValueKey<int>(_refreshCounter)),
      // QuickMenuDesigns.familyGuy => MainMenuFamilyGuyWidget(key: ValueKey<int>(_refreshCounter)),
    };
  }
}
