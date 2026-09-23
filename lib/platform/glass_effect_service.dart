import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../models/glass_effect.dart';

/// The native backdrop has its own clipped window, below Flutter. Never apply a
/// system backdrop or a window region to the oversized interactive Flutter HWND.
abstract final class GlassEffectService {
  static const MethodChannel _channel = MethodChannel('tabame/native_window');
  static bool get supported => Platform.isWindows;
  static String? _lastRequest;

  static Future<void> update({
    required GlassEffect effect,
    required GlassEffectOptions options,
    required int tint,
    required List<Map<String, Object>> regions,
  }) async {
    if (!supported) {
      //TODO: Implement multiplatform
      return;
    }
    final Map<String, Object> request = <String, Object>{
      'effect': effect.name,
      'tint': tint,
      'customAcrylicTint': effect == GlassEffect.acrylic && options.customAcrylicTint,
      'acrylicTintOpacity': options.acrylicTintOpacity,
      'micaAlt': effect == GlassEffect.mica && options.micaAlt,
      'regions': effect == GlassEffect.none ? <Map<String, Object>>[] : regions,
    };
    final String signature = jsonEncode(request);
    if (signature == _lastRequest) return;
    _lastRequest = signature;
    try {
      await _channel.invokeMethod<void>('setGlassEffect', request);
    } on MissingPluginException {
      debugPrint('Glass effects require the updated Windows runner.');
    } on PlatformException catch (error) {
      _lastRequest = null;
      debugPrint('Unable to update glass effect: $error');
    }
  }
}
