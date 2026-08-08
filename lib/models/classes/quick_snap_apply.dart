import '../../platform/platform_models.dart';
import '../../platform/quick_snap_service.dart';
import 'saved_maps.dart';

/// Shared QuickSnap orchestration. Placement math and native window movement
/// belong to [QuickSnapService] adapters; this class only translates persisted
/// QuickGrid data into the neutral contract.
class QuickSnapApply {
  QuickSnapApply._();

  static Future<bool> apply(
    PlatformWindow window,
    PlatformMonitor monitor,
    QuickGridRect zone,
    int gap, {
    double topInsetPhysical = 0,
  }) {
    return QuickSnapService.instance.snap(
      window: window,
      monitor: monitor,
      zone: PlatformSnapZone(
        left: zone.left,
        top: zone.top,
        right: zone.right,
        bottom: zone.bottom,
      ),
      gap: gap.toDouble(),
      topInset: topInsetPhysical,
    );
  }
}
