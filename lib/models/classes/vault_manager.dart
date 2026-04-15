import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:encrypt/encrypt.dart';

import '../win32/win32.dart';
import 'vault_item.dart';

class VaultMetadata {
  VaultMetadata({required this.iv, required this.data});
  final String iv;
  final String data;

  Map<String, dynamic> toJson() => <String, dynamic>{'iv': iv, 'data': data};
  factory VaultMetadata.fromJson(Map<String, dynamic> json) => VaultMetadata(
        iv: json['iv'] as String,
        data: json['data'] as String,
      );
}

class VaultManager {
  static String get _filePath => "${WinUtils.getTabameAppDataFolder(settings: true)}\\vault.json";

  static Future<Map<String, VaultMetadata>> loadAllMetadata() async {
    final File file = File(_filePath);
    if (!file.existsSync()) return <String, VaultMetadata>{};
    try {
      final String content = await file.readAsString();
      final Map<String, dynamic> json = jsonDecode(content) as Map<String, dynamic>;
      return json.map((String key, dynamic value) => MapEntry<String, VaultMetadata>(key, VaultMetadata.fromJson(value as Map<String, dynamic>)));
    } catch (e) {
      return <String, VaultMetadata>{};
    }
  }

  static Future<void> saveVault(String name, String password, VaultData data) async {
    final Key key = _deriveKey(password);
    final IV iv = IV.fromSecureRandom(16);
    final Encrypter encrypter = Encrypter(AES(key, mode: AESMode.cbc));

    final Encrypted encrypted = encrypter.encrypt(data.toJson(), iv: iv);

    final Map<String, VaultMetadata> currentMetadata = await loadAllMetadata();
    currentMetadata[name] = VaultMetadata(iv: iv.base64, data: encrypted.base64);

    final File file = File(_filePath);
    await file.writeAsString(jsonEncode(currentMetadata.map((String k, VaultMetadata v) => MapEntry<String, dynamic>(k, v.toJson()))));
  }

  static Future<VaultData?> decryptVault(String name, String password) async {
    final VaultMetadata? metadata = (await loadAllMetadata())[name];
    if (metadata == null) return null;

    try {
      final Key key = _deriveKey(password);
      final IV iv = IV.fromBase64(metadata.iv);
      final Encrypter encrypter = Encrypter(AES(key, mode: AESMode.cbc));

      final String decrypted = encrypter.decrypt(Encrypted.fromBase64(metadata.data), iv: iv);
      return VaultData.fromJson(decrypted);
    } catch (e) {
      // If decryption fails or data is not valid JSON
      return null;
    }
  }

  static Future<void> deleteVault(String name) async {
    final Map<String, VaultMetadata> currentMetadata = await loadAllMetadata();
    if (currentMetadata.containsKey(name)) {
      currentMetadata.remove(name);
      final File file = File(_filePath);
      await file.writeAsString(jsonEncode(currentMetadata.map((String k, VaultMetadata v) => MapEntry<String, dynamic>(k, v.toJson()))));
    }
  }

  static Key _deriveKey(String password) {
    final List<int> bytes = utf8.encode(password);
    final Digest digest = sha256.convert(bytes);
    return Key(Uint8List.fromList(digest.bytes));
  }
}
