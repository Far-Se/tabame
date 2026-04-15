import 'dart:convert';
import 'saved_maps.dart';

class AppItem extends SavedMap {
  String name;
  String path;
  String? arguments;

  AppItem({
    required this.name,
    required this.path,
    this.arguments,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'path': path,
      'arguments': arguments,
    };
  }

  factory AppItem.fromMap(Map<String, dynamic> map) {
    return AppItem(
      name: (map['name'] ?? '') as String,
      path: (map['path'] ?? '') as String,
      arguments: map['arguments'] as String?,
    );
  }

  String toJson() => json.encode(toMap());

  factory AppItem.fromJson(String source) => AppItem.fromMap(json.decode(source) as Map<String, dynamic>);
}

enum AppCategoryViewType { list, grid }

class AppCategory extends SavedMap {
  String name;
  AppCategoryViewType viewType;
  List<AppItem> items;
  String? folderPath;
  bool isCollapsed;

  AppCategory({
    required this.name,
    this.viewType = AppCategoryViewType.grid,
    this.items = const <AppItem>[],
    this.folderPath,
    this.isCollapsed = false,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'name': name,
      'viewType': viewType.index,
      'items': items.map((AppItem x) => x.toMap()).toList(),
      'folderPath': folderPath,
      'isCollapsed': isCollapsed,
    };
  }

  factory AppCategory.fromMap(Map<String, dynamic> map) {
    return AppCategory(
      name: (map['name'] ?? '') as String,
      viewType: AppCategoryViewType.values[(map['viewType'] ?? 1) as int],
      items: List<AppItem>.from(
        (map['items'] as List<dynamic>? ?? <dynamic>[]).map<AppItem>(
        (dynamic x) => AppItem.fromMap(x as Map<String, dynamic>),
        ),
      ),
      folderPath: map['folderPath'] as String?,
      isCollapsed: (map['isCollapsed'] ?? false) as bool,
    );
  }

  String toJson() => json.encode(toMap());

  factory AppCategory.fromJson(String source) => AppCategory.fromMap(json.decode(source) as Map<String, dynamic>);
}
