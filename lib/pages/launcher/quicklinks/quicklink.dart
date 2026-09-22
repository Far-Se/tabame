import 'package:uuid/uuid.dart';

import 'quicklink_template.dart';

/// A personal shortcut. The first four JSON fields also accept Raycast exports.
class Quicklink {
  const Quicklink({
    required this.id,
    required this.name,
    required this.link,
    this.openWith = '',
    this.iconName = 'link',
    this.alias = '',
    this.tags = const <String>[],
    this.pinned = false,
    this.hidden = false,
  });

  final String id;
  final String name;
  final String link;
  final String openWith;
  final String iconName;
  final String alias;
  final List<String> tags;
  final bool pinned;
  final bool hidden;

  QuicklinkTemplate get template => QuicklinkTemplate(link);

  factory Quicklink.fromJson(Map<String, dynamic> json) {
    if (json['name'] is! String || json['link'] is! String) {
      throw const FormatException('Each quicklink needs a name and a link.');
    }
    final Quicklink result = Quicklink(
      id: json['id'] is String && (json['id'] as String).isNotEmpty ? json['id'] as String : const Uuid().v4(),
      name: (json['name'] as String).trim(),
      link: (json['link'] as String).trim(),
      openWith: json['openWith'] is String ? (json['openWith'] as String).trim() : '',
      iconName: json['iconName'] is String ? json['iconName'] as String : 'link',
      alias: json['alias'] is String ? (json['alias'] as String).trim() : '',
      tags: json['tags'] is List<dynamic>
          ? (json['tags'] as List<dynamic>)
              .whereType<String>()
              .map((String tag) => tag.trim())
              .where((String tag) => tag.isNotEmpty)
              .toSet()
              .toList()
          : const <String>[],
      pinned: json['pinned'] == true,
      hidden: json['hidden'] == true,
    );
    result.validate();
    return result;
  }

  void validate() {
    if (name.trim().isEmpty) throw const FormatException('Enter a name.');
    if (link.trim().isEmpty) throw const FormatException('Enter a URL, file path, folder, or app deeplink.');
    if (alias.isNotEmpty && !RegExp(r'^[a-zA-Z][a-zA-Z0-9_-]*$').hasMatch(alias)) {
      throw const FormatException('Use a single word for the alias, starting with a letter.');
    }
    template.validate();
  }

  Quicklink copyWith({
    String? id,
    String? name,
    String? link,
    String? openWith,
    String? iconName,
    String? alias,
    List<String>? tags,
    bool? pinned,
    bool? hidden,
  }) =>
      Quicklink(
        id: id ?? this.id,
        name: name ?? this.name,
        link: link ?? this.link,
        openWith: openWith ?? this.openWith,
        iconName: iconName ?? this.iconName,
        alias: alias ?? this.alias,
        tags: tags ?? this.tags,
        pinned: pinned ?? this.pinned,
        hidden: hidden ?? this.hidden,
      );

  Map<String, Object> toJson() => <String, Object>{
        'name': name,
        'link': link,
        'openWith': openWith,
        'iconName': iconName,
        'id': id,
        'alias': alias,
        'tags': tags,
        'pinned': pinned,
        'hidden': hidden,
      };
}

/// Templates are saved only after the user reviews the editor.
const List<Quicklink> quicklinkLibrary = <Quicklink>[
  Quicklink(
      id: '',
      name: 'Search Google',
      alias: 'google',
      iconName: 'search',
      link: 'https://www.google.com/search?q={argument name="Query"}'),
  Quicklink(
      id: '',
      name: 'Search DuckDuckGo',
      alias: 'ddg',
      iconName: 'search',
      link: 'https://duckduckgo.com/?q={argument name="Query"}'),
  Quicklink(
      id: '',
      name: 'Search YouTube',
      alias: 'youtube',
      iconName: 'video',
      link: 'https://www.youtube.com/results?search_query={argument name="Query"}'),
  Quicklink(
      id: '',
      name: 'Search Wikipedia',
      alias: 'wiki',
      iconName: 'book',
      link: 'https://en.wikipedia.org/w/index.php?search={argument name="Query"}'),
  Quicklink(
      id: '',
      name: 'Search GitHub',
      alias: 'github',
      iconName: 'code',
      link: 'https://github.com/search?q={argument name="Query"}'),
  Quicklink(
      id: '',
      name: 'Open GitHub Repository',
      alias: 'repo',
      iconName: 'code',
      link: 'https://github.com/{argument name="Owner"}/{argument name="Repository"}'),
  Quicklink(
      id: '',
      name: 'Search Stack Overflow',
      alias: 'so',
      iconName: 'code',
      link: 'https://stackoverflow.com/search?q={argument name="Query"}'),
  Quicklink(
      id: '',
      name: 'Google Translate',
      alias: 'translate',
      iconName: 'translate',
      link:
          'https://translate.google.com/?sl=auto&tl={argument name="Language" default="en"}&text={argument name="Text"}&op=translate'),
];
