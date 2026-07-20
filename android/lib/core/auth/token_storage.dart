import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Bearer-token vault — Android parity of iOS Keychain storage
/// (`kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`).
///
/// Backed by Android Keystore via EncryptedSharedPreferences; the token grants
/// full API access so it never touches plain SharedPreferences.
class TokenStorage {
  TokenStorage({FlutterSecureStorage? storage})
      : _storage = storage ??
            const FlutterSecureStorage(
              aOptions: AndroidOptions(),
            );

  final FlutterSecureStorage _storage;

  static const _key = 'athlynk.api.token';

  Future<String?> read() => _storage.read(key: _key);

  Future<void> write(String token) => _storage.write(key: _key, value: token);

  Future<void> clear() => _storage.delete(key: _key);
}
