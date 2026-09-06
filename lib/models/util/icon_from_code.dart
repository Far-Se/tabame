import 'package:flutter/material.dart';

/// Resolves saved icon codes without constructing icons at runtime, allowing
/// Flutter to tree-shake the Material icon font.
///
/// Add new selectable icons to [_supportedIcons] when extending an icon picker.
/// Unknown codes and unsupported font families use [fallback].
IconData iconFromCode(
  int codePoint, {
  String? fontFamily = 'MaterialIcons',
  IconData fallback = Icons.help_outline,
}) {
  if (fontFamily != 'MaterialIcons') return fallback;
  return _iconsByCode[codePoint] ?? fallback;
}

final Map<int, IconData> _iconsByCode = <int, IconData>{
  for (final IconData icon in _supportedIcons) icon.codePoint: icon,
};

const List<IconData> _supportedIcons = <IconData>[
  // App audio picker.
  Icons.music_note,
  Icons.music_video,
  Icons.audiotrack,
  Icons.queue_music,
  Icons.library_music,
  Icons.album,
  Icons.radio,
  Icons.speaker,
  Icons.headset,
  Icons.play_circle,
  Icons.fast_forward,
  Icons.volume_up,
  Icons.surround_sound,
  // Subscription categories.
  Icons.movie,
  Icons.work,
  Icons.health_and_safety,
  Icons.attach_money,
  Icons.shopping_bag,
  Icons.category,
  // Existing tray picker codes, preserving their actual Material glyphs.
  Icons.cloud_queue_sharp, // 0xe870
  Icons.sort, // 0xe5d2
  Icons.help_center, // 0xe30a
  Icons.credit_score_sharp, // 0xe89e
  Icons.delete_sharp, // 0xe8b8
  Icons.lock, // 0xe3ae
  Icons.crop_7_5, // 0xe1a7
  Icons.hide_image, // 0xe30d
  Icons.lock_clock, // 0xe3af
  Icons.done_sharp, // 0xe8f5
  Icons.desktop_access_disabled, // 0xe1c1
  Icons.code_off_sharp, // 0xe873
];
