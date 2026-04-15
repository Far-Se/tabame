import 'dart:convert';

class AuthenticatorEntry {
  AuthenticatorEntry({
    required this.id,
    required this.secret,
    this.issuer = '',
    this.accountName = '',
    this.algorithm = 'SHA1',
    this.digits = 6,
    this.period = 30,
  });

  final String id;
  final String issuer;
  final String accountName;
  final String secret;
  final String algorithm;
  final int digits;
  final int period;

  String get title {
    if (issuer.trim().isNotEmpty) return issuer.trim();
    if (accountName.trim().isNotEmpty) return accountName.trim();
    return 'Authenticator';
  }

  String get subtitle {
    if (issuer.trim().isNotEmpty && accountName.trim().isNotEmpty) {
      return accountName.trim();
    }
    if (accountName.trim().isNotEmpty) return accountName.trim();
    return algorithm.toUpperCase();
  }

  String get fingerprint =>
      '${issuer.trim().toLowerCase()}|${accountName.trim().toLowerCase()}|${secret.trim().toUpperCase()}';

  Map<String, dynamic> toMap() => <String, dynamic>{
        'id': id,
        'issuer': issuer,
        'accountName': accountName,
        'secret': secret,
        'algorithm': algorithm,
        'digits': digits,
        'period': period,
      };

  factory AuthenticatorEntry.fromMap(Map<String, dynamic> map) {
    return AuthenticatorEntry(
      id: (map['id'] ?? '').toString(),
      issuer: (map['issuer'] ?? '').toString(),
      accountName: (map['accountName'] ?? '').toString(),
      secret: (map['secret'] ?? '').toString(),
      algorithm: (map['algorithm'] ?? 'SHA1').toString(),
      digits: (map['digits'] ?? 6) as int,
      period: (map['period'] ?? 30) as int,
    );
  }

  String toJson() => jsonEncode(toMap());

  factory AuthenticatorEntry.fromJson(String source) {
    return AuthenticatorEntry.fromMap(jsonDecode(source) as Map<String, dynamic>);
  }
}
