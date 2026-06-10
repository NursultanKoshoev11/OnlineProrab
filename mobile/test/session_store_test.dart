import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/services/session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('SessionStore saves and loads session', () async {
    final store = SessionStore();
    await store.save(const SessionData(phone: '+996700000000', accessToken: 'token-123'));

    final session = await store.load();

    expect(session, isNotNull);
    expect(session!.phone, '+996700000000');
    expect(session.accessToken, 'token-123');
    expect(session.isValid, isTrue);
  });

  test('SessionStore clear removes session', () async {
    final store = SessionStore();
    await store.save(const SessionData(phone: '+996700000000', accessToken: 'token-123'));
    await store.clear();

    final session = await store.load();

    expect(session, isNull);
  });
}
