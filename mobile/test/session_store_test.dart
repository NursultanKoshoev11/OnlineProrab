import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/services/session_store.dart';

class MemorySecureStore implements SecureKeyValueStore {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

void main() {
  test('SessionStore saves and loads session', () async {
    final storage = MemorySecureStore();
    final store = SessionStore(storage: storage);
    await store.save(const SessionData(phone: '+996700000000', accessToken: 'token-123'));

    final session = await store.load();

    expect(session, isNotNull);
    expect(session!.phone, '+996700000000');
    expect(session.accessToken, 'token-123');
    expect(session.isValid, isTrue);
  });

  test('SessionStore clear removes session', () async {
    final storage = MemorySecureStore();
    final store = SessionStore(storage: storage);
    await store.save(const SessionData(phone: '+996700000000', accessToken: 'token-123'));
    await store.clear();

    final session = await store.load();

    expect(session, isNull);
    expect(storage.values, isEmpty);
  });

  test('SessionStore rejects incomplete session', () async {
    final store = SessionStore(storage: MemorySecureStore());

    expect(
      () => store.save(const SessionData(phone: '', accessToken: 'token-123')),
      throwsArgumentError,
    );
  });
}
