import 'dart:convert';

import 'package:flutter/material.dart';

import 'classes/boxes/boxes_base.dart';

const Map<String, IconData> quickLaunchIcons = <String, IconData>{
  'rocket': Icons.rocket_launch_outlined,
  'apps': Icons.apps_rounded,
  'work': Icons.work_outline_rounded,
  'code': Icons.code_rounded,
  'terminal': Icons.terminal_rounded,
  'web': Icons.language_rounded,
  'folder': Icons.folder_outlined,
  'star': Icons.star_outline_rounded,
  'games': Icons.sports_esports_outlined,
  'music': Icons.music_note_outlined,
  'chat': Icons.chat_bubble_outline_rounded,
  'tools': Icons.build_outlined,
};

enum QuickLaunchKind { file, link, command, app }

class QuickLaunchEntry {
  QuickLaunchEntry({required this.name, required this.target, required this.kind, this.iconPath = ''});

  final String name;
  final String target;
  final QuickLaunchKind kind;
  final String iconPath;

  IconData get icon => switch (kind) {
        QuickLaunchKind.file => Icons.insert_drive_file_outlined,
        QuickLaunchKind.link => Icons.language_rounded,
        QuickLaunchKind.command => Icons.terminal_rounded,
        QuickLaunchKind.app => Icons.apps_rounded,
      };

  factory QuickLaunchEntry.fromJson(Map<String, dynamic> json) => QuickLaunchEntry(
        name: json['name'] as String? ?? '',
        target: json['target'] as String? ?? '',
        kind: QuickLaunchKind.values
            .firstWhere((QuickLaunchKind kind) => kind.name == json['kind'], orElse: () => QuickLaunchKind.file),
        iconPath: json['iconPath'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'name': name,
        'target': target,
        'kind': kind.name,
        'iconPath': iconPath,
      };
}

class QuickLaunchGroup {
  QuickLaunchGroup({required this.name, this.icon = 'rocket', List<QuickLaunchEntry>? items})
      : items = items ?? <QuickLaunchEntry>[];

  String name;
  String icon;
  final List<QuickLaunchEntry> items;
  IconData get iconData => quickLaunchIcons[icon] ?? Icons.rocket_launch_outlined;

  factory QuickLaunchGroup.fromJson(Map<String, dynamic> json, int index) => QuickLaunchGroup(
        name: json['name'] as String? ?? 'QuickLaunch ${index + 1}',
        icon: json['icon'] as String? ?? 'rocket',
        items: (json['items'] as List<dynamic>? ?? <dynamic>[])
            .map((dynamic item) => QuickLaunchEntry.fromJson(Map<String, dynamic>.from(item as Map<dynamic, dynamic>)))
            .toList(),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{'name': name, 'icon': icon, 'items': items};
}

class QuickLaunchStore {
  static final ValueNotifier<int> revision = ValueNotifier<int>(0);

  static List<QuickLaunchGroup> read() {
    List<dynamic> saved = <dynamic>[];
    try {
      saved = jsonDecode(Boxes.pref.getString('quickLaunchGroups') ?? '[]') as List<dynamic>;
    } catch (_) {
      // Older or malformed settings must not prevent the quick bar from opening.
    }
    return List<QuickLaunchGroup>.generate(8, (int index) {
      try {
        if (index < saved.length) {
          return QuickLaunchGroup.fromJson(Map<String, dynamic>.from(saved[index] as Map<dynamic, dynamic>), index);
        }
      } catch (_) {
        // Keep the remaining slots available if one group cannot be decoded.
      }
      return QuickLaunchGroup(name: 'QuickLaunch ${index + 1}');
    });
  }

  static Future<void> save(List<QuickLaunchGroup> groups) async {
    await Boxes.updateSettings('quickLaunchGroups', jsonEncode(groups));
    revision.value++;
  }
}
