import 'dart:convert';

// --------------------------------------------------------------------------
// QuickActions
// --------------------------------------------------------------------------

class QuickActions {
  String name;
  String type;
  String value;

  QuickActions({required this.name, required this.type, required this.value});

  QuickActions copyWith({String? name, String? type, String? value}) {
    return QuickActions(
      name: name ?? this.name,
      type: type ?? this.type,
      value: value ?? this.value,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{'name': name, 'type': type, 'value': value};
  }

  factory QuickActions.fromMap(Map<String, dynamic> map) {
    return QuickActions(
      name: (map['name'] ?? '') as String,
      type: (map['type'] ?? '') as String,
      value: (map['value'] ?? '') as String,
    );
  }

  String toJson() => json.encode(toMap());

  factory QuickActions.fromJson(String source) => QuickActions.fromMap(json.decode(source) as Map<String, dynamic>);

  @override
  String toString() => 'QuickActions(name: $name, type: $type, value: $value)';

  @override
  bool operator ==(covariant QuickActions other) {
    if (identical(this, other)) return true;
    return other.name == name && other.type == type && other.value == value;
  }

  @override
  int get hashCode => name.hashCode ^ type.hashCode ^ value.hashCode;
}
