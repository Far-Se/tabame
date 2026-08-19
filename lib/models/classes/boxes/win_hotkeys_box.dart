import 'package:flutter/foundation.dart';

import '../../../platform/hotkey_binding_factory.dart';
import '../../../platform/hotkey_service.dart';
import '../../globals.dart';
import '../boxes.dart';

// --------------------------------------------------------------------------
// WinHotkeys
// --------------------------------------------------------------------------

class WinHotkeys {
  static Future<void> update() async {
    if (!Globals.debugHooks && !kReleaseMode) return;
    await HotkeyService.instance.registerBindings(
      HotkeyBindingFactory.fromModels(Boxes.remap),
    );
  }
}
