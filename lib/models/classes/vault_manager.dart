import 'dart:convert';
import 'dart:io';

import '../util/secret_crypto.dart';
import '../win32/win_utils.dart';
import 'vault_item.dart';

/// Opaque, versioned on-disk envelope for a single vault. The shape depends on
/// how the vault was sealed (see [SecretCrypto]); this just carries the raw map
/// so the format can evolve without changing callers, which only need the names.
class VaultMetadata {
  VaultMetadata(this.raw);
  final Map<String, dynamic> raw;

  Map<String, dynamic> toJson() => raw;
  factory VaultMetadata.fromJson(Map<String, dynamic> json) => VaultMetadata(json);
}

class VaultManager {
  static String get _filePath => "${WinUtils.getTabameAppDataFolder(settings: true)}\\vault.json";

  /// Sentinel the UI used for "no password" vaults. Legacy files were encrypted
  /// with `sha256("n0p@s5")` — a constant — so they are read here only to be
  /// migrated onto the device key.
  static const String _legacyNoPassword = 'n0p@s5';

  static Future<Map<String, VaultMetadata>> loadAllMetadata() async {
    final File file = File(_filePath);
    if (!file.existsSync()) return <String, VaultMetadata>{};
    try {
      final String content = await file.readAsString();
      final Map<String, dynamic> json = jsonDecode(content) as Map<String, dynamic>;
      return json.map((String key, dynamic value) =>
          MapEntry<String, VaultMetadata>(key, VaultMetadata.fromJson(value as Map<String, dynamic>)));
    } catch (e) {
      return <String, VaultMetadata>{};
    }
  }

  static Future<void> _persist(Map<String, VaultMetadata> all) async {
    final File file = File(_filePath);
    await file.writeAsString(
        jsonEncode(all.map((String k, VaultMetadata v) => MapEntry<String, dynamic>(k, v.toJson()))));
  }

  /// Seals a vault. An empty [password] binds the vault to the current Windows
  /// account (DPAPI); a non-empty one derives a key with PBKDF2 and seals with
  /// AES-256-GCM.
  static Future<void> saveVault(String name, String password, VaultData data) async {
    final Map<String, dynamic> envelope = password.isEmpty
        ? SecretCrypto.sealWithMachineKey(data.toJson())
        : SecretCrypto.sealWithPassword(data.toJson(), password);

    final Map<String, VaultMetadata> all = await loadAllMetadata();
    all[name] = VaultMetadata(envelope);
    await _persist(all);
  }

  static Future<VaultData?> decryptVault(String name, String password) async {
    final Map<String, VaultMetadata> all = await loadAllMetadata();
    final VaultMetadata? metadata = all[name];
    if (metadata == null) return null;

    final String? plaintext = _open(metadata.raw, password);
    if (plaintext == null) return null;

    VaultData? result;
    try {
      result = VaultData.fromJson(plaintext);
    } catch (_) {
      return null;
    }

    // Forward-migrate legacy (unsalted sha256 + AES-CBC) vaults the first time
    // they are opened successfully, so the constant-key format disappears.
    if (_isLegacy(metadata.raw)) {
      try {
        final bool wasNoPassword = password.isEmpty || password == _legacyNoPassword;
        all[name] = VaultMetadata(wasNoPassword
            ? SecretCrypto.sealWithMachineKey(plaintext)
            : SecretCrypto.sealWithPassword(plaintext, password));
        await _persist(all);
      } catch (_) {
        // Migration is best-effort; the vault is still usable in its old form.
      }
    }

    return result;
  }

  static Future<void> deleteVault(String name) async {
    final Map<String, VaultMetadata> all = await loadAllMetadata();
    if (all.containsKey(name)) {
      all.remove(name);
      await _persist(all);
    }
  }

  static bool _isLegacy(Map<String, dynamic> envelope) =>
      envelope['kdf'] == null && envelope['iv'] is String && envelope['data'] is String;

  static String? _open(Map<String, dynamic> envelope, String password) {
    switch (envelope['kdf']) {
      case SecretCrypto.dpapiKdf:
        return SecretCrypto.openWithMachineKey(envelope);
      case SecretCrypto.pbkdf2Kdf:
        return SecretCrypto.openWithPassword(envelope, password);
      default:
        // Legacy AES-CBC with sha256(password); no-password vaults used a
        // constant sentinel as the password.
        if (_isLegacy(envelope)) {
          return SecretCrypto.legacyDecryptCbcSha256(
            envelope['iv'] as String,
            envelope['data'] as String,
            password.isEmpty ? _legacyNoPassword : password,
          );
        }
        return null;
    }
  }
}
