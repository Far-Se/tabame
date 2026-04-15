import 'dart:convert';

class SearchHistory {
  final String filename;
  final String path;
  final bool isDirectory;
  int timesOpened;

  SearchHistory({
    required this.filename,
    required this.path,
    this.isDirectory = false,
    this.timesOpened = 1,
  });

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'filename': filename,
      'path': path,
      'isDirectory': isDirectory,
      'timesOpened': timesOpened,
    };
  }

  factory SearchHistory.fromMap(Map<String, dynamic> map) {
    return SearchHistory(
      filename: (map['filename'] ?? '') as String,
      path: (map['path'] ?? '') as String,
      isDirectory: (map['isDirectory'] ?? false) as bool,
      timesOpened: (map['timesOpened'] ?? 1) as int,
    );
  }

  Map<String, dynamic> toJson() => toMap();

  factory SearchHistory.fromJson(String source) => SearchHistory.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() {
    return 'SearchHistory(filename: $filename, path: $path, timesOpened: $timesOpened)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is SearchHistory && other.path == path;
  }

  @override
  int get hashCode => path.hashCode;
}
