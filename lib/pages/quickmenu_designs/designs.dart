import 'package:flutter/cupertino.dart';

import '../../models/classes/boxes/quick_menu_box.dart';
import '../../models/settings.dart';
import 'main_menu_classic_design.dart';
import 'main_menu_interface_design.dart';
import 'main_menu_modern_design.dart';

class LoadQuickMenuDesign extends StatefulWidget {
  const LoadQuickMenuDesign({super.key});

  @override
  State<LoadQuickMenuDesign> createState() => _LoadQuickMenuDesignState();
}

class _LoadQuickMenuDesignState extends State<LoadQuickMenuDesign> with QuickMenuTriggers {
  int _refreshCounter = 0;

  @override
  void onQuickActionExecute(String actionName) {
    if (actionName == "refreshQuickMenu") {
      PaintingBinding.instance.imageCache.clear();
      PaintingBinding.instance.imageCache.clearLiveImages();
      if (mounted) {
        setState(() {
          _refreshCounter++;
        });
      }
    }
  }

  @override
  void initState() {
    QuickMenuFunctions.addListener(this);
    super.initState();
  }

  @override
  void dispose() {
    QuickMenuFunctions.removeListener(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return switch (QuickMenuDesigns.values[globalSettings.quickMenuDesign]) {
      QuickMenuDesigns.classic => MainMenuClassicWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.interface => MainMenuInterfaceWidget(key: ValueKey<int>(_refreshCounter)),
      QuickMenuDesigns.modern => MainMenuModernWidget(key: ValueKey<int>(_refreshCounter)),
    };
  }
}
