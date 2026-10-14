import 'package:flutter_test/flutter_test.dart';
import 'package:online_prorab/core/config/app_config.dart';

void main() {
  test('legal URLs use public HTTPS production pages', () {
    expect(AppConfig.privacyPolicyUrl, 'https://stroy.com.kg/privacy/');
    expect(
      AppConfig.accountDeletionUrl,
      'https://stroy.com.kg/account-deletion/',
    );
  });
}
