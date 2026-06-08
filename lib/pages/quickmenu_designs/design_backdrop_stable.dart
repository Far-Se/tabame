import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../widgets/quickmenu/design_backdrop.dart';

class StableBackdrop extends StatelessWidget {
  const StableBackdrop({super.key});

  static final GlobalKey _backdropKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final bool hasBackdrop =
        userSettings.themeColors.backdropType.isNotEmpty && userSettings.activeBackdropPath.isNotEmpty;

    return Positioned.fill(
      child: Offstage(
        offstage: !hasBackdrop,
        child: RepaintBoundary(
          key: _backdropKey,
          child: const DesignBackdrop(),
        ),
      ),
    );
  }
}
