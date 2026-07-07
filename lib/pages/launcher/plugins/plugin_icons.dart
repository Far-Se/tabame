import 'package:flutter/material.dart';

/// Resolves a plugin-supplied icon name to a concrete [IconData].
///
/// Flutter tree-shakes icon fonts, so we can't build an [IconData] from an
/// arbitrary code point at runtime. Instead we expose a curated allow-list of
/// commonly useful Material icon names; anything unknown falls back to
/// [Icons.extension_rounded]. Names are matched case-insensitively and ignore a
/// trailing `_rounded` / `_outlined` suffix.
abstract final class PluginIcons {
  static const IconData fallback = Icons.extension_rounded;

  static const Map<String, IconData> _byName = <String, IconData>{
    'search': Icons.search_rounded,
    'star': Icons.star_rounded,
    'favorite': Icons.favorite_rounded,
    'heart': Icons.favorite_rounded,
    'home': Icons.home_rounded,
    'settings': Icons.settings_rounded,
    'gear': Icons.settings_rounded,
    'folder': Icons.folder_rounded,
    'file': Icons.insert_drive_file_rounded,
    'document': Icons.description_rounded,
    'link': Icons.link_rounded,
    'globe': Icons.public_rounded,
    'world': Icons.public_rounded,
    'cloud': Icons.cloud_rounded,
    'sun': Icons.wb_sunny_rounded,
    'weather': Icons.cloud_rounded,
    'moon': Icons.nightlight_round,
    'bolt': Icons.bolt_rounded,
    'flash': Icons.bolt_rounded,
    'terminal': Icons.terminal_rounded,
    'code': Icons.code_rounded,
    'calculator': Icons.calculate_rounded,
    'calc': Icons.calculate_rounded,
    'clock': Icons.access_time_rounded,
    'timer': Icons.timer_outlined,
    'calendar': Icons.calendar_today_rounded,
    'mail': Icons.mail_rounded,
    'email': Icons.mail_rounded,
    'message': Icons.chat_bubble_rounded,
    'chat': Icons.chat_bubble_rounded,
    'person': Icons.person_rounded,
    'user': Icons.person_rounded,
    'people': Icons.people_rounded,
    'image': Icons.image_rounded,
    'photo': Icons.photo_rounded,
    'music': Icons.music_note_rounded,
    'video': Icons.videocam_rounded,
    'play': Icons.play_arrow_rounded,
    'download': Icons.download_rounded,
    'upload': Icons.upload_rounded,
    'copy': Icons.content_copy_rounded,
    'content_copy': Icons.content_copy_rounded,
    'clipboard': Icons.content_paste_rounded,
    'paste': Icons.content_paste_rounded,
    'edit': Icons.edit_rounded,
    'pencil': Icons.edit_rounded,
    'delete': Icons.delete_rounded,
    'trash': Icons.delete_rounded,
    'add': Icons.add_rounded,
    'plus': Icons.add_rounded,
    'remove': Icons.remove_rounded,
    'minus': Icons.remove_rounded,
    'check': Icons.check_rounded,
    'close': Icons.close_rounded,
    'info': Icons.info_outline_rounded,
    'warning': Icons.warning_amber_rounded,
    'error': Icons.error_outline_rounded,
    'help': Icons.help_outline_rounded,
    'tag': Icons.tag_rounded,
    'label': Icons.label_rounded,
    'bookmark': Icons.bookmark_rounded,
    'money': Icons.attach_money_rounded,
    'currency': Icons.currency_exchange_rounded,
    'cart': Icons.shopping_cart_rounded,
    'shop': Icons.storefront_rounded,
    'chart': Icons.bar_chart_rounded,
    'graph': Icons.show_chart_rounded,
    'database': Icons.storage_rounded,
    'server': Icons.dns_rounded,
    'wifi': Icons.wifi_rounded,
    'bluetooth': Icons.bluetooth_rounded,
    'battery': Icons.battery_full_rounded,
    'power': Icons.power_settings_new_rounded,
    'lock': Icons.lock_rounded,
    'unlock': Icons.lock_open_rounded,
    'key': Icons.key_rounded,
    'shield': Icons.shield_rounded,
    'bell': Icons.notifications_rounded,
    'flag': Icons.flag_rounded,
    'location': Icons.location_on_rounded,
    'map': Icons.map_rounded,
    'translate': Icons.translate_rounded,
    'language': Icons.language_rounded,
    'palette': Icons.palette_rounded,
    'color': Icons.color_lens_rounded,
    'brush': Icons.brush_rounded,
    'emoji': Icons.emoji_emotions_rounded,
    'grid': Icons.grid_view_rounded,
    'list': Icons.list_rounded,
    'menu': Icons.menu_rounded,
    'app': Icons.apps_rounded,
    'window': Icons.window_rounded,
    'extension': Icons.extension_rounded,
    'plugin': Icons.extension_rounded,
    'refresh': Icons.refresh_rounded,
    'sync': Icons.sync_rounded,
    'gamepad': Icons.sports_esports_rounded,
    'game': Icons.sports_esports_rounded,
    'book': Icons.menu_book_rounded,
    'note': Icons.sticky_note_2_rounded,
    'run': Icons.play_circle_rounded,
    'open': Icons.open_in_new_rounded,
  };

  static IconData resolve(String? name) {
    if (name == null) return fallback;
    String key = name.trim().toLowerCase();
    if (key.isEmpty) return fallback;
    // Drop a common style suffix so `cloud_rounded` matches `cloud`.
    for (final String suffix in const <String>['_rounded', '_outlined', '_sharp', '_filled']) {
      if (key.endsWith(suffix)) {
        key = key.substring(0, key.length - suffix.length);
        break;
      }
    }
    return _byName[key] ?? fallback;
  }
}
