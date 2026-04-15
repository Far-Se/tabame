import 'dart:convert';

class VaultItem {
  String key;
  String value;

  VaultItem({required this.key, required this.value});

  Map<String, dynamic> toJson() => <String, dynamic>{
        'key': key,
        'value': value,
      };

  factory VaultItem.fromJson(Map<String, dynamic> json) => VaultItem(
        key: json['key'] as String,
        value: json['value'] as String,
      );
}

class VaultData {
  List<VaultItem> items;

  VaultData({required this.items});

  String toJson() => jsonEncode(items.map((VaultItem e) => e.toJson()).toList());

  factory VaultData.fromJson(String source) {
    final List<dynamic> decoded = jsonDecode(source) as List<dynamic>;
    return VaultData(
      items: decoded.map((dynamic e) => VaultItem.fromJson(e as Map<String, dynamic>)).toList(),
    );
  }
}
