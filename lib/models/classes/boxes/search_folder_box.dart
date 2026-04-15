import 'dart:convert';
import 'package:flutter/foundation.dart';

// --------------------------------------------------------------------------
// SearchFolder
// --------------------------------------------------------------------------

class SearchFolder {
  final String path;
  final bool includeFolders;
  final bool includeFiles;
  final List<String> allowedExtensions; // Should include the dot, e.g., '.exe'
  final int? maxDepth;

  SearchFolder({
    required this.path,
    this.includeFolders = true,
    this.includeFiles = true,
    this.allowedExtensions = const <String>[],
    this.maxDepth,
  });

  SearchFolder copyWith({
    String? path,
    bool? includeFolders,
    bool? includeFiles,
    List<String>? allowedExtensions,
    int? maxDepth,
  }) {
    return SearchFolder(
      path: path ?? this.path,
      includeFolders: includeFolders ?? this.includeFolders,
      includeFiles: includeFiles ?? this.includeFiles,
      allowedExtensions: allowedExtensions ?? this.allowedExtensions,
      maxDepth: maxDepth ?? this.maxDepth,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'path': path,
      'includeFolders': includeFolders,
      'includeFiles': includeFiles,
      'allowedExtensions': allowedExtensions,
      'maxDepth': maxDepth,
    };
  }

  factory SearchFolder.fromMap(Map<String, dynamic> map) {
    return SearchFolder(
      path: (map['path'] ?? '') as String,
      includeFolders: (map['includeFolders'] ?? false) as bool,
      includeFiles: (map['includeFiles'] ?? false) as bool,
      allowedExtensions: List<String>.from((map['allowedExtensions'] ?? const <String>[]) as List<dynamic>),
      maxDepth: map['maxDepth'] != null ? map['maxDepth'] as int : null,
    );
  }

  String toJson() => json.encode(toMap());

  factory SearchFolder.fromJson(String source) => SearchFolder.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'SearchFolder(path: $path, includeFolders: $includeFolders, includeFiles: $includeFiles, allowedExtensions: $allowedExtensions, maxDepth: $maxDepth)';
  }

  @override
  bool operator ==(covariant SearchFolder other) {
    if (identical(this, other)) return true;

    return other.path == path &&
        other.includeFolders == includeFolders &&
        other.includeFiles == includeFiles &&
        listEquals(other.allowedExtensions, allowedExtensions) &&
        other.maxDepth == maxDepth;
  }

  @override
  int get hashCode {
    return path.hashCode ^ includeFolders.hashCode ^ includeFiles.hashCode ^ allowedExtensions.hashCode ^ maxDepth.hashCode;
  }
}
