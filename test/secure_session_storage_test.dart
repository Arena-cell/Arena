import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:playon/core/services/secure_session_storage.dart';

class Legacy extends LocalStorage {
  String? value;
  bool removed = false;
  Legacy(this.value);
  @override
  Future<void> initialize() async {}
  @override
  Future<String?> accessToken() async => value;
  @override
  Future<bool> hasAccessToken() async => value != null;
  @override
  Future<void> persistSession(String persistSessionString) async {
    value = persistSessionString;
  }

  @override
  Future<void> removePersistedSession() async {
    removed = true;
    value = null;
  }
}

class UnavailableStorage extends FlutterSecureStorage {
  const UnavailableStorage();
  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    throw StateError('Unavailable');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => FlutterSecureStorage.setMockInitialValues({}));
  test('migrates existing session before removing plaintext', () async {
    final old = Legacy('LOCAL SESSION FIXTURE');
    final storage = SecureSessionStorage(key: 'test', legacy: old);
    await storage.initialize();
    expect(await storage.accessToken(), 'LOCAL SESSION FIXTURE');
    expect(old.value, isNull);
    expect(old.removed, isTrue);
  });
  test('migration failure preserves old session for recovery', () async {
    final old = Legacy('LOCAL SESSION FIXTURE');
    final storage = SecureSessionStorage(
      key: 'test',
      legacy: old,
      secure: const UnavailableStorage(),
    );
    await expectLater(storage.initialize(), throwsStateError);
    expect(old.value, 'LOCAL SESSION FIXTURE');
    expect(old.removed, isFalse);
  });
  test('existing encrypted session wins over stale legacy session', () async {
    FlutterSecureStorage.setMockInitialValues({'test': 'CURRENT'});
    final old = Legacy('STALE');
    final storage = SecureSessionStorage(key: 'test', legacy: old);
    await storage.initialize();
    expect(await storage.accessToken(), 'CURRENT');
    expect(old.value, isNull);
  });
  test('persist, restart and logout use secure store', () async {
    final storage = SecureSessionStorage(key: 'test', legacy: Legacy(null));
    await storage.initialize();
    await storage.persistSession('LOCAL NEW SESSION');
    final restarted = SecureSessionStorage(key: 'test', legacy: Legacy(null));
    await restarted.initialize();
    expect(await restarted.hasAccessToken(), isTrue);
    expect(await restarted.accessToken(), 'LOCAL NEW SESSION');
    await restarted.removePersistedSession();
    expect(await restarted.hasAccessToken(), isFalse);
  });
}
