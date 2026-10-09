import 'package:flutter/material.dart';

import '../../models/settings.dart';
import '../../widgets/quickmenu/design_backdrop.dart';
import '../../widgets/widgets/design_preview.dart';

class StableBackdrop extends StatelessWidget {
  const StableBackdrop({super.key});

  static final GlobalKey _backdropKey = GlobalKey();

  @override
  Widget build(BuildContext context) {
    final bool hasBackdrop = Design.hasBackdrop;

    return Positioned.fill(
      child: Offstage(
        offstage: !hasBackdrop,
        child: RepaintBoundary(
          key: DesignPreview.isActive(context) ? null : _backdropKey,
          child: const DesignBackdrop(),
        ),
      ),
    );
  }
}
