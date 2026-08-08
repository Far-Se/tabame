import 'package:flutter/material.dart';

import '../../../models/settings.dart';
import '../../../platform/quick_snap_service.dart';
import '../../widgets/quick_actions_item.dart';

class QuickSnapStandalone extends StatelessWidget {
  const QuickSnapStandalone({super.key});

  @override
  Widget build(BuildContext context) {
    final QuickSnapService service = QuickSnapService.instance;
    return QuickActionItem(
      message: service.supportsStandalone ? "Open QuickSnap Standalone" : service.unavailableReason,
      icon: const Icon(Icons.view_quilt_rounded),
      hoverColor: Design.accentHue(58, saturation: 0.92),
      onTap: service.supportsStandalone ? () async => service.toggleStandalone() : null,
    );
  }
}
