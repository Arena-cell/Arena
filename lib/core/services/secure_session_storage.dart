import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Native sessions use platform secure storage. Legacy plaintext is removed
/// only after the encrypted copy has been written and read back successfully.
class SecureSessionStorage extends LocalStorage {
  SecureSessionStorage({
    required String key,
    FlutterSecureStorage secure = const FlutterSecureStorage(),
    LocalStorage? legacy,
  }) : _key = key,
       _secure = secure,
       _legacy =
           legacy ?? SharedPreferencesLocalStorage(persistSessionKey: key);
  final String _key;
  final FlutterSecureStorage _secure;
  final LocalStorage _legacy;
  @override
  Future<void> initialize() async {
    await _legacy.initialize();
    if (kIsWeb) return;
    final encrypted = await _secure.read(key: _key);
    final previous = await _legacy.accessToken();
    if (encrypted == null && previous != null) {
      await _secure.write(key: _key, value: previous);
      if (await _secure.read(key: _key) != previous) {
        throw StateError('Secure session migration could not be verified');
      }
    }
    if (previous != null) await _legacy.removePersistedSession();
  }

  @override
  Future<String?> accessToken() =>
      kIsWeb ? _legacy.accessToken() : _secure.read(key: _key);
  @override
  Future<bool> hasAccessToken() async => await accessToken() != null;
  @override
  Future<void> persistSession(String persistSessionString) async {
    if (kIsWeb) return _legacy.persistSession(persistSessionString);
    await _secure.write(key: _key, value: persistSessionString);
    await _legacy.removePersistedSession();
  }

  @override
  Future<void> removePersistedSession() async {
    if (kIsWeb) return _legacy.removePersistedSession();
    Object? failure;
    try {
      await _secure.delete(key: _key);
    } on Object catch (error) {
      failure = error;
    }
    try {
      await _legacy.removePersistedSession();
    } on Object catch (error) {
      failure ??= error;
    }
    if (failure != null) throw failure;
  }
}
