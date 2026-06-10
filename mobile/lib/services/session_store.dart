import 'package:shared_preferences/shared_preferences.dart';

class SessionData {
  const SessionData({required this.phone, required this.accessToken});

  final String phone;
  final String accessToken;

  bool get isValid => phone.isNotEmpty && accessToken.isNotEmpty;
}

class SessionStore {
  static const _phoneKey = 'online_prorab_session_phone';
  static const _accessTokenKey = 'online_prorab_access_token';

  Future<SessionData?> load() async {
    final preferences = await SharedPreferences.getInstance();
    final phone = preferences.getString(_phoneKey) ?? '';
    final accessToken = preferences.getString(_accessTokenKey) ?? '';
    if (phone.isEmpty || accessToken.isEmpty) {
      return null;
    }
    return SessionData(phone: phone, accessToken: accessToken);
  }

  Future<void> save(SessionData session) async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_phoneKey, session.phone);
    await preferences.setString(_accessTokenKey, session.accessToken);
  }

  Future<void> clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_phoneKey);
    await preferences.remove(_accessTokenKey);
  }
}
